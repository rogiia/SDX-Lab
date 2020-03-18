-module(muty_dist).
-export([start/4, stop/1]).

start(Lock, Sleep, Work, [Node1,Node2,Node3,Node4]) ->
    spawn(Node1, fun() -> 
        register(l1,Lock:start(1)), 
        register(w1,worker:start("John", l1, Sleep, Work)) end),
    spawn(Node2, fun() -> 
        register(l2,Lock:start(2)), 
        register(w2,worker:start("Ringo", l2, Sleep, Work)) end),
    spawn(Node3, fun() -> 
        register(l3,Lock:start(3)), 
        register(w3,worker:start("Paul", l3, Sleep, Work)) end),
    spawn(Node4, fun() -> 
        register(l4,Lock:start(4)), 
        register(w4,worker:start("George", l4, Sleep, Work)) end),
    {l1,Node1} ! {peers, [{l2,Node2}, {l3,Node3}, {l4,Node4}]},
    {l2,Node2} ! {peers, [{l1,Node1}, {l3,Node3}, {l4,Node4}]},
    {l3,Node3} ! {peers, [{l1,Node1}, {l2,Node2}, {l4,Node4}]},
    {l4,Node4} ! {peers, [{l1,Node1}, {l2,Node2}, {l3,Node3}]},
    
    ok.

stop([Node1,Node2,Node3,Node4]) ->
    {w1,Node1} ! stop,
    {w2,Node2} ! stop,
    {w3,Node3} ! stop,
    {w4,Node4} ! stop.