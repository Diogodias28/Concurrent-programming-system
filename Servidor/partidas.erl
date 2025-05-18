-module(partidas).
-export([start/0, add_partida/1, get_partidas/0, update_partida/2, remove_partida/1, get_partida_by_player/1]).
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