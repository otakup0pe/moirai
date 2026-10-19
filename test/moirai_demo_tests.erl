-module(moirai_demo_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("klotho/include/klotho.hrl").

safe_stop_dead_process_test() ->
    {Pid, Ref} = spawn_monitor(fun() -> ok end),
    receive
        {'DOWN', Ref, process, Pid, normal} -> ok
    after 1000 ->
        error(process_did_not_stop)
    end,
    ?assertEqual(ok, moirai:safe_stop(Pid)).

llm_request_timeout_stays_below_client_deadline_test() ->
    Config = moirai:build_config(
        <<"test/model">>, [], false, <<"system">>, <<"user">>),
    LlmOpts = maps:get(opts, maps:get(llm, Config)),
    ?assertEqual(60000, maps:get(timeout, LlmOpts)).

banner_names_the_assembled_stack_test() ->
    Banner = moirai:banner(),
    ?assertMatch({_, _}, binary:match(Banner, <<"erl_openrouter">>)),
    ?assertMatch({_, _}, binary:match(Banner, <<"magicbeam">>)).

shellbeam_supports_custom_banner_test() ->
    {module, shellbeam} = code:ensure_loaded(shellbeam),
    ?assert(erlang:function_exported(shellbeam, start_shell, 3)).

quit_is_a_shell_command_test() ->
    Commands = moirai_shell:commands(),
    ?assertMatch({["quit"], _, _}, lists:keyfind(["quit"], 1, Commands)).

shell_status_is_human_readable_test() ->
    Text = iolist_to_binary(moirai_shell:format_status(#{
        model => <<"test/model">>,
        tools => [<<"one">>, <<"two">>],
        discovery_pending => 2,
        discovery_errors => [
            {<<"geoip">>, timeout},
            {<<"weather">>, unavailable}
        ],
        agent_started => true
    })),
    ?assertMatch({_, _}, binary:match(Text, <<"Model: test/model">>)),
    ?assertMatch({_, _}, binary:match(Text, <<"Conversation: active">>)),
    ?assertMatch({_, _}, binary:match(Text, <<"Resources: connecting (2 pending)">>)),
    ?assertMatch({_, _}, binary:match(Text, <<"Tools: 2 available">>)),
    ?assertMatch({_, _}, binary:match(Text, <<"Warnings: geoip, weather">>)),
    ?assertEqual(nomatch, binary:match(Text, <<"#{">>)).

assistant_reply_has_conversation_boundaries_test() ->
    {ok, _} = application:ensure_all_started(magicbeam),
    {Format, Args} = moirai_shell:format_success(<<"hello">>, 2, 31),
    Text = iolist_to_binary(io_lib:format(Format, Args)),
    ?assertEqual(<<"\n">>, binary:part(Text, 0, 1)),
    ?assertMatch({_, _}, binary:match(Text, <<"moirai">>)),
    ?assertMatch({_, _}, binary:match(Text, <<"\nhello\n">>)),
    ?assertMatch({_, _}, binary:match(Text, <<"[2 steps, 31ms]">>)).

ignored_paths_are_hidden_without_git_metadata_test() ->
    with_filesystem_tool_tree(fun(Root) ->
        ?assertNot(filelib:is_dir(filename:join(Root, ".git"))),
        #klotho_tool{handler = ListDirectory} =
            moirai_tools:list_directory_tool(Root),
        {ok, Entries} = ListDirectory(#{<<"path">> => <<".">>}),
        ?assertEqual(nomatch, binary:match(Entries, <<"_build/">>)),
        ?assertMatch({_, _}, binary:match(Entries, <<"visible.txt">>)),
        #klotho_tool{handler = ReadFile} =
            moirai_tools:read_file_tool(Root),
        {error, Error} =
            ReadFile(#{<<"path">> => <<"_build/hidden.txt">>}),
        ?assertMatch(
            {_, _},
            binary:match(Error, <<"excluded by .gitignore">>)),
        {ok, <<"visible">>} =
            ReadFile(#{<<"path">> => <<"visible.txt">>}),
        {error, TraversalError} =
            ReadFile(#{<<"path">> => <<"../etc/passwd">>}),
        ?assertMatch(
            {_, _},
            binary:match(TraversalError, <<"traversal blocked">>))
    end).

with_filesystem_tool_tree(Fun) ->
    Root = filename:join(
        "/tmp",
        "moirai_tools_" ++
            integer_to_list(erlang:unique_integer([positive]))),
    ok = filelib:ensure_dir(filename:join(Root, "_build/placeholder")),
    ok = file:write_file(
        filename:join(Root, ".gitignore"),
        <<"_build/\n">>),
    ok = file:write_file(
        filename:join(Root, "_build/hidden.txt"),
        <<"hidden">>),
    ok = file:write_file(
        filename:join(Root, "visible.txt"),
        <<"visible">>),
    try
        Fun(Root)
    after
        ok = file:del_dir_r(Root)
    end.

gitmcp_tools_are_repo_namespaced_test() ->
    Tool = moirai_tools:read_file_tool("."),
    [Namespaced] = moirai:namespace_gitmcp_tools(
        <<"otakup0pe/erl_mcp">>, [Tool]),
    ?assertEqual(<<"erl_mcp__read_file">>, Namespaced#klotho_tool.name),
    ?assertMatch(
        {_, _},
        binary:match(
            Namespaced#klotho_tool.description,
            <<"GitMCP otakup0pe/erl_mcp">>)).

weather_tool_filter_test() ->
    Tools = [
        #klotho_tool{name = <<"weather_forecast">>},
        #klotho_tool{name = <<"air_quality">>},
        #klotho_tool{name = <<"weather_archive">>}
    ],
    Filtered = moirai_weather:filter_tools(Tools),
    ?assertEqual(
        [<<"weather_forecast">>, <<"air_quality">>],
        [Tool#klotho_tool.name || Tool <- Filtered]).

weather_system_prompt_includes_location_test() ->
    Prompt = moirai_weather:system_prompt(
        <<"Base prompt.">>, <<"Approximate location: Oakland.">>),
    ?assertMatch({_, _}, binary:match(Prompt, <<"weather_forecast">>)),
    ?assertMatch({_, _}, binary:match(Prompt, <<"Approximate location: Oakland.">>)).
