%% Utilidades de prueba: arranque/parada limpios del arbol y un escenario pequeno y real
%% (partidos 1, 2 y 104 del Mundial 2026; 2 quinielas con reglas distintas; 4 participantes).
-module(p73_test_util).
-export([arrancar/0, parar/1, escenario/0, esperar/2, ranking/1]).

arrancar() ->
  logger:set_primary_config(level, emergency),   %% los kill inyectados generan reportes de supervisor esperados
  {ok, Pid} = p73_quiniela_del_mundial_sup:start_link(),
  unlink(Pid),
  ok = p73_poblacion:limpiar(),
  Pid.

parar(Pid) ->
  Ref = erlang:monitor(process, Pid),
  exit(Pid, shutdown),
  receive {'DOWN', Ref, process, Pid, _} -> ok after 10000 -> exit(no_paro) end.

%% Devuelve #{inicio := Inicio del partido 1}. El reloj queda 1 hora antes.
escenario() ->
  Ps = [P || #{id := I} = P <- p73_torneo:partidos(), lists:member(I, [1, 2, 104])],
  [ok = p73_poblacion:registrar_partido(maps:with([id, fase, grupo, local, visitante, inicio], P)) || P <- Ps],
  ok = p73_poblacion:registrar_quiniela(<<"Q1">>, <<"Clasica">>, #{}),
  ok = p73_poblacion:registrar_quiniela(<<"Q2">>, <<"Generosa">>, #{exacto => 5, diferencia => 3, ganador => 2}),
  ok = p73_poblacion:registrar_participante(<<"U1">>, <<"Uno">>, [<<"Q1">>]),
  ok = p73_poblacion:registrar_participante(<<"U2">>, <<"Dos">>, [<<"Q1">>, <<"Q2">>]),
  ok = p73_poblacion:registrar_participante(<<"U3">>, <<"Tres">>, [<<"Q2">>]),
  ok = p73_poblacion:registrar_participante(<<"U4">>, <<"Cuatro">>, [<<"Q1">>]),
  #{partidos := 3, quinielas := 2, participantes := 4} = p73_poblacion:asegurar(),
  [#{inicio := I}] = [P || #{id := 1} = P <- Ps],
  p73_reloj:usar_simulado(I - 3600000),
  #{inicio => I}.

esperar(Fun, Intentos) ->
  case Fun() of
    true -> ok;
    _ when Intentos =< 0 -> timeout;
    _ -> timer:sleep(20), esperar(Fun, Intentos - 1)
  end.

%% Ranking de una quiniela como lista [{Participante, Puntos, Posicion}].
ranking(Q) ->
  #{filas := F} = p73_quiniela:ranking(Q, 1000),
  [{P, Pts, Pos} || #{participante := P, pts := Pts, pos := Pos} <- F].
