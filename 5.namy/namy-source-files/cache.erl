-module(cache).
-export([lookup/2, add/4, remove/2, purge/1]).

lookup(Name, Cache) ->
  case lists:keyfind(Name, 1, Cache) of 
    {Name, Expire, Reply} -> 
      Now = erlang:monotonic_time(),
      CurrentTime = erlang:convert_time_unit(Now, native, second),
      case Expire < CurrentTime of
        true -> invalid;
        false -> Reply
      end;
    false -> unknown
  end.

add(Name, Expire, Reply, Cache) ->
  lists:keystore(Name, 1, Cache, {Name, Expire, Reply}).

remove(Name, Cache) ->
  lists:keydelete(Name, 1, Cache).

purge(Cache) -> 
  lists:filter(
    fun({_, Expire, _}) ->
      Now = erlang:monotonic_time(),
      CurrentTime = erlang:convert_time_unit(Now, native, second),
      Expire >= CurrentTime
    end, Cache).