-module(moirai_purge_zombie_deps_tests).
-include_lib("eunit/include/eunit.hrl").

orphaned_compiled_checkout_is_removed_test() ->
    with_tree(
        fun(_Root, BuildRoot, Checkouts) ->
            Orphan = make_dir(BuildRoot, "default/checkouts/klotho"),
            run_script(BuildRoot, Checkouts),
            ?assertNot(filelib:is_dir(Orphan))
        end
    ).

live_checkout_removes_shadowing_lib_copy_test() ->
    with_tree(
        fun(Root, BuildRoot, Checkouts) ->
            Source = make_dir(Root, "klotho-source"),
            ok = file:make_symlink(Source, filename:join(Checkouts, "klotho")),
            LibCopy = make_dir(BuildRoot, "default/lib/klotho"),
            CompiledCheckout = make_dir(BuildRoot, "default/checkouts/klotho"),
            run_script(BuildRoot, Checkouts),
            ?assertNot(filelib:is_dir(LibCopy)),
            ?assert(filelib:is_dir(CompiledCheckout))
        end
    ).

locked_dependency_is_preserved_test() ->
    with_tree(
        fun(_Root, BuildRoot, Checkouts) ->
            Locked = make_dir(BuildRoot, "default/lib/klotho"),
            run_script(BuildRoot, Checkouts),
            ?assert(filelib:is_dir(Locked))
        end
    ).

plain_checkout_directory_is_live_test() ->
    with_tree(
        fun(_Root, BuildRoot, Checkouts) ->
            _Checkout = make_dir(Checkouts, "klotho"),
            LibCopy = make_dir(BuildRoot, "test/lib/klotho"),
            run_script(BuildRoot, Checkouts),
            ?assertNot(filelib:is_dir(LibCopy))
        end
    ).

with_tree(Test) ->
    Root = filename:join(
        "/tmp",
        "moirai_purge_zombie_deps_" ++
            integer_to_list(erlang:unique_integer([positive]))
    ),
    ok = file:make_dir(Root),
    try
        BuildRoot = make_dir(Root, "build"),
        Checkouts = make_dir(Root, "checkouts"),
        Test(Root, BuildRoot, Checkouts)
    after
        _ = file:del_dir_r(Root)
    end.

run_script(BuildRoot, Checkouts) ->
    Script = filename:join(project_root(), "scripts/purge-zombie-deps"),
    ?assert(filelib:is_regular(Script)),
    Command = "sh " ++ Script ++ " " ++ BuildRoot ++ " " ++ Checkouts ++
        " 2>&1",
    _Output = os:cmd(Command),
    ok.

make_dir(Parent, Relative) ->
    Path = filename:join(Parent, Relative),
    ok = filelib:ensure_dir(filename:join(Path, "placeholder")),
    Path.

project_root() ->
    parent(filename:absname(code:which(?MODULE)), 6).

parent(Path, 0) ->
    Path;
parent(Path, Count) ->
    parent(filename:dirname(Path), Count - 1).
