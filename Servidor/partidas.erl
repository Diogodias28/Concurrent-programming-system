-module(partidas).
-export([update_position/2, update_speed/2, update_acceleration/2, update_score/2, update_last_shot/2, update_shot_cooldown/2, update_shot_speed/2, update_keys/2, update_projectiles/2, update_modificadores/2, update_modificador_spawn_time/2, start/0, add_partida/1, get_partidas/0, update_partida/2, remove_partida/1, get_partida_by_player/1]).
-include("partida.hrl").

start() ->
    ets:new(partidas_table, [set, named_table, public, {keypos, #partida.player1}]),
    ok.

add_partida(Partida) ->
    ets:insert(partidas_table, Partida).

get_partidas() ->
    ets:tab2list(partidas_table).

update_partida(Player1, UpdatedPartida) ->
    ets:insert(partidas_table, UpdatedPartida).

remove_partida(Player1) ->
    ets:delete(partidas_table, Player1).

get_partida_by_player(PlayerName) ->
    case ets:match_object(partidas_table, #partida{player1 = PlayerName, _ = '_'}) of
        [Partida] -> {ok, Partida};
        [] -> 
            case ets:match_object(partidas_table, #partida{player2 = PlayerName, _ = '_'}) of
                [Partida] -> {ok, Partida};
                [] -> {error, not_found}
            end
    end.

%% Position updates (for either player)
update_position(PlayerName, {NewX, NewY}) ->
    case get_partida_by_player(PlayerName) of
        {ok, #partida{player1 = PlayerName}} ->
            ets:update_element(partidas_table, PlayerName, {#partida.player1Position, {NewX, NewY}});
        {ok, Partida} -> % Player is player2
            ets:update_element(partidas_table, Partida#partida.player1, {#partida.player2Position, {NewX, NewY}});
        Error -> Error
    end.

%% Speed updates
update_speed(PlayerName, {NewSpeedX, NewSpeedY}) ->
    case get_partida_by_player(PlayerName) of
        {ok, #partida{player1 = PlayerName}} ->
            ets:update_element(partidas_table, PlayerName, {#partida.player1Speed, {NewSpeedX, NewSpeedY}});
        {ok, Partida} ->
            ets:update_element(partidas_table, Partida#partida.player1, {#partida.player2Speed, {NewSpeedX, NewSpeedY}});
        Error -> Error
    end.

%% Acceleration updates
update_acceleration(PlayerName, {NewAccX, NewAccY}) ->
    case get_partida_by_player(PlayerName) of
        {ok, #partida{player1 = PlayerName}} ->
            ets:update_element(partidas_table, PlayerName, {#partida.player1acceleration, {NewAccX, NewAccY}});
        {ok, Partida} ->
            ets:update_element(partidas_table, Partida#partida.player1, {#partida.player2acceleration, {NewAccX, NewAccY}});
        Error -> Error
    end.

%% Score updates
update_score(PlayerName, NewScore) ->
    case get_partida_by_player(PlayerName) of
        {ok, #partida{player1 = PlayerName}} ->
            ets:update_element(partidas_table, PlayerName, {#partida.player1Score, NewScore});
        {ok, Partida} ->
            ets:update_element(partidas_table, Partida#partida.player1, {#partida.player2Score, NewScore});
        Error -> Error
    end.

%% Last shot timestamp updates
update_last_shot(PlayerName, Timestamp) ->
    case get_partida_by_player(PlayerName) of
        {ok, #partida{player1 = PlayerName}} ->
            ets:update_element(partidas_table, PlayerName, {#partida.player1LastShot, Timestamp});
        {ok, Partida} ->
            ets:update_element(partidas_table, Partida#partida.player1, {#partida.player2LastShot, Timestamp});
        Error -> Error
    end.

%% Shot cooldown updates
update_shot_cooldown(PlayerName, NewCooldown) ->
    case get_partida_by_player(PlayerName) of
        {ok, #partida{player1 = PlayerName}} ->
            ets:update_element(partidas_table, PlayerName, {#partida.player1ShotCooldown, NewCooldown});
        {ok, Partida} ->
            ets:update_element(partidas_table, Partida#partida.player1, {#partida.player2ShotCooldown, NewCooldown});
        Error -> Error
    end.

%% Shot speed updates
update_shot_speed(PlayerName, NewSpeed) ->
    case get_partida_by_player(PlayerName) of
        {ok, #partida{player1 = PlayerName}} ->
            ets:update_element(partidas_table, PlayerName, {#partida.player1ShotSpeed, NewSpeed});
        {ok, Partida} ->
            ets:update_element(partidas_table, Partida#partida.player1, {#partida.player2ShotSpeed, NewSpeed});
        Error -> Error
    end.

%% Key state updates
update_keys(PlayerName, NewKeys) ->
    case get_partida_by_player(PlayerName) of
        {ok, #partida{player1 = PlayerName}} ->
            ets:update_element(partidas_table, PlayerName, {#partida.player1_keys, NewKeys});
        {ok, Partida} ->
            ets:update_element(partidas_table, Partida#partida.player1, {#partida.player2_keys, NewKeys});
        Error -> Error
    end.

%% Projectiles updates (shared game state)
update_projectiles(PlayerName, NewProjectiles) ->
    case get_partida_by_player(PlayerName) of
        {ok, Partida} ->
            ets:update_element(partidas_table, Partida#partida.player1, {#partida.projectiles, NewProjectiles});
        Error -> Error
    end.

%% Modifiers updates (shared game state)
update_modificadores(PlayerName, NewModificadores) ->
    case get_partida_by_player(PlayerName) of
        {ok, Partida} ->
            ets:update_element(partidas_table, Partida#partida.player1, {#partida.modificadores, NewModificadores});
        Error -> Error
    end.

%% Modifier spawn time updates
update_modificador_spawn_time(PlayerName, NewTime) ->
    case get_partida_by_player(PlayerName) of
        {ok, Partida} ->
            ets:update_element(partidas_table, Partida#partida.player1, {#partida.modificadorSpawnTime, NewTime});
        Error -> Error
    end.