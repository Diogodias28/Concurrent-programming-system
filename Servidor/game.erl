-module(game).
-import(gen_tcp, [listen/2]).
-import(server,[create_account/2, login/2, close_account/2, logout/1, start/0, online/0, get_player_level/1, get_player_streak/1]).
-import(queuelist, [add_to_queue/2, get_queue/0, startqueue/0, remove_from_queue/1]).
-import(partidas, [add_partida/1, get_partidas/0, update_partida/2, remove_partida/1, get_partida_by_player/1]).
-include("partida.hrl").
-export([start/1, authenticator/1, parse_auth_input/1]).


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
-define(SHOT_COOLDOWN, 5000).

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
            % Send player stats after login
            Level = case server:get_player_level(Username) of
                {ok, L} -> L;
                _ -> 1
            end,
            Streak = case server:get_player_streak(Username) of
                {ok, S} -> S;
                _ -> 0
            end,
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
                {error, _} ->
                    io:format("Invalid queue command: ~s~n", [Data]),
                    gen_tcp:send(Sock, "INVALID_QUEUE_COMMAND\n"),
                    queue_handler(Sock, Player)
            end;
        {tcp_closed, Sock} ->
            io:format("Socket closed.~n"),
            server:logout(Player),
            ok;
        {tcp_error, Sock, Reason} ->
            io:format("Socket error: ~p~n", [Reason]),
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
        _ ->
            {error, "Invalid queue command"}
    end.



comecarjogo(Sock1, Username1, Sock2, Username2) ->
    io:format("Starting game between ~s and ~s~n", [Username1, Username2]),
    gen_tcp:send(Sock1, "MATCHED " ++ Username2 ++ "\n"),
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
        startTime = erlang:monotonic_time(millisecond)
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
                    io:format("GameState for ~s: ~p~n", [Player, GameState]),
                    UpdatedGameState = handle_player_input(GameState, Player, Data),
                    io:format("Updated GameState: ~p~n", [UpdatedGameState]),
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
        ["LAUNCH_PROJ", IdStr, Owner, XStr, YStr, VXStr, VYStr] ->
            case partidas:get_partida_by_player(PlayerName) of
                {ok, NewGameState} ->
                    Now = erlang:monotonic_time(millisecond),
                    Player1Name = NewGameState#partida.player1,
                    Player2Name = NewGameState#partida.player2,
                    {CanShoot, TempGameState} =
                        if 
                            PlayerName == Player1Name ->
                                Last = NewGameState#partida.player1LastShot,
                                if
                                    Now - Last >= ?SHOT_COOLDOWN ->
                                        {true, NewGameState#partida{player1LastShot = Now}};
                                    true ->
                                        {false, NewGameState}
                                end;
                            PlayerName == Player2Name ->
                                Last = NewGameState#partida.player2LastShot,
                                if
                                    Now - Last >= ?SHOT_COOLDOWN ->
                                        {true, NewGameState#partida{player2LastShot = Now}};
                                    true ->
                                        {false, NewGameState}
                                end
                        end,
                case CanShoot of
                    true ->
                        Id = list_to_integer(IdStr),
                        X = list_to_float(XStr),
                        Y = list_to_float(YStr),
                        VX = list_to_float(VXStr),
                        VY = list_to_float(VYStr),
                        NewProjectile = #projectile{
                            id = Id,
                            owner = Owner,
                            position = {X, Y},
                            velocity = {VX, VY}
                        },
                        UpdatedProjectiles = [NewProjectile | TempGameState#partida.projectiles],
                        UpdatedGameState = TempGameState#partida{projectiles = UpdatedProjectiles},
                        UpdatedGameState;
                    false ->
                        io:format("Player ~s tried to shot before the cooldown ~n", [PlayerName]),
                        NewGameState
                end;
                {error, not_found} ->
                    io:format("No partida found for player ~s~n", [PlayerName]),
                    GameState
            end;
        _ ->
            io:format("Unknown input: ~s~n", [Data]),
            GameState
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

    NewProjectiles = update_projectiles(Partida#partida.projectiles),

    % Update the partida record
    UpdatedPartida = Partida#partida{
        player1Position = {NewPlayer1PosX, NewPlayer1PosY},
        player2Position = {NewPlayer2PosX, NewPlayer2PosY},
        player1acceleration = {NewPlayer1AccX, NewPlayer1AccY},
        player2acceleration = {NewPlayer2AccX, NewPlayer2AccY},
        player1Speed = {NewPlayer1SpeedX, NewPlayer1SpeedY},
        player2Speed = {NewPlayer2SpeedX, NewPlayer2SpeedY},
        projectiles = NewProjectiles
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

gestorPartidas(Username1) ->
    %io:format("GestorPartidas called for ~s~n", [Username1]),
    Partida = get_partida_by_player(Username1),
    case Partida of
        {ok, P} ->
            %io:format("Partida found for ~s: ~p~n", [Username1, P]),
            % Debug print before sending partida
            %io:format("Sending partida to client: ~p~n", [P]),
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
                    UpdatedPartida = calculate_playerPosition(P),

                    UpdatedPartida2 = check_collisions(UpdatedPartida),


                    %io:format("Updated partida: ~p~n", [UpdatedPartida]),
                    update_partida(Username1, UpdatedPartida2),
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

send_partida(Partida, TimeLeft) ->
    CustomData = io_lib:format("P1:~s|P2:~s|P1_POS:~w|P2_POS:~w|P1_SCORE:~p|P2_SCORE:~p|TIME:~p",
                               [Partida#partida.player1,
                                Partida#partida.player2,
                                Partida#partida.player1Position,
                                Partida#partida.player2Position,
                                Partida#partida.player1Score,
                                Partida#partida.player2Score,
                                TimeLeft]),
    gen_tcp:send(Partida#partida.sock1, CustomData ++ "\n"),
    gen_tcp:send(Partida#partida.sock2, CustomData ++ "\n").

check_collisions(Partida) ->
    % Constantes
    {P1X, P1Y} = Partida#partida.player1Position,
    {P2X, P2Y} = Partida#partida.player2Position,
    Projectiles = Partida#partida.projectiles,
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
            % Se não houve reset, processa colisão de projéteis
            lists:foldl(
                fun(Proj, AccPartida) ->
                    ProjX = element(1, Proj#projectile.position),
                    ProjY = element(2, Proj#projectile.position),
                    Owner = Proj#projectile.owner,

                    % Colisão com borda
                    if
                        ProjX < Wall + ?PROJECTILE_RADIUS; ProjX > ArenaW - Wall - ?PROJECTILE_RADIUS; ProjY < Wall + ?PROJECTILE_RADIUS; ProjY > ArenaH - Wall - ?PLAYER_RADIUS ->
                            AccPartida#partida{projectiles = lists:delete(Proj, AccPartida#partida.projectiles)};
                        true ->
                            % Colisão com jogadores
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
                Partida,
                Projectiles
            )
    end.

distance({X1, Y1}, {X2, Y2}) ->
    math:sqrt(math:pow(X1 - X2, 2) + math:pow(Y1 - Y2, 2)).

end_game(GameState, Winner) ->
    Player1 = GameState#partida.player1,
    Player2 = GameState#partida.player2,
    io:format("Game ended. Winner: ~p~n", [Winner]),
%draw == 0
    if 
        Winner == 0 ->
            gen_tcp:send(GameState#partida.sock1, io_lib:format("GAME_DRAW\n")),
            gen_tcp:send(GameState#partida.sock2, io_lib:format("GAME_DRAW\n")),
            remove_partida(Player1);
        true ->
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
            
            remove_partida(Player1)
        end.

update_projectiles(Projectiles) ->
    lists:filtermap(
        fun(Proj) ->
            {X, Y} = Proj#projectile.position,
            if
                X < ?WALL_THICKNESS; X > (?ARENA_WIDTH - ?WALL_THICKNESS);
                Y < ?WALL_THICKNESS; Y > (?ARENA_HEIGHT - ?WALL_THICKNESS) ->
                    false;
                true ->
                    {VX, VY} = Proj#projectile.velocity,
                    {true, Proj#projectile{position = {X + VX, Y + VY}}}
            end
        end, Projectiles).