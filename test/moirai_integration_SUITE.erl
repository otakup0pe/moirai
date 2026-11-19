-module(moirai_integration_SUITE).

%% @doc Integration test suite for moirai.
%%
%% Exercises the full end-to-end path: moirai builds a klotho agent
%% config with filesystem tools pointed at the real source checkout,
%% runs a real LLM call through erl_openrouter, and verifies the agent
%% completes successfully.
%%
%% moirai_runs_to_stop requires OPENROUTER_API_KEY in the
%% environment. mcp_tool_discovery requires network access to
%% gitmcp.io. Both skip automatically when prerequisites are
%% not met.
%%
%% Run manually:
%%   OPENROUTER_API_KEY=sk-... rebar3 ct --suite moirai_integration_SUITE

-include_lib("common_test/include/ct.hrl").
-include_lib("klotho/include/klotho.hrl").

-export([all/0, groups/0,
         init_per_suite/1, end_per_suite/1,
         init_per_group/2, end_per_group/2]).
-export([moirai_runs_to_stop/1, mcp_tool_discovery/1]).

all() ->
    [{group, llm_tests}, {group, mcp_tests}].

groups() ->
    [{llm_tests, [], [moirai_runs_to_stop]},
     {mcp_tests, [], [mcp_tool_discovery]}].

init_per_suite(Config) ->
    {ok, _Apps} = application:ensure_all_started(moirai),
    Config.

end_per_suite(_Config) ->
    application:stop(moirai),
    ok.

init_per_group(llm_tests, Config) ->
    case os:getenv("OPENROUTER_API_KEY") of
        false ->
            {skip, "OPENROUTER_API_KEY not set"};
        "" ->
            {skip, "OPENROUTER_API_KEY is empty"};
        _Key ->
            Config
    end;
init_per_group(mcp_tests, Config) ->
    Config;
init_per_group(_Group, Config) ->
    Config.

end_per_group(_Group, _Config) ->
    ok.

%% @doc Verify that Moirai can inspect its own checkout.
moirai_runs_to_stop(_Config) ->
    Prompt = <<"List the files in the project root using the "
               "list_directory tool, then tell me what you found.">>,
    Result = moirai:run(#{prompt => Prompt, verbose => false}),
    ct:pal("Moirai result: ~p", [Result]),
    case Result of
        {ok, #klotho_result{status = ok}} ->
            ok;
        {ok, #klotho_result{status = Status, error = Reason}} ->
            ct:fail({demo_failed, Status, Reason});
        {error, Reason} ->
            ct:fail({demo_failed, Reason})
    end.

%% @doc Verify that MCP tool discovery works against gitmcp.io.
%%
%% Starts an erl_mcp_client for an allow-listed repository,
%% calls klotho_mcp:tools_from_client/2, and asserts at least one
%% tool is returned. Skips if gitmcp.io is unreachable.
mcp_tool_discovery(_Config) ->
    Url = moirai_mcp_config:gitmcp_url(<<"otakup0pe/magicbeam">>),
    ClientConfig = #{
        server_url => Url,
        transport => erl_mcp_transport_http_streamable,
        auth => none,
        client_info => #{name => <<"moirai-test">>, version => moirai:version()}
    },
    case erl_mcp_client:start_link(ClientConfig) of
        {ok, Pid} ->
            unlink(Pid),
            try
                case wait_for_client(Pid, 15000) of
                    {error, WaitErr} ->
                        ct:pal("Client not ready: ~p", [WaitErr]),
                        {skip, "gitmcp.io handshake failed"};
                    ok ->
                        {ok, Tools} =
                            klotho_mcp:tools_from_client(Pid, 30000),
                        ct:pal("Discovered ~B tools from gitmcp.io",
                            [length(Tools)]),
                        true = length(Tools) > 0,
                        Names = [T#klotho_tool.name || T <- Tools],
                        ct:pal("Tool names: ~p", [Names]),
                        ok
                end
            after
                safe_stop_client(Pid)
            end;
        {error, Reason} ->
            ct:pal("Cannot connect to gitmcp.io: ~p", [Reason]),
            {skip, "Cannot connect to gitmcp.io"}
    end.

%% @private Poll erl_mcp_client until ready or timeout.
wait_for_client(Pid, Timeout) ->
    Deadline = erlang:monotonic_time(millisecond) + Timeout,
    wait_for_client_loop(Pid, Deadline).

wait_for_client_loop(Pid, Deadline) ->
    case client_status(Pid) of
        #{state := ready} ->
            ok;
        #{state := failed, last_error := Err} ->
            {error, {client_failed, Err}};
        _ ->
            Now = erlang:monotonic_time(millisecond),
            case Now >= Deadline of
                true -> {error, timeout};
                false ->
                    timer:sleep(100),
                    wait_for_client_loop(Pid, Deadline)
            end
    end.

client_status(Pid) ->
    try erl_mcp_client:status(Pid)
    catch
        exit:noproc -> #{state => failed, last_error => noproc};
        exit:{noproc, _} -> #{state => failed, last_error => noproc}
    end.

safe_stop_client(Pid) ->
    try erl_mcp_client:stop(Pid)
    catch
        exit:noproc -> ok;
        exit:{noproc, _} -> ok
    end.
