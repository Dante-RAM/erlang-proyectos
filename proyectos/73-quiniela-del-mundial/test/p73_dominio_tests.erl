%% Pruebas con procesos reales: bloqueo exacto, VAR, recuperacion tras kill y rest_for_one.
-module(p73_dominio_tests).
-include_lib("eunit/include/eunit.hrl").

dominio_test_() ->
  {foreach, fun p73_test_util:arrancar/0, fun p73_test_util:parar/1,
   [fun(_) -> {"pronostico: acepta hasta 1 ms antes y rechaza en el instante exacto", fun bloqueo_exacto/0} end,
    fun(_) -> {"reloj atrasado/saltos: el cierre no se reabre", fun reloj_atrasado/0} end,
    fun(_) -> {"el cliente no decide la hora (marcador invalido y participante inexistente)", fun validaciones/0} end,
    fun(_) -> {"VAR: gol contado, ranking, gol anulado, ranking vuelve", fun var_anula/0} end,
    fun(_) -> {"reglas distintas: la misma jugada da puntos distintos por quiniela", fun reglas_por_quiniela/0} end,
    fun(_) -> {"bono de campeon (final) se fija y se revierte con una correccion", fun bono_campeon/0} end,
    fun(_) -> {"kill de una quiniela: reinicia y converge al mismo ranking", fun kill_quiniela/0} end,
    fun(_) -> {"kill de un partido en vivo: retoma estado y numeracion de eventos", fun kill_partido/0} end,
    fun(_) -> {"kill de un participante: recupera sus pronosticos", fun kill_participante/0} end,
    fun(_) -> {"cae un supervisor dinamico: rest_for_one + poblacion repueblan desde ETS", fun cae_supervisor/0} end,
    fun(_) -> {"incremental == desde cero tras una secuencia de eventos y correcciones", fun incremental_igual/0} end]}.

%% ---- bloqueo ----
bloqueo_exacto() ->
  #{inicio := I} = #{inicio => maps:get(inicio, p73_torneo_1())},
  p73_test_util:escenario(),
  p73_reloj:usar_simulado(I - 1),
  ?assertEqual(ok, p73_participante:pronosticar(<<"U1">>, 1, 2, 0)),
  ?assertEqual(ok, p73_participante:pronosticar(<<"U1">>, 1, 1, 0)),   %% puede cambiarlo antes del cierre
  p73_reloj:usar_simulado(I),
  ?assertEqual({error, cerrado}, p73_participante:pronosticar(<<"U2">>, 1, 2, 0)),
  ?assertEqual({error, cerrado}, p73_participante:pronosticar(<<"U1">>, 1, 5, 5)),   %% ni cambiar el que ya tenia
  p73_reloj:usar_simulado(I + 5000),
  ?assertEqual({error, cerrado}, p73_participante:pronosticar(<<"U3">>, 1, 0, 0)),
  %% Lo guardado es el ultimo valido antes del cierre.
  ?assertMatch([{_, 1, 0, _}], ets:lookup(p73_pronosticos, {1, <<"U1">>})),
  ?assertEqual([], ets:lookup(p73_pronosticos, {1, <<"U2">>})).

reloj_atrasado() ->
  #{inicio := I} = p73_test_util:escenario(),
  p73_reloj:usar_simulado(I - 10),
  ?assertEqual(ok, p73_participante:pronosticar(<<"U1">>, 1, 1, 1)),
  ok = p73_partido:iniciar(1),
  %% El reloj del servidor "salta" una hora hacia atras (NTP, error operativo...): el estado manda.
  p73_reloj:usar_simulado(I - 3600000),
  ?assertEqual({error, cerrado}, p73_participante:pronosticar(<<"U2">>, 1, 1, 1)),
  %% Y otro partido (aun programado) sigue abierto con ese mismo reloj.
  ?assertEqual(ok, p73_participante:pronosticar(<<"U2">>, 2, 1, 1)).

validaciones() ->
  #{inicio := I} = p73_test_util:escenario(),
  p73_reloj:usar_simulado(I - 1000),
  ?assertEqual({error, marcador_invalido}, p73_participante:pronosticar(<<"U1">>, 1, -1, 0)),
  ?assertEqual({error, marcador_invalido}, p73_participante:pronosticar(<<"U1">>, 1, 99, 0)),
  ?assertEqual({error, no_disponible}, p73_participante:pronosticar(<<"NADIE">>, 1, 1, 0)),
  ?assertEqual({error, no_disponible}, p73_partido:pronosticar(999, <<"U1">>, 1, 0)).

%% ---- VAR / puntos ----
var_anula() ->
  #{inicio := I} = p73_test_util:escenario(),
  p73_reloj:usar_simulado(I - 1000),
  ok = p73_participante:pronosticar(<<"U1">>, 1, 2, 0),   %% marcador final real
  ok = p73_participante:pronosticar(<<"U2">>, 1, 1, 0),   %% acierta ganador
  ok = p73_participante:pronosticar(<<"U4">>, 1, 0, 1),   %% falla
  p73_reloj:usar_simulado(I),
  ok = p73_partido:iniciar(1),
  {ok, 1} = p73_partido:gol(1, local, 4),
  {ok, 2} = p73_partido:gol(1, local, 7),
  sync(),
  ?assertEqual([{<<"U1">>, 3, 1}, {<<"U2">>, 1, 2}, {<<"U4">>, 0, 3}], p73_test_util:ranking(<<"Q1">>)),
  {ok, 3} = p73_partido:gol(1, local, 20),               %% 3-0: ahora nadie acierta el exacto
  sync(),
  ?assertEqual([{<<"U1">>, 1, 1}, {<<"U2">>, 1, 1}, {<<"U4">>, 0, 3}], p73_test_util:ranking(<<"Q1">>)),
  ok = p73_partido:anular_gol(1, 3),                     %% VAR: se anula DESPUES de haberse contado
  sync(),
  ?assertEqual([{<<"U1">>, 3, 1}, {<<"U2">>, 1, 2}, {<<"U4">>, 0, 3}], p73_test_util:ranking(<<"Q1">>)),
  ?assertEqual({error, evento_inexistente}, p73_partido:anular_gol(1, 3)),   %% ya anulado
  ok = p73_partido:finalizar(1),
  sync(),
  ?assertMatch(#{marcador := {2, 0}, definitivo := true}, p73_partido:snapshot(1)),
  ?assertEqual([{<<"U1">>, 3, 1}, {<<"U2">>, 1, 2}, {<<"U4">>, 0, 3}], p73_test_util:ranking(<<"Q1">>)),
  %% Correccion tardia tras el final (permitida): cambia el resultado definitivo.
  ?assertEqual({error, {estado_invalido, finalizado}}, p73_partido:gol(1, local, 90)),
  ?assertEqual(ok, p73_quiniela:verificar(<<"Q1">>)).

reglas_por_quiniela() ->
  #{inicio := I} = p73_test_util:escenario(),
  p73_reloj:usar_simulado(I - 1000),
  ok = p73_participante:pronosticar(<<"U2">>, 1, 3, 1),   %% U2 esta en Q1 y Q2
  p73_reloj:usar_simulado(I),
  ok = p73_partido:iniciar(1),
  {ok, _} = p73_partido:gol(1, local, 1),
  {ok, _} = p73_partido:gol(1, local, 2),                 %% 2-0: ganador y misma diferencia? 3-1 vs 2-0 -> diff 2 = 2
  sync(),
  ?assertEqual([{<<"U2">>, 1, 1}, {<<"U1">>, 0, 2}, {<<"U4">>, 0, 2}], p73_test_util:ranking(<<"Q1">>)),   %% clasica: ganador = 1
  ?assertEqual([{<<"U2">>, 3, 1}, {<<"U3">>, 0, 2}], p73_test_util:ranking(<<"Q2">>)).                    %% generosa: misma diferencia = 3

bono_campeon() ->
  #{inicio := I} = p73_test_util:escenario(),
  ok = p73_participante:elegir_campeon(<<"U2">>, <<"España"/utf8>>),
  ok = p73_participante:elegir_campeon(<<"U3">>, <<"Argentina">>),
  ?assertEqual({error, equipo_invalido}, p73_participante:elegir_campeon(<<"U1">>, <<"Atlantis">>)),
  p73_reloj:usar_simulado(I),                              %% ya inicio el torneo: no se puede elegir campeon
  ?assertEqual({error, cerrado}, p73_participante:elegir_campeon(<<"U1">>, <<"España"/utf8>>)),
  ok = p73_partido:iniciar(104),
  {ok, N} = p73_partido:gol(104, local, 106),              %% Espana 1-0 Argentina (alargue)
  ok = p73_partido:finalizar(104),
  sync(),
  ?assertMatch(#{ganador := <<"España"/utf8>>}, p73_partido:snapshot(104)),
  %% Quiniela clasica: bono 5 para quien acerto a Espana; Q2 igual (bono por defecto 5).
  ?assertEqual([{<<"U2">>, 5, 1}, {<<"U1">>, 0, 2}, {<<"U4">>, 0, 2}], p73_test_util:ranking(<<"Q1">>)),
  %% VAR tardio anula el gol decisivo: 0-0 y sin penales definidos => nadie es campeon, el bono se revierte.
  ok = p73_partido:anular_gol(104, N),
  sync(),
  ?assertEqual([{<<"U1">>, 0, 1}, {<<"U2">>, 0, 1}, {<<"U4">>, 0, 1}], p73_test_util:ranking(<<"Q1">>)).

%% ---- fallas ----
kill_quiniela() ->
  #{inicio := I} = p73_test_util:escenario(),
  p73_reloj:usar_simulado(I - 1000),
  ok = p73_participante:pronosticar(<<"U1">>, 1, 2, 0),
  ok = p73_participante:pronosticar(<<"U2">>, 1, 1, 0),
  p73_reloj:usar_simulado(I),
  ok = p73_partido:iniciar(1),
  {ok, _} = p73_partido:gol(1, local, 3),
  {ok, _} = p73_partido:gol(1, local, 9),
  sync(),
  Antes = p73_test_util:ranking(<<"Q1">>),
  ?assertMatch({ok, #{recuperado_ms := _}}, p73_caos:matar(quiniela, <<"Q1">>)),
  ?assertEqual(Antes, p73_test_util:ranking(<<"Q1">>)),
  %% Y sigue recibiendo actualizaciones despues de reiniciar.
  {ok, _} = p73_partido:gol(1, visitante, 30),
  sync(),
  ?assertEqual([{<<"U1">>, 1, 1}, {<<"U2">>, 1, 1}, {<<"U4">>, 0, 3}], p73_test_util:ranking(<<"Q1">>)),   %% 2-1: ganador
  ?assertEqual(ok, p73_quiniela:verificar(<<"Q1">>)).

kill_partido() ->
  #{inicio := I} = p73_test_util:escenario(),
  p73_reloj:usar_simulado(I),
  ok = p73_partido:iniciar(1),
  {ok, 1} = p73_partido:gol(1, local, 3),
  {ok, 2} = p73_partido:gol(1, visitante, 5),
  Antes = p73_partido:snapshot(1),
  {ok, _} = p73_caos:matar(partido, 1),
  ?assertEqual(Antes, p73_partido:snapshot(1)),
  ?assertMatch(#{estado := en_vivo, marcador := {1, 1}}, p73_partido:snapshot(1)),
  ?assertEqual({ok, 3}, p73_partido:gol(1, local, 50)),   %% la numeracion de eventos no se reinicia
  %% Un partido reiniciado tampoco reabre el pronostico.
  ?assertEqual({error, cerrado}, p73_participante:pronosticar(<<"U1">>, 1, 0, 0)).

kill_participante() ->
  #{inicio := I} = p73_test_util:escenario(),
  p73_reloj:usar_simulado(I - 1000),
  ok = p73_participante:pronosticar(<<"U2">>, 1, 2, 0),
  ok = p73_participante:pronosticar(<<"U2">>, 2, 1, 1),
  ?assertMatch(#{pronosticos := 2, quinielas := [<<"Q1">>, <<"Q2">>]}, p73_participante:info(<<"U2">>)),
  {ok, _} = p73_caos:matar(participante, <<"U2">>),
  ?assertMatch(#{pronosticos := 2, quinielas := [<<"Q1">>, <<"Q2">>]}, p73_participante:info(<<"U2">>)),
  ?assertEqual(ok, p73_participante:pronosticar(<<"U2">>, 2, 3, 3)),   %% sigue operando
  ?assertMatch([{_, 3, 3, _}], ets:lookup(p73_pronosticos, {2, <<"U2">>})).

cae_supervisor() ->
  #{inicio := I} = p73_test_util:escenario(),
  p73_reloj:usar_simulado(I - 1000),
  ok = p73_participante:pronosticar(<<"U1">>, 1, 2, 0),
  p73_reloj:usar_simulado(I),
  ok = p73_partido:iniciar(1),
  {ok, _} = p73_partido:gol(1, local, 3),
  {ok, _} = p73_partido:gol(1, local, 9),
  sync(),
  Antes = p73_test_util:ranking(<<"Q1">>),
  Viejo = whereis(p73_quinielas_sup),
  exit(Viejo, kill),   %% cae el supervisor de TODAS las quinielas
  Vuelve = fun() ->
               whereis(p73_quinielas_sup) =/= Viejo andalso
                 p73_reg:buscar({quiniela, <<"Q1">>}) =/= {error, no_disponible} andalso
                 p73_reg:buscar({quiniela, <<"Q2">>}) =/= {error, no_disponible} andalso
                 p73_reg:buscar({participante, <<"U1">>}) =/= {error, no_disponible} andalso
                 p73_reg:buscar({partido, 1}) =/= {error, no_disponible}
           end,
  ?assertEqual(ok, p73_test_util:esperar(Vuelve, 250)),
  ?assertEqual(Antes, p73_test_util:ranking(<<"Q1">>)),
  ?assertEqual(ok, p73_quiniela:verificar(<<"Q1">>)).

%% ---- consistencia ----
incremental_igual() ->
  #{inicio := I} = p73_test_util:escenario(),
  p73_reloj:usar_simulado(I - 1000),
  [ok = p73_participante:pronosticar(U, P, L, V)
   || {U, P, L, V} <- [{<<"U1">>, 1, 2, 0}, {<<"U2">>, 1, 1, 1}, {<<"U3">>, 1, 0, 2}, {<<"U4">>, 1, 3, 0},
                       {<<"U1">>, 2, 2, 1}, {<<"U2">>, 2, 0, 0}, {<<"U3">>, 2, 2, 1}]],
  p73_reloj:usar_simulado(I),
  [ok = p73_partido:iniciar(P) || P <- [1, 2]],
  {ok, A} = p73_partido:gol(1, local, 1),
  {ok, _} = p73_partido:gol(2, local, 2),
  {ok, _} = p73_partido:gol(2, visitante, 3),
  {ok, B} = p73_partido:gol(1, visitante, 4),
  ok = p73_partido:anular_gol(1, A),
  {ok, _} = p73_partido:gol(1, local, 5),
  ok = p73_partido:anular_gol(1, B),
  [ok = p73_partido:finalizar(P) || P <- [1, 2]],
  sync(),
  ?assertEqual(ok, p73_quiniela:verificar(<<"Q1">>)),
  ?assertEqual(ok, p73_quiniela:verificar(<<"Q2">>)).

sync() -> [ok = p73_quiniela:sincronizar(Q) || Q <- [<<"Q1">>, <<"Q2">>]], ok.

p73_torneo_1() -> {ok, P} = p73_torneo:por_id(1), P.
