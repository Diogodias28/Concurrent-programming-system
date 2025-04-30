-module(server).
-export([create_account/2, login/2, close_account/2, logout/1, start/0, online/0]).

% Client API functions
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

% Server implementation
start() ->
    % Load existing accounts from file if available
    InitialMap = case file:consult("Accounts.txt") of
        {ok, [Terms]} when is_list(Terms) -> 
            try maps:from_list(Terms) of
                Map -> Map
            catch
                _:_ -> #{}
            end;
        _ -> #{}
    end,
    Pid = spawn(fun() -> loop(InitialMap) end),
    register(?MODULE, Pid),
    {ok, Pid}.

loop(Map) ->
    receive
        {Pid, {create_account, U, P}} -> 
            case maps:find(U, Map) of
                {ok, _} ->
                    Pid ! user_exists,
                    loop(Map);
                error ->
                    NewMap = maps:put(U, {P, false, 1, 0}, Map),
                    save_accounts(NewMap),
                    Pid ! ok,
                    loop(NewMap)
            end;

        {Pid, {close_account, U, P}} -> 
            case maps:find(U, Map) of
                {ok, {P, _, _, _}} ->
                    NewMap = maps:remove(U, Map),
                    save_accounts(NewMap),
                    Pid ! ok,
                    loop(NewMap);
                _ ->
                    Pid ! invalid,
                    loop(Map) 
            end;

        {Pid, {login, U, P}} -> 
            case maps:find(U, Map) of
                {ok, {P, false, L, V}} ->
                    NewMap = maps:put(U, {P, true, L, V}, Map),
                    save_logged_account(U),
                    Pid ! ok,
                    loop(NewMap);
                _ ->
                    Pid ! invalid,
                    loop(Map) 
            end;

        {Pid, {logout, U}} -> 
            case maps:find(U, Map) of
                {ok, {P, true, L, V}} ->
                    NewMap = maps:put(U, {P, false, L, V}, Map),
                    logout_account(),
                    Pid ! ok,
                    loop(NewMap);
                _ ->
                    Pid ! invalid,
                    loop(Map) 
            end;

        {Pid, online} -> 
            OnlineUsers = [{U, L} || {U, {_, true, L, _}} <- maps:to_list(Map)],
            Pid ! OnlineUsers,
            loop(Map)
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