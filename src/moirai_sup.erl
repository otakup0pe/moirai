-module(moirai_sup).
-behaviour(supervisor).

%% @doc Top-level supervisor for moirai.
%%
%% Phase 1 has no moirai-specific long-lived processes; the
%% supervisor exists as the OTP application's root and as a place
%% to grow Phase 2's children (the in-process moirai_fs_server
%% and an erl_mcp_client wired to it via local transport).
%%
%% The openrouter_client is started by erl_openrouter's own
%% application supervision tree (openrouter_sup), not here.
%% erl_openrouter is in moirai.app.src's `applications' list, so
%% OTP boots it before moirai. Starting openrouter_client a
%% second time from this supervisor would collide on the
%% registered name.
%%
%% klotho_agent instances are NOT supervised here. They are
%% per-task one-shots started directly by moirai_demo (or any
%% consumer) via klotho_agent:start_link/1. When the task
%% completes, the agent process stops. This matches klotho's
%% design: workers are ephemeral, supervision is the consumer's
%% concern.

-export([start_link/0]).
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    SupFlags = #{
        strategy => one_for_one,
        intensity => 5,
        period => 60
    },
    {ok, {SupFlags, []}}.
