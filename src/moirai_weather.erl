-module(moirai_weather).

-include_lib("klotho/include/klotho.hrl").

-export([filter_tools/1, system_prompt/2]).

-define(ALLOWED_TOOLS, [
    <<"weather_forecast">>,
    <<"air_quality">>,
    <<"geocoding">>
]).

-spec filter_tools([#klotho_tool{}]) -> [#klotho_tool{}].
filter_tools(Tools) ->
    [Tool || #klotho_tool{name = Name} = Tool <- Tools,
             lists:member(Name, ?ALLOWED_TOOLS)].

-spec system_prompt(binary(), binary()) -> binary().
system_prompt(BasePrompt, LocationContext) ->
    iolist_to_binary([
        BasePrompt,
        "\n\n",
        "Weather tools are available through Open-Meteo. Use geocoding "
        "when the user names a place, weather_forecast for forecasts, "
        "and air_quality for air conditions.\n",
        LocationContext
    ]).
