-module(server).
-export([
    create_account/2, login/2, close_account/2, logout/1,
    start/0, online/0, get_player_level/1
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

        {Pid, {get_player_level, Username}} ->
            case maps:find(Username, Map) of
                {ok, {_, _, Level, _}} ->
                    Pid ! {ok, Level};
                error ->
                    Pid ! {error, user_not_found}
            end,
            loop({Map, Queue})
    end.

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

get_player_level(Username) ->
    rpc({get_player_level, Username}).


