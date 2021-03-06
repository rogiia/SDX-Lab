gms2.erl                                                                                            0000644 0001750 0001750 00000005462 13646610500 011460  0                                                                                                    ustar   roger                           roger                                                                                                                                                                                                                  -module(gms2).
-export([start/1, start/2]).
-define(timeout, 1000).
-define(arghh, 100).

start(Name) ->
    Self = self(),
    spawn_link(fun()-> init(Name, Self) end).

init(Name, Master) ->
    leader(Name, Master, []).

start(Name, Grp) ->
    Self = self(),
    spawn_link(fun()-> init(Name, Grp, Self) end).

init(Name, Grp, Master) ->
    Self = self(), 
    Grp ! {join, Self},
    receive
        {view, Leader, Slaves} ->
            Ref = erlang:monitor(process, Leader),
            Master ! joined,
            slave(Name, Master, Leader, Slaves, Ref)
    after ?timeout ->
        Master ! {error, "No reply from the leader"}
    end.

leader(Name, Master, Slaves) ->    
    receive
        {mcast, Msg} ->
            bcast(Name, {msg, Msg}, Slaves),
            Master ! {deliver, Msg},
            leader(Name, Master, Slaves);
        {join, Peer} ->
            NewSlaves = lists:append(Slaves, [Peer]),           
            bcast(Name, {view, self(), NewSlaves}, NewSlaves),
            leader(Name, Master, NewSlaves);
        stop ->
            ok;
        Error ->
            io:format("leader ~s: strange message ~w~n", [Name, Error])
    end.
    
bcast(Name, Msg, Nodes) ->
    lists:foreach(fun(Node) ->
            Node ! Msg,
            crash(Name, Msg)
        end,
        Nodes).

crash(Name, Msg) ->
    case rand:uniform(?arghh) of
        ?arghh ->
            io:format("leader ~s CRASHED: msg ~w~n", [Name, Msg]),
            exit(no_luck);
        _ ->
            ok
    end.

slave(Name, Master, Leader, Slaves, Ref) ->
    receive
        {mcast, Msg} ->
            Leader ! {mcast, Msg},
            slave(Name, Master, Leader, Slaves, Ref);
        {join, Peer} ->
            Leader ! {join, Peer},
            slave(Name, Master, Leader, Slaves, Ref);
        {msg, Msg} ->
            Master ! {deliver, Msg},
            slave(Name, Master, Leader, Slaves, Ref);
        {view, Leader, NewSlaves} ->
            slave(Name, Master, Leader, NewSlaves, Ref);
        {view, NewLeader, NewSlaves} ->
            erlang:demonitor(Ref, [flush]),
            NewRef = erlang:monitor(process, NewLeader),
            slave(Name, Master, NewLeader, NewSlaves, NewRef);
        {'DOWN', _Ref, process, Leader, _Reason} ->
            election(Name, Master, Slaves);
        stop ->
            ok;
        Error ->
            io:format("slave ~s: strange message ~w~n", [Name, Error])
    end.

election(Name, Master, Slaves) -> 
    Self = self(),
    case Slaves of
        [Self|Rest] ->
            bcast(Name, {view, Self, Rest}, Rest),
            leader(Name, Master, Rest);
        [NewLeader|Rest] ->
            Ref = erlang:monitor(process, NewLeader),
            slave(Name, Master, NewLeader, Rest, Ref)
    end.                                                                                                                                                                                                              gms3.erl                                                                                            0000644 0001750 0001750 00000006341 13646620006 011460  0                                                                                                    ustar   roger                           roger                                                                                                                                                                                                                  -module(gms3).
-export([start/1, start/2]).
-define(timeout, 1000).
-define(arghh, 100).

start(Name) ->
    Self = self(),
    spawn_link(fun()-> init(Name, Self) end).

init(Name, Master) ->
    leader(Name, Master, [], 1).

start(Name, Grp) ->
    Self = self(),
    spawn_link(fun()-> init(Name, Grp, Self) end).

init(Name, Grp, Master) ->
    Self = self(), 
    Grp ! {join, Self},
    receive
        {view, N, Leader, Slaves} = NewLast ->
            Ref = erlang:monitor(process, Leader),
            Master ! joined,
            slave(Name, Master, Leader, Slaves, Ref, N+1, NewLast)
    after ?timeout ->
        Master ! {error, "No reply from the leader"}
    end.

leader(Name, Master, Slaves, N) ->
    receive
        {mcast, Msg} ->
            bcast(Name, {msg, N, Msg}, Slaves),
            Master ! {deliver, Msg},
            leader(Name, Master, Slaves, N+1);
        {join, Peer} ->
            NewSlaves = lists:append(Slaves, [Peer]),           
            bcast(Name, {view, N, self(), NewSlaves}, NewSlaves),
            leader(Name, Master, NewSlaves, N+1);
        stop ->
            ok;
        Error ->
            io:format("leader ~s: strange message ~w~n", [Name, Error])
    end.
    
bcast(Name, Msg, Nodes) ->
    lists:foreach(fun(Node) ->
            Node ! Msg,
            crash(Name, Msg)
        end,
        Nodes).

crash(Name, Msg) ->
    case rand:uniform(?arghh) of
        ?arghh ->
            io:format("leader ~s CRASHED: msg ~w~n", [Name, Msg]),
            exit(no_luck);
        _ ->
            ok
    end.

slave(Name, Master, Leader, Slaves, Ref, N, Last) ->
    receive
        {mcast, Msg}->
            Leader ! {mcast, Msg},
            slave(Name, Master, Leader, Slaves, Ref, N, Last);
        {join, Peer} ->
            Leader ! {join, Peer},
            slave(Name, Master, Leader, Slaves, Ref, N, Last);
        {msg, N, Msg} = NewLast ->
            Master ! {deliver, Msg},
            slave(Name, Master, Leader, Slaves, Ref, N+1, NewLast);
        {msg, I, _} when I < N ->
            slave(Name, Master, Leader, Slaves, Ref, N, Last);
        {view, N, Leader, NewSlaves} = NewLast ->
            slave(Name, Master, Leader, NewSlaves, Ref, N+1, NewLast);
        {view, N, NewLeader, NewSlaves} = NewLast ->
            erlang:demonitor(Ref, [flush]),
            NewRef = erlang:monitor(process, NewLeader),
            slave(Name, Master, NewLeader, NewSlaves, NewRef, N+1, NewLast);
        {view, I, Leader, _} when I < N ->
            slave(Name, Master, Leader, Slaves, Ref, N, Last);
        {'DOWN', _Ref, process, Leader, _Reason} ->
            election(Name, Master, Slaves, N, Last);
        stop ->
            ok;
        Error ->
            io:format("slave ~s: strange message ~w~n", [Name, Error])
    end.

election(Name, Master, Slaves, N, Last) ->
    Self = self(),
    case Slaves of
        [Self|Rest] ->
            bcast(Name, Last, Rest),
            bcast(Name, {view, N, Self, Rest}, Rest),
            leader(Name, Master, Rest, N+1);
        [NewLeader|Rest] ->
            Ref = erlang:monitor(process, NewLeader),
            slave(Name, Master, NewLeader, Rest, Ref, N, Last)
    end.                                                                                                                                                                                                                                                                                               groupy.erl                                                                                          0000644 0001750 0001750 00000001412 12466365644 012143  0                                                                                                    ustar   roger                           roger                                                                                                                                                                                                                  -module(groupy).
-export([start/2, stop/0]).

% We use the name of the module (i.e. gms3) as the parameter Module to the start procedure. Sleep stands for up to how many milliseconds the workers should wait until the next message is sent.

start(Module, Sleep) ->
    P = worker:start("P1", Module, Sleep),
    register(a, P), 
    register(b, worker:start("P2", Module, P, Sleep)),
    register(c, worker:start("P3", Module, P, Sleep)),
    register(d, worker:start("P4", Module, P, Sleep)),
    register(e, worker:start("P5", Module, P, Sleep)).

stop() ->
    stop(a),
    stop(b),
    stop(c),
    stop(d),
    stop(e).

stop(Name) ->
    case whereis(Name) of
        undefined ->
            ok;
        Pid ->
            Pid ! stop
    end.

                                                                                                                                                                                                                                                      gui.erl                                                                                             0000644 0001750 0001750 00000002257 12267463626 011410  0                                                                                                    ustar   roger                           roger                                                                                                                                                                                                                  -module(gui).
-export([start/2]).
-define(width, 200).
-define(height, 200).
-include_lib("wx/include/wx.hrl").

start(Name, Master) ->
    spawn_link(fun() -> init(Name, Master) end).

init(Name, Master) ->
    Frame = make_frame(Name),
    loop(Frame, Master).

make_frame(Name) ->       %Name is the window title
    Server = wx:new(),  %Server will be the parent for the Frame
    Frame = wxFrame:new(Server, -1, Name, [{size,{?width, ?height}}]),
    wxFrame:setBackgroundColour(Frame, ?wxBLACK),
    wxFrame:show(Frame),
    %monitor closing window event
    wxFrame:connect(Frame, close_window),
    Frame.

loop(Frame, Master)->
    receive
        %check if the window was closed by the user
        #wx{event=#wxClose{}} ->
            wxWindow:destroy(Frame),  
            Master ! stop,
            ok;
        {color, Color} ->
            color(Frame, Color),
            loop(Frame, Master);
        stop ->
            ok;
        Error ->
            io:format("gui: strange message ~w ~n", [Error]),
            loop(Frame, Master)
    end.

color(Frame, Color) ->
    wxFrame:setBackgroundColour(Frame, Color),
    wxFrame:refresh(Frame).                                                                                                                                                                                                                                                                                                                                                 worker.erl                                                                                          0000644 0001750 0001750 00000005365 13224470042 012120  0                                                                                                    ustar   roger                           roger                                                                                                                                                                                                                  -module(worker).
-export([start/3, start/4]).

-define(change, 20).
-define(color, {0,0,0}).

start(Name, Module, Sleep) ->
    spawn(fun() -> init(Name, Module, Sleep) end).

init(Name, Module, Sleep) ->
    Cast = apply(Module, start, [Name]),
    Color = ?color,
    init_cont(Name, Cast, Color, Sleep).

start(Name, Module, Peer, Sleep) ->
    spawn(fun() -> init(Name, Module, Peer, Sleep) end).

init(Name, Module, Peer, Sleep) ->
    Cast = apply(Module, start, [Name, Peer]),
    receive
        joined ->
            Ref = make_ref(),
            Cast ! {mcast, {state_req, Ref}},
            Color = state_transfer(Cast, Ref),
            if Color /= stop ->
                 init_cont(Name, Cast, Color, Sleep),
                 Cast ! stop;
               true ->
                 Cast ! stop
            end;
        {error, Error} ->
            io:format("worker ~s: error: ~s~n", [Name, Error]);
        stop -> 
            ok
    end.

state_transfer(Cast, Ref) ->
    receive
        {deliver, {state_req, Ref}} ->
            receive
                {deliver, {set_state, Ref, Color}} ->
                    Color
            end;
        {join, Peer} ->
            Cast ! {join, Peer},
            state_transfer(Cast, Ref);
        stop -> 
            stop;
        _Ignore ->
            state_transfer(Cast, Ref)
    end.

init_cont(Name, Cast, Color, Sleep) ->
    Gui = gui:start(Name, self()),
    Gui ! {color, Color}, 
    Wait = if Sleep == 0 -> 0; true -> rand:uniform(Sleep) end,
    timer:send_after(Wait, cast_change),
    worker(Name, Cast, Color, Gui, Sleep),
    Gui ! stop.

worker(Name, Cast, Color, Gui, Sleep) ->
    receive
        {deliver, {change_state, N}} ->
            NewColor = change_color(N, Color),
            Gui ! {color, NewColor},
            worker(Name, Cast, NewColor, Gui, Sleep);
        {deliver, {state_req, Ref}} ->
            Cast ! {mcast, {set_state, Ref, Color}},
            worker(Name, Cast, Color, Gui, Sleep);
        {deliver, {set_state, _, _}} ->
            worker(Name, Cast, Color, Gui, Sleep);
        {join, Peer} ->
            Cast ! {join, Peer},
            worker(Name, Cast, Color, Gui, Sleep);
        cast_change ->
            Cast !  {mcast, {change_state, rand:uniform(?change)}},
            Wait = if Sleep == 0 -> 0; true -> rand:uniform(Sleep) end,
            timer:send_after(Wait, cast_change),
            worker(Name, Cast, Color, Gui, Sleep);
        stop ->
            Cast ! stop,
            ok;
        Error ->
            io:format("worker ~s: strange message: ~w~n", [Name, Error]),
            worker(Name, Cast, Color, Gui, Sleep)
    end.

change_color(N, {R,G,B}) ->
    {G, B, ((R+N) rem 256)}.
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           