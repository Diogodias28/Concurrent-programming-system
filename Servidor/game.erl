-module(game).
-import(gen_tcp, [listen/2]).
-import(server,[create_account/2, login/2, close_account/2, logout/1, start/0, online/0]).
-import(queuelist, [add_to_queue/2, get_queue/0, startqueue/0, remove_from_queue/1]).
-export([start/1, authenticator/1, parse_auth_input/1]).

-define(FRICTION, 0.98).
-define(INITIAL_ACCELERATION, 0.01).
-define(ACCELERATION_INCREMENT, 0.01).
-define(MAX_SPEED, 6).
-define(GUI_HEIGHT, 70).
-define(ARENA_HEIGHT, 600).
-define(WALL_THICKNESS, 10).
-define(ARENA_WIDTH, 800).

start(Port) ->
    io:format("Starting game server on port ~p~n", [Port]),
    queuelist:start(),
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
            queue_handler(Sock);
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
                    queue_handler(Sock),
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

queue_handler(Sock) ->
    inet:setopts(Sock, [{active, once}]),
    receive
        {tcp, Sock, Data} ->
            case parse_queue_input(Data) of
                {add_to_queue, Username} ->
                    case server:get_player_level(Username) of  
                        {ok, Level} ->
                            case queuelist:add_to_queue(Username, Level, Sock) of
                                {matched, U1, Sock1, U2, Sock2} ->
                                    io:format("Matched players: ~s and ~s~n", [U1, U2]),
                                    gen_tcp:send(Sock1, "MATCHED " ++ U2 ++ "\n"),
                                    gen_tcp:send(Sock2, "MATCHED " ++ U1 ++ "\n"),
                                    Pid1 = spawn(fun() -> 
                                        worker(Sock1, {?ARENA_WIDTH / 4, (?ARENA_HEIGHT - ?GUI_HEIGHT) / 2 + ?GUI_HEIGHT}, {0, 0}, none) 
                                    end),
                                    Pid2 = spawn(fun() -> 
                                        worker(Sock2, {3 * ?ARENA_WIDTH / 4, (?ARENA_HEIGHT - ?GUI_HEIGHT) / 2 + ?GUI_HEIGHT}, {0, 0}, Pid1) 
                                    end),
                                    Pid1 ! {opponent_pid, Pid2};
                                queued ->
                                    gen_tcp:send(Sock, "QUEUED\n"),
                                    queue_handler(Sock);
                                already_queued ->
                                    gen_tcp:send(Sock, "ALREADY_IN_QUEUE\n"),
                                    queue_handler(Sock)
                            end;
                        {error, _} ->
                            gen_tcp:send(Sock, "USER_NOT_FOUND\n"),
                            queue_handler(Sock)
                    end;
                {remove_from_queue, Username} ->
                    io:format("Removing user ~s from queue~n", [Username]),
                    queuelist:remove_from_queue(Username),
                    gen_tcp:send(Sock, "UNQUEUED\n"),
                    queue_handler(Sock);
                {error, _} ->
                    gen_tcp:send(Sock, "INVALID_QUEUE_COMMAND\n"),
                    queue_handler(Sock)
            end;
        {tcp_closed, Sock} ->
            io:format("Socket closed.~n"),
            ok;
        {tcp_error, Sock, Reason} ->
            io:format("Socket error: ~p~n", [Reason]),
            ok
    end.

parse_queue_input(Data) ->
    Trimmed = string:trim(Data),
    case string:split(Trimmed, ":", all) of
        ["QUEUE", Username] ->
            {add_to_queue, string:trim(Username)};
        ["UNQUEUE", Username] ->
            {remove_from_queue, string:trim(Username)};
        _ ->
            {error, "Invalid queue command"}
    end.

worker(Sock, {PlayerX, PlayerY}, {PlayerSpeedX, PlayerSpeedY}, OpponentPid) ->
    worker(Sock, {PlayerX, PlayerY}, {PlayerSpeedX, PlayerSpeedY}, OpponentPid, sets:new()).

worker(Sock, {PlayerX, PlayerY}, {PlayerSpeedX, PlayerSpeedY}, OpponentPid, ActiveKeys) ->
    inet:setopts(Sock, [{active, once}]),
    receive
        {tcp, Sock, Data} ->
            case parse_input(Data) of
                {key_press, Direction} ->
                    NewActiveKeys = sets:add_element(Direction, ActiveKeys),
                    worker(Sock, {PlayerX, PlayerY}, {PlayerSpeedX, PlayerSpeedY}, OpponentPid, NewActiveKeys);
                {key_release, Direction} ->
                    NewActiveKeys = sets:del_element(Direction, ActiveKeys),
                    worker(Sock, {PlayerX, PlayerY}, {PlayerSpeedX, PlayerSpeedY}, OpponentPid, NewActiveKeys);
                {error, Reason} ->
                    io:format("Invalid input: ~s~n", [Reason]),
                    worker(Sock, {PlayerX, PlayerY}, {PlayerSpeedX, PlayerSpeedY}, OpponentPid, ActiveKeys)
            end;
        {position_update, OppX, OppY} ->
            % Send full game state to client
            GameState = io_lib:format("GAME_STATE ~f ~f ~f ~f\n", 
                                    [PlayerX, PlayerY, OppX, OppY]),
            gen_tcp:send(Sock, GameState),
            worker(Sock, {PlayerX, PlayerY}, {PlayerSpeedX, PlayerSpeedY}, OpponentPid, ActiveKeys);
        {opponent_pid, NewOpponentPid} ->
            worker(Sock, {PlayerX, PlayerY}, {PlayerSpeedX, PlayerSpeedY}, NewOpponentPid, ActiveKeys);
        update ->
            % Calculate acceleration based on active keys
            {AccX, AccY} = calculate_acceleration(ActiveKeys),
            
            % Calculate new velocity and position
            {NewPlayerSpeedX, NewPlayerSpeedY} = calculate_velocity(PlayerSpeedX, PlayerSpeedY, AccX, AccY),
            {NewPlayerX, NewPlayerY} = calculate_position(PlayerX, PlayerY, NewPlayerSpeedX, NewPlayerSpeedY),
            
            % Check boundaries
            {FinalX, FinalY} = check_boundaries(NewPlayerX, NewPlayerY),
            
            % Notify opponent
            case OpponentPid of
                none -> ok;
                _ -> OpponentPid ! {position_update, FinalX, FinalY}
            end,
            
            % Schedule next update
            erlang:send_after(16, self(), update), % ~60fps
            
            worker(Sock, {FinalX, FinalY}, {NewPlayerSpeedX, NewPlayerSpeedY}, OpponentPid, ActiveKeys);
        {tcp_closed, Sock} ->
            io:format("Socket closed.~n"),
            ok;
        {tcp_error, Sock, Reason} ->
            io:format("Socket error: ~p~n", [Reason]),
            ok
    after 0 ->
        % Initial update message
        self() ! update,
        worker(Sock, {PlayerX, PlayerY}, {PlayerSpeedX, PlayerSpeedY}, OpponentPid, ActiveKeys)
    end.

parse_input(Data) ->
    case string:split(string:trim(Data), ":", all) of
        ["KEY_PRESS", Direction] -> {key_press, list_to_atom(string:to_lower(Direction))};
        ["KEY_RELEASE", Direction] -> {key_release, list_to_atom(string:to_lower(Direction))};
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

calculate_acceleration(ActiveKeys) ->
    lists:foldl(
        fun(Direction, {AccX, AccY}) ->
            {DirX, DirY} = get_acceleration(Direction),
            {AccX + DirX, AccY + DirY}
        end,
        {0, 0},
        sets:to_list(ActiveKeys)
    ).

check_boundaries(X, Y) ->
    NewX = if
        X < ?WALL_THICKNESS -> ?WALL_THICKNESS;
        X > ?ARENA_WIDTH - ?WALL_THICKNESS -> ?ARENA_WIDTH - ?WALL_THICKNESS;
        true -> X
    end,
    NewY = if
        Y < ?GUI_HEIGHT + ?WALL_THICKNESS -> ?GUI_HEIGHT + ?WALL_THICKNESS;
        Y > ?ARENA_HEIGHT + ?GUI_HEIGHT - ?WALL_THICKNESS -> ?ARENA_HEIGHT + ?GUI_HEIGHT - ?WALL_THICKNESS;
        true -> Y
    end,
    {NewX, NewY}.

get_acceleration(left) ->
    {-(?INITIAL_ACCELERATION + 1 * ?ACCELERATION_INCREMENT), 0};
get_acceleration(right) ->
    {?INITIAL_ACCELERATION + 1 * ?ACCELERATION_INCREMENT, 0};
get_acceleration(up) ->
    {0, -(?INITIAL_ACCELERATION + 1 * ?ACCELERATION_INCREMENT)};
get_acceleration(down) ->
    {0, ?INITIAL_ACCELERATION + 1 * ?ACCELERATION_INCREMENT}.