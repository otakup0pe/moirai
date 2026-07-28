-module(moirai_mcp_config).

%% @doc Guardrail module for gitmcp.io access.
%%
%% Hardcodes the set of GitHub repos that moirai is allowed to
%% query through gitmcp.io. Prevents the demo agent from reaching
%% arbitrary repositories.

-export([allowed_repos/0, gitmcp_url/1, validate_repo/1]).

%% @doc Return the list of allowed GitHub repos for gitmcp.io access.
-spec allowed_repos() -> [binary()].
allowed_repos() ->
    [<<"otakup0pe/erl_openrouter">>,
     <<"otakup0pe/erl_mcp">>].

%% @doc Build the gitmcp.io MCP endpoint URL for a repo.
%% Repo must be in "owner/name" format.
-spec gitmcp_url(binary()) -> binary().
gitmcp_url(Repo) ->
    <<"https://gitmcp.io/", Repo/binary>>.

%% @doc Validate that a repo is in the allow-list.
-spec validate_repo(binary()) -> ok | {error, {repo_not_allowed, binary()}}.
validate_repo(Repo) ->
    case lists:member(Repo, allowed_repos()) of
        true -> ok;
        false -> {error, {repo_not_allowed, Repo}}
    end.
