%% Pruebas de las partes PURAS: puntos, ranking, JSON y datos del torneo.
-module(p73_puros_tests).
-include_lib("eunit/include/eunit.hrl").

%% ---- puntos ----
base() -> p73_puntos:reglas(#{}).

puntos_base_test_() ->
  R = base(),
  [?_assertEqual({3, exacto}, p73_puntos:puntos(R, grupos, {2, 1}, {2, 1})),
   ?_assertEqual({3, exacto}, p73_puntos:puntos(R, grupos, {0, 0}, {0, 0})),
   ?_assertEqual({1, ganador}, p73_puntos:puntos(R, grupos, {3, 0}, {1, 0})),
   ?_assertEqual({1, ganador}, p73_puntos:puntos(R, grupos, {0, 0}, {2, 2})),      %% empate acertado, otro marcador
   ?_assertEqual({1, ganador}, p73_puntos:puntos(R, grupos, {0, 2}, {1, 4})),
   ?_assertEqual({0, nada}, p73_puntos:puntos(R, grupos, {1, 0}, {0, 1})),
   ?_assertEqual({0, nada}, p73_puntos:puntos(R, grupos, {1, 1}, {2, 1}))].

reglas_distintas_por_quiniela_test_() ->
  Generosa = p73_puntos:reglas(#{exacto => 5, diferencia => 3, ganador => 2}),
  SoloExactos = p73_puntos:reglas(#{exacto => 3, ganador => 0}),
  Eliminatorias = p73_puntos:reglas(#{multiplicador => #{final => 4, cuartos => 2}}),
  [?_assertEqual({3, diferencia}, p73_puntos:puntos(Generosa, grupos, {2, 1}, {3, 2})),
   ?_assertEqual({2, ganador}, p73_puntos:puntos(Generosa, grupos, {3, 0}, {1, 0})),
   ?_assertEqual({5, exacto}, p73_puntos:puntos(Generosa, grupos, {1, 0}, {1, 0})),
   ?_assertEqual({0, nada}, p73_puntos:puntos(SoloExactos, grupos, {3, 0}, {1, 0})),   %% ganador vale 0
   ?_assertEqual({3, exacto}, p73_puntos:puntos(SoloExactos, grupos, {1, 0}, {1, 0})),
   ?_assertEqual({12, exacto}, p73_puntos:puntos(Eliminatorias, final, {1, 0}, {1, 0})),
   ?_assertEqual({2, ganador}, p73_puntos:puntos(Eliminatorias, cuartos, {2, 0}, {1, 0})),
   ?_assertEqual({1, ganador}, p73_puntos:puntos(Eliminatorias, octavos, {2, 0}, {1, 0}))].   %% fase sin multiplicador = x1

marcador_valido_test_() ->
  [?_assert(p73_puntos:valido({0, 0})), ?_assert(p73_puntos:valido({30, 3})),
   ?_assertNot(p73_puntos:valido({-1, 0})), ?_assertNot(p73_puntos:valido({31, 0})),
   ?_assertNot(p73_puntos:valido({a, 0})), ?_assertNot(p73_puntos:valido({1.5, 0}))].

%% ---- ranking ----
t(Pts, Ex, Ga) -> #{pts => Pts, exactos => Ex, ganadores => Ga, bonos => 0}.

ranking_desempate_test() ->
  R = p73_ranking:ordenar(#{<<"A">> => t(10, 1, 7), <<"B">> => t(10, 3, 1), <<"C">> => t(12, 0, 0),
                            <<"D">> => t(10, 3, 1), <<"E">> => t(10, 3, 0)}),
  %% C (12 pts) > B,D (10 pts, 3 exactos, 1 ganador: empatados) > E (menos ganadores) > A (menos exactos)
  ?assertEqual([{<<"C">>, 1}, {<<"B">>, 2}, {<<"D">>, 2}, {<<"E">>, 4}, {<<"A">>, 5}],
               [{P, Pos} || #{participante := P, pos := Pos} <- R]).

ranking_bonos_suman_test() ->
  R = p73_ranking:ordenar(#{<<"A">> => (t(3, 1, 0))#{bonos := 5}, <<"B">> => t(7, 2, 0)}),
  ?assertEqual([{<<"A">>, 8}, {<<"B">>, 7}], [{P, Pts} || #{participante := P, pts := Pts} <- R]).

ranking_es_determinista_test() ->
  T = maps:from_list([{integer_to_binary(I), t(I rem 5, I rem 3, 0)} || I <- lists:seq(1, 200)]),
  ?assertEqual(p73_ranking:ordenar(T), p73_ranking:ordenar(T)).

%% ---- json ----
json_ida_y_vuelta_test_() ->
  Casos = [#{<<"a">> => 1, <<"b">> => [true, false, null], <<"c">> => <<"hola \"mundo\"\n">>},
           #{<<"x">> => #{<<"y">> => [1, 2, #{<<"z">> => -3}]}},
           [], #{}, <<"España ⚽"/utf8>>],
  [?_assertEqual({ok, C}, p73_json:decodificar(p73_json:codificar(C))) || C <- Casos].

json_numeros_y_errores_test_() ->
  [?_assertEqual({ok, 12}, p73_json:decodificar(<<" 12 ">>)),
   ?_assertEqual({ok, -3}, p73_json:decodificar(<<"-3">>)),
   ?_assertEqual({ok, 1.5}, p73_json:decodificar(<<"1.5">>)),
   ?_assertEqual({ok, 100000.0}, p73_json:decodificar(<<"1e5">>)),
   ?_assertEqual({ok, <<"é"/utf8>>}, p73_json:decodificar(<<"\"\\u00e9\"">>)),
   ?_assertEqual({error, json_invalido}, p73_json:decodificar(<<"{no">>)),
   ?_assertEqual({error, json_invalido}, p73_json:decodificar(<<"[1,]">>)),
   ?_assertEqual({error, json_invalido}, p73_json:decodificar(<<"{\"a\":1,}">>)),
   ?_assertEqual({ok, #{}}, p73_json:decodificar(<<" { } ">>)),
   ?_assertEqual({ok, []}, p73_json:decodificar(<<"[ ]">>)),
   ?_assertEqual({error, json_invalido}, p73_json:decodificar(<<"{} basura">>)),
   ?_assertEqual({error, json_invalido}, p73_json:decodificar(<<>>))].

%% ---- datos del torneo (integridad de lo verificado a mano) ----
torneo_104_partidos_test() ->
  Ps = p73_torneo:partidos(),
  ?assertEqual(104, length(Ps)),
  ?assertEqual(lists:seq(1, 104), lists:sort([I || #{id := I} <- Ps])),
  Por = fun(F) -> length([x || #{fase := X} <- Ps, X =:= F]) end,
  ?assertEqual([72, 16, 8, 4, 2, 1, 1],
               [Por(F) || F <- [grupos, dieciseisavos, octavos, cuartos, semifinales, tercer_puesto, final]]).

torneo_48_equipos_y_3_partidos_de_grupo_test() ->
  Eq = p73_torneo:equipos(),
  ?assertEqual(48, length(Eq)),
  Grupos = [P || #{fase := grupos} = P <- p73_torneo:partidos()],
  Juegos = lists:flatmap(fun(#{local := L, visitante := V}) -> [L, V] end, Grupos),
  [?assertEqual({E, 3}, {E, length([X || X <- Juegos, X =:= E])}) || E <- Eq],
  %% Cada partido de grupo enfrenta a equipos del mismo grupo.
  G = p73_mundial2026:grupos(),
  [?assertEqual(Gr, hd([K || {K, Ts} <- maps:to_list(G), lists:member(L, Ts) andalso lists:member(V, Ts)]))
   || #{grupo := Gr, local := L, visitante := V} <- Grupos].

torneo_final_y_campeon_test() ->
  {ok, #{local := L, visitante := V, goles := {GL, GV}, cierre := C}} = p73_torneo:por_id(104),
  ?assertEqual({<<"España"/utf8>>, <<"Argentina">>, {1, 0}, alargue}, {L, V, {GL, GV}, C}),
  ?assertEqual(<<"España"/utf8>>, p73_mundial2026:campeon()).

torneo_ventanas_de_maximo_4_test() ->
  Vs = p73_torneo:ventanas(),
  ?assert(lists:all(fun({_, Ms}) -> length(Ms) =< 4 end, Vs)),
  ?assertEqual(104, lists:sum([length(Ms) || {_, Ms} <- Vs])),
  Inicios = [I || {I, _} <- Vs],
  ?assertEqual(Inicios, lists:sort(Inicios)),
  %% Cronologico: el partido 1 (apertura) es el primero y la final el ultimo.
  ?assertEqual(1, maps:get(id, hd(p73_torneo:partidos()))),
  ?assertEqual(104, maps:get(id, lists:last(p73_torneo:partidos()))).
