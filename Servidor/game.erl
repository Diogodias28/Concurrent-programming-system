-module(game).
-import(gen_tcp, [listen/2]).
-import(server,[create_account/2, login/2, close_account/2, logout/1, start/0, online/0]).
-import(queuelist, [add_to_queue/2, get_queue/0, startqueue/0]).
-export([start/1, authenticator/1, parse_auth_input/1]).

-define(FRICTION, 0.98).
-define(INITIAL_ACCELERATION, 0.01).
-define(ACCELERATION_INCREMENT, 0.01).
-define(MAX_SPEED, 6).
-define(GUI_HEIGHT, 70).
-define(ARENA_HEIGHT, 600).
-define(ARENA_WIDTH, 800).

start(Port) ->
    io:format("Starting game server on port ~p~n", [Port]),
    % Start the account server first
    case server:start() of
        {ok, _Pid} ->
            io:format("Account server started successfully~n"),
            {ok, LSock} = gen_tcp:listen(Port, [
                {packet, line}, {reuseaddr, true}, {active, false}
            ]),
            io:format("Listening for connections...~n"),
            spawn(fun() -> acceptor(LSock) end);
        {error, already_started} ->
            io:format("Account server already running~n"),
            {ok, LSock} = gen_tcp:listen(Port, [
                {packet, line}, {reuseaddr, true}, {active, false}
            ]),
            io:format("Listening for connections...~n"),
            spawn(fun() -> acceptor(LSock) end);
        Error ->
            io:format("Failed to start account server: ~p~n", [Error]),
            Error
    end.

acceptor(LSock) ->
    {ok, Sock} = gen_tcp:accept(LSock),
    {ok, {IP, Port}} = inet:peername(Sock),
    io:format("New connection from ~p:~p~n", [IP, Port]),
    spawn(fun() -> acceptor(LSock) end),
    case authenticator(Sock) of
        {ok, Username} ->
            io:format("Authentication successful for ~s from ~p:~p~n", [Username, IP, Port]),
            worker(Sock, {?ARENA_WIDTH / 4, (?ARENA_HEIGHT - ?GUI_HEIGHT) / 2 + ?GUI_HEIGHT}, {0, 0});
        {error, Reason} ->
            io:format("Connection closed (~p) from ~p:~p~n", [Reason, IP, Port]),
            gen_tcp:close(Sock)
    end.

authenticator(Sock) ->
    {ok, {IP, _}} = inet:peername(Sock),
    inet:setopts(Sock, [{active, once}]),
    receive
        {tcp, Sock, Data} ->
            io:format("Auth attempt from ~p: ~s", [IP, Data]),
            case parse_auth_input(Data) of
                {login, Username, Password} ->
                    handle_login(Sock, IP, Username, Password);
                {create_account, Username, Password} ->
                    handle_create_account(Sock, IP, Username, Password);
                {error, Reason} ->
                    io:format("Invalid auth command from ~p: ~p~n", [IP, Reason]),
                    gen_tcp:send(Sock, "INVALID_COMMAND\n"),
                    authenticator(Sock)
            end;
        {tcp_closed, Sock} ->
            io:format("Client from ~p closed connection during auth~n", [IP]),
            {error, closed};
        {tcp_error, Sock, Reason} ->
            io:format("Socket error from ~p during auth: ~p~n", [IP, Reason]),
            {error, Reason}
    end.

handle_login(Sock, IP, Username, Password) ->
    case server:login(Username, Password) of
        ok ->
            io:format("Login successful for ~s from ~p~n", [Username, IP]),
            gen_tcp:send(Sock, "LOGIN_SUCCESS\n"),
            {ok, Username};
        invalid ->
            io:format("Failed login for ~s from ~p~n", [Username, IP]),
            gen_tcp:send(Sock, "LOGIN_FAILED\n"),
            authenticator(Sock)
    end.

handle_create_account(Sock, IP, Username, Password) ->
    case server:create_account(Username, Password) of
        ok ->
            io:format("Account created for ~s from ~p~n", [Username, IP]),
            gen_tcp:send(Sock, "ACCOUNT_CREATED\n"),
            % Immediately attempt login with new credentials
            case server:login(Username, Password) of
                ok ->
                    io:format("Auto-login successful for ~s from ~p~n", [Username, IP]),
                    gen_tcp:send(Sock, "LOGIN_SUCCESS\n"),
                    {ok, Username};
                invalid ->
                    io:format("Auto-login failed for ~s from ~p~n", [Username, IP]),
                    gen_tcp:send(Sock, "ACCOUNT_CREATED_LOGIN_FAILED\n"),
                    authenticator(Sock)
            end;
        user_exists ->
            io:format("Username ~s already exists (from ~p)~n", [Username, IP]),
            gen_tcp:send(Sock, "USERNAME_TAKEN\n"),
            authenticator(Sock)
    end.

% Rest of your existing functions...
parse_auth_input(Data) ->
    Trimmed = string:trim(Data),
    case string:split(Trimmed, ":", all) of
        ["LOGIN", Username, Password] ->
            {login, string:trim(Username), string:trim(Password)};
        ["CREATE_ACCOUNT", Username, Password] ->
            {create_account, string:trim(Username), string:trim(Password)};
        _ ->
            {error, "Invalid authentication command"}
    end.

worker(Sock, {PlayerX, PlayerY}, {PlayerSpeedX, PlayerSpeedY}) ->
    inet:setopts(Sock, [{active, once}]),
    receive
        {tcp, Sock, Data} ->
            io:format("Received data: ~s~n", [Data]),
            case parse_input(Data) of
                {move, Direction} ->  
                    Confirmation = io_lib:format("comando recebido move,~s\n", [string:to_upper(atom_to_list(Direction))]),
                    gen_tcp:send(Sock, Confirmation),
                    {AccX, AccY} = get_acceleration(Direction),
                    {NewPlayerSpeedX, NewPlayerSpeedY} = calculate_velocity(PlayerSpeedX, PlayerSpeedY, AccX, AccY),
                    {NewPlayerX, NewPlayerY} = calculate_position(PlayerX, PlayerY, NewPlayerSpeedX, NewPlayerSpeedY),
                    Response = io_lib:format("PLAYER_POS ~f ~f\n", [NewPlayerX, NewPlayerY]),
                    case gen_tcp:send(Sock, Response) of
                        ok -> ok;
                        {error, Reason} ->
                            io:format("Failed to send data: ~p~n", [Reason])
                    end,
                    worker(Sock, {NewPlayerX, NewPlayerY}, {NewPlayerSpeedX, NewPlayerSpeedY});
                {stop, Direction} ->
                    Confirmation = io_lib:format("Comando recebido, stop,~s\n", [string:to_upper(atom_to_list(Direction))]),
                    gen_tcp:send(Sock, Confirmation),
                    {NewPlayerSpeedX, NewPlayerSpeedY} = calculate_velocity(PlayerSpeedX, PlayerSpeedY, 0, 0),
                    {NewPlayerX, NewPlayerY} = calculate_position(PlayerX, PlayerY, NewPlayerSpeedX, NewPlayerSpeedY),
                    Response = io_lib:format("PLAYER_POS ~f ~f\n", [NewPlayerX, NewPlayerY]),
                    case gen_tcp:send(Sock, Response) of
                        ok -> ok;
                        {error, Reason} ->
                            io:format("Failed to send data: ~p~n", [Reason])
                    end,
                    worker(Sock, {NewPlayerX, NewPlayerY}, {NewPlayerSpeedX, NewPlayerSpeedY});
                {error, Reason} ->
                    io:format("Invalid input: ~s~n", [Reason]),
                    worker(Sock, {PlayerX, PlayerY}, {PlayerSpeedX, PlayerSpeedY})
            end;
        {tcp_closed, Sock} ->
            io:format("Socket closed. ~n"),
            ok;
        {tcp_error, Sock, Reason} ->
            io:format("Socket error: ~p~n", [Reason]),
            ok
    end.

parse_input(Data) ->
    case [string:trim(Part) || Part <- string:split(string:trim(Data), ",", all)] of
        ["MOVE", "UP"] -> {move, up};
        ["MOVE", "DOWN"] -> {move, down};
        ["MOVE", "LEFT"] -> {move, left};
        ["MOVE", "RIGHT"] -> {move, right};
        ["STOP", "UP"] -> {stop, up};
        ["STOP", "DOWN"] -> {stop, down};
        ["STOP", "LEFT"] -> {stop, left};
        ["STOP", "RIGHT"] -> {stop, right};
        _ -> {error, "Invalid input"}
    end.

calculate_velocity(SpeedX, SpeedY, AccX, AccY) ->
    NewSpeedX = speed_limit(SpeedX + AccX, ?MAX_SPEED, -?MAX_SPEED) * ?FRICTION,
    NewSpeedY = speed_limit(SpeedY + AccY, ?MAX_SPEED, -?MAX_SPEED) * ?FRICTION,
    {NewSpeedX, NewSpeedY}.

calculate_position(X, Y, SpeedX, SpeedY) ->
    {X + SpeedX, Y + SpeedY}.

speed_limit(Vel, Max, Min) ->
    if 
        Vel > Max ->
            Max;
        Vel < Min ->
            Min;
        true ->
            Vel
    end.

get_acceleration(left) ->
    {-(?INITIAL_ACCELERATION + 1 * ?ACCELERATION_INCREMENT), 0};
get_acceleration(right) ->
    {?INITIAL_ACCELERATION + 1 * ?ACCELERATION_INCREMENT, 0};
get_acceleration(up) ->
    {0, -(?INITIAL_ACCELERATION + 1 * ?ACCELERATION_INCREMENT)};
get_acceleration(down) ->
    {0, ?INITIAL_ACCELERATION + 1 * ?ACCELERATION_INCREMENT}.   