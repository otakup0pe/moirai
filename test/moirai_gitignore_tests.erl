-module(moirai_gitignore_tests).

-include_lib("eunit/include/eunit.hrl").

common_patterns_work_without_git_metadata_test() ->
    with_temp_tree(fun(Root) ->
        ok = file:write_file(
            filename:join(Root, ".gitignore"),
            <<"_build/\n"
              "*.beam\n"
              "/root-only.txt\n"
              "nested/*.tmp\n"
              "!important.beam\n">>),
        {ok, Rules} = moirai_gitignore:load(Root),
        ?assert(moirai_gitignore:ignored("_build", directory, Rules)),
        ?assert(moirai_gitignore:ignored("_build/cache/file", file, Rules)),
        ?assert(moirai_gitignore:ignored("nested/module.beam", file, Rules)),
        ?assert(moirai_gitignore:ignored("root-only.txt", file, Rules)),
        ?assertNot(moirai_gitignore:ignored(
            "nested/root-only.txt", file, Rules)),
        ?assert(moirai_gitignore:ignored("nested/cache.tmp", file, Rules)),
        ?assertNot(moirai_gitignore:ignored("other/cache.tmp", file, Rules)),
        ?assertNot(moirai_gitignore:ignored("important.beam", file, Rules))
    end).

negation_cannot_reinclude_a_file_below_ignored_parent_test() ->
    with_temp_tree(fun(Root) ->
        ok = file:write_file(
            filename:join(Root, ".gitignore"),
            <<"private/\n!private/public.txt\n">>),
        {ok, Rules} = moirai_gitignore:load(Root),
        ?assert(moirai_gitignore:ignored(
            "private/public.txt", file, Rules))
    end).

missing_gitignore_means_everything_is_visible_test() ->
    with_temp_tree(fun(Root) ->
        {ok, Rules} = moirai_gitignore:load(Root),
        ?assertNot(moirai_gitignore:ignored("anything", file, Rules))
    end).

with_temp_tree(Fun) ->
    Root = filename:join(
        "/tmp",
        "moirai_gitignore_" ++
            integer_to_list(erlang:unique_integer([positive]))),
    ok = filelib:ensure_dir(filename:join(Root, "placeholder")),
    try
        Fun(Root)
    after
        ok = file:del_dir_r(Root)
    end.
