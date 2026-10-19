-module(moirai).

-include_lib("klotho/include/klotho.hrl").

-export([shell/0, spawn_shell/0, run/1, chat/1, tools/0, status/0,
         reset/0, summarize/0, banner/0]).

-ifdef(TEST).
-export([build_config/5, safe_stop/1, namespace_gitmcp_tools/2]).
-endif.

-define(STATE_KEY, {?MODULE, shell_state}).
-define(MODEL, <<"google/gemma-4-26b-a4b-it">>).
-define(MAX_STEPS, 10).
-define(MAX_WALL_CLOCK_MS, 120000).
-define(LLM_TIMEOUT_MS, 60000).
-define(TOOL_TIMEOUT_MS, 30000).
-define(MCP_TIMEOUT_MS, 60000).
-define(SUMMARY_PROMPT, <<"Summarize our conversation in a concise closing "
    "note. Include what we learned, any decisions made, and useful next "
    "steps. Do not call tools.">>).

-define(BASE_PROMPT, <<"You are Moirai, an Erlang/OTP agent application "
    "assembled from erl_openrouter, erl_mcp, klotho, and magicbeam. "
    "You can inspect the real Moirai source checkout with list_directory "
    "and read_file, and search the public Erlang agent-stack repositories "
    "with MCP tools as they become available. Use tools before making claims "
    "about the project. Be concise.">>).

-spec spawn_shell() -> pid().
spawn_shell() ->
    spawn(fun shell/0).

-spec shell() -> terminated.
shell() ->
    PreviousAnsi = application:get_env(magicbeam, shellbeam_ansi),
    ok = application:set_env(magicbeam, shellbeam_ansi, true),
    try
        put(?STATE_KEY, new_shell_state()),
        start_resource_discovery(),
        try
            shellbeam:start_shell(
                [moirai_shell],
                "moirai",
                #{banner => banner()})
        after
            teardown_shell()
        end
    after
        restore_shell_ansi(PreviousAnsi)
    end.

-spec run(map()) -> {ok, #klotho_result{}} | {error, term()}.
run(Opts) when is_map(Opts) ->
    Model = maps:get(model, Opts, ?MODEL),
    Verbose = maps:get(verbose, Opts, false),
    Root = maps:get(project_root, Opts, project_root()),
    Tools = local_tools(Root),
    Prompt = to_binary(maps:get(prompt, Opts)),
    Config = build_config(Model, Tools, Verbose, ?BASE_PROMPT, Prompt),
    {ok, Pid} = klotho_agent:start_link(Config),
    unlink(Pid),
    Result = klotho_agent:run(Pid, ?MAX_WALL_CLOCK_MS + 5000),
    safe_stop(Pid),
    Result.

-spec chat(binary() | string()) ->
    {ok, #klotho_result{}} | {error, term()}.
chat(Message0) ->
    State0 = state_for_chat(),
    Message = to_binary(Message0),
    case maps:get(agent, State0) of
        undefined ->
            Config = build_config(
                maps:get(model, State0),
                maps:get(tools, State0),
                true,
                maps:get(system_prompt, State0),
                Message),
            {ok, Pid} = klotho_agent:start_link(Config),
            put(?STATE_KEY, State0#{agent => Pid}),
            klotho_agent:run(Pid, ?MAX_WALL_CLOCK_MS + 5000);
        Pid ->
            klotho_agent:resume(Pid, Message)
    end.

-spec tools() -> [binary()].
tools() ->
    State = refresh_state(),
    [Name || #klotho_tool{name = Name} <- maps:get(tools, State)].

-spec status() -> #{
    model := binary(),
    tools := [binary()],
    discovery_pending := non_neg_integer(),
    discovery_errors := [{binary(), term()}],
    agent_started := boolean()
}.
status() ->
    State = refresh_state(),
    #{
        model => maps:get(model, State),
        tools => [Name || #klotho_tool{name = Name} <-
            maps:get(tools, State)],
        discovery_pending => maps:get(discovery_pending, State),
        discovery_errors => lists:reverse(maps:get(discovery_errors, State)),
        agent_started => is_pid(maps:get(agent, State))
    }.

-spec reset() -> ok.
reset() ->
    State = refresh_state(),
    case maps:get(agent, State) of
        undefined -> ok;
        Pid -> safe_stop(Pid)
    end,
    put(?STATE_KEY, State#{agent => undefined}),
    ok.

-spec summarize() ->
    {ok, #klotho_result{}} | {error, no_conversation | term()}.
summarize() ->
    State = refresh_state(),
    case maps:get(agent, State) of
        undefined ->
            {error, no_conversation};
        Pid ->
            klotho_agent:resume(Pid, ?SUMMARY_PROMPT)
    end.

-spec banner() -> binary().
banner() ->
    iolist_to_binary([
        "                         _\n",
        " _ __ ___   ___ (_)_ __ __ _(_)\n",
        "| '_  _ \\ / _ \\| | '__/ _  | |\n",
        "| | | | | | (_) | | | | (_| | |\n",
        "|_| |_| |_|\\___/|_|_|  \\__,_|_|\n",
        "\n",
        "erl_openrouter x erl_mcp x klotho x magicbeam\n",
        "The Erlang/OTP agent stack, talking about its own source.\n",
        "Weather and repository tools connect in the background.\n",
        "Type naturally; use help, tools, status, or reset.\n",
        "Use quit for a closing summary, or exit to leave immediately."
    ]).

new_shell_state() ->
    #{
        model => ?MODEL,
        tools => local_tools(project_root()),
        clients => [],
        workers => [],
        discovery_pending => 0,
        discovery_errors => [],
        agent => undefined,
        weather => false,
        location_context => <<>>,
        system_prompt => ?BASE_PROMPT
    }.

local_tools(Root) ->
    [
        moirai_tools:list_directory_tool(Root),
        moirai_tools:read_file_tool(Root)
    ].

project_root() ->
    filename:absname(os:getenv("MOIRAI_PROJECT_ROOT", ".")).

start_resource_discovery() ->
    Parent = self(),
    Specs = resource_specs(),
    Workers = [
        spawn(fun() -> discover_endpoint(Parent, Label, Url, Filter) end)
        || {Label, Url, Filter} <- Specs
    ],
    GeoWorker = spawn(fun() -> discover_location(Parent) end),
    State = get(?STATE_KEY),
    put(?STATE_KEY, State#{
        workers => [GeoWorker | Workers],
        discovery_pending => length(Workers) + 1
    }).

resource_specs() ->
    WeatherUrl = to_binary(os:getenv(
        "MOIRAI_WEATHER_MCP_URL", "http://weather:3000/mcp")),
    Weather = {<<"weather">>, WeatherUrl,
        fun moirai_weather:filter_tools/1},
    GitMcp = [
        {Repo, moirai_mcp_config:gitmcp_url(Repo),
            fun(Tools) ->
                namespace_gitmcp_tools(Repo, filter_gitmcp_tools(Tools))
            end}
        || Repo <- moirai_mcp_config:allowed_repos()
    ],
    [Weather | GitMcp].

discover_location(Parent) ->
    Result = case moirai_geoip:lookup() of
        {ok, Location} -> {location, moirai_geoip:context(Location)};
        {error, Reason} -> {location_error, Reason}
    end,
    Parent ! {?MODULE, resource, Result}.

discover_endpoint(Parent, Label, Url, Filter) ->
    Config = #{
        server_url => Url,
        transport => erl_mcp_transport_http_streamable,
        auth => none,
        client_info => #{name => <<"moirai">>, version => <<"0.1.0">>}
    },
    case erl_mcp_client:start_link(Config) of
        {ok, Pid} ->
            discover_tools(Parent, Label, Filter, Pid);
        {error, Reason} ->
            Parent ! {?MODULE, resource,
                {endpoint_error, Label, Reason}}
    end.

discover_tools(Parent, Label, Filter, Pid) ->
    case wait_until_ready(Pid, ?MCP_TIMEOUT_MS) of
        ok ->
            case klotho_mcp:tools_from_client(Pid, ?TOOL_TIMEOUT_MS) of
                {ok, Tools} ->
                    Parent ! {?MODULE, resource,
                        {endpoint, Label, Filter(Tools), Pid}};
                {error, Reason} ->
                    safe_stop_client(Pid),
                    Parent ! {?MODULE, resource,
                        {endpoint_error, Label, Reason}}
            end;
        {error, Reason} ->
            safe_stop_client(Pid),
            Parent ! {?MODULE, resource,
                {endpoint_error, Label, Reason}}
    end.

state_for_chat() ->
    State = refresh_state(),
    case {maps:get(agent, State), maps:get(discovery_pending, State)} of
        {undefined, Pending} when Pending > 0 ->
            io:format("Waiting for ~B background resources...~n", [Pending]),
            Deadline = erlang:monotonic_time(millisecond)
                + ?MCP_TIMEOUT_MS + ?TOOL_TIMEOUT_MS + 1000,
            await_resource_discovery(Deadline);
        _ ->
            State
    end.

await_resource_discovery(Deadline) ->
    State = refresh_state(),
    case maps:get(discovery_pending, State) of
        0 ->
            State;
        _Pending ->
            case erlang:monotonic_time(millisecond) >= Deadline of
                true ->
                    State;
                false ->
                    receive
                    after 100 ->
                        await_resource_discovery(Deadline)
                    end
            end
    end.

refresh_state() ->
    case get(?STATE_KEY) of
        undefined ->
            error(shell_not_started);
        State ->
            Refreshed = drain_resources(State),
            put(?STATE_KEY, Refreshed),
            Refreshed
    end.

drain_resources(State) ->
    receive
        {?MODULE, resource, Resource} ->
            drain_resources(apply_resource(Resource, State))
    after 0 ->
        State
    end.

apply_resource({location, Context}, State) ->
    rebuild_prompt(State#{
        location_context => Context,
        discovery_pending => decrement_pending(State)
    });
apply_resource({location_error, Reason}, State) ->
    add_discovery_error(<<"geoip">>, Reason, State);
apply_resource({endpoint, Label, Tools, Pid}, State) ->
    rebuild_prompt(State#{
        tools => dedup_tools(maps:get(tools, State) ++ Tools),
        clients => [Pid | maps:get(clients, State)],
        weather => maps:get(weather, State) orelse Label =:= <<"weather">>,
        discovery_pending => decrement_pending(State)
    });
apply_resource({endpoint_error, Label, Reason}, State) ->
    add_discovery_error(Label, Reason, State).

add_discovery_error(Label, Reason, State) ->
    State#{
        discovery_pending => decrement_pending(State),
        discovery_errors => [{Label, Reason} |
            maps:get(discovery_errors, State)]
    }.

decrement_pending(State) ->
    max(0, maps:get(discovery_pending, State) - 1).

rebuild_prompt(State) ->
    Location = maps:get(location_context, State),
    Prompt = case maps:get(weather, State) of
        true -> moirai_weather:system_prompt(?BASE_PROMPT, Location);
        false when Location =:= <<>> -> ?BASE_PROMPT;
        false -> <<?BASE_PROMPT/binary, "\n\n", Location/binary>>
    end,
    State#{system_prompt => Prompt}.

teardown_shell() ->
    State = refresh_state(),
    case maps:get(agent, State) of
        undefined -> ok;
        Agent -> safe_stop(Agent)
    end,
    lists:foreach(fun safe_stop_client/1, maps:get(clients, State)),
    lists:foreach(fun(Pid) -> exit(Pid, shutdown) end,
        maps:get(workers, State)),
    erase(?STATE_KEY),
    ok.

restore_shell_ansi(undefined) ->
    application:unset_env(magicbeam, shellbeam_ansi);
restore_shell_ansi({ok, Value}) ->
    application:set_env(magicbeam, shellbeam_ansi, Value).

filter_gitmcp_tools(Tools) ->
    [Tool || #klotho_tool{name = Name} = Tool <- Tools,
             Name =/= <<"fetch_generic_url_content">>].

namespace_gitmcp_tools(Repo, Tools) ->
    RepoName = lists:last(binary:split(Repo, <<"/">>, [global])),
    [Tool#klotho_tool{
        name = <<RepoName/binary, "__", Name/binary>>,
        description = <<"GitMCP ", Repo/binary, ": ", Description/binary>>
     } || #klotho_tool{name = Name, description = Description} = Tool <- Tools].

dedup_tools(Tools) ->
    {_Seen, Result} = lists:foldl(
        fun(#klotho_tool{name = Name} = Tool, {Seen, Acc}) ->
            case maps:is_key(Name, Seen) of
                true -> {Seen, Acc};
                false -> {Seen#{Name => true}, [Tool | Acc]}
            end
        end,
        {#{}, []},
        Tools),
    lists:reverse(Result).

wait_until_ready(Pid, Timeout) ->
    Deadline = erlang:monotonic_time(millisecond) + Timeout,
    wait_until_ready_loop(Pid, Deadline).

wait_until_ready_loop(Pid, Deadline) ->
    case erl_mcp_client:status(Pid) of
        #{state := ready} ->
            ok;
        #{state := failed, last_error := Error} ->
            {error, {client_failed, Error}};
        _ ->
            case erlang:monotonic_time(millisecond) >= Deadline of
                true -> {error, timeout};
                false ->
                    timer:sleep(250),
                    wait_until_ready_loop(Pid, Deadline)
            end
    end.

build_config(Model, Tools, Verbose, SystemPrompt, FirstPrompt) ->
    Base = #{
        llm => #{
            model => Model,
            temperature => 0.0,
            opts => #{timeout => ?LLM_TIMEOUT_MS}
        },
        tools => Tools,
        system_messages => [SystemPrompt],
        user_messages => [FirstPrompt],
        max_steps => ?MAX_STEPS,
        max_turns => infinity,
        max_wall_clock_ms => ?MAX_WALL_CLOCK_MS,
        tool_timeout_ms => ?TOOL_TIMEOUT_MS
    },
    case Verbose of
        true -> Base#{telemetry => fun log_event/1};
        false -> Base
    end.

log_event({tool_calls, Step, Turn, Calls}) ->
    Names = [maps:get(<<"name">>,
        maps:get(<<"function">>, Call, #{}), <<"??">>) || Call <- Calls],
    io:format("  [turn ~B/step ~B] ~ts~n",
        [Turn, Step, lists:join(", ", Names)]);
log_event({step_complete, #klotho_step{step_number = Step,
                                       duration_ms = Duration}}) ->
    io:format("  [step ~B complete, ~Bms]~n", [Step, Duration]);
log_event({done, _Result}) ->
    ok;
log_event({turn_start, _Turn}) ->
    ok;
log_event({turn_end, _Turn}) ->
    ok;
log_event({finished, _FinishReason, _Result}) ->
    ok;
log_event({turn_limit_hit, _TurnsUsed, _MaxTurns}) ->
    ok;
log_event({tool_timeout, _ToolCallId, _TimeoutMs}) ->
    ok;
log_event({caller_died, _Reason}) ->
    ok;
log_event({circuit_open, _Reason}) ->
    ok;
log_event({error, _Reason}) ->
    ok;
log_event(max_steps_exceeded) ->
    ok.

safe_stop(Pid) ->
    try klotho_agent:stop(Pid)
    catch
        exit:noproc -> ok;
        exit:{noproc, _} -> ok
    end.

safe_stop_client(Pid) ->
    try erl_mcp_client:stop(Pid)
    catch
        exit:noproc -> ok;
        exit:{noproc, _} -> ok
    end.

to_binary(Value) when is_binary(Value) -> Value;
to_binary(Value) when is_list(Value) -> unicode:characters_to_binary(Value).
