-module(queuelist).
-export([add_to_queue/2, get_queue/0, startqueue/0, remove_from_queue/1]).

startqueue() ->
    % Initialize the queue storage
    erlang:put(queue, queue:new()).

% Adds a user to the queue if not already present
add_to_queue(User, Level) when is_integer(Level), Level > 0 ->
    case user_already_queued(User) of
        true -> already_queued;
        false ->
            Q = get_current_queue(),
            NewQueue = queue:in({User, Level}, Q),
            update_queue(NewQueue),
            case try_match(NewQueue) of
                {matched, {U1, U2}, RemainingQueue} ->
                    update_queue(RemainingQueue),
                    {matched, U1, U2};
                no_match ->
                    queued
            end
    end;
add_to_queue(_, _) -> invalid.

get_queue() -> queue:to_list(get_current_queue()).

% Add this to queuelist.erl
remove_from_queue(User) ->
    Q = get_current_queue(),
    Filtered = lists:filter(fun({U, _}) -> U =/= User end, queue:to_list(Q)),
    update_queue(list_to_queue(Filtered)),
    ok.

% Helper functions
user_already_queued(User) ->
    lists:keymember(User, 1, get_queue()).

get_current_queue() ->
    case erlang:get(queue) of
        undefined -> queue:new();
        Q -> Q
    end.

update_queue(Q) -> erlang:put(queue, Q).

% Improved matching logic
try_match(Queue) ->
    QList = queue:to_list(Queue),
    case find_match(QList) of
        {P1, P2} ->
            Filtered = lists:filter(fun
                ({P, _}) when P =:= P1; P =:= P2 -> false;
                (_) -> true
            end, QList),
            {matched, {P1, P2}, list_to_queue(Filtered)};
        none -> no_match
    end.

find_match([{P1,L1}|Rest]) ->
    case lists:search(fun({_,L2}) -> abs(L1 - L2) =< 1 end, Rest) of
        {value, {P2,_L2}} -> {P1,P2};
        false -> find_match(Rest)
    end;
find_match([]) -> none.

list_to_queue(List) ->
    lists:foldl(fun queue:in/2, queue:new(), List).