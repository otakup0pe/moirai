-module(moirai_app).
-behaviour(application).

%% @doc OTP application callback for moirai.

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    moirai_sup:start_link().

stop(_State) ->
    ok.
