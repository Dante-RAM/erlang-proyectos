%% El escenario del enunciado a escala reducida (el completo se corre con scripts/simular.sh).
-module(p73_simulador_tests).
-include_lib("eunit/include/eunit.hrl").

simulacion_reducida_test_() ->
  {timeout, 120,
   {setup, fun p73_test_util:arrancar/0, fun p73_test_util:parar/1,
    fun(_) -> {"escenario con rafaga, VAR y caos converge y cuadra con el oraculo", fun escenario/0} end}}.

escenario() ->
  R = p73_simulador:correr(#{participantes => 120, quinielas => 8, partidos => 24,
                             rafaga => 60, rafaga_tarde => 20, workers => 8}),
  #{rafaga := Rafaga, consistencia := Cons, caos := Caos, var := Var, simultaneos_max := Sim} = R,
  %% 24 partidos: 6 ventanas de 4 simultaneos en promedio; en algun momento hubo 4 vivos a la vez.
  ?assertEqual(4, Sim),
  %% Rafaga previa al inicio: todo lo que llego a tiempo se acepto, incluido 1 ms antes del cierre.
  ?assertMatch(#{intentos := 60, aceptadas := 60, rechazadas_a_tiempo := 0,
                 borde_inicio_menos_1ms := #{intentos := 50, aceptadas := 50}}, Rafaga),
  %% Lo que llego en el inicio exacto, o con el reloj atrasado, se rechazo SIEMPRE.
  ?assertMatch(#{tarde_intentos := 20, tarde_rechazadas := 20,
                 tarde_en_inicio_exacto := #{aceptadas := 0}, tarde_con_reloj_atrasado := #{aceptadas := 0}}, Rafaga),
  %% Incremental == desde cero, y == oraculo independiente, en TODAS las quinielas.
  ?assertMatch(#{incremental_vs_desde_cero_fallos := [], oraculo_independiente_fallos := [],
                 quinielas_verificadas := 8}, Cons),
  %% Hubo goles anulados por VAR y fallas inyectadas, y todas se recuperaron sin perder estado.
  ?assert(length(Var) >= 1),
  ?assert(length(Caos) >= 1),
  [?assertMatch(#{ranking_identico_tras_reiniciar := true, partido_estado_identico := true}, C) || C <- Caos],
  [?assert(maps:get(quiniela_recuperada_ms, C) < 1000) || C <- Caos],
  %% Todas las predicciones de las ventanas se aceptaron (120 participantes x 24 partidos).
  ?assertEqual(120 * 24, maps:get(<<"predicciones_aceptadas">>, maps:get(metricas, R))),
  ?assertEqual(20, maps:get(<<"predicciones_rechazadas">>, maps:get(metricas, R))).

%% Regresion: consultar el estado mientras corre NO debe perder el resultado (bug real: handle_call(estado)
%% devolvia un estado sin `pid` y la simulacion terminada se descartaba; la UI consulta cada 2 s).
simulacion_en_segundo_plano_test_() ->
  {setup, fun p73_test_util:arrancar/0, fun p73_test_util:parar/1,
   fun(_) ->
       [{timeout, 60, {"sondear el estado en bucle mientras corre => termina con reporte", fun en_segundo_plano/0}},
        {timeout, 60, {"una segunda simulacion mientras hay una en curso se rechaza", fun ocupado/0}}]
   end}.

esperar_terminada() ->
  p73_test_util:esperar(fun() -> maps:get(estado, p73_simulador:estado()) =:= terminado end, 1500).

en_segundo_plano() ->
  ?assertEqual(ok, p73_simulador:iniciar(#{participantes => 80, quinielas => 5, partidos => 16,
                                           rafaga => 40, rafaga_tarde => 10, workers => 4})),
  ?assertEqual(ok, esperar_terminada()),   %% cada sondeo llama estado(), como la UI
  #{estado := terminado, reporte := #{consistencia := Cons}} = p73_simulador:estado(),
  ?assertMatch(#{incremental_vs_desde_cero_fallos := [], oraculo_independiente_fallos := []}, Cons).

ocupado() ->
  %% Escala suficiente para que siga corriendo cuando llega la segunda peticion.
  ?assertEqual(ok, p73_simulador:iniciar(#{participantes => 1500, quinielas => 10, partidos => 60})),
  ?assertEqual({error, ocupado}, p73_simulador:iniciar(#{participantes => 10, quinielas => 1, partidos => 2})),
  ?assertEqual(ok, esperar_terminada()),
  %% Terminada la anterior, se puede lanzar otra.
  ?assertEqual(ok, p73_simulador:iniciar(#{participantes => 20, quinielas => 2, partidos => 4, rafaga => 10,
                                           rafaga_tarde => 4, workers => 2})),
  ?assertEqual(ok, esperar_terminada()).

%% Regresion: con pocas quinielas (1 o 2) la asignacion de membresias se colgaba en un bucle infinito.
pocas_quinielas_test_() ->
  {timeout, 60,
   {setup, fun p73_test_util:arrancar/0, fun p73_test_util:parar/1,
    fun(_) -> [{"con " ++ integer_to_list(N) ++ " quiniela(s) termina y es consistente",
                fun() ->
                    R = p73_simulador:correr(#{participantes => 30, quinielas => N, partidos => 6, rafaga => 10,
                                               rafaga_tarde => 4, workers => 2}),
                    ?assertMatch(#{consistencia := #{incremental_vs_desde_cero_fallos := [],
                                                     oraculo_independiente_fallos := []}}, R)
                end} || N <- [1, 2, 3]]
    end}}.
