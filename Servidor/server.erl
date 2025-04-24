-module(server).
-export([create_account/2, login/2, close_account/2, logout/1, start/0, online/0]).

% client

rpc(Msg) ->
    ?MODULE ! {self(), Msg},
    receive Response -> Response end.

create_account(User, Pass) -> %ok | user_exists
    rpc({create_account, User, Pass}).

close_account(User, Pass) -> %ok | invalid
    rpc({close_account, User, Pass}).

login(User, Pass) -> %ok | invalid
    rpc({login, User, Pass}).

logout(User) -> %ok
    rpc({logout, User}).

online() -> %[User]
        rpc(online).


% server

start() ->
    Map = #{},% mapa vazio Ã© criado assim
    Pid = spawn(fun () -> loop(Map) end),
    register(?MODULE, Pid).

loop(Map) ->
    receive
        {Pid, {create_account, U, P}} -> 
            case maps:find(U, Map) of
                {ok, _} ->
                    Pid ! user_exists,
                    loop(Map);
                error ->
                    NewMap = maps:put(U, {P, false, 1, 0}, Map),% Username, {Password, Status, Level, Victory Sequence}
                    Pid ! ok,
                    loop(NewMap)
            end;
        {Pid, {close_account, U, P}} -> 
            case maps:find(U, Map) of
                %{ok, {P1, _, _, _}} ->
                    %case P1 == P of 
                        %true -> 
                            %NewMap = maps:remove(U, Map),
                            %Pid ! ok,
                            %loop(NewMap);
                        %false ->
                            %Pid ! invalid,
                            %loop(Map)
                    %end;
                {ok, {P1, _, _, _}} when P1 =:= P ->
                    NewMap = maps:remove(U, Map),
                    Pid ! ok,
                    loop(NewMap);
                error ->
                    Pid ! invalid,
                    loop(Map) 
            end;
        {Pid, {login, U, P}} -> 
            case maps:find(U, Map) of
                {ok, {P, false, L, V}} ->
                    NewMap = maps:put(U, {P, true, L, V}, Map),
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
                    Pid ! ok,
                    loop(NewMap);
                _ ->
                    Pid ! invalid,
                    loop(Map) 
            end;
        {Pid, online} -> 
            Pid ! [{U, L} || {U , {_, true, L, _}} <- maps:to_list(Map)],
            loop(Map)
    end.

% & "D:\Erlang OTP\bin\erl.exe" - make