-module(queuelist).
-export([start/0, add_to_queue/3, get_queue/0, remove_from_queue/1]).
-export([loop/1]).

start() ->
    Pid = spawn(?MODULE, loop, [queue:new()]),
    register(global_queue, Pid),
    {ok, Pid}.

loop(Queue) ->
    receive
        {add, From, User, Level, Socket} ->  % Adicione Socket como parâmetro
            case user_in_queue(User, Queue) of
                true ->
                    From ! {response, already_queued},
                    loop(Queue);
                false ->
                    NewQueue = queue:in({User, Level, Socket}, Queue),  % Armazene o socket
                    case try_match(NewQueue) of
                        {matched, U1, S1, U2, S2, RemainingQueue} ->  % Retorne ambos os sockets
                            From ! {response, {matched, U1, S1, U2, S2}},
                            loop(RemainingQueue);
                        no_match ->
                            From ! {response, queued},
                            loop(NewQueue)
                    end
            end;
        {get, From} ->
            From ! {queue, queue:to_list(Queue)},
            loop(Queue);
        {remove, From, User} ->
            NewQueue = remove_user(User, Queue),
            From ! {response, ok},
            loop(NewQueue)
    end.

add_to_queue(User, Level, Socket) ->
    global_queue ! {add, self(), User, Level, Socket},  % Adicione Socket
    receive
        {response, Res} -> Res
    after 5000 -> timeout
    end.

get_queue() ->
    global_queue ! {get, self()},
    receive
        {queue, Q} -> Q
    after 5000 -> []
    end.

remove_from_queue(User) ->
    global_queue ! {remove, self(), User},
    receive
        {response, Res} -> Res
    after 5000 -> timeout
    end.

% Helper functions
user_in_queue(User, Queue) ->
    lists:keymember(User, 1, queue:to_list(Queue)).

remove_user(User, Queue) ->
    Filtered = lists:filter(fun({U, _, _}) -> U =/= User end, queue:to_list(Queue)),
    queue:from_list(Filtered).

% In queuelist.erl, modify the try_match function
try_match(Queue) ->
    QList = queue:to_list(Queue),
    case find_match(QList) of
        {P1, L1, S1, P2, L2, S2} ->
            Filtered = lists:filter(fun({U, _, _}) -> U =/= P1 andalso U =/= P2 end, QList),
            {matched, P1, S1, P2, S2, queue:from_list(Filtered)};
        none ->
            no_match
    end.

find_match(Players) ->
    case [ {P1, L1, S1, P2, L2, S2} || 
        {P1, L1, S1} <- Players, 
        {P2, L2, S2} <- Players, 
        P1 < P2, 
        abs(L1 - L2) =< 1 ] of
        [] -> none;
        [{P1, L1, S1, P2, L2, S2}|_] -> {P1, L1, S1, P2, L2, S2}
    end.