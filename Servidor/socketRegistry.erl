-module(socketRegistry).
-export([start/0, add/1, remove/1, get_all/0, broadcast/1, set_shutdown/1, is_shutting_down/0]).

start() ->
    register(socketRegistry, spawn(fun() -> loop([], false) end)).

loop(Sockets, Shutdown) ->
    receive
        {add, Sock} ->
            loop([Sock | Sockets], Shutdown);
        {remove, Sock} ->
            loop(lists:delete(Sock, Sockets), Shutdown);
        {get_all, Caller} ->
            Caller ! {sockets, Sockets},
            loop(Sockets, Shutdown);
        {broadcast, Msg} ->
            lists:foreach(fun(S) -> catch gen_tcp:send(S, Msg) end, Sockets),
            loop(Sockets, Shutdown);
        {set_shutdown, Bool} ->
            loop(Sockets, Bool);
        {get_shutdown, Caller} ->
            Caller ! {shutdown, Shutdown},
            loop(Sockets, Shutdown)
    end.

add(Sock) -> socketRegistry ! {add, Sock}.
remove(Sock) -> socketRegistry ! {remove, Sock}.
get_all() -> socketRegistry ! {get_all, self()}, receive {sockets, S} -> S end.
broadcast(Msg) -> socketRegistry ! {broadcast, Msg}.
set_shutdown(Bool) -> socketRegistry ! {set_shutdown, Bool}.
is_shutting_down() ->
    socketRegistry ! {get_shutdown, self()},
    receive
        {shutdown, Val} -> Val
    end.