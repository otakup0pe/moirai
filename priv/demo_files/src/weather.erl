-module(weather).
-export([forecast/1]).

forecast(Location) ->
    case Location of
        <<"london">> -> #{temp => 12, condition => <<"cloudy">>};
        <<"tokyo">>  -> #{temp => 24, condition => <<"sunny">>};
        <<"oslo">>   -> #{temp => -3, condition => <<"snow">>};
        _            -> #{temp => 20, condition => <<"unknown">>}
    end.
