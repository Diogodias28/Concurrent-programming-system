-module(game).
-import(gen_tcp, [listen/2]).
-import(server,[create_account/2, login/2, close_account/2, logout/1, start/0, online/0, get_player_level/1, get_player_streak/1, update_account_stats/4,top_10/0, updateStats/3]).
-import(queuelist, [add_to_queue/2, get_queue/0, startqueue/0, remove_from_queue/1]).
-import(partidas, [add_partida/1, get_partidas/0, update_partida/2, remove_partida/1, get_partida_by_player/1]).
-include("partida.hrl").
-export([start/1, authenticator/1, parse_auth_input/1, shutdown_server/0]).


-define(FRICTION, 0.98).
-define(ACCEL_FRICTION, 0.95).
-define(INITIAL_ACCELERATION, 0.01).
-define(ACCELERATION_INCREMENT, 0.02).
-define(MAX_SPEED, 6).
-define(GUI_HEIGHT, 70).
-define(ARENA_HEIGHT, 600).
-define(WALL_THICKNESS, 10).
-define(ARENA_WIDTH, 800).
-define(PLAYER_RADIUS, 15).
-define(PROJECTILE_RADIUS, 5).
-define(MODIFICADOR_RADIUS, 10).
-define(SHOT_COOLDOWN, 5000).
-define(SHOT_SPEED, 10).
-define(PROJECTILE_SPEED_MOD, 8).
-define(SHOT_COOLDOWN_MOD, 3500).
-define(MOD_DECAY_TIME, 20000). % 20 seconds in ms

start(Port) ->
    io:format("Starting game server on port ~p~n", [Port]),
    queuelist:start(),
    partidas:start(),
    socketRegistry:start(),
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
    socketRegistry:add(Sock),
    {ok, {IP, Port}} = inet:peername(Sock),
    io:format("New connection from ~p:~p~n", [IP, Port]),
    spawn(fun() -> acceptor(LSock) end),
    case authenticator(Sock) of
        {ok, Username} ->
            io:format("Authentication successful for ~s from ~p:~p~n", [Username, IP, Port]);
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
            socketRegistry:remove(Sock),
            {error, closed};
        {tcp_error, Sock, Reason} ->
            io:format("Socket error from ~p during auth: ~p~n", [IP, Reason]),
            socketRegistry:remove(Sock),
            {error, Reason}
    end.

handle_login(Sock, IP, Username, Password) ->
    case server:login(Username, Password) of
        ok ->
            io:format("Login successful for ~s from ~p~n", [Username, IP]),
            gen_tcp:send(Sock, "LOGIN_SUCCESS\n"),
            {Level, Streak} = get_player_stats(Username),
            gen_tcp:send(Sock, io_lib:format("STATS:~p,~p\n", [Level, Streak])),
            queue_handler(Sock, Username),
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
                    queue_handler(Sock, Username),
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

queue_handler(Sock, Player) ->
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
                                    comecarjogo(Sock1, U1, Sock2, U2),
                                    ciclojogo(Username, Sock);
                                queued ->
                                    io:format("Socket ~p queued for user ~s~n", [Sock, Username]),
                                    gen_tcp:send(Sock, "QUEUED\n"),
                                    io:format("current queue: ~p~n", [get_queue()]),
                                    queue_handler(Sock, Player);
                                already_queued ->
                                    gen_tcp:send(Sock, "ALREADY_IN_QUEUE\n"),
                                    queue_handler(Sock, Player)
                            end;
                        {error, _} ->
                            gen_tcp:send(Sock, "USER_NOT_FOUND\n"),
                            queue_handler(Sock, Player)
                    end;
                {remove_from_queue, Username} ->
                    io:format("Removing user ~s from queue~n", [Username]),
                    queuelist:remove_from_queue(Username),
                    gen_tcp:send(Sock, "UNQUEUED\n"),
                    io:format("current queue: ~p~n", [get_queue()]),
                    queue_handler(Sock, Player);
                {close_function, Username} ->
                    io:format("Closing function for user~n"),
                    ciclojogo(Username, Sock);
                {logout, Username} ->
                    io:format("Logging out user ~s~n", [Username]),
                    server:logout(Username),
                    gen_tcp:send(Sock, "LOGOUT_SUCCESS\n"),
                    authenticator(Sock);
                {close_account, Username, Password} ->
                    io:format("Closing account for user ~s~n", [Username]),
                    case server:close_account(Username, Password) of
                        ok ->
                            gen_tcp:send(Sock, "ACCOUNT_CLOSED\n"),
                            authenticator(Sock);
                        error ->
                            gen_tcp:send(Sock, "ACCOUNT_CLOSURE_FAILED\n"),
                            queue_handler(Sock, Player)
                    end;
                {top_10, Username} ->
                    io:format("Top 10 players requested by ~s~n", [Username]),
                    Top10Str = server:top_10(),
                    gen_tcp:send(Sock, "TOP_10:" ++ Top10Str ++ "\n"),
                    queue_handler(Sock, Player);
                {error, _} ->
                    io:format("Invalid queue command: ~s~n", [Data]),
                    gen_tcp:send(Sock, "INVALID_QUEUE_COMMAND\n"),
                    queue_handler(Sock, Player)
            end;
        {tcp_closed, Sock} ->
            io:format("Socket closed.~n"),
            socketRegistry:remove(Sock),
            server:logout(Player),
            ok;
        {tcp_error, Sock, Reason} ->
            io:format("Socket error: ~p~n", [Reason]),
            socketRegistry:remove(Sock),
            ok
    end.

parse_queue_input(Data) ->
    Trimmed = string:trim(Data),
    io:format("Parsing queue input: ~s~n", [Trimmed]),
    case string:split(Trimmed, ":", all) of
        ["QUEUE", Username] ->
            {add_to_queue, string:trim(Username)};
        ["UNQUEUE", Username] ->
            {remove_from_queue, string:trim(Username)};
        ["MATCH_FOUND", Username] ->
            {close_function, Username};
        ["LOGOUT", Username] ->
            {logout, string:trim(Username)};
        ["CLOSE_ACCOUNT", Username, Password] ->
            {close_account, string:trim(Username), string:trim(Password)};
        ["TOP_10", Username] ->
            {top_10, string:trim(Username)};
        _ ->
            {error, "Invalid queue command"}
    end.



comecarjogo(Sock1, Username1, Sock2, Username2) ->
    io:format("Starting game between ~s and ~s~n", [Username1, Username2]),
    gen_tcp:send(Sock1, "MATCHED " ++ Username1 ++ " " ++ Username2 ++ "\n"),
    gen_tcp:send(Sock2, "MATCHED " ++ Username1 ++ " " ++ Username2 ++ "\n"),
    CurrentTime = erlang:monotonic_time(millisecond),
    RandomTime = (5000 + rand:uniform(10000)),
    % Initialize game state
    NewPartida = #partida{
        player1 = Username1,
        player2 = Username2,
        sock1 = Sock1,
        sock2 = Sock2,
        player1Position = {100, 300},
        player2Position = {700, 300},
        player1LastShot = CurrentTime - ?SHOT_COOLDOWN,
        player2LastShot = CurrentTime - ?SHOT_COOLDOWN,
        player1ShotCooldown = ?SHOT_COOLDOWN,
        player2ShotCooldown = ?SHOT_COOLDOWN,
        player1ShotSpeed = ?SHOT_SPEED,
        player2ShotSpeed = ?SHOT_SPEED,
        modificadorSpawnTime = CurrentTime + RandomTime,
        startTime = CurrentTime
    },
    add_partida(NewPartida),
    io:format("Partida added: ~p~n", [NewPartida]),
    % Spawn gestorPartidas in a separate process
    spawn(fun() -> gestorPartidas(Username1) end).
    

ciclojogo(Player, Sock) ->
    io:format("Entering game loop for ~s~n", [Player]),
    inet:setopts(Sock, [{active, once}]),
    receive
        {tcp, Sock, Data} ->
            io:format("Received input from ~s: ~s~n", [Player, Data]),
            case get_partida_by_player(Player) of
                {ok, GameState} ->
                    %io:format("GameState for ~s: ~p~n", [Player, GameState]),
                    UpdatedGameState = handle_player_input(GameState, Player, Data),
                    %io:format("Updated GameState: ~p~n", [UpdatedGameState]),
                    update_partida(GameState#partida.player1, UpdatedGameState),
                    ciclojogo(Player, Sock);
                {error, not_found} ->
                    % Se o comando for MATCH_ENDED, retorna para a fila
                    case string:split(string:trim(Data), ":", all) of
                        ["MATCH_ENDED", _Username] ->
                            io:format("No partida found, but received MATCH_ENDED. Returning ~s to queue handler~n", [Player]),
                            queue_handler(Sock, Player);
                        _ ->
                            io:format("No partida found for player ~s~n", [Player]),
                            ok
                    end
            end;
        {tcp_closed, Sock} ->
            socketRegistry:remove(Sock),
            % Only process as a "loss" if not shutting down
            case socketRegistry:is_shutting_down() of
                true ->
                    io:format("Server is shutting down, not sending GAME_OVER for ~s~n", [Player]),
                    ok;
                false ->
                    case get_partida_by_player(Player) of
                        {ok, GameState} ->
                            io:format("Player (~s) disconnected~n", [Player]),
                            OtherPlayer = case Player of
                                P when P =:= GameState#partida.player1 -> GameState#partida.player2;
                                P when P =:= GameState#partida.player2 -> GameState#partida.player1
                            end,
                            io:format("otherPlayer: ~s~n", [OtherPlayer]),
                            server:logout(Player),
                            WinnerNum = case OtherPlayer of
                                _ when OtherPlayer =:= GameState#partida.player1 -> 1;
                                _ when OtherPlayer =:= GameState#partida.player2 -> 2
                            end,
                            end_game(GameState, WinnerNum);
                        {error, not_found} ->
                            io:format("No partida found for player ~s after disconnection~n", [Player]),
                            ok
                    end
            end;
        {error, _} ->
            io:format("Error in game loop for ~s~n", [Player]),
            socketRegistry:remove(Sock),
            ciclojogo(Player, Sock)
    end.

handle_player_input(GameState, PlayerName, Data) ->
    %io:format("Handling input for Player ~p: ~s~n", [PlayerName, Data]),
    Trimmed = string:trim(Data),
    case string:split(Trimmed, ":", all) of
        ["KEY_PRESS", Key] ->
            update_key_state(GameState, PlayerName, string:to_upper(Key), press);
        ["KEY_RELEASE", Key] ->
            update_key_state(GameState, PlayerName, string:to_upper(Key), release);
        ["MOVE", "UP"] ->
            case partidas:get_partida_by_player(PlayerName) of
                {ok, NewGameState} ->
                    UpdatedGameState =
                        case PlayerName == NewGameState#partida.player1 of
                            true ->
                                {NewAcc} = calculate_acceleration(
                                    element(2, NewGameState#partida.player1acceleration),
                                    -?ACCELERATION_INCREMENT
                                ),
                                NewGameState#partida{
                                    player1acceleration = {element(1, NewGameState#partida.player1acceleration), NewAcc}
                                };
                            false when PlayerName == NewGameState#partida.player2 ->
                                {NewAcc} = calculate_acceleration(
                                    element(2, NewGameState#partida.player2acceleration),
                                    -?ACCELERATION_INCREMENT
                                ),
                                NewGameState#partida{
                                    player2acceleration = {element(1, NewGameState#partida.player2acceleration), NewAcc}
                                }
                        end,
                    UpdatedGameState;
                {error, not_found} ->
                    io:format("No partida found for player ~s~n", [PlayerName]),
                    GameState
            end;
        ["MOVE", "DOWN"] ->
            case partidas:get_partida_by_player(PlayerName) of
                {ok, NewGameState} ->
                    UpdatedGameState =
                        case PlayerName == NewGameState#partida.player1 of
                            true ->
                                {NewAcc} = calculate_acceleration(
                                    element(2, NewGameState#partida.player1acceleration),
                                    ?ACCELERATION_INCREMENT
                                ),
                                NewGameState#partida{
                                    player1acceleration = {element(1, NewGameState#partida.player1acceleration), NewAcc}
                                };
                            false when PlayerName == NewGameState#partida.player2 ->
                                {NewAcc} = calculate_acceleration(
                                    element(2, NewGameState#partida.player2acceleration),
                                    ?ACCELERATION_INCREMENT
                                ),
                                NewGameState#partida{
                                    player2acceleration = {element(1, NewGameState#partida.player2acceleration), NewAcc}
                                }
                        end,
                    UpdatedGameState;
                {error, not_found} ->
                    io:format("No partida found for player ~s~n", [PlayerName]),
                    GameState
            end;
        ["MOVE", "LEFT"] ->
            case partidas:get_partida_by_player(PlayerName) of
                {ok, NewGameState} ->
                    UpdatedGameState =
                        case PlayerName == NewGameState#partida.player1 of
                            true ->
                                {NewAcc} = calculate_acceleration(
                                    element(1, NewGameState#partida.player1acceleration),
                                    -?ACCELERATION_INCREMENT
                                ),
                                NewGameState#partida{
                                    player1acceleration = {NewAcc,element(2, NewGameState#partida.player1acceleration)}
                                };
                            false when PlayerName == NewGameState#partida.player2 ->
                                {NewAcc} = calculate_acceleration(
                                    element(1, NewGameState#partida.player2acceleration),
                                    -?ACCELERATION_INCREMENT
                                ),
                                NewGameState#partida{
                                    player2acceleration = {NewAcc,element(2, NewGameState#partida.player2acceleration)}
                                }
                        end,
                    UpdatedGameState;
                {error, not_found} ->
                    io:format("No partida found for player ~s~n", [PlayerName]),
                    GameState
            end;
        ["MOVE", "RIGHT"] -> 
            case partidas:get_partida_by_player(PlayerName) of
                {ok, NewGameState} ->
                    UpdatedGameState =
                        case PlayerName == NewGameState#partida.player1 of
                            true ->
                                {NewAcc} = calculate_acceleration(
                                    element(1, NewGameState#partida.player1acceleration),
                                    ?ACCELERATION_INCREMENT
                                ),
                                NewGameState#partida{
                                    player1acceleration = {NewAcc,element(2, NewGameState#partida.player1acceleration)}
                                };
                            false when PlayerName == NewGameState#partida.player2 ->
                                {NewAcc} = calculate_acceleration(
                                    element(1, NewGameState#partida.player2acceleration),
                                    ?ACCELERATION_INCREMENT
                                ),
                                NewGameState#partida{
                                    player2acceleration = {NewAcc,element(2, NewGameState#partida.player2acceleration)}
                                }
                        end,
                    UpdatedGameState;
                {error, not_found} ->
                    io:format("No partida found for player ~s~n", [PlayerName]),
                    GameState
            end;
        ["STOP", "UP"] -> 
            io:format("Stopping UP for player ~s~n", [PlayerName]),
            GameState;
        ["STOP", "DOWN"] -> 
            io:format("Stopping DOWN for player ~s~n", [PlayerName]),
            GameState;
        ["STOP", "LEFT"] -> 
            io:format("Stopping LEFT for player ~s~n", [PlayerName]),
            GameState;
        ["STOP", "RIGHT"] -> 
            io:format("Stopping RIGHT for player ~s~n", [PlayerName]),
            GameState;
        ["MATCH_FOUND", Username] ->
            io:format("Match found for player ~s~n", [Username]),
            GameState;
        ["MATCH_ENDED", Username] ->
            io:format("Match ended for player ~s~n", [Username]),
            {match_ended, Username};
        ["LAUNCH_PROJ", AngleStr] ->
            case partidas:get_partida_by_player(PlayerName) of
                {ok, GameState2} ->
                    io:format("Launching projectile for player ~s at angle ~s~n", [PlayerName, AngleStr]),
                    Angle = list_to_float(AngleStr),
                    case PlayerName of
                        Player when Player == GameState2#partida.player1 ->
                            case erlang:monotonic_time(millisecond) - GameState2#partida.player1LastShot > GameState2#partida.player1ShotCooldown of
                                true ->
                                    NewProjectile = #projectile{
                                        position = GameState2#partida.player1Position,
                                        velocity = {GameState2#partida.player1ShotSpeed * math:cos(Angle), GameState2#partida.player1ShotSpeed * math:sin(Angle)},
                                        owner = PlayerName
                                    },
                                    NewGameState = GameState2#partida{
                                        projectiles = [NewProjectile | GameState2#partida.projectiles],
                                        player1LastShot = erlang:monotonic_time(millisecond)
                                    },
                                    NewGameState;
                                false ->
                                    io:format("Shot cooldown for player ~s~n", [PlayerName]),
                                    GameState2
                            end;
                        Player when Player == GameState2#partida.player2 ->
                            case erlang:monotonic_time(millisecond) - GameState2#partida.player2LastShot > GameState2#partida.player2ShotCooldown of
                                true ->
                                    NewProjectile = #projectile{
                                        position = GameState2#partida.player2Position,
                                        velocity = {GameState2#partida.player2ShotSpeed * math:cos(Angle), GameState2#partida.player2ShotSpeed * math:sin(Angle)},
                                        owner = PlayerName
                                    },
                                    NewGameState = GameState2#partida{
                                        projectiles = [NewProjectile | GameState2#partida.projectiles],
                                        player2LastShot = erlang:monotonic_time(millisecond)
                                    },
                                    NewGameState;
                                false ->
                                    io:format("Shot cooldown for player ~s~n", [PlayerName]),
                                    GameState2
                            end
                    end;
                {error, not_found} ->
                    io:format("No partida found for player ~s when launching projectile~n", [PlayerName]),
                    GameState
            end;
        _ ->
            io:format("Unknown input: ~s~n", [Data]),
            GameState
    end.

update_key_state(GameState, PlayerName, Key, press) ->
    case PlayerName of
        P when P =:= GameState#partida.player1 ->
            Keys = GameState#partida.player1_keys,
            io:format("Updating key state for player 1: ~p~n", [Keys]),
            io:format("Adding key ~p to player 1 keys~n", [Key]),
            NewKeys = lists:usort([Key | Keys]),
            io:format("New keys for player 1: ~p~n", [NewKeys]),
            GameState#partida{player1_keys = NewKeys};
        P when P =:= GameState#partida.player2 ->
            Keys = GameState#partida.player2_keys,
            io:format("Updating key state for player 2: ~p~n", [Keys]),
            io:format("Adding key ~p to player 2 keys~n", [Key]),
            NewKeys = lists:usort([Key | Keys]),
            io:format("New keys for player 2: ~p~n", [NewKeys]),
            GameState#partida{player2_keys = NewKeys}
    end;
update_key_state(GameState, PlayerName, Key, release) ->
    case PlayerName of
        P when P =:= GameState#partida.player1 ->
            Keys = GameState#partida.player1_keys,
            io:format("Updating key state for player 1: ~p~n", [Keys]),
            io:format("Removing key ~p from player 1 keys~n", [Key]),
            NewKeys = lists:delete(Key, Keys),
            io:format("New keys for player 1: ~p~n", [NewKeys]),
            GameState#partida{player1_keys = NewKeys};
        P when P =:= GameState#partida.player2 ->
            Keys = GameState#partida.player2_keys,
            io:format("Updating key state for player 2: ~p~n", [Keys]),
            io:format("Removing key ~p from player 2 keys~n", [Key]),
            NewKeys = lists:delete(Key, Keys),
            io:format("New keys for player 2: ~p~n", [NewKeys]),
            GameState#partida{player2_keys = NewKeys}
    end.

calculate_velocity(SpeedX, SpeedY, {AccX, AccY}) ->
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

calculate_acceleration(Acc, AccAmount) ->
    NewAcc = speed_limit(Acc + AccAmount, ?MAX_SPEED, -?MAX_SPEED),
    {NewAcc}.

calculate_playerPosition(Partida) ->
    {Player1X, Player1Y} = Partida#partida.player1Position,
    {Player2X, Player2Y} = Partida#partida.player2Position,
    {Player1SpeedX, Player1SpeedY} = Partida#partida.player1Speed,
    {Player2SpeedX, Player2SpeedY} = Partida#partida.player2Speed,
    {Player1AccX, Player1AccY} = Partida#partida.player1acceleration,
    {Player2AccX, Player2AccY} = Partida#partida.player2acceleration,

    % Calculate new velocities based on acceleration
    {NewPlayer1SpeedX, NewPlayer1SpeedY} = calculate_velocity(Player1SpeedX, Player1SpeedY, {Player1AccX, Player1AccY}),
    {NewPlayer2SpeedX, NewPlayer2SpeedY} = calculate_velocity(Player2SpeedX, Player2SpeedY, {Player2AccX, Player2AccY}),

    % Calculate new positions based on velocity
    {NewPlayer1PosX, NewPlayer1PosY} = calculate_position(Player1X, Player1Y, NewPlayer1SpeedX, NewPlayer1SpeedY),
    {NewPlayer2PosX, NewPlayer2PosY} = calculate_position(Player2X, Player2Y, NewPlayer2SpeedX, NewPlayer2SpeedY),

    % Apply friction to acceleration
    NewPlayer1AccX = Player1AccX * ?ACCEL_FRICTION,
    NewPlayer1AccY = Player1AccY * ?ACCEL_FRICTION,
    NewPlayer2AccX = Player2AccX * ?ACCEL_FRICTION,
    NewPlayer2AccY = Player2AccY * ?ACCEL_FRICTION,

    % Update the partida record
    UpdatedPartida = Partida#partida{
        player1Position = {NewPlayer1PosX, NewPlayer1PosY},
        player2Position = {NewPlayer2PosX, NewPlayer2PosY},
        player1acceleration = {NewPlayer1AccX, NewPlayer1AccY},
        player2acceleration = {NewPlayer2AccX, NewPlayer2AccY},
        player1Speed = {NewPlayer1SpeedX, NewPlayer1SpeedY},
        player2Speed = {NewPlayer2SpeedX, NewPlayer2SpeedY}
    },
    UpdatedPartida.

getWinner(Partida) ->
    case Partida#partida.player1Score > Partida#partida.player2Score of
        true -> 1;
        false -> 
            case Partida#partida.player1Score < Partida#partida.player2Score of
                true -> 2;
                false -> 0
            end
    end.

calculate_projectiles(Partida) ->
    Projectiles = Partida#partida.projectiles,
    UpdatedProjectiles = lists:map(fun(Proj) ->
        {X, Y} = Proj#projectile.position,
        {VX, VY} = Proj#projectile.velocity,
        NewX = X + VX,
        NewY = Y + VY,
        Proj#projectile{position = {NewX, NewY}}
    end, Projectiles),
    Partida#partida{projectiles = UpdatedProjectiles}.

spawnmodificador(Partida) ->
    CurrentTime = erlang:monotonic_time(millisecond),
    case Partida#partida.modificadorSpawnTime < CurrentTime of
        true ->
            % Spawn a new modificador
            NewModificador = #modificador{
                position = {((rand:uniform((?ARENA_WIDTH - 50)*100)/100) + 25), ((rand:uniform((?ARENA_HEIGHT - 50)*100)/100) + 25)},
                type = rand:uniform(4) % Random type
            },
            UpdatedPartida = Partida#partida{
                modificadores = [NewModificador | Partida#partida.modificadores],
                modificadorSpawnTime = CurrentTime + (5000 + rand:uniform(10000)) % Next spawn time
            },
            UpdatedPartida;
        false ->
            Partida
    end.

decay_modificadores_aplicados(Partida) ->
    % Decay constants (modifier effect decays over MOD_DECAY_TIME ms)
    SpeedStep = ?PROJECTILE_SPEED_MOD / (?MOD_DECAY_TIME / 16), % 16ms per tick
    CooldownStep = ?SHOT_COOLDOWN_MOD / (?MOD_DECAY_TIME / 16),

    % Player 1
    P1Speed = Partida#partida.player1ShotSpeed,
    P1Cooldown = Partida#partida.player1ShotCooldown,
    NewP1Speed =
        if
            P1Speed > ?SHOT_SPEED -> max(?SHOT_SPEED, P1Speed - SpeedStep);
            P1Speed < ?SHOT_SPEED -> min(?SHOT_SPEED, P1Speed + SpeedStep);
            true -> P1Speed
        end,
    NewP1Cooldown =
        if
            P1Cooldown > ?SHOT_COOLDOWN -> max(?SHOT_COOLDOWN, P1Cooldown - CooldownStep);
            P1Cooldown < ?SHOT_COOLDOWN -> min(?SHOT_COOLDOWN, P1Cooldown + CooldownStep);
            true -> P1Cooldown
        end,

    % Player 2
    P2Speed = Partida#partida.player2ShotSpeed,
    P2Cooldown = Partida#partida.player2ShotCooldown,
    NewP2Speed =
        if
            P2Speed > ?SHOT_SPEED -> max(?SHOT_SPEED, P2Speed - SpeedStep);
            P2Speed < ?SHOT_SPEED -> min(?SHOT_SPEED, P2Speed + SpeedStep);
            true -> P2Speed
        end,
    NewP2Cooldown =
        if
            P2Cooldown > ?SHOT_COOLDOWN -> max(?SHOT_COOLDOWN, P2Cooldown - CooldownStep);
            P2Cooldown < ?SHOT_COOLDOWN -> min(?SHOT_COOLDOWN, P2Cooldown + CooldownStep);
            true -> P2Cooldown
        end,

    Partida#partida{
        player1ShotSpeed = NewP1Speed,
        player2ShotSpeed = NewP2Speed,
        player1ShotCooldown = NewP1Cooldown,
        player2ShotCooldown = NewP2Cooldown
    }.

gestorPartidas(Username1) ->
    %io:format("GestorPartidas called for ~s~n", [Username1]),
    Partida = get_partida_by_player(Username1),
    case Partida of
        {ok, P} ->
            % Apply acceleration based on held keys
            % Continue as before, but use P2 instead of P
            StartTime = P#partida.startTime,
            CurrentTime = erlang:monotonic_time(millisecond),
            Elapsed = CurrentTime - StartTime,
            TimeLeft = max(0, 120 - (Elapsed div 1000)), % 120 seconds game

            % Check if game is over
            case TimeLeft of
                0 ->
                    io:format("Game over for ~s~n", [Username1]),
                    end_game(P, getWinner(P)),
                    ok;
                _ ->
                    P1Keys = P#partida.player1_keys,
                    P2Keys = P#partida.player2_keys,
                    %io:format("P1Keys: ~p\nP2Keys: ~p" ,[P1Keys,P2Keys]),
                    P2 = apply_held_keys(P, P1Keys, P2Keys),
                    UpdatedPartida = calculate_playerPosition(P2),

                    UpdatedPartida2 = calculate_projectiles(UpdatedPartida),

                    UpdatedPartida3 = check_collisions(UpdatedPartida2),

                    UpdatedPartida4 = spawnmodificador(UpdatedPartida3),

                    UpdatedPartida5 = decay_modificadores_aplicados(UpdatedPartida4),

                    %io:format("Updated partida: ~p~n", [UpdatedPartida]),
                    update_partida(Username1, UpdatedPartida5),
                    %check collision
                    

                    %atualizar projeteis
                    %ver se spawna modificador
                    %check if game is over

                    send_partida(UpdatedPartida2, TimeLeft),
                    erlang:send_after(16, self(), {continue, Username1}),
                    wait_for_continue()
            end;

        {error, not_found} ->
            io:format("No partida found for ~s~n", [Username1])
    end.

wait_for_continue() ->
    receive
        {continue, Username1} ->
            gestorPartidas(Username1)
    end.

format_projectiles(Projectiles) ->
    lists:map(fun(Proj) ->
        {X, Y} = Proj#projectile.position,
        Owner = Proj#projectile.owner,
        io_lib:format("~p,~p,~s", [X, Y, Owner])
    end, Projectiles).

format_modificadores(Modificadores) ->
    lists:flatmap(fun(Mod) ->
        {X, Y} = Mod#modificador.position,
        Type = Mod#modificador.type,
        % Extract just X,Y,Type and flatten into single list
        [io_lib:format("~p", [X]), ",", 
         io_lib:format("~p", [Y]), ",",
         io_lib:format("~p", [Type]), ","]
    end, Modificadores).

send_partida(Partida, TimeLeft) ->
    TrimmedProjectiles = format_projectiles(Partida#partida.projectiles),
    FlatProj = lists:flatten("[" ++ string:join(TrimmedProjectiles, ",") ++ "]"),

    ModData = format_modificadores(Partida#partida.modificadores),
    TrimmedMod = case ModData of
        [] -> "[]";
        _ -> lists:flatten("[" ++ lists:sublist(ModData, length(ModData)-1) ++ "]")
    end,

    CustomData = io_lib:format("P1:~s|P2:~s|P1_POS:~w|P2_POS:~w|P1_SCORE:~p|P2_SCORE:~p|MOD:~s|PROJ:~s|TIME:~p",
                               [Partida#partida.player1,
                                Partida#partida.player2,
                                Partida#partida.player1Position,
                                Partida#partida.player2Position,
                                Partida#partida.player1Score,
                                Partida#partida.player2Score,
                                TrimmedMod,
                                FlatProj,
                                TimeLeft]),
    gen_tcp:send(Partida#partida.sock1, CustomData ++ "\n"),
    gen_tcp:send(Partida#partida.sock2, CustomData ++ "\n").

check_collisions(Partida) ->
    % Constantes
    {P1X, P1Y} = Partida#partida.player1Position,
    {P2X, P2Y} = Partida#partida.player2Position,
    Projectiles = Partida#partida.projectiles,
    Modificadores = Partida#partida.modificadores,
    ArenaW = ?ARENA_WIDTH,
    ArenaH = ?ARENA_HEIGHT,
    Wall = ?WALL_THICKNESS,

    % Verificar colisão dos jogadores com as bordas
    case true of
        _ when P1X < Wall + ?PLAYER_RADIUS; P1X > ArenaW - Wall - ?PLAYER_RADIUS; P1Y < Wall + ?PLAYER_RADIUS; P1Y > ArenaH - Wall - ?PLAYER_RADIUS ->
            % Reset player1, player2 ganha 2 pontos
            Partida#partida{
                player1Position = {100,300},
                player2Position = {700,300},
                player1Speed = {0, 0},
                player2Speed = {0, 0},
                player1acceleration = {0, 0},
                player2acceleration = {0, 0},
                player2Score = Partida#partida.player2Score + 2,
                projectiles = []
            };
        _ when P2X < Wall + ?PLAYER_RADIUS; P2X > ArenaW - Wall - ?PLAYER_RADIUS; P2Y < Wall + ?PLAYER_RADIUS; P2Y > ArenaH - Wall - ?PLAYER_RADIUS ->
            % Reset player2, player1 ganha 2 pontos
            Partida#partida{
                player1Position = {100,300},
                player2Position = {700,300},
                player1Speed = {0, 0},
                player2Speed = {0, 0},
                player1acceleration = {0, 0},
                player2acceleration = {0, 0},
                player1Score = Partida#partida.player1Score + 2,
                projectiles = []
            };
        true ->
            % Checar colisão dos jogadores com modificadores
            UpdatedPartida1 = lists:foldl(
                fun(Mod, AccPartida) ->
                    {ModX, ModY} = Mod#modificador.position,
                    Type = Mod#modificador.type,
                    DistP1 = distance({ModX, ModY}, AccPartida#partida.player1Position),
                    DistP2 = distance({ModX, ModY}, AccPartida#partida.player2Position),
                    case true of
                        _ when DistP1 < (?PLAYER_RADIUS + ?MODIFICADOR_RADIUS) ->
                            % Player 1 pega o modificador
                            case Type of
                                1 -> % aumenta velocidade projeteis
                                    AccPartida#partida{
                                        player1ShotSpeed = max(1, AccPartida#partida.player1ShotSpeed + ?PROJECTILE_SPEED_MOD),
                                        modificadores = lists:delete(Mod, AccPartida#partida.modificadores)
                                    };
                                2 -> % diminui velocidade projeteis
                                    AccPartida#partida{
                                        player1ShotSpeed = max(1, AccPartida#partida.player1ShotSpeed - ?PROJECTILE_SPEED_MOD),
                                        modificadores = lists:delete(Mod, AccPartida#partida.modificadores)
                                    };
                                3 -> % diminui cooldown projeteis
                                    NewCooldown = max(500, AccPartida#partida.player1ShotCooldown - ?SHOT_COOLDOWN_MOD),
                                    AccPartida#partida{
                                        player1ShotCooldown = NewCooldown,
                                        player1LastShot = erlang:monotonic_time(millisecond) - (NewCooldown - 1),
                                        modificadores = lists:delete(Mod, AccPartida#partida.modificadores)
                                    };
                                4 -> % aumenta cooldown projeteis
                                    NewCooldown = AccPartida#partida.player1ShotCooldown + ?SHOT_COOLDOWN_MOD,
                                    AccPartida#partida{
                                        player1ShotCooldown = NewCooldown,
                                        player1LastShot = erlang:monotonic_time(millisecond) - (NewCooldown - 1),
                                        modificadores = lists:delete(Mod, AccPartida#partida.modificadores)
                                    }
                            end;
                        _ when DistP2 < (?PLAYER_RADIUS + ?MODIFICADOR_RADIUS) ->
                            % Player 2 pega o modificador
                            case Type of
                                1 ->
                                    AccPartida#partida{
                                        player2ShotSpeed = max(1, AccPartida#partida.player2ShotSpeed + 8),
                                        modificadores = lists:delete(Mod, AccPartida#partida.modificadores)
                                    };
                                2 ->
                                    AccPartida#partida{
                                        player2ShotSpeed = max(1, AccPartida#partida.player2ShotSpeed - 8),
                                        modificadores = lists:delete(Mod, AccPartida#partida.modificadores)
                                    };
                                3 ->
                                    AccPartida#partida{
                                        player2ShotCooldown = max(500, AccPartida#partida.player2ShotCooldown - 3500),
                                        modificadores = lists:delete(Mod, AccPartida#partida.modificadores)
                                    };
                                4 ->
                                    AccPartida#partida{
                                        player2ShotCooldown = AccPartida#partida.player2ShotCooldown + 3500,
                                        modificadores = lists:delete(Mod, AccPartida#partida.modificadores)
                                    }
                            end;
                        _ ->
                            AccPartida
                    end
                end,
                Partida,
                Modificadores
            ),

            % Se não houve reset, processa colisão de projéteis
            lists:foldl(
                fun(Proj, AccPartida) ->
                    ProjX = element(1, Proj#projectile.position),
                    ProjY = element(2, Proj#projectile.position),
                    Owner = Proj#projectile.owner,
                    % Colisão com borda
                    if
                        ProjX < Wall + ?PROJECTILE_RADIUS; ProjX > ArenaW - Wall - ?PROJECTILE_RADIUS; ProjY < Wall + ?PROJECTILE_RADIUS; ProjY > ArenaH - ?PLAYER_RADIUS ->
                            AccPartida#partida{projectiles = lists:delete(Proj, AccPartida#partida.projectiles)};
                        true ->
                            DistP1 = distance({ProjX, ProjY}, AccPartida#partida.player1Position),
                            DistP2 = distance({ProjX, ProjY}, AccPartida#partida.player2Position),
                            case true of
                                _ when Owner =/= AccPartida#partida.player1, DistP1 < (?PLAYER_RADIUS + ?PROJECTILE_RADIUS) ->
                                    AccPartida#partida{
                                        player2Score = AccPartida#partida.player2Score + 1,
                                        projectiles = lists:delete(Proj, AccPartida#partida.projectiles)
                                    };
                                _ when Owner =/= AccPartida#partida.player2, DistP2 < (?PLAYER_RADIUS + ?PROJECTILE_RADIUS) ->
                                    AccPartida#partida{
                                        player1Score = AccPartida#partida.player1Score + 1,
                                        projectiles = lists:delete(Proj, AccPartida#partida.projectiles)
                                    };
                                _ ->
                                    AccPartida
                            end
                    end
                end,
                UpdatedPartida1,
                Projectiles
            )
    end.

distance({X1, Y1}, {X2, Y2}) ->
    math:sqrt(math:pow(X1 - X2, 2) + math:pow(Y1 - Y2, 2)).

end_game(GameState, Winner) ->
    Player1 = GameState#partida.player1,
    Player2 = GameState#partida.player2,
    io:format("Game ended. Winner: ~p~n", [Winner]),
    if 
        Winner == 0 ->
            gen_tcp:send(GameState#partida.sock1, "GAME_OVER: DRAW\n"),
            gen_tcp:send(GameState#partida.sock2, "GAME_OVER: DRAW\n"),
            remove_partida(Player1);
        true ->
            {WinnerUsername, LoserUsername} = 
                case Winner of
                    1 -> {Player1, Player2};
                    2 -> {Player2, Player1};
                    _ -> {Player1, Player2}
                end,

            WinnerLevel = case get_player_level(WinnerUsername) of
                {ok, WL} -> WL;
                _ -> 1
            end,
            LoserLevel = case get_player_level(LoserUsername) of
                {ok, LL} -> LL;
                _ -> 1
            end,
            WinnerStreak = case server:get_player_streak(WinnerUsername) of
                {ok, WS} -> WS;
                _ -> 0
            end,
            LoserStreak = case server:get_player_streak(LoserUsername) of
                {ok, LS} -> LS;
                _ -> 0
            end,

            server:update_account_stats(WinnerUsername, WinnerLevel, WinnerStreak, 1),
            server:update_account_stats(LoserUsername, LoserLevel, LoserStreak, -1), 

            gen_tcp:send(GameState#partida.sock1, io_lib:format("GAME_OVER: Winner - ~s\n", [WinnerUsername])),
            gen_tcp:send(GameState#partida.sock2, io_lib:format("GAME_OVER: Winner - ~s\n", [WinnerUsername])),
            % Send updated stats to both players
            {Level1, Streak1} = get_player_stats(Player1),
            {Level2, Streak2} = get_player_stats(Player2),
            gen_tcp:send(GameState#partida.sock1, io_lib:format("STATS:~p,~p\n", [Level1, Streak1])),
            gen_tcp:send(GameState#partida.sock2, io_lib:format("STATS:~p,~p\n", [Level2, Streak2])),
            remove_partida(Player1)
    end.

get_player_stats(Username) ->
    Level = case get_player_level(Username) of
        {ok, L} -> L;
        _ -> 1
    end,
    Streak = case server:get_player_streak(Username) of
        {ok, S} -> S;
        _ -> 0
    end,
    {Level, Streak}.

apply_held_keys(Partida, P1Keys, P2Keys) ->
    % For player 1
    {AccX1, AccY1} = Partida#partida.player1acceleration,
    AccX1a = case lists:member("LEFT", P1Keys) of
        true -> AccX1 - ?ACCELERATION_INCREMENT;
        false -> AccX1
    end,
    AccX1b = case lists:member("RIGHT", P1Keys) of
        true -> AccX1a + ?ACCELERATION_INCREMENT;
        false -> AccX1a
    end,
    AccY1a = case lists:member("UP", P1Keys) of
        true -> AccY1 - ?ACCELERATION_INCREMENT;
        false -> AccY1
    end,
    AccY1b = case lists:member("DOWN", P1Keys) of
        true -> AccY1a + ?ACCELERATION_INCREMENT;
        false -> AccY1a
    end,

    % For player 2
    {AccX2, AccY2} = Partida#partida.player2acceleration,
    AccX2a = case lists:member("LEFT", P2Keys) of
        true -> AccX2 - ?ACCELERATION_INCREMENT;
        false -> AccX2
    end,
    AccX2b = case lists:member("RIGHT", P2Keys) of
        true -> AccX2a + ?ACCELERATION_INCREMENT;
        false -> AccX2a
    end,
    AccY2a = case lists:member("UP", P2Keys) of
        true -> AccY2 - ?ACCELERATION_INCREMENT;
        false -> AccY2
    end,
    AccY2b = case lists:member("DOWN", P2Keys) of
        true -> AccY2a + ?ACCELERATION_INCREMENT;
        false -> AccY2a
    end,

    Partida#partida{
        player1acceleration = {AccX1b, AccY1b},
        player2acceleration = {AccX2b, AccY2b}
    }.

shutdown_server() ->
    socketRegistry:set_shutdown(true), % Set global shutdown flag
    io:format("Server is shutting down, notifying all clients...~n"),
    catch socketRegistry:broadcast("SERVER_SHUTDOWN\n"),
    timer:sleep(100),
    init:stop().