-module(moirai_gitignore).

-export([load/1, ignored/3]).

-type path_kind() :: file | directory.
-type rule() :: #{
    negated := boolean(),
    directory_only := boolean(),
    exact := term(),
    descendant := term()
}.

-export_type([path_kind/0, rule/0]).

-spec load(file:filename_all()) ->
    {ok, [rule()]} | {error, binary()}.
load(Root) ->
    Path = filename:join(Root, ".gitignore"),
    case file:read_file(Path) of
        {ok, Content} ->
            compile_lines(binary:split(Content, <<"\n">>, [global]), 1, []);
        {error, enoent} ->
            {ok, []};
        {error, Reason} ->
            {error, iolist_to_binary(io_lib:format(
                "could not read ~ts: ~p", [Path, Reason]))}
    end.

-spec ignored(file:filename_all(), path_kind(), [rule()]) -> boolean().
ignored(Path0, Kind, Rules) ->
    Path = normalize_path(Path0),
    path_ignored(Path, Kind, Rules) orelse
        lists:any(
            fun(Parent) -> path_ignored(Parent, directory, Rules) end,
            parent_paths(Path)).

compile_lines([], _LineNumber, Acc) ->
    {ok, lists:reverse(Acc)};
compile_lines([Line | Rest], LineNumber, Acc) ->
    case compile_line(Line) of
        skip ->
            compile_lines(Rest, LineNumber + 1, Acc);
        {ok, Rule} ->
            compile_lines(Rest, LineNumber + 1, [Rule | Acc]);
        {error, Reason} ->
            {error, iolist_to_binary(io_lib:format(
                "invalid .gitignore pattern at line ~B: ~p",
                [LineNumber, Reason]))}
    end.

compile_line(Line0) ->
    Line = string:trim(
        binary_to_list(strip_trailing_cr(Line0)), trailing, " "),
    case Line of
        [] ->
            skip;
        [$# | _] ->
            skip;
        _ ->
            compile_pattern(Line)
    end.

compile_pattern(Line) ->
    {Negated, Pattern0} = case Line of
        [$! | Rest] -> {true, Rest};
        _ -> {false, Line}
    end,
    {DirectoryOnly, Pattern1} = strip_trailing_slash(Pattern0),
    {LeadingSlash, Pattern} = strip_leading_slash(Pattern1),
    case Pattern of
        [] ->
            skip;
        _ ->
            Anchored = LeadingSlash orelse lists:member($/, Pattern),
            case glob_to_regex(Pattern, []) of
                {ok, Body} ->
                    compile_regexes(
                        Body, Anchored, DirectoryOnly, Negated);
                {error, _} = Error ->
                    Error
            end
    end.

compile_regexes(Body, Anchored, DirectoryOnly, Negated) ->
    Prefix = case Anchored of
        true -> "^";
        false -> "(?:^|/)"
    end,
    ExactSource = iolist_to_binary([Prefix, Body, "$"]),
    DescendantSource = iolist_to_binary([Prefix, Body, "/.*$"]),
    case re:compile(ExactSource, [unicode]) of
        {ok, Exact} ->
            case re:compile(DescendantSource, [unicode]) of
                {ok, Descendant} ->
                    {ok, #{
                        negated => Negated,
                        directory_only => DirectoryOnly,
                        exact => Exact,
                        descendant => Descendant
                    }};
                {error, Reason} ->
                    {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

glob_to_regex([], Acc) ->
    {ok, lists:reverse(Acc)};
glob_to_regex([$*, $*, $/ | Rest], Acc) ->
    glob_to_regex(Rest, ["(?:.*/)?" | Acc]);
glob_to_regex([$*, $* | Rest], Acc) ->
    glob_to_regex(Rest, [".*" | Acc]);
glob_to_regex([$* | Rest], Acc) ->
    glob_to_regex(Rest, ["[^/]*" | Acc]);
glob_to_regex([$? | Rest], Acc) ->
    glob_to_regex(Rest, ["[^/]" | Acc]);
glob_to_regex([$[, $] | _Rest], _Acc) ->
    {error, empty_character_class};
glob_to_regex([$[ | Rest], Acc) ->
    case take_character_class(Rest, []) of
        {ok, Class, Tail} ->
            glob_to_regex(Tail, [
                [$[, normalize_character_class(Class), $]] | Acc
            ]);
        {error, _} = Error ->
            Error
    end;
glob_to_regex([$\\, Escaped | Rest], Acc) ->
    glob_to_regex(Rest, [escape_regex(Escaped) | Acc]);
glob_to_regex([$\\], Acc) ->
    glob_to_regex([], [escape_regex($\\) | Acc]);
glob_to_regex([Character | Rest], Acc) ->
    glob_to_regex(Rest, [escape_regex(Character) | Acc]).

take_character_class([], _Acc) ->
    {error, unmatched_character_class};
take_character_class([$] | Rest], Acc) ->
    {ok, lists:reverse(Acc), Rest};
take_character_class([Character | Rest], Acc) ->
    take_character_class(Rest, [Character | Acc]).

normalize_character_class([$! | Rest]) ->
    [$^ | escape_character_class(Rest)];
normalize_character_class([$^ | Rest]) ->
    [$\\, $^ | escape_character_class(Rest)];
normalize_character_class(Class) ->
    escape_character_class(Class).

escape_character_class([]) ->
    [];
escape_character_class([$\\ | Rest]) ->
    [$\\, $\\ | escape_character_class(Rest)];
escape_character_class([$[ | Rest]) ->
    [$\\, $[ | escape_character_class(Rest)];
escape_character_class([Character | Rest]) ->
    [Character | escape_character_class(Rest)].

escape_regex(Character)
        when Character =:= $.;
             Character =:= $^;
             Character =:= $$;
             Character =:= $+;
             Character =:= $(;
             Character =:= $);
             Character =:= 123;
             Character =:= $};
             Character =:= $|;
             Character =:= $\\ ->
    [$\\, Character];
escape_regex(Character) ->
    [Character].

path_ignored(".", _Kind, _Rules) ->
    false;
path_ignored(Path, Kind, Rules) ->
    lists:foldl(
        fun(Rule, State) ->
            case rule_matches(Path, Kind, Rule) of
                true -> not maps:get(negated, Rule);
                false -> State
            end
        end,
        false,
        Rules).

rule_matches(Path, Kind, Rule) ->
    DescendantMatch =
        re:run(Path, maps:get(descendant, Rule), [{capture, none}])
            =:= match,
    ExactMatch =
        re:run(Path, maps:get(exact, Rule), [{capture, none}])
            =:= match,
    DescendantMatch orelse
        (ExactMatch andalso
            (not maps:get(directory_only, Rule) orelse
                Kind =:= directory)).

parent_paths(".") ->
    [];
parent_paths(Path) ->
    parent_paths(filename:split(Path), [], []).

parent_paths([_Last], _Current, Acc) ->
    lists:reverse(Acc);
parent_paths([Part | Rest], [], Acc) ->
    parent_paths(Rest, Part, [Part | Acc]);
parent_paths([Part | Rest], Current, Acc) ->
    Next = filename:join(Current, Part),
    parent_paths(Rest, Next, [Next | Acc]);
parent_paths([], _Current, Acc) ->
    lists:reverse(Acc).

normalize_path(Path) when is_binary(Path) ->
    normalize_path(binary_to_list(Path));
normalize_path(Path) ->
    Parts = [
        Part
        || Part <- filename:split(Path),
           Part =/= ".",
           Part =/= "/"
    ],
    case Parts of
        [] -> ".";
        _ -> filename:join(Parts)
    end.

strip_trailing_cr(<<>>) ->
    <<>>;
strip_trailing_cr(Line) ->
    case binary:last(Line) of
        $\r -> binary:part(Line, 0, byte_size(Line) - 1);
        _ -> Line
    end.

strip_trailing_slash(Pattern) ->
    case lists:reverse(Pattern) of
        [$/ | Rest] -> {true, lists:reverse(Rest)};
        _ -> {false, Pattern}
    end.

strip_leading_slash([$/ | Rest]) ->
    {true, Rest};
strip_leading_slash(Pattern) ->
    {false, Pattern}.
