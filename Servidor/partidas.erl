-module(partidas).

-export([start/0, add_partida/1, get_partidas/0, update_partida/2, remove_partida/1, get_partida_by_player/1]).

-include("partida.hrl").

% Start the partida manager process
start() ->
    register(partida_manager, spawn(fun() -> loop([]) end)).

% Add a partida to the list
add_partida(Partida) ->
    partida_manager ! {add, Partida}.

% Get the list of partidas
get_partidas() ->
    partida_manager ! {self(), get},
    receive
        {ok, Partidas} -> Partidas
    end.

% Update a partida in the list
update_partida(Player1, UpdatedPartida) ->
    partida_manager ! {update, Player1, UpdatedPartida}.

% Remove a partida from the list
remove_partida(Player1) ->
    partida_manager ! {remove, Player1}.

% Get a partida by a player's name
get_partida_by_player(PlayerName) ->
    partida_manager ! {self(), {get_by_player, PlayerName}},
    receive
        {ok, Partida} -> {ok, Partida};
        {error, not_found} -> {error, not_found}
    end.

% Internal loop to manage the state
loop(Partidas) ->
    receive
        {add, Partida} ->
            loop([Partida | Partidas]);
        {Caller, get} when Caller =:= self() ->
            Caller ! {ok, Partidas},
            loop(Partidas);
        {update, Player1, UpdatedPartida} ->
            UpdatedPartidas = lists:map(
                fun(Partida) ->
                    case Partida#partida.player1 of
                        Player1 -> UpdatedPartida;
                        _ -> Partida
                    end
                end, Partidas),
            loop(UpdatedPartidas);
        {remove, Player1} ->
            FilteredPartidas = lists:filter(
                fun(Partida) -> Partida#partida.player1 =/= Player1 end,
                Partidas),
            loop(FilteredPartidas);
        {Caller, {get_by_player, PlayerName}} ->
            case lists:filter(
                fun(Partida) ->
                    Partida#partida.player1 =:= PlayerName orelse
                    Partida#partida.player2 =:= PlayerName
                end, Partidas) of
                [Partida | _] -> Caller ! {ok, Partida};
                [] -> Caller ! {error, not_found}
            end,
            loop(Partidas)
    end.