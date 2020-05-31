-module(node3).
-export([start/1, start/2]).

-define(Stabilize, 1000).
-define(Timeout, 5000).

start(MyKey) ->
    start(MyKey, nil).

start(MyKey, PeerPid) ->
    timer:start(),
    spawn(fun() -> init(MyKey, PeerPid) end).

init(MyKey, PeerPid) ->
    Predecessor = nil,
    {ok, Successor} = connect(MyKey, PeerPid),
    schedule_stabilize(),
    Store = storage:create(),
    node(MyKey, Predecessor, Successor, Store, nil).

connect(MyKey, nil) ->
    {ok, {MyKey, nil, self()}};
connect(_, PeerPid) ->
    Qref = make_ref(),
    PeerPid ! {key, Qref, self()},
    receive
        {Qref, Skey} ->
            MonitorRef = monit(PeerPid),
            {ok, {Skey, MonitorRef, PeerPid}}
    after ?Timeout ->
        io:format("Timeout: no response from ~w~n", [PeerPid])
    end.

schedule_stabilize() ->
    timer:send_interval(?Stabilize, self(), stabilize).

node(MyKey, Predecessor, Successor, Store, Next) ->
    receive
        {key, Qref, PeerPid} ->
            PeerPid ! {Qref, MyKey},
            node(MyKey, Predecessor, Successor, Store, Next);
        {notify, New} ->
            {NewPredecessor, NewStore} = notify(New, MyKey, Predecessor, Store),
            node(MyKey, NewPredecessor, Successor, NewStore, Next);
        {request, Peer} ->
            request(Peer, Predecessor, Successor),
            node(MyKey, Predecessor, Successor, Store, Next);
        {status, Pred, Nx} ->
            {NewSuccessor, NewNext} = stabilize(Pred, Nx, MyKey, Successor),
            node(MyKey, Predecessor, NewSuccessor, Store, NewNext);
        stabilize ->
            stabilize(Successor),
            node(MyKey, Predecessor, Successor, Store, Next);
        stop ->
            ok;
        probe ->
            create_probe(MyKey, Successor),
            node(MyKey, Predecessor, Successor, Store, Next);
        {probe, MyKey, Nodes, T} ->
            remove_probe(MyKey, Nodes, T),
            node(MyKey, Predecessor, Successor, Store, Next);
        {probe, RefKey, Nodes, T} ->
            forward_probe(RefKey, [MyKey|Nodes], T, Successor),
            node(MyKey, Predecessor, Successor, Store, Next);
        {add, Key, Value, Qref, Client} ->
            Added = add(Key, Value, Qref, Client,
                MyKey, Predecessor, Successor, Store),
            node(MyKey, Predecessor, Successor, Added, Next);
        {lookup, Key, Qref, Client} ->
            lookup(Key, Qref, Client, MyKey, Predecessor, Successor, Store),
            node(MyKey, Predecessor, Successor, Store, Next);
        {handover, Elements} ->
            Merged = storage:merge(Store, Elements),
            node(MyKey, Predecessor, Successor, Merged, Next);
        {'DOWN', Ref, process, _, _} -> 
            {NewPred, NewSucc, NewNext} = down(Ref, Predecessor, Successor, Next),
            node(MyKey, NewPred, NewSucc, Store, NewNext)
   end.

stabilize(Pred, Nx, MyKey, Successor) ->
  {Skey, Smonit, Spid} = Successor,
  case Pred of
      nil ->
          Spid ! {notify, {MyKey, self()}},
          { Successor, Nx };
      {MyKey, _} ->
          { Successor, Nx };
      {Skey, _} ->
          Spid ! {notify, {MyKey, self()}},
          { Successor, Nx };
      {Xkey, Xpid} ->
            case key:between(Xkey, MyKey, Skey) of
                true ->
                    self() ! stabilize,
                    demonit(Smonit),
                    Xmonit = monit(Xpid),
                    {{Xkey, Xmonit, Xpid}, {Skey, Spid}};
                false ->
                    Spid ! {notify, {MyKey, self()}},
                    { Successor, Nx }
            end
    end.

stabilize({_, _, Spid}) ->
    Spid ! {request, self()}.

request(Peer, Predecessor, {Skey, _, Spid}) ->
    case Predecessor of
        nil ->
            Peer ! {status, nil, {Skey, Spid}};
        {Pkey, _, Ppid} ->
            Peer ! {status, {Pkey, Ppid}, {Skey, Spid}}
    end.

notify({Nkey, Npid}, MyKey, Predecessor, Store) ->
    case Predecessor of
        nil ->
            Keep = handover(Store, MyKey, Nkey, Npid),
            Nmonit = monit(Npid),
            {{Nkey, Nmonit, Npid}, Keep};
        {Pkey, Pmonit, _} ->
            case key:between(Nkey, Pkey, MyKey) of
                true ->
                    Keep = handover(Store, MyKey, Nkey, Npid),
                    demonit(Pmonit),
                    Nmonit = monit(Npid),
                    {{Nkey, Nmonit, Npid}, Keep};
                false ->
                    {Predecessor, Store}
            end
    end.

create_probe(MyKey, {_, _, Spid}) ->
    Spid ! {probe, MyKey, [MyKey], erlang:monotonic_time()},
    io:format("Create probe ~w!~n", [MyKey]).
	
remove_probe(MyKey, Nodes, T) ->
    T2 = erlang:monotonic_time(),
    Time = erlang:convert_time_unit(T2-T, native, millisecond),
    io:format("Received probe ~w in ~w ms Ring: ~w~n", [MyKey, Time, Nodes]).
	
forward_probe(RefKey, Nodes, T, {_, _, Spid}) ->
    Spid ! {probe, RefKey, Nodes, T},
    io:format("Forward probe ~w!~n", [RefKey]).


add(Key, Value, Qref, Client, MyKey, {Pkey, _, _}, {_, _, Spid}, Store) ->
    case key:between(Key, Pkey, MyKey) of
        true ->
            Added = storage:add(Key, Value, Store),
            Client ! {Qref, ok},
            Added;
        false ->
            Spid ! {add, Key, Value, Qref, Client},
            Store
    end.

lookup(Key, Qref, Client, MyKey, {Pkey, _}, {_, Spid}, Store) ->
    case key:between(Key, Pkey, MyKey) of
        true ->
            Result = storage:lookup(Key, Store),
            Client ! {Qref, Result};
        false ->
            Spid ! {lookup, Key, Qref, Client}
    end.

handover(Store, MyKey, Nkey, Npid) ->
    {Keep, Leave} = storage:split(MyKey, Nkey, Store),
    Npid ! {handover, Leave},
    Keep.

monit(Pid) ->
    erlang:monitor(process, Pid).

demonit(nil) ->
    ok;
demonit(MonitorRef) ->
    erlang:demonitor(MonitorRef, [flush]).

down(Ref, {_, Ref, _}, Successor, Next) ->
    {nil, Successor, Next};
down(Ref, Predecessor, {_, Ref, _}, {Nkey, Npid}) ->
    self() ! stabilize,
    Nmonit = monit(Npid),
    {Predecessor, {Nkey, Nmonit, Npid}, nil}.