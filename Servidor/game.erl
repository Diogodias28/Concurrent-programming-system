-module(game).
-export([start/1]).

-define(FRICTION, 0.98).
-define(INITIAL_ACCELERATION, 0.01).
-define(ACCELERATION_INCREMENT, 0.01).
-define(MAX_SPEED, 6).
-define(GUI_HEIGHT, 70).
-define(ARENA_HEIGHT, 600).
-define(ARENA_WIDTH, 800).

start(Port) ->
    {ok, LSock} = gen_tcp:start_listen(Port, [
        {packet, line}, {reuseaddr, true}, {active, false}
    ]),
    spawn(fun() -> acceptor(LSock) end).

acceptor(LSock) ->
    {ok, Sock} = gen_tcp:accept(LSock),
    spawn(fun() -> acceptor(LSock) end),
    worker(Sock, {width / 4, (height - GUI_HEIGHT) / 2 + GUI_HEIGHT}, {0, 0}). %posição, velocidade 

worker(Sock, {PlayerX, PlayerY}, {PlayerSpeedX, PlayerSpeedY}) ->
    receive
        {tcp, Sock, Data} ->
            io:format("Received data: ~s~n", [Data]),
            case parse_input(Data) of
                {move, Direction} -> 
                    {AccX, AccY} = get_acceleration(Direction),
                    {NewPlayerSpeedX, NewPlayerSpeedY} = calculate_velocity(PlayerSpeedX, PlayerSpeedY, AccX, AccY),
                    {NewPlayerX, NewPlayerY} = calculate_position(PlayerX, PlayerY, NewPlayerSpeedX, NewPlayerSpeedY),
                    gen_tcp:send(Sock, io_lib:format("PLAYER_POS ~p~p~n", [NewPlayerX, NewPlayerY])),
                    worker(Sock, {NewPlayerX, NewPlayerY}, {NewPlayerSpeedX, NewPlayerSpeedY});
                {stop, Direction} ->
                    {AccX, AccY} = get_deceleration(Direction, PlayerSpeedX, PlayerSpeedY),
                    {NewPlayerSpeedX, NewPlayerSpeedY} = calculate_velocity(PlayerSpeedX, PlayerSpeedY, AccX, AccY),
                    {NewPlayerX, NewPlayerY} = calculate_position(PlayerX, PlayerY, NewPlayerSpeedX, NewPlayerSpeedY),
                    gen_tcp:send(Sock, io_lib:format("PLAYER_POS ~p~p~n", [NewPlayerX, NewPlayerY])),
                    worker(Sock, {NewPlayerX, NewPlayerY}, {NewPlayerSpeedX, NewPlayerSpeedY});
                {error, Reason} ->
                    io:format("Invalid input: ~s~n", [Reason]),
                    worker(Sock, {NewPlayerX, NewPlayerY}, {NewPlayerSpeedX, NewPlayerSpeedY})
            end;
        {tcp_closed, Sock} ->
            io:format("Socket closed. ~n"),
            ok
    end.

parse_input(Data) ->
    case string:split(string:trim(Data), ",", all) of
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
    NewSpeedX = speed_limit(SpeedX + AccX, -MAX_SPEED, MAX_SPEED) * FRICTION,
    NewSpeedY = speed_limit(SpeedY + AccY, -MAX_SPEED, MAX_SPEED) * FRICTION,
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
    {-(INITIAL_ACCELERATION + 1 * ACCELERATION_INCREMENT), 0};
get_acceleration(right) ->
    {INITIAL_ACCELERATION + 1 * ACCELERATION_INCREMENT, 0};
get_acceleration(up) ->
    {0, -(INITIAL_ACCELERATION + 1 * ACCELERATION_INCREMENT)};
get_acceleration(down) ->
    {0, INITIAL_ACCELERATION + 1 * ACCELERATION_INCREMENT}.    
