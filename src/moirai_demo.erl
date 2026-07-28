-module(moirai_demo).

%% @doc Interactive multi-turn demo.
%%
%% Starts a single klotho_agent with filesystem tools pointed at
%% priv/demo_files/, then loops on stdin. Each line becomes a
%% resume/2 call. On EOF or "quit"/"exit", injects a summary
%% prompt via one final resume/2 before stopping the agent.
%%
%% Phase 2 adds optional MCP support: pass `mcp_repos' to wire
%% gitmcp.io documentation tools alongside the local filesystem
%% tools in the same agent.
%%
%% Prerequisites:
%%   - moirai application running (application:ensure_all_started(moirai))
%%   - OPENROUTER_API_KEY set in environment

-include_lib("klotho/include/klotho.hrl").

-export([run/0, run/1, run_with_mcp/0]).

-define(DEMO_MODEL, <<"google/gemma-4-26b-a4b-it:free">>).
-define(DEMO_MAX_STEPS, 10).
-define(DEMO_MAX_WALL_CLOCK_MS, 120000).
-define(DEMO_TOOL_TIMEOUT_MS, 30000).
-define(MCP_TOOL_TIMEOUT_MS, 30000).
-define(MCP_CONNECT_TIMEOUT_MS, 10000).

-define(SYSTEM_PROMPT, <<"You are a helpful assistant that can explore "
    "a small project directory using the list_directory and read_file "
    "tools. When asked about the project, use these tools to find and "
    "read relevant files before answering. Be concise.">>).

-define(SYSTEM_PROMPT_MCP, <<"You are a helpful assistant that can explore "
    "a small project directory using the list_directory and read_file "
    "tools, and can also search GitHub documentation for Erlang/OTP "
    "agent stack projects (moirai, klotho, erl_mcp, erl_openrouter) "
    "using the fetch and search documentation tools. Be concise.">>).

-define(SUMMARY_PROMPT, <<"Please provide a brief summary of our "
    "conversation: what was asked, what you found, and any key "
    "takeaways. Keep it to a few sentences.">>).

%% @doc Run the demo with defaults.
run() ->
    run(#{}).

%% @doc Run the demo with all allowed gitmcp.io repos enabled.
run_with_mcp() ->
    run(#{mcp_repos => moirai_mcp_config:allowed_repos()}).

%% @doc Run the demo with options.
%%
%% Options:
%%   model     => binary()   -- LLM model (default: DEMO_MODEL)
%%   prompt    => string()   -- single prompt for one-shot mode
%%   verbose   => boolean()  -- print step trace (default: true)
%%   sandbox   => string()   -- path to sandbox root (default: priv/demo_files)
%%   mcp_repos => [binary()] -- gitmcp.io repos to connect (default: [])
run(Opts) when is_map(Opts) ->
    Model = maps:get(model, Opts, ?DEMO_MODEL),
    Verbose = maps:get(verbose, Opts, true),
    SandboxRoot = maps:get(sandbox, Opts, default_sandbox()),
    LocalTools = [
        moirai_tools:list_directory_tool(SandboxRoot),
        moirai_tools:read_file_tool(SandboxRoot)
    ],
    McpRepos = maps:get(mcp_repos, Opts, []),
    case McpRepos of
        [] ->
            %% No MCP -- original path
            run_with_tools(Opts, Model, LocalTools, Verbose, ?SYSTEM_PROMPT);
        Repos ->
            case start_mcp_clients(Repos) of
                {ok, Clients} ->
                    case collect_mcp_tools(Clients) of
                        {ok, McpTools} ->
                            AllTools = LocalTools ++ McpTools,
                            Result = run_with_tools(
                                Opts, Model, AllTools, Verbose,
                                ?SYSTEM_PROMPT_MCP),
                            stop_mcp_clients(Clients),
                            Result;
                        {error, Reason} ->
                            io:format(standard_error,
                                "WARNING: MCP tool discovery failed (~p), "
                                "continuing with local tools only~n",
                                [Reason]),
                            stop_mcp_clients(Clients),
                            run_with_tools(
                                Opts, Model, LocalTools, Verbose,
                                ?SYSTEM_PROMPT)
                    end;
                {error, Reason} ->
                    io:format(standard_error,
                        "WARNING: MCP client start failed (~p), "
                        "continuing with local tools only~n",
                        [Reason]),
                    run_with_tools(
                        Opts, Model, LocalTools, Verbose,
                        ?SYSTEM_PROMPT)
            end
    end.

%%--------------------------------------------------------------------
%% Dispatch to one-shot or interactive
%%--------------------------------------------------------------------

run_with_tools(Opts, Model, Tools, Verbose, SystemPrompt) ->
    case maps:get(prompt, Opts, undefined) of
        undefined ->
            interactive(Model, Tools, Verbose, SystemPrompt);
        Prompt ->
            one_shot(Model, Tools, Verbose, SystemPrompt, to_binary(Prompt))
    end.

%%--------------------------------------------------------------------
%% One-shot mode (for integration tests and scripted use)
%%--------------------------------------------------------------------

one_shot(Model, Tools, Verbose, SystemPrompt, Prompt) ->
    Config = build_config(Model, Tools, Verbose, SystemPrompt, Prompt),
    {ok, Pid} = klotho_agent:start_link(Config),
    unlink(Pid),
    Timeout = ?DEMO_MAX_WALL_CLOCK_MS + 5000,
    Result = klotho_agent:run(Pid, Timeout),
    klotho_agent:stop(Pid),
    case Result of
        {ok, R} ->
            print_result(R),
            {ok, R};
        {error, Reason} ->
            print_error(Reason),
            {error, Reason}
    end.

%%--------------------------------------------------------------------
%% Interactive multi-turn mode
%%--------------------------------------------------------------------

interactive(Model, Tools, Verbose, SystemPrompt) ->
    print_banner(Model, Tools),
    FirstPrompt = read_line(),
    case FirstPrompt of
        eof -> ok;
        quit -> ok;
        Line ->
            Config = build_config(Model, Tools, Verbose, SystemPrompt, Line),
            {ok, Pid} = klotho_agent:start_link(Config),
            unlink(Pid),
            Timeout = ?DEMO_MAX_WALL_CLOCK_MS + 5000,
            case klotho_agent:run(Pid, Timeout) of
                {ok, #klotho_result{status = ok} = R1} ->
                    print_assistant(R1),
                    interactive_loop(Pid, Timeout);
                {ok, R1} ->
                    print_result(R1);
                {error, Reason} ->
                    print_error(Reason)
            end
    end.

interactive_loop(Pid, Timeout) ->
    Line = read_line(),
    case Line of
        eof ->
            summarize_and_stop(Pid);
        quit ->
            summarize_and_stop(Pid);
        UserMsg ->
            case klotho_agent:resume(Pid, UserMsg) of
                {ok, #klotho_result{status = ok} = Result} ->
                    print_assistant(Result),
                    interactive_loop(Pid, Timeout);
                {ok, Result} ->
                    print_result(Result);
                {error, Reason} ->
                    print_error(Reason),
                    safe_stop(Pid)
            end
    end.

summarize_and_stop(Pid) ->
    io:format("~n--- Generating summary ---~n~n"),
    case klotho_agent:resume(Pid, ?SUMMARY_PROMPT) of
        {ok, Result} ->
            io:format("~s~n", [fmt_msg(Result#klotho_result.message)]);
        {error, Reason} ->
            print_error(Reason)
    end,
    klotho_agent:stop(Pid).

%%--------------------------------------------------------------------
%% MCP client lifecycle
%%--------------------------------------------------------------------

-spec start_mcp_clients([binary()]) ->
    {ok, [{pid(), binary()}]} | {error, term()}.
start_mcp_clients(Repos) ->
    start_mcp_clients(Repos, []).

start_mcp_clients([], Acc) ->
    {ok, lists:reverse(Acc)};
start_mcp_clients([Repo | Rest], Acc) ->
    case moirai_mcp_config:validate_repo(Repo) of
        ok ->
            Url = moirai_mcp_config:gitmcp_url(Repo),
            Config = #{
                server_url => Url,
                transport => erl_mcp_transport_http_streamable,
                auth => none,
                client_info => #{
                    name => <<"moirai">>,
                    version => <<"0.1.0">>
                }
            },
            case erl_mcp_client:start_link(Config) of
                {ok, Pid} ->
                    unlink(Pid),
                    start_mcp_clients(Rest, [{Pid, Repo} | Acc]);
                {error, Reason} ->
                    stop_mcp_clients(Acc),
                    {error, {client_start_failed, Repo, Reason}}
            end;
        {error, _} = Err ->
            stop_mcp_clients(Acc),
            Err
    end.

-spec stop_mcp_clients([{pid(), binary()}]) -> ok.
stop_mcp_clients(Clients) ->
    lists:foreach(fun({Pid, _Repo}) -> safe_stop_client(Pid) end, Clients),
    ok.

safe_stop_client(Pid) ->
    try erl_mcp_client:stop(Pid)
    catch exit:{noproc, _} -> ok
    end.

-spec collect_mcp_tools([{pid(), binary()}]) ->
    {ok, [#klotho_tool{}]} | {error, term()}.
collect_mcp_tools(Clients) ->
    collect_mcp_tools(Clients, []).

collect_mcp_tools([], Acc) ->
    All = lists:flatten(lists:reverse(Acc)),
    {ok, dedup_tools(filter_blocked_tools(All))};
collect_mcp_tools([{Pid, Repo} | Rest], Acc) ->
    case wait_until_ready(Pid, ?MCP_CONNECT_TIMEOUT_MS) of
        ok ->
            case klotho_mcp:tools_from_client(Pid, ?MCP_TOOL_TIMEOUT_MS) of
                {ok, Tools} ->
                    collect_mcp_tools(Rest, [Tools | Acc]);
                {error, Reason} ->
                    {error, {tool_discovery_failed, Repo, Reason}}
            end;
        {error, Reason} ->
            {error, {client_not_ready, Repo, Reason}}
    end.

%% @private Filter out tools that should not be exposed in the demo.
-spec filter_blocked_tools([#klotho_tool{}]) -> [#klotho_tool{}].
filter_blocked_tools(Tools) ->
    [T || #klotho_tool{name = Name} = T <- Tools,
          not is_blocked_tool(Name)].

is_blocked_tool(<<"fetch_generic_url_content">>) -> true;
is_blocked_tool(_) -> false.

%% @private Remove duplicate tools by name, keeping first occurrence.
-spec dedup_tools([#klotho_tool{}]) -> [#klotho_tool{}].
dedup_tools(Tools) ->
    dedup_tools(Tools, #{}, []).

dedup_tools([], _Seen, Acc) ->
    lists:reverse(Acc);
dedup_tools([#klotho_tool{name = Name} = T | Rest], Seen, Acc) ->
    case maps:is_key(Name, Seen) of
        true -> dedup_tools(Rest, Seen, Acc);
        false -> dedup_tools(Rest, Seen#{Name => true}, [T | Acc])
    end.

%% @private Poll erl_mcp_client status until ready or timeout.
-spec wait_until_ready(pid(), timeout()) -> ok | {error, term()}.
wait_until_ready(Pid, Timeout) ->
    Deadline = erlang:monotonic_time(millisecond) + Timeout,
    wait_until_ready_loop(Pid, Deadline).

wait_until_ready_loop(Pid, Deadline) ->
    case erl_mcp_client:status(Pid) of
        #{state := ready} ->
            ok;
        #{state := failed, last_error := Err} ->
            {error, {client_failed, Err}};
        _ ->
            Now = erlang:monotonic_time(millisecond),
            case Now >= Deadline of
                true ->
                    {error, timeout};
                false ->
                    timer:sleep(250),
                    wait_until_ready_loop(Pid, Deadline)
            end
    end.

%%--------------------------------------------------------------------
%% Config
%%--------------------------------------------------------------------

build_config(Model, Tools, Verbose, SystemPrompt, FirstPrompt) ->
    Base = #{
        llm => #{model => Model, temperature => 0.0},
        tools => Tools,
        system_messages => [SystemPrompt],
        user_messages => [FirstPrompt],
        max_steps => ?DEMO_MAX_STEPS,
        max_turns => infinity,
        max_wall_clock_ms => ?DEMO_MAX_WALL_CLOCK_MS,
        tool_timeout_ms => ?DEMO_TOOL_TIMEOUT_MS
    },
    case Verbose of
        true -> Base#{telemetry => fun log_event/1};
        false -> Base
    end.

%%--------------------------------------------------------------------
%% I/O helpers
%%--------------------------------------------------------------------

read_line() ->
    case io:get_line("moirai> ") of
        eof -> eof;
        {error, _} -> eof;
        Line ->
            Trimmed = string:trim(Line),
            case string:lowercase(Trimmed) of
                "quit" -> quit;
                "exit" -> quit;
                "" -> read_line();
                _ -> to_binary(Trimmed)
            end
    end.

print_banner(Model, Tools) ->
    ToolNames = [Name || #klotho_tool{name = Name} <- Tools],
    io:format("~n=== moirai interactive demo ===~n"),
    io:format("Model: ~s~n", [Model]),
    io:format("Tools: ~s~n", [lists:join(", ", ToolNames)]),
    io:format("Type a message, or 'quit' to summarize and exit.~n~n").

print_assistant(#klotho_result{message = Msg, total_steps = Steps,
                                elapsed_ms = Elapsed}) ->
    io:format("~n~s~n", [fmt_msg(Msg)]),
    io:format("  [~B steps, ~Bms]~n~n", [Steps, Elapsed]).

print_result(#klotho_result{status = ok} = R) ->
    print_assistant(R);
print_result(#klotho_result{status = Status, message = Msg, error = Error,
                             total_steps = Steps, elapsed_ms = Elapsed}) ->
    io:format("~n[~p] ~s~n", [Status, fmt_msg(Msg)]),
    case Error of
        undefined -> ok;
        _ -> io:format("  reason: ~p~n", [Error])
    end,
    io:format("  [~B steps, ~Bms]~n~n", [Steps, Elapsed]).

print_error(Reason) ->
    io:format(standard_error, "Error: ~p~n", [Reason]).

fmt_msg(undefined) -> <<"<no message>">>;
fmt_msg(null) -> <<"<no message>">>;
fmt_msg(<<>>) -> <<"<no message>">>;
fmt_msg(Msg) when is_binary(Msg) -> Msg;
fmt_msg(Msg) -> iolist_to_binary(io_lib:format("~p", [Msg])).

log_event({tool_calls, Step, Turn, TCs}) ->
    Names = [maps:get(<<"name">>,
                maps:get(<<"function">>, TC, #{}), <<"??">>)
             || TC <- TCs],
    io:format("  [turn ~B/step ~B] tool calls: ~s~n",
              [Turn, Step, lists:join(", ", Names)]);
log_event({step_complete, #klotho_step{step_number = N, duration_ms = D}}) ->
    io:format("  [step ~B complete, ~Bms]~n", [N, D]);
log_event({done, _Result}) ->
    ok;
log_event(_) ->
    ok.

%%--------------------------------------------------------------------
%% Internal
%%--------------------------------------------------------------------

safe_stop(Pid) ->
    try klotho_agent:stop(Pid)
    catch exit:{noproc, _} -> ok
    end.

default_sandbox() ->
    case code:priv_dir(moirai) of
        {error, _} ->
            filename:join([filename:absname(""), "priv", "demo_files"]);
        PrivDir ->
            filename:join(PrivDir, "demo_files")
    end.

to_binary(S) when is_binary(S) -> S;
to_binary(S) when is_list(S) -> list_to_binary(S).
