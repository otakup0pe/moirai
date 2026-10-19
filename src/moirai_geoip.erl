-module(moirai_geoip).

-export([lookup/0, decode/1, context/1]).

-define(DEFAULT_URL, "https://ipwho.is/").
-define(TIMEOUT_MS, 5000).

-type location() :: #{
    city := binary(),
    region := binary(),
    country := binary(),
    latitude := float(),
    longitude := float(),
    timezone := binary()
}.
-type lookup_error() ::
    invalid_json
    | invalid_response
    | {http_status, integer()}
    | {provider_error, binary()}
    | {transport_error, term()}.

-spec lookup() -> {ok, location()} | {error, lookup_error()}.
lookup() ->
    Url = os:getenv("MOIRAI_GEOIP_URL", ?DEFAULT_URL),
    Request = {Url, [{"accept", "application/json"}]},
    HttpOptions = [{timeout, ?TIMEOUT_MS}],
    Options = [{body_format, binary}],
    case httpc:request(get, Request, HttpOptions, Options) of
        {ok, {{_Version, 200, _Reason}, _Headers, Body}} ->
            decode(Body);
        {ok, {{_Version, Status, _Reason}, _Headers, _Body}} ->
            {error, {http_status, Status}};
        {error, Reason} ->
            {error, {transport_error, Reason}}
    end.

-spec decode(binary()) -> {ok, location()} | {error, lookup_error()}.
decode(Body) ->
    try json:decode(Body) of
        #{
            <<"success">> := true,
            <<"latitude">> := Latitude,
            <<"longitude">> := Longitude
        } = Data when is_number(Latitude), is_number(Longitude) ->
            City = maps:get(<<"city">>, Data, <<>>),
            Region = maps:get(<<"region">>, Data, <<>>),
            Country = maps:get(<<"country">>, Data, <<>>),
            Timezone = timezone_id(maps:get(<<"timezone">>, Data, #{})),
            case is_binary(City)
                    andalso is_binary(Region)
                    andalso is_binary(Country) of
                true ->
                    {ok, #{
                        city => City,
                        region => Region,
                        country => Country,
                        latitude => float(Latitude),
                        longitude => float(Longitude),
                        timezone => Timezone
                    }};
                false ->
                    {error, invalid_response}
            end;
        #{<<"success">> := false} = Data ->
            case maps:get(
                    <<"message">>, Data, <<"unknown provider error">>) of
                Message when is_binary(Message) ->
                    {error, {provider_error, Message}};
                _ ->
                    {error, invalid_response}
            end;
        _ ->
            {error, invalid_response}
    catch
        error:unexpected_end ->
            {error, invalid_json};
        error:{invalid_byte, _} ->
            {error, invalid_json};
        error:{unexpected_sequence, _} ->
            {error, invalid_json}
    end.

-spec context(location()) -> binary().
context(Location) ->
    iolist_to_binary(io_lib:format(
        "The user's approximate GeoIP location is ~ts, ~ts, ~ts "
        "(~.4f, ~.4f; timezone ~ts). Treat this as approximate and "
        "ask before assuming it is the location they mean.",
        [
            maps:get(city, Location, <<>>),
            maps:get(region, Location, <<>>),
            maps:get(country, Location, <<>>),
            maps:get(latitude, Location),
            maps:get(longitude, Location),
            maps:get(timezone, Location, <<>>)
        ])).

timezone_id(#{<<"id">> := Id}) when is_binary(Id) -> Id;
timezone_id(_) -> <<>>.
