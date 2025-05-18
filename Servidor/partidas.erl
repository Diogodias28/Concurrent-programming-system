-module(partidas).
-export([start/0, add_partida/1, get_partidas/0, update_partida/2, remove_partida/1, get_partida_by_player/1,update_player_keys_in_partida/2]).
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

update_player_keys_in_partida(PlayerName, NewKeys) ->
    case get_partida_by_player(PlayerName) of
        {ok, Partida} ->
            case true of
                _ when PlayerName == Partida#partida.player1 ->
                    ets:update_element(partidas_table, Partida#partida.player1, 
                                      {#partida.player1_keys, NewKeys});
                _ when PlayerName == Partida#partida.player2 ->
                    ets:update_element(partidas_table, Partida#partida.player1, 
                                      {#partida.player2_keys, NewKeys})
            end,
            ok;
        Error -> Error
    end.