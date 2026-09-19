-module(moirai_demo_tests).

-include_lib("eunit/include/eunit.hrl").

safe_stop_dead_process_test() ->
    {Pid, Ref} = spawn_monitor(fun() -> ok end),
    receive
        {'DOWN', Ref, process, Pid, normal} -> ok
    after 1000 ->
        error(process_did_not_stop)
    end,
    ?assertEqual(ok, moirai_demo:safe_stop(Pid)).
