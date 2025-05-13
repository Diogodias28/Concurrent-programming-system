-module(server).
-export([
    create_account/2, login/2, close_account/2, logout/1,
    start/0, online/0, get_player_level/1, get_player_streak/1, 
    update_account_status/4
]).

create_account(User, Pass) -> rpc({create_account, User, Pass}).
close_account(User, Pass) -> rpc({close_account, User, Pass}).
login(User, Pass) -> rpc({login, User, Pass}).
logout(User) -> rpc({logout, User}).
online() -> rpc(online).

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
                {ok, {P, false, L, S}} ->
                    NewMap = maps:put(U, {P, true, L, S}, Map),
                    Pid ! ok,
                    loop({NewMap, Queue});
                _ ->
                    Pid ! invalid,
                    loop({Map, Queue})
            end;

        {Pid, {logout, U}} ->
            case maps:find(U, Map) of
                {ok, {P, true, L, S}} ->
                    NewMap = maps:put(U, {P, false, L, S}, Map),
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

        {Pid, {get_player_level, Username}} ->
            case maps:find(Username, Map) of
                {ok, {_, _, Level, _}} ->
                    Pid ! {ok, Level};
                error ->
                    Pid ! {error, user_not_found}
            end,
            loop({Map, Queue});

        {Pid, {get_player_streak, Username}} ->
            case maps:find(Username, Map) of
                {ok, {_, _, _, Streak}} ->
                    Pid ! {ok, Streak};
                error ->
                    Pid ! {error, user_not_found}
            end,
            loop({Map, Queue});

        {Pid, {update_account_stats, Username, Level, Streak, Add}} ->
            case maps:find(Username, Map) of
                {ok, {P, S, L, S}} ->
                    NewStreak = 
                        case Add of
                            1 -> 
                                if 
                                    Streak >= 0 -> Streak + 1;
                                    true -> 1
                                end;
                            -1 -> 
                                if 
                                    Streak >= 0 -> -1;
                                    true -> Streak -1
                                end;
                            _ -> 
                                Streak
                        end,
                    
                    NewLevel = 
                        if
                            NewStreak == Level -> Level + 1;
                            true -> 
                                if 
                                    NewStreak == -(Level/2) -> 
                                        if 
                                            Level == 1 -> 1;
                                            true -> Level - 1;
                                        end;
                                    true -> Level
                                end;
                            end,

                    NewMap = maps:put(Username, {P, S, NewLevel, NewStreak}, Map),
                    save_accounts(NewMap),
                    Pid ! ok,
                    loop({NewMap, Queue});
                _ ->
                    Pid ! invalid,
                    loop({Map, Queue})
            end;
    end.

logout_all_list(Accounts) ->
    lists:map(fun({User, {Pass, _, Level, Visits}}) ->
        {User, {Pass, false, Level, Visits}}
    end, Accounts).

save_accounts(Map) ->
    Accounts = maps:to_list(Map),
    LoggedOutAccounts = logout_all_list(Accounts),
    file:write_file("Accounts.txt", io_lib:format("~p.", [LoggedOutAccounts])).

logout_account() ->
    file:write_file("../DueloArena/Login.txt", "").

get_player_level(Username) ->
    rpc({get_player_level, Username}).

get_player_streak(Username) ->
    rpc({get_player_streak, Username}).

update_account_stats(Username, Level, Streak, Add) ->
    rpc({update_account_stats, Username, Level, Streak, Add}).


