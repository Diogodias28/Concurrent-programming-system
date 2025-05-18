-module(server).
-export([
    create_account/2, login/2, close_account/2, logout/1,
    start/0, online/0, get_player_level/1, get_player_streak/1, 
    update_account_stats/4,top_10/0, updateStats/3
]).

create_account(User, Pass) -> rpc({create_account, User, Pass}).
close_account(User, Pass) -> rpc({close_account, User, Pass}).
login(User, Pass) -> rpc({login, User, Pass}).
logout(User) -> rpc({logout, User}).
online() -> rpc(online).
get_player_level(User) -> rpc({get_player_level, User}).
top_10() -> rpc(top_10).
updateStats(User, NewLevel, NewStreak) -> rpc({updateStats, User, NewLevel, NewStreak}).
get_player_streak(Username) ->
    rpc({get_player_streak, Username}).

update_account_stats(Username, Level, Streak, Add) ->
    rpc({update_account_stats, Username, Level, Streak, Add}).

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
                {ok, {P, S, _, _}} ->
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

                    {NewLevel, FinalStreak} =
                        if
                            NewStreak == Level -> {Level + 1, 0};
                            NewStreak == -(Level/2) ->
                                if
                                    Level == 1 -> {1, 0};
                                    true -> {Level - 1, 0}
                                end;
                            true -> {Level, NewStreak}
                        end,

                    NewMap = maps:put(Username, {P, S, NewLevel, FinalStreak}, Map),
                    save_accounts(NewMap),
                    Pid ! ok,
                    loop({NewMap, Queue});
                _ ->
                    Pid ! invalid,
                    loop({Map, Queue})
            end;


        {Pid, top_10} ->
            Top10 = lists:sort(
                fun({_, {_, _, L1, Streak1}}, {_, {_, _, L2, Streak2}}) ->
                    case L1 == L2 of
                        true -> Streak1 > Streak2;
                        false -> L1 > L2
                    end
                end,
                maps:to_list(Map)
            ),
            Top10List = lists:sublist(Top10, 10),
            Top10Str = format_top10(Top10List),
            Pid ! Top10Str,
            loop({Map, Queue});

        % Apenas para testar o top10
        {Pid, {updateStats, User, NewLevel, NewStreak}} ->
            case maps:find(User, Map) of
                {ok, {Pass, Online, _, _}} ->
                    NewMap = maps:put(User, {Pass, Online, NewLevel, NewStreak}, Map),
                    save_accounts(NewMap),
                    Pid ! ok,
                    loop({NewMap, Queue});
                _ -> 
                    Pid ! {error, "User not found"},
        
                            
                    loop({Map, Queue})
            end
    end.

logout_all_list(Accounts) ->
    lists:map(fun({User, {Pass, _, Level, Visits}}) ->
        {User, {Pass, false, Level, Visits}}
    end, Accounts).

save_accounts(Map) ->
    Accounts = maps:to_list(Map),
    LoggedOutAccounts = logout_all_list(Accounts),
    file:write_file("Accounts.txt", io_lib:format("~p.", [LoggedOutAccounts])).

format_top10(Top10List) ->
    Formatted =
        lists:map(
            fun({User, {_, _, Level, Streak}}) ->
                io_lib:format("~s | Nível: ~p | Streak: ~p", [User, Level, Streak])
            end,
            Top10List
        ),
    string:join([lists:flatten(Line) || Line <- Formatted], "||").