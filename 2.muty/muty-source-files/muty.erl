-module(muty).
-export([start/3, stop/0]).

start(Lock, Sleep, Work) ->
    register(l1, apply(Lock, start, [1])),
    register(l2, apply(Lock, start, [2])),
    register(l3, apply(Lock, start, [3])),
    register(l4, apply(Lock, start, [4])),
    l1 ! {peers, [l2, l3, l4]},
    l2 ! {peers, [l1, l3, l4]},
    l3 ! {peers, [l1, l2, l4]},
    l4 ! {peers, [l1, l2, l3]},
    register(w1, worker:start("John", l1, Sleep, Work)),
    register(w2, worker:start("Ringo", l2, Sleep, Work)),
    register(w3, worker:start("Paul", l3, Sleep, Work)),
    register(w4, worker:start("George", l4, Sleep, Work)),
    ok.

stop() ->
    w1 ! stop,
    w2 ! stop,
    w3 ! stop,
    w4 ! stop.
