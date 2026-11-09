%% Calendario del torneo: toma los 104 partidos reales y les asigna instante de inicio.
%%
%% SUPUESTO declarado: los datos de origen traen solo la FECHA. Aqui se reparten en "ventanas" de
%% hasta 4 partidos simultaneos por dia, a las 16:00 UTC y cada 3 h. Los resultados y fechas son reales;
%% las horas son un modelo para poder ejercitar el bloqueo exacto al inicio y los partidos en paralelo.
-module(p73_torneo).
-export([partidos/0, por_id/1, primer_inicio/0, equipos/0, ventanas/0]).

-define(HORA_BASE_UTC, 16).
-define(SEPARACION_MS, 3 * 3600 * 1000).
-define(SIMULTANEOS, 4).
-define(EPOCA, 62167219200). %% segundos gregorianos de 1970-01-01

%% Lista de mapas ordenada cronologicamente: #{id, fase, grupo, local, visitante, inicio, goles, cierre}
partidos() ->
  Crudos = lists:sort(fun({IdA, _, _, _, _, _, _, FA, _}, {IdB, _, _, _, _, _, _, FB, _}) ->
                          {FA, IdA} =< {FB, IdB} end, p73_mundial2026:partidos()),
  asignar(Crudos, undefined, 0, []).

asignar([], _, _, Acc) -> lists:reverse(Acc);
asignar([{Id, Fase, Grupo, L, V, GL, GV, Fecha, Cierre} | R], FechaAnt, K, Acc) ->
  K1 = case Fecha =:= FechaAnt of true -> K + 1; false -> 0 end,
  Inicio = base_ms(Fecha) + (K1 div ?SIMULTANEOS) * ?SEPARACION_MS,
  P = #{id => Id, fase => Fase, grupo => Grupo, local => L, visitante => V,
        inicio => Inicio, goles => {GL, GV}, cierre => Cierre},
  asignar(R, Fecha, K1, [P | Acc]).

base_ms(Fecha) ->
  (calendar:datetime_to_gregorian_seconds({Fecha, {?HORA_BASE_UTC, 0, 0}}) - ?EPOCA) * 1000.

por_id(Id) ->
  case [P || #{id := I} = P <- partidos(), I =:= Id] of
    [P] -> {ok, P};
    [] -> error
  end.

primer_inicio() -> maps:get(inicio, hd(partidos())).

equipos() ->
  lists:sort(lists:append(maps:values(p73_mundial2026:grupos()))).

%% Partidos agrupados por instante de inicio: cada elemento es la lista de los que se juegan a la vez.
ventanas() ->
  Ps = partidos(),
  Inicios = lists:usort([I || #{inicio := I} <- Ps]),
  [{I, [P || #{inicio := J} = P <- Ps, J =:= I]} || I <- Inicios].
