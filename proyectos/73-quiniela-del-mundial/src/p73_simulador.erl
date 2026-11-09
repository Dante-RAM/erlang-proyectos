%% Simulador del escenario del enunciado sobre el Mundial 2026 (datos reales de los 104 partidos):
%%   5,000 participantes, 50 quinielas con reglas distintas, 4 partidos en simultaneo,
%%   2,000 pronosticos en los 60 s previos a un inicio, gol anulado por VAR tras contarse,
%%   y fallas inyectadas (kill de quinielas, partidos y participantes en pleno juego).
%% Todo es determinista dada la `semilla`. Los pronosticos de los participantes SON generados
%% (sesgados hacia el resultado real para que haya competencia); los resultados de los partidos son reales.
-module(p73_simulador).
-behaviour(gen_server).

-export([start_link/0, iniciar/1, estado/0, correr/1, correr/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-define(MIN, 60000).

defaults() ->
  #{participantes => 5000, quinielas => 50, partidos => 104, semilla => 2026,
    rafaga => 2000, rafaga_tarde => 200, caos => true, var => true, workers => 32,
    rafaga_partido => ultimo}.

%% ---- servicio (para la UI/HTTP): una simulacion a la vez, en segundo plano ----
start_link() -> gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

-spec iniciar(map()) -> ok | {error, ocupado}.
iniciar(Opts) -> gen_server:call(?MODULE, {iniciar, Opts}).

estado() -> gen_server:call(?MODULE, estado).

init([]) -> {ok, #{estado => inactivo, progreso => #{}, reporte => undefined, pid => undefined}}.

handle_call({iniciar, _}, _From, #{estado := corriendo} = S) -> {reply, {error, ocupado}, S};
handle_call({iniciar, Opts}, _From, S) ->
  Yo = self(),
  {Pid, _} = spawn_monitor(fun() ->
    Resultado = try {ok, correr(Opts, fun(P) -> gen_server:cast(Yo, {progreso, P}) end)}
                catch Clase:Razon:Pila -> {error, {Clase, Razon, Pila}}
                end,
    Yo ! {resultado, self(), Resultado}
  end),
  {reply, ok, S#{estado := corriendo, progreso := #{fase => <<"preparando">>}, reporte := undefined, pid := Pid}};
%% Consultar el estado NO debe tocar el estado interno (antes se perdia `pid` y el resultado se descartaba).
handle_call(estado, _From, S) ->
  {reply, maps:with([estado, progreso, reporte], S), S}.

handle_cast({progreso, P}, #{estado := corriendo} = S) -> {noreply, S#{progreso := P}};
handle_cast(_, S) -> {noreply, S}.

handle_info({resultado, Pid, {ok, Reporte}}, #{pid := Pid} = S) ->
  {noreply, S#{estado := terminado, reporte := Reporte, pid := undefined}};
handle_info({resultado, Pid, {error, Razon}}, #{pid := Pid} = S) ->
  logger:error("simulacion fallo: ~p", [Razon]),
  {noreply, S#{estado := error, reporte := #{error => iolist_to_binary(io_lib:format("~p", [Razon]))}, pid := undefined}};
%% Si el trabajador muere sin entregar resultado (kill externo, falta de memoria...), no quedarse "corriendo" para siempre.
handle_info({'DOWN', _, process, Pid, Razon}, #{pid := Pid, estado := corriendo} = S) when Razon =/= normal ->
  logger:error("simulacion: el trabajador murio sin resultado: ~p", [Razon]),
  {noreply, S#{estado := error, pid := undefined,
               reporte := #{error => iolist_to_binary(io_lib:format("trabajador muerto: ~p", [Razon]))}}};
handle_info(_, S) -> {noreply, S}.

%% ---- escenario ----
correr(Opts) -> correr(Opts, fun(_) -> ok end).

-spec correr(map(), fun((map()) -> any())) -> map().
correr(Opts0, Prog) ->
  O = maps:merge(defaults(), Opts0),
  #{participantes := NU, quinielas := NQ, partidos := NP, semilla := Sem, workers := W} = O,
  T0 = erlang:monotonic_time(millisecond),
  ok = p73_poblacion:limpiar(),
  Partidos = lists:sublist(p73_torneo:partidos(), NP),
  [ok = p73_poblacion:registrar_partido(maps:with([id, fase, grupo, local, visitante, inicio], P)) || P <- Partidos],
  p73_reloj:usar_simulado(maps:get(inicio, hd(Partidos)) - 2 * 86400 * 1000),
  Qs = [{qid(I), nombre_quiniela(I), reglas_de(I)} || I <- lists:seq(1, NQ)],
  [ok = p73_poblacion:registrar_quiniela(Id, N, R) || {Id, N, R} <- Qs],
  QIds = [Id || {Id, _, _} <- Qs],
  Us = [uid(I) || I <- lists:seq(1, NU)],
  [ok = p73_poblacion:registrar_participante(U, <<"Participante ", U/binary>>, membresia(Sem, U, QIds)) || U <- Us],
  Arranque = p73_poblacion:asegurar(),
  Prog(#{fase => <<"campeones">>, partidos_hechos => 0, partidos_total => length(Partidos)}),
  pmap(fun(U) -> ok = p73_participante:elegir_campeon(U, campeon_de(Sem, U)) end, Us, W),

  Ventanas = ventanas(Partidos),
  RafagaId = rafaga_id(O, Partidos),
  Estado0 = #{hechos => 0, total => length(Partidos), var => [], caos => [], rafaga => undefined,
              simultaneos_max => 0},
  Estado = lists:foldl(fun({Idx, {Inicio, Ms}}, Acc) ->
                           ventana(Idx, length(Ventanas), Inicio, Ms, Us, QIds, O, RafagaId, Prog, Acc)
                       end, Estado0, lists:zip(lists:seq(1, length(Ventanas)), Ventanas)),

  Prog(#{fase => <<"verificando">>, partidos_hechos => length(Partidos), partidos_total => length(Partidos)}),
  [ok = p73_quiniela:sincronizar(Q) || Q <- QIds],
  Verif = pmap(fun(Q) -> {Q, p73_quiniela:verificar(Q), oraculo(Q)} end, QIds, 8),
  FallosInc = [Q || {Q, V, _} <- Verif, V =/= ok],
  FallosOra = [Q || {Q, _, Ok} <- Verif, Ok =/= ok],
  Dur = erlang:monotonic_time(millisecond) - T0,
  #{opciones => O,
    arranque => Arranque,
    duracion_ms => Dur,
    partidos_simulados => length(Partidos),
    ventanas => length(Ventanas),
    simultaneos_max => maps:get(simultaneos_max, Estado),
    rafaga => maps:get(rafaga, Estado),
    var => lists:reverse(maps:get(var, Estado)),
    caos => lists:reverse(maps:get(caos, Estado)),
    consistencia => #{incremental_vs_desde_cero_fallos => FallosInc, oraculo_independiente_fallos => FallosOra,
                      quinielas_verificadas => length(QIds)},
    metricas => maps:from_list([{metrica_nombre(K), V} || {K, V} <- p73_metricas:todas(), is_atom(K)]),
    ranking_ejemplo => ranking_ejemplo(hd(QIds)),
    procesos_vm => erlang:system_info(process_count),
    memoria_mb => erlang:memory(total) div 1048576}.

%% ---- una ventana: pronosticos, rafaga, arranque, eventos, final ----
ventana(Idx, TotalV, Inicio, Ms, Us, QIds, O, RafagaId, Prog, Acc) ->
  #{semilla := Sem, workers := W} = O,
  Ids = [maps:get(id, M) || M <- Ms],
  Prog(#{fase => <<"ventana ", (integer_to_binary(Idx))/binary, "/", (integer_to_binary(TotalV))/binary>>,
         partidos_hechos => maps:get(hechos, Acc), partidos_total => maps:get(total, Acc),
         partidos_en_vivo => Ids}),
  %% 1) Pronosticos normales, 30 min antes: todos los participantes, en paralelo.
  p73_reloj:usar_simulado(Inicio - 30 * ?MIN),
  pmap(fun(U) ->
           [ok = p73_participante:pronosticar(U, maps:get(id, M), L, V)
            || M <- Ms, {L, V} <- [pronostico(Sem, U, maps:get(id, M), maps:get(goles, M))]]
       end, Us, W),
  %% 2) Rafaga en el ultimo minuto (solo en el partido elegido).
  {Rafaga, Acc1} =
    case lists:member(RafagaId, Ids) of
      true -> {rafaga_previa(RafagaId, Inicio, Us, O), Acc};
      false -> {undefined, Acc}
    end,
  %% 3) Bloqueo exacto: en el instante de inicio (guardia de RELOJ) ...
  p73_reloj:usar_simulado(Inicio),
  Tarde1 = case Rafaga of undefined -> undefined; _ -> intentar_tarde(RafagaId, Us, maps:get(rafaga_tarde, O) div 2, O) end,
  [ok = p73_partido:iniciar(I) || I <- Ids],
  %% ... y con el reloj ATRASADO una hora, ya iniciado el partido (guardia de ESTADO).
  Tarde2 = case Rafaga of
             undefined -> undefined;
             _ -> p73_reloj:usar_simulado(Inicio - 60 * ?MIN),
                  R = intentar_tarde(RafagaId, Us, maps:get(rafaga_tarde, O) div 2, O),
                  p73_reloj:usar_simulado(Inicio), R
           end,
  Acc2 = case Rafaga of
           undefined -> Acc1;
           _ -> Acc1#{rafaga := Rafaga#{tarde_intentos => cuenta(Tarde1) + cuenta(Tarde2),
                                        tarde_rechazadas => rechazos(Tarde1) + rechazos(Tarde2),
                                        tarde_en_inicio_exacto => Tarde1, tarde_con_reloj_atrasado => Tarde2}}
         end,
  %% 4) Eventos en vivo de los partidos simultaneos, intercalados por minuto.
  Acc3 = eventos(Ms, Inicio, QIds, O, Idx, Acc2#{simultaneos_max := max(length(Ms), maps:get(simultaneos_max, Acc2))}),
  %% 5) Final de cada partido.
  [begin
     p73_reloj:usar_simulado(Inicio + 125 * ?MIN),
     ok = p73_partido:finalizar(maps:get(id, M), penales(maps:get(cierre, M)))
   end || M <- Ms],
  Acc3#{hechos := maps:get(hechos, Acc3) + length(Ms)}.

penales({penales, A, B}) -> {A, B};
penales(_) -> undefined.

%% 2,000 pronosticos (cambios de marcador) repartidos en los 60 s previos, 60 pasos de 1 s,
%% cada paso con sus pronosticos EN PARALELO (un proceso por pronostico).
rafaga_previa(PId, Inicio, Us, #{rafaga := N, semilla := Sem}) ->
  Muestra = lists:sublist(Us, min(N, length(Us))),
  Pasos = 60,
  T0 = erlang:monotonic_time(millisecond),
  Lotes = reparto(Muestra, Pasos),
  Resultados = lists:append([begin
      p73_reloj:usar_simulado(Inicio - (?MIN - S * 1000)),
      pmap(fun(U) -> p73_participante:pronosticar(U, PId, rand_gol(Sem, U, S), rand_gol(Sem, U, S + 1000)) end,
            Lote, length(Lote))
    end || {S, Lote} <- lists:zip(lists:seq(0, Pasos - 1), Lotes)]),
  Dt = max(1, erlang:monotonic_time(millisecond) - T0),
  Ok = length([R || R <- Resultados, R =:= ok]),
  %% Ultimo milisegundo antes del inicio: todavia debe aceptarse.
  p73_reloj:usar_simulado(Inicio - 1),
  Borde = pmap(fun(U) -> p73_participante:pronosticar(U, PId, 1, 1) end, lists:sublist(Us, 50), 50),
  #{partido => PId, intentos => length(Resultados), aceptadas => Ok,
    rechazadas_a_tiempo => length(Resultados) - Ok, duracion_real_ms => Dt,
    tasa_por_s => round(length(Resultados) * 1000 / Dt),
    borde_inicio_menos_1ms => #{intentos => 50, aceptadas => length([R || R <- Borde, R =:= ok])}}.

intentar_tarde(PId, Us, N, #{semilla := Sem}) ->
  Rs = pmap(fun(U) -> p73_participante:pronosticar(U, PId, rand_gol(Sem, U, 7), rand_gol(Sem, U, 8)) end,
            lists:sublist(Us, N), max(1, N)),
  #{intentos => length(Rs), rechazadas => length([R || R <- Rs, R =:= {error, cerrado}]),
    aceptadas => length([R || R <- Rs, R =:= ok])}.

cuenta(#{intentos := N}) -> N;
cuenta(_) -> 0.
rechazos(#{rechazadas := N}) -> N;
rechazos(_) -> 0.

%% Goles reales en minutos al azar (determinista); cada 8 partidos hay un gol fantasma que se cuenta
%% y 3 min despues el VAR lo anula. A mitad de la ventana se inyectan fallas (kill) en pleno juego.
eventos(Ms, Inicio, QIds, #{semilla := Sem, var := ConVar} = O, Idx, Acc) ->
  Evs = lists:sort(lists:append([eventos_de(Sem, M, ConVar) || M <- Ms])),
  Mitad = length(Evs) div 2,
  Q1 = hd(QIds),
  PCaos = maps:get(id, hd(Ms)),
  {Acc1, _, _} = lists:foldl(fun({Min, _Ord, PId, Que}, {A, F, N}) ->
      p73_reloj:usar_simulado(Inicio + Min * ?MIN),
      {A1, F1} = aplicar(Que, PId, Min, Q1, QIds, A, F),
      A2 = case N =:= Mitad of
             true -> caos_si_toca(Idx, PCaos, QIds, O, A1);
             false -> A1
           end,
      {A2, F1, N + 1}
  end, {Acc, #{}, 0}, Evs),
  Acc1.

eventos_de(Sem, #{id := Id, goles := {GL, GV}, cierre := Cierre}, ConVar) ->
  Lados = lists:duplicate(GL, local) ++ lists:duplicate(GV, visitante),
  S0 = rand:seed_s(exsss, {Sem, Id, 11}),
  {Normales, S1} = lists:mapfoldl(fun(Lado, S) ->
                      {Min, S2} = rand:uniform_s(88, S),
                      {{Min, Id, Id, {gol, Lado}}, S2} end, S0, Lados),
  %% En alargue (la final) el gol decisivo cae en tiempo extra (min 106 en el partido real).
  Normales1 = case Cierre of
                alargue when Normales =/= [] ->
                  [{_, Ord, I2, Q} | Resto] = lists:reverse(lists:sort(Normales)),
                  [{106, Ord, I2, Q} | Resto];
                _ -> Normales
              end,
  Fantasma = case ConVar andalso Id rem 8 =:= 1 of
               true ->
                 {M0, S3} = rand:uniform_s(70, S1),
                 {L0, _} = rand:uniform_s(2, S3),
                 Lado = case L0 of 1 -> local; 2 -> visitante end,
                 [{M0 + 5, Id, Id, {gol_fantasma, Lado}}, {M0 + 8, Id, Id, {anular_fantasma}}];
               false -> []
             end,
  Normales1 ++ Fantasma.

aplicar({gol, Lado}, PId, Min, _Q1, _QIds, A, F) ->
  {ok, _} = p73_partido:gol(PId, Lado, Min),
  {A, F};
aplicar({gol_fantasma, Lado}, PId, Min, _Q1, _QIds, A, F) ->
  {ok, N} = p73_partido:gol(PId, Lado, Min),
  {A, F#{PId => N}};
aplicar({anular_fantasma}, PId, Min, Q1, QIds, #{var := Var} = A, F) ->
  %% Medir el efecto: ranking de la primera quiniela con el gol contado vs. ya anulado.
  [ok = p73_quiniela:sincronizar(Q) || Q <- QIds],
  Antes = top(Q1, 3),
  ok = p73_partido:anular_gol(PId, maps:get(PId, F)),
  [ok = p73_quiniela:sincronizar(Q) || Q <- QIds],
  Despues = top(Q1, 3),
  Reg = #{partido => PId, minuto_anulacion => Min, quiniela => Q1, top3_con_gol_contado => Antes, top3_tras_anular => Despues,
          cambio => Antes =/= Despues},
  A1 = case length(Var) < 5 of true -> A#{var := [Reg | Var]}; false -> A end,
  {A1, F}.

top(Q, N) ->
  #{filas := Fs} = p73_quiniela:ranking(Q, N),
  [#{participante => P, pts => Pts} || #{participante := P, pts := Pts} <- Fs].

%% Fallas inyectadas en pleno juego, en ventanas espaciadas; luego se comprueba que todo converge.
caos_si_toca(Idx, PId, QIds, #{caos := Activo}, #{caos := Caos} = A) ->
  case Activo andalso Idx rem 3 =:= 2 andalso length(Caos) < 12 of
    false -> A;
    true ->
      Q = lists:nth(rand:uniform(length(QIds)), QIds),
      RankAntes = p73_quiniela:ranking(Q, 100000),
      SnapAntes = p73_partido:snapshot(PId),
      {ok, RQ} = p73_caos:matar(quiniela, Q),
      ok = p73_quiniela:sincronizar(Q),
      RankDesp = p73_quiniela:ranking(Q, 100000),
      {ok, RP} = p73_caos:matar(partido, PId),
      SnapDesp = p73_partido:snapshot(PId),
      Us = ets:select(p73_participantes, [{{'$1', '_', '_'}, [], ['$1']}]),
      Victimas = lists:sublist(Us, 1 + (Idx rem 7), 20),
      RU = [begin {ok, R} = p73_caos:matar(participante, U), R end || U <- Victimas],
      Pre = #{n => length(Caos) + 1, ventana => Idx,
              quiniela_muerta => Q, ranking_identico_tras_reiniciar => ranking_igual(RankAntes, RankDesp),
              quiniela_recuperada_ms => maps:get(recuperado_ms, RQ),
              partido_muerto => PId, partido_estado_identico => SnapAntes =:= SnapDesp,
              partido_recuperado_ms => maps:get(recuperado_ms, RP),
              participantes_muertos => length(RU),
              participantes_recuperados_ms_max => lists:max([maps:get(recuperado_ms, R) || R <- RU])},
      A#{caos := [Pre | Caos]}
  end.

%% Compara el ranking (sin el contador de version, que cambia al reiniciar).
ranking_igual(#{filas := A}, #{filas := B}) -> A =:= B.

%% ---- verificacion independiente ----
%% Oraculo: recalcula todo el ranking de una quiniela con las funciones puras, sin usar el estado
%% incremental del proceso, y lo compara con lo que ese proceso reporta.
oraculo(QId) ->
  [{QId, _, Reglas}] = ets:lookup(p73_quinielas, QId),
  Miembros = [P || {_, P} <- ets:lookup(p73_miembros, QId)],
  Snaps = [S || #{estado := E} = S <- p73_partido:snapshots_persistidos(), E =/= programado],
  Campeon = case [G || #{fase := final, definitivo := true, ganador := G} <- Snaps] of [G0 | _] -> G0; [] -> undefined end,
  Totales = maps:from_list([{P, lists:foldl(fun(#{id := PId, fase := Fase, marcador := Res}, Tot) ->
      case ets:lookup(p73_pronosticos, {PId, P}) of
        [{_, L, V, _}] ->
          {Pts, Tipo} = p73_puntos:puntos(Reglas, Fase, {L, V}, Res),
          Tot1 = Tot#{pts := maps:get(pts, Tot) + Pts},
          case Tipo of
            exacto -> Tot1#{exactos := maps:get(exactos, Tot1) + 1};
            nada -> Tot1;
            _ -> Tot1#{ganadores := maps:get(ganadores, Tot1) + 1}
          end;
        [] -> Tot
      end end, bono(P, Reglas, Campeon), Snaps)} || P <- Miembros]),
  Esperado = p73_ranking:ordenar(Totales),
  #{filas := Real} = p73_quiniela:ranking(QId, length(Miembros) + 1),
  case Esperado =:= Real of true -> ok; false -> diferente end.

bono(P, Reglas, Campeon) ->
  Acierto = case ets:lookup(p73_campeones, P) of [{_, E}] -> E =:= Campeon; [] -> false end,
  (p73_ranking:nuevo_total())#{bonos := p73_puntos:bono_campeon(Reglas, Acierto)}.

ranking_ejemplo(Q) -> #{quiniela => Q, top5 => top(Q, 5)}.

%% ---- generadores deterministas ----
qid(I) -> iolist_to_binary(io_lib:format("Q~2..0w", [I])).
uid(I) -> iolist_to_binary(io_lib:format("U~4..0w", [I])).

nombre_quiniela(I) ->
  Tipos = {<<"Clasica">>, <<"Generosa">>, <<"Solo exactos">>, <<"Eliminatorias x2 + campeon">>},
  Lugares = {<<"Oficina">>, <<"Escuela">>, <<"Familia">>, <<"Amigos">>, <<"Barrio">>},
  iolist_to_binary([element(((I - 1) rem 5) + 1, Lugares), " ", integer_to_binary(I), " - ",
                    element(((I - 1) rem 4) + 1, Tipos)]).

%% Cuatro familias de reglas: las quinielas conviven con reglas de puntos distintas.
reglas_de(I) ->
  case (I - 1) rem 4 of
    0 -> #{};
    1 -> #{exacto => 5, diferencia => 3, ganador => 2};
    2 -> #{exacto => 3, ganador => 0};
    3 -> #{multiplicador => #{octavos => 2, cuartos => 2, semifinales => 3, final => 4}, bono_campeon => 10}
  end.

%% Cada participante esta en 1 quiniela (60%), 2 (30%) o 3 (10%).
membresia(Sem, U, QIds) ->
  S0 = rand:seed_s(exsss, {Sem, erlang:phash2(U), 3}),
  {R, S1} = rand:uniform_s(S0),
  K0 = if R < 0.6 -> 1; R < 0.9 -> 2; true -> 3 end,
  %% No se pueden elegir mas quinielas distintas de las que existen (con 1 o 2 quinielas se colgaba).
  elegir(min(K0, length(QIds)), QIds, S1, []).

elegir(0, _, _, Acc) -> lists:sort(Acc);
elegir(K, Qs, S, Acc) ->
  {I, S1} = rand:uniform_s(length(Qs), S),
  Q = lists:nth(I, Qs),
  case lists:member(Q, Acc) of
    true -> elegir(K, Qs, S1, Acc);
    false -> elegir(K - 1, Qs, S1, [Q | Acc])
  end.

campeon_de(Sem, U) ->
  Fav = [{<<"España"/utf8>>, 22}, {<<"Argentina">>, 18}, {<<"Francia">>, 16}, {<<"Inglaterra">>, 12},
         {<<"Brasil">>, 10}, {<<"Portugal">>, 8}, {<<"Alemania">>, 6}, {<<"Países Bajos"/utf8>>, 4}, {<<"México"/utf8>>, 4}],
  {R, _} = rand:uniform_s(100, rand:seed_s(exsss, {Sem, erlang:phash2(U), 5})),
  elegir_peso(Fav, R).

elegir_peso([{E, _}], _) -> E;
elegir_peso([{E, P} | _], R) when R =< P -> E;
elegir_peso([{_, P} | T], R) -> elegir_peso(T, R - P).

%% Pronostico = 14% el marcador real, 36% ganador correcto con otro marcador, 50% al azar.
pronostico(Sem, U, PId, {RL, RV}) ->
  S0 = rand:seed_s(exsss, {Sem, erlang:phash2(U), PId}),
  {R, S1} = rand:uniform_s(S0),
  if R < 0.14 -> {RL, RV};
     R < 0.50 -> mismo_ganador({RL, RV}, S1);
     true -> {A, S2} = rand:uniform_s(4, S1), {B, _} = rand:uniform_s(4, S2), {A - 1, B - 1}
  end.

mismo_ganador({RL, RV}, S) ->
  {K, S1} = rand:uniform_s(2, S),
  {B, _} = rand:uniform_s(2, S1),
  case p73_puntos:resultado({RL, RV}) of
    local -> {B - 1 + K, B - 1};
    visitante -> {B - 1, B - 1 + K};
    empate -> {B - 1 + (K - 1), B - 1 + (K - 1)}
  end.

rand_gol(Sem, U, Salt) ->
  {G, _} = rand:uniform_s(4, rand:seed_s(exsss, {Sem, erlang:phash2(U), Salt})),
  G - 1.

rafaga_id(#{rafaga_partido := ultimo}, Partidos) -> maps:get(id, lists:last(Partidos));
rafaga_id(#{rafaga_partido := Id}, _) -> Id.

%% Agrupa partidos por inicio (ya vienen ordenados cronologicamente).
ventanas(Partidos) ->
  Inicios = lists:usort([I || #{inicio := I} <- Partidos]),
  [{I, [P || #{inicio := J} = P <- Partidos, J =:= I]} || I <- Inicios].

%% Reparte una lista en N lotes de tamano casi igual.
reparto(Lista, N) ->
  Base = length(Lista) div N, Extra = length(Lista) rem N,
  reparto(Lista, N, Base, Extra, []).
reparto(_, 0, _, _, Acc) -> lists:reverse(Acc);
reparto(Lista, N, Base, Extra, Acc) ->
  Tam = Base + case Extra > 0 of true -> 1; false -> 0 end,
  {Lote, Resto} = lists:split(min(Tam, length(Lista)), Lista),
  reparto(Resto, N - 1, Base, max(0, Extra - 1), [Lote | Acc]).

metrica_nombre(K) -> atom_to_binary(K, utf8).

%% Mapa paralelo con N procesos trabajadores; el orden de salida es el de entrada.
pmap(_F, [], _W) -> [];
pmap(F, Lista, W) ->
  Tam = max(1, (length(Lista) + W - 1) div W),
  Yo = self(),
  Hijos = [begin
             Ref = make_ref(),
             {_, MRef} = spawn_monitor(fun() -> Yo ! {Ref, [F(X) || X <- Trozo]} end),
             {Ref, MRef}
           end || Trozo <- trozos(Lista, Tam)],
  lists:append([receive
                  {Ref, R} -> erlang:demonitor(MRef, [flush]), R;
                  {'DOWN', MRef, process, _, Razon} -> exit({trabajador_fallo, Razon})
                end || {Ref, MRef} <- Hijos]).

trozos([], _) -> [];
trozos(L, N) when length(L) =< N -> [L];
trozos(L, N) -> {A, B} = lists:split(N, L), [A | trozos(B, N)].
