-module(server).
-export([
    create_account/2, login/2, close_account/2, logout/1,
    start/0, online/0, queue/1, get_queue/0
]).

create_account(User, Pass) -> rpc({create_account, User, Pass}).
close_account(User, Pass) -> rpc({close_account, User, Pass}).
login(User, Pass) -> rpc({login, User, Pass}).
logout(User) -> rpc({logout, User}).
online() -> rpc(online).
queue(User) -> rpc({queue, User}).
get_queue() -> rpc(get_queue).

rpc(Msg) ->
    ?MODULE ! {self(), Msg},
    receive
        Response -> Response
    after 5000 ->
        timeout
    end.

start() ->
    InitialMap = case file:consult("Accounts.txt") of
        {ok, [Terms]} when is_list(Terms) ->
            try maps:from_list(Terms) of
                Map -> Map
            catch
                _:_ -> #{}
            end;
        _ -> #{}
    end,
    Queue = queue:new(),
    Pid = spawn(fun() -> loop({InitialMap, Queue}) end),
    register(?MODULE, Pid),
    {ok, Pid}.

loop({Map, Queue}) ->
    receive
        {Pid, {create_account, U, P}} ->
            case maps:find(U, Map) of
                {ok, _} ->
                    Pid ! user_exists,
                    loop({Map, Queue});
                error ->
                    NewMap = maps:put(U, {P, false, 1, 0}, Map),
                    save_accounts(NewMap),
                    Pid ! ok,
                    loop({NewMap, Queue})
            end;

        {Pid, {close_account, U, P}} ->
            case maps:find(U, Map) of
                {ok, {P, _, _, _}} ->
                    NewMap = maps:remove(U, Map),
                    save_accounts(NewMap),
                    Pid ! ok,
                    loop({NewMap, Queue});
                _ ->
                    Pid ! invalid,
                    loop({Map, Queue})
            end;

        {Pid, {login, U, P}} ->
            case maps:find(U, Map) of
                {ok, {P, false, L, V}} ->
                    NewMap = maps:put(U, {P, true, L, V}, Map),
                    save_logged_account(U),
                    Pid ! ok,
                    loop({NewMap, Queue});
                _ ->
                    Pid ! invalid,
                    loop({Map, Queue})
            end;

        {Pid, {logout, U}} ->
            case maps:find(U, Map) of
                {ok, {P, true, L, V}} ->
                    NewMap = maps:put(U, {P, false, L, V}, Map),
                    logout_account(),
                    Pid ! ok,
                    loop({NewMap, Queue});
                _ ->
                    Pid ! invalid,
                    loop({Map, Queue})
            end;

        {Pid, online} ->
            OnlineUsers = [{U, L} || {U, {_, true, L, _}} <- maps:to_list(Map)],
            Pid ! OnlineUsers,
            loop({Map, Queue});

        {Pid, {queue, User}} ->
            case maps:find(User, Map) of
                {ok, {_, true, Level, _}} ->
                    case user_already_queued(User, Queue) of
                        true ->
                            Pid ! already_queued,
                            loop({Map, Queue});
                        false ->
                            NewQueue = queue:in({User, Level}, Queue),
                            case try_match(NewQueue) of
                                {matched, Q2} ->
                                    Pid ! matched,
                                    loop({Map, Q2});
                                {no_match, Q2} ->
                                    Pid ! queued,
                                    loop({Map, Q2})
                            end
                    end;
                _ ->
                    Pid ! invalid,
                    loop({Map, Queue})
            end;

        {Pid, get_queue} ->
            QueueList = queue:to_list(Queue),
            Pid ! QueueList,
            loop({Map, Queue})
    end.

try_match(Queue) ->
    List = queue:to_list(Queue),
    try_match(List, Queue).

try_match([{U1, L1} | Rest], Queue) ->
    case find_compatible(U1, L1, Rest) of
        {ok, U2, L2, Remainder} ->
            Remaining = remove_first({U1, L1}, Remainder),
            NewQ = lists:foldl(fun queue:in/2, queue:new(), Remaining),
            io:format("Match found: ~p (Lv~p) vs ~p (Lv~p)~n", [U1, L1, U2, L2]),
            {matched, NewQ};
        not_found ->
            try_match(Rest, Queue)
    end;
try_match([], Queue) ->
    {no_match, Queue}.

find_compatible(U1, L1, [{U2, L2} | T]) ->
    if abs(L1 - L2) =< 1 ->
            {ok, U2, L2, [{U1, L1} | remove_first({U2, L2}, T)]};
       true ->
            case find_compatible(U1, L1, T) of
                {ok, U, L, Tail} -> {ok, U, L, [{U2, L2} | Tail]};
                not_found -> not_found
            end
    end;
find_compatible(_, _, []) -> not_found.

remove_first(Elem, List) ->
    case lists:splitwith(fun(X) -> X =/= Elem end, List) of
        {Before, [_ | After]} -> Before ++ After;
        {Before, []} -> Before
    end.

user_already_queued(User, Queue) ->
    lists:any(fun({U, _}) -> U =:= User end, queue:to_list(Queue)).

logout_all_list(Accounts) ->
    lists:map(fun({User, {Pass, _, Level, Visits}}) ->
        {User, {Pass, false, Level, Visits}}
    end, Accounts).

save_accounts(Map) ->
    Accounts = maps:to_list(Map),
    LoggedOutAccounts = logout_all_list(Accounts),
    file:write_file("Accounts.txt", io_lib:format("~p.", [LoggedOutAccounts])).

save_logged_account(User) ->
    file:write_file("../DueloArena/Login.txt", io_lib:format("~p", [User])).

logout_account() ->
    file:write_file("../DueloArena/Login.txt", "").
