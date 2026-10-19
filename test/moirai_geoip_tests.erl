-module(moirai_geoip_tests).

-include_lib("eunit/include/eunit.hrl").

provider_response_decode_test() ->
    Body = <<"{\"ip\":\"8.8.8.8\",\"success\":true,"
             "\"country\":\"United States\",\"region\":\"California\","
             "\"city\":\"San Jose\",\"latitude\":37.3393939,"
             "\"longitude\":-121.8949553,"
             "\"timezone\":{\"id\":\"America/Los_Angeles\"}}">>,
    {ok, Location} = moirai_geoip:decode(Body),
    ?assertEqual(<<"San Jose">>, maps:get(city, Location)),
    ?assertEqual(37.3393939, maps:get(latitude, Location)),
    ?assertEqual(<<"America/Los_Angeles">>, maps:get(timezone, Location)).

provider_error_decode_test() ->
    Body = <<"{\"success\":false,\"message\":\"Reserved range\"}">>,
    ?assertEqual(
        {error, {provider_error, <<"Reserved range">>}},
        moirai_geoip:decode(Body)).

invalid_location_fields_test() ->
    Body = <<"{\"success\":true,\"latitude\":null,\"longitude\":1.0}">>,
    ?assertEqual({error, invalid_response}, moirai_geoip:decode(Body)).

location_context_marks_geoip_as_approximate_test() ->
    Location = #{
        city => <<"San Jose">>,
        region => <<"California">>,
        country => <<"United States">>,
        latitude => 37.3393939,
        longitude => -121.8949553,
        timezone => <<"America/Los_Angeles">>
    },
    Context = moirai_geoip:context(Location),
    ?assertMatch({_, _}, binary:match(Context, <<"approximate">>)),
    ?assertMatch({_, _}, binary:match(Context, <<"37.3394">>)),
    ?assertMatch({_, _}, binary:match(Context, <<"-121.8950">>)).
