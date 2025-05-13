-module(game).
-import(gen_tcp, [listen/2]).
-import(server,[create_account/2, login/2, close_account/2, logout/1, start/0, online/0, get_player_level/1, get_player_streak/1]).
-import(queuelist, [add_to_queue/2, get_queue/0, startqueue/0, remove_from_queue/1]).
-import(partidas, [add_partida/1, get_partidas/0, update_partida/2, remove_partida/1, get_partida_by_player/1]).
-include("partida.hrl").
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
    partidas:start(),
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
                                    io:format("Sock is: ~p~n", [Sock]),
                                    io:format("Sockets matched: ~p and ~p~n", [Sock1, Sock2]),
                                    io:format("Matched players: ~s and ~s~n", [U1, U2]),
                                    comecarjogo(Sock1, U1, Sock2, U2);
                                queued ->
                                    io:format("Socket ~p queued for user ~s~n", [Sock, Username]),
                                    gen_tcp:send(Sock, "QUEUED\n"),
                                    io:format("current queue: ~p~n", [get_queue()]),
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
                    io:format("current queue: ~p~n", [get_queue()]),
                    queue_handler(Sock);
                {close_function, Username} ->
                    io:format("Closing function for user~n"),
                    ciclojogo(Username, Sock);
                {error, _} ->
                    io:format("Invalid queue command: ~s~n", [Data]),
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
        ["MATCH_FOUND", Username] ->
            {close_function, Username};
        _ ->
            {error, "Invalid queue command"}
    end.



comecarjogo(Sock1, Username1, Sock2, Username2) ->
    io:format("Starting game between ~s and ~s~n", [Username1, Username2]),
    gen_tcp:send(Sock1, "MATCHED LATE " ++ Username2 ++ "\n"),
    gen_tcp:send(Sock2, "MATCHED " ++ Username1 ++ "\n"),
    % Initialize game state
    NewPartida = #partida{
        player1 = Username1,
        player2 = Username2,
        sock1 = Sock1,
        sock2 = Sock2,
        player1Position = {100, 300},
        player2Position = {700, 300},
        player1Score = 0,
        player2Score = 0,
        projectiles = [],
        time = 120
    },
    add_partida(NewPartida),
    io:format("Partida added: ~p~n", [NewPartida]),
    % Spawn gestorPartidas in a separate process
    spawn(fun() -> gestorPartidas(Username1) end),
    ciclojogo(Username2, Sock2).
    

ciclojogo(Player, Sock) ->
    io:format("Entering game loop for ~s~n", [Player]),
    inet:setopts(Sock, [{active, once}]),
    
    receive
        {tcp, Sock, Data} ->
            io:format("Received input from ~s: ~s~n", [Player, Data]),
            case get_partida_by_player(Player) of
                {ok, GameState} ->
                    io:format("GameState for ~s: ~p~n", [Player, GameState]),
                    UpdatedGameState = handle_player_input(GameState, Player, Data),
                    update_partida(GameState#partida.player1, UpdatedGameState),
                    ciclojogo(Player, Sock);
                {error, not_found} ->
                    io:format("No partida found for player ~s~n", [Player]),
                    ok
            end;
        {tcp_closed, Sock} ->
            case get_partida_by_player(Player) of
                {ok, GameState} ->
                    io:format("Player (~s) disconnected~n", [Player]);
                    %OtherPlayer = case Player of
                    %    GameState#partida.player1 -> GameState#partida.player2;
                    %    GameState#partida.player2 -> GameState#partida.player1
                    %end,
                    %end_game(GameState, OtherPlayer);
                {error, not_found} ->
                    io:format("No partida found for player ~s after disconnection~n", [Player]),
                    ok
            end;
        {error, _} ->
            io:format("Error in game loop for ~s~n", [Player]),
            ciclojogo(Player, Sock)
    end.

handle_player_input(GameState, PlayerName, Data) ->
    io:format("Handling input for Player ~p: ~s~n", [PlayerName, Data]),
    Trimmed = string:trim(Data),
    case string:split(Trimmed, ":", all) of
        ["PLAYER1SCORE"] ->
            CurrentScore = GameState#partida.player1Score,
            NewScore = CurrentScore + 1,
            io:format("Increasing Player 1 score from ~p to ~p~n", [CurrentScore, NewScore]),
            UpdatedGameState = GameState#partida{player1Score = NewScore},
            UpdatedGameState;
        ["MOVE", "UP"] ->
            % Retrieve the partida dynamically using PlayerName
            case partidas:get_partida_by_player(PlayerName) of
                {ok, GameState} ->
                    {AccX, AccY} = get_acceleration(up),
                    UpdatedGameState =
                        case PlayerName == GameState#partida.player1 of
                            true ->
                                {NewSpeedX, NewSpeedY} = calculate_velocity(
                                    element(1, GameState#partida.palyer1Speed),
                                    element(2, GameState#partida.palyer1Speed),
                                    AccX, AccY),
                                {NewPosX, NewPosY} = calculate_position(
                                    element(1, GameState#partida.player1Position),
                                    element(2, GameState#partida.player1Position),
                                    NewSpeedX, NewSpeedY),
                                GameState#partida{
                                    palyer1Speed = {NewSpeedX, NewSpeedY},
                                    player1Position = {NewPosX, NewPosY}
                                };
                            false when PlayerName == GameState#partida.player2 ->
                                {NewSpeedX, NewSpeedY} = calculate_velocity(
                                    element(1, GameState#partida.player2Speed),
                                    element(2, GameState#partida.player2Speed),
                                    AccX, AccY),
                                {NewPosX, NewPosY} = calculate_position(
                                    element(1, GameState#partida.player2Position),
                                    element(2, GameState#partida.player2Position),
                                    NewSpeedX, NewSpeedY),
                                GameState#partida{
                                    player2Speed = {NewSpeedX, NewSpeedY},
                                    player2Position = {NewPosX, NewPosY}
                                }
                        end,
                    partidas:update_partida(GameState#partida.player1, UpdatedGameState),
                    UpdatedGameState;
                {error, not_found} ->
                    io:format("No partida found for player ~s~n", [PlayerName]),
                    GameState
            end;
        ["MOVE", "DOWN"] -> {move, down};
        ["MOVE", "LEFT"] -> {move, left};
        ["MOVE", "RIGHT"] -> {move, right};
        ["STOP", "UP"] -> {stop, up};
        ["STOP", "DOWN"] -> {stop, down};
        ["STOP", "LEFT"] -> {stop, left};
        ["STOP", "RIGHT"] -> {stop, right};
        _ ->
            io:format("Unknown input: ~s~n", [Data]),
            GameState
    end.


calculate_velocity(SpeedX, SpeedY, AccX, AccY) ->
    NewSpeedX = speed_limit(SpeedX + AccX, -?MAX_SPEED, ?MAX_SPEED) * ?FRICTION,
    NewSpeedY = speed_limit(SpeedY + AccY, -?MAX_SPEED, ?MAX_SPEED) * ?FRICTION,
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


gestorPartidas(Username1) ->
    %io:format("GestorPartidas called for ~s~n", [Username1]),
    Partida = get_partida_by_player(Username1),
    case Partida of
        {ok, P} ->
            %io:format("Partida found for ~s: ~p~n", [Username1, P]),
            % Debug print before sending partida
            %io:format("Sending partida to client: ~p~n", [P]),
            send_partida(P),
            erlang:send_after(16, self(), {continue, Username1}),
            wait_for_continue();
        {error, not_found} ->
            io:format("No partida found for ~s~n", [Username1])
    end.

wait_for_continue() ->
    receive
        {continue, Username1} ->
            gestorPartidas(Username1)
    end.

send_partida(Partida) ->
    % Convert the partida record to a custom delimited string
    CustomData = io_lib:format("P1:~s|P2:~s|S1:~p|S2:~p|T:~p",
                               [Partida#partida.player1,
                                Partida#partida.player2,
                                Partida#partida.player1Score,
                                Partida#partida.player2Score,
                                Partida#partida.time]),
    % Send the custom delimited data to both players
    gen_tcp:send(Partida#partida.sock1, CustomData ++ "\n"),
    gen_tcp:send(Partida#partida.sock2, CustomData ++ "\n").

end_game(GameState, Winner) ->
    Player1 = GameState#partida.player1,
    Player2 = GameState#partida.player2,
    io:format("Game ended. Winner: ~p~n", [Winner]),

    {WinnerUsername, LoserUsername} = 
        case Winner of
            1 -> {Player1, Player2};
            2 -> {Player2, Player1};
            _ -> {Player1, Player2}
        end,

    WinnerLevel = get_player_level(WinnerUsername),
    LoserLevel = get_player_level(LoserUsername),
    WinnerStrak = server:get_player_streak(WinnerUsername),
    LoserStreak = server:get_player_streak(LoserUsername),

    server:update_account_stats(WinnerUsername, WinnerLevel, WinnerStrak, 1),
    server:update_account_stats(LoserUsername, LoserLevel, LoserStreak, -1), 

    gen_tcp:send(GameState#partida.sock1, io_lib:format("GAME_OVER: Winner - ~s\n", [WinnerUsername])),
    gen_tcp:send(GameState#partida.sock2, io_lib:format("GAME_OVER: Winner - ~s\n", [WinnerUsername])),
    
    remove_partida(Player1).