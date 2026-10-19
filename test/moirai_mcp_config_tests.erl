-module(moirai_mcp_config_tests).
-include_lib("eunit/include/eunit.hrl").

allowed_repos_include_public_stack_test() ->
    Repos = moirai_mcp_config:allowed_repos(),
    ?assertEqual(
        [<<"otakup0pe/erl_openrouter">>,
         <<"otakup0pe/erl_mcp">>,
         <<"otakup0pe/magicbeam">>],
        Repos).

gitmcp_url_builds_correct_url_test() ->
    ?assertEqual(<<"https://gitmcp.io/otakup0pe/erl_mcp">>,
                 moirai_mcp_config:gitmcp_url(<<"otakup0pe/erl_mcp">>)).

validate_repo_allows_known_test() ->
    ?assertEqual(ok, moirai_mcp_config:validate_repo(<<"otakup0pe/erl_openrouter">>)),
    ?assertEqual(ok, moirai_mcp_config:validate_repo(<<"otakup0pe/erl_mcp">>)),
    ?assertEqual(ok, moirai_mcp_config:validate_repo(<<"otakup0pe/magicbeam">>)).

validate_repo_blocks_unknown_test() ->
    ?assertEqual({error, {repo_not_allowed, <<"evil/repo">>}},
                 moirai_mcp_config:validate_repo(<<"evil/repo">>)).

validate_repo_blocks_private_test() ->
    ?assertEqual({error, {repo_not_allowed, <<"otakup0pe/moirai">>}},
                 moirai_mcp_config:validate_repo(<<"otakup0pe/moirai">>)).
