%% Ordenamiento del ranking: modulo PURO. Criterios de desempate, en orden:
%%   1) mas puntos  2) mas marcadores exactos  3) mas aciertos de ganador/empate.
%% Si persiste el empate comparten posicion (ranking "1224"); el orden dentro del empate es
%% alfabetico por id solo para que la presentacion sea estable (no es criterio deportivo).
-module(p73_ranking).
-export([ordenar/1, vacio/0, nuevo_total/0]).

nuevo_total() -> #{pts => 0, exactos => 0, ganadores => 0, bonos => 0}.
vacio() -> [].

-spec ordenar(#{binary() => map()}) -> [map()].
ordenar(Totales) ->
  Filas = [{clave(T), P, T} || {P, T} <- maps:to_list(Totales)],
  Orden = lists:sort(Filas),
  posiciones(Orden, 1, 0, undefined, []).

clave(#{pts := P, exactos := E, ganadores := G, bonos := B}) -> {-(P + B), -E, -G}.

posiciones([], _N, _PosAct, _ClaveAct, Acc) -> lists:reverse(Acc);
posiciones([{Clave, P, T} | R], N, PosAct, ClaveAct, Acc) ->
  Pos = case Clave =:= ClaveAct of true -> PosAct; false -> N end,
  Fila = #{pos => Pos, participante => P, pts => maps:get(pts, T) + maps:get(bonos, T),
           exactos => maps:get(exactos, T), ganadores => maps:get(ganadores, T)},
  posiciones(R, N + 1, Pos, Clave, [Fila | Acc]).
