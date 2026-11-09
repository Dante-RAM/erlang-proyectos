%% Un proceso (gen_statem) por partido. Es el UNICO arbitro del bloqueo de pronosticos:
%%   programado --(inicio)--> en_vivo --(final)--> finalizado
%% Un pronostico se acepta solo si el partido sigue `programado` Y el reloj del servidor < inicio.
%% Doble guardia (caso dificil "pronostico en el limite"): la hora puede estar mal (salto de reloj),
%% pero el cambio de estado es irreversible y lo dispara un temporizador monotonico; jamas se "reabre".
%%
%% Estado durable en ETS (p73_partidos): si el proceso muere, el supervisor lo reinicia y retoma
%% exactamente donde estaba (marcador, eventos, estado) sin perder nada.
-module(p73_partido).
-behaviour(gen_statem).

-export([start_link/1, via/1]).
-export([pronosticar/4, iniciar/1, gol/3, anular_gol/2, finalizar/1, finalizar/2]).
-export([snapshot/1, detalle/1]).
-export([snapshot_de_datos/2, snapshots_persistidos/0, marcador/1]).
-export([init/1, callback_mode/0, programado/3, en_vivo/3, finalizado/3]).

via(Id) -> {via, p73_reg, {partido, Id}}.

start_link(Id) -> gen_statem:start_link(via(Id), ?MODULE, Id, []).

%% ---- API ----
pronosticar(Id, Participante, L, V) -> llamar(Id, {pronosticar, Participante, L, V}).
iniciar(Id) -> llamar(Id, iniciar).
gol(Id, Lado, Minuto) -> llamar(Id, {gol, Lado, Minuto}).
anular_gol(Id, EventoN) -> llamar(Id, {anular_gol, EventoN}).
finalizar(Id) -> finalizar(Id, undefined).
finalizar(Id, Penales) -> llamar(Id, {finalizar, Penales}).
snapshot(Id) -> llamar(Id, snapshot).
detalle(Id) -> llamar(Id, detalle).

llamar(Id, Req) ->
  try gen_statem:call(via(Id), Req, 10000)
  catch
    exit:{timeout, _} -> {error, timeout};
    exit:_ -> {error, no_disponible}
  end.

%% ---- Funciones puras sobre el estado ----
marcador(Eventos) ->
  lists:foldl(fun(#{tipo := gol, lado := local, anulado := false}, {L, V}) -> {L + 1, V};
                 (#{tipo := gol, lado := visitante, anulado := false}, {L, V}) -> {L, V + 1};
                 (_, Acc) -> Acc end, {0, 0}, Eventos).

snapshot_de_datos(Estado, #{id := Id, eventos := Ev} = D) ->
  M = marcador(Ev),
  #{id => Id, fase => maps:get(fase, D), grupo => maps:get(grupo, D),
    local => maps:get(local, D), visitante => maps:get(visitante, D),
    inicio => maps:get(inicio, D), estado => Estado, marcador => M,
    definitivo => Estado =:= finalizado,
    ganador => ganador(Estado, M, D)}.

ganador(finalizado, {L, V}, #{local := Lo, visitante := Vi}) when L > V -> ganador_de(Lo, Vi, local);
ganador(finalizado, {L, V}, #{local := Lo, visitante := Vi}) when L < V -> ganador_de(Lo, Vi, visitante);
ganador(finalizado, _, #{penales := {PL, PV}, local := Lo, visitante := Vi}) when PL > PV -> ganador_de(Lo, Vi, local);
ganador(finalizado, _, #{penales := {_, _}, local := Lo, visitante := Vi}) -> ganador_de(Lo, Vi, visitante);
ganador(_, _, _) -> undefined.

ganador_de(Lo, _Vi, local) -> Lo;
ganador_de(_Lo, Vi, visitante) -> Vi.

snapshots_persistidos() ->
  [snapshot_de_datos(E, D) || {_, E, D} <- ets:tab2list(p73_partidos)].

%% ---- gen_statem ----
callback_mode() -> state_functions.

init(Id) ->
  case ets:lookup(p73_partidos, Id) of
    [{Id, Estado, Datos}] ->
      armar_temporizador(Estado, Datos),
      %% Idempotente: si caimos entre persistir y notificar, los suscriptores se ponen al dia.
      notificar(Estado, Datos),
      {ok, Estado, Datos};
    [] ->
      {stop, {no_registrado, Id}}
  end.

programado({call, From}, {pronosticar, P, L, V}, #{id := Id, inicio := Inicio}) ->
  Ahora = p73_reloj:ahora(),
  case Ahora < Inicio of
    true ->
      case ets:member(p73_pronosticos, {Id, P}) of
        true -> p73_metricas:inc(predicciones_cambiadas);
        false -> p73_metricas:inc({predicciones_partido, Id}), p73_metricas:inc(predicciones_aceptadas)
      end,
      true = ets:insert(p73_pronosticos, {{Id, P}, L, V, Ahora}),
      true = ets:insert(p73_pron_usuario, {{P, Id}, L, V}),
      {keep_state_and_data, [{reply, From, ok}]};
    false ->
      rechazar(From, Id, Ahora, Inicio)
  end;
programado({call, From}, iniciar, D) ->
  {next_state, en_vivo, arrancar(D), [{reply, From, ok}]};
programado(info, hora_de_inicio, D) ->
  {next_state, en_vivo, arrancar(D)};
programado(Tipo, Ev, D) -> comunes(Tipo, Ev, programado, D).

en_vivo({call, From}, {gol, Lado, Minuto}, #{eventos := Ev, sig := N} = D) when Lado =:= local; Lado =:= visitante ->
  E = #{n => N, tipo => gol, lado => Lado, minuto => Minuto, anulado => false},
  D1 = D#{eventos := Ev ++ [E], sig := N + 1},
  cambiar(en_vivo, D1),
  p73_metricas:inc(eventos_partido),
  p73_bitacora:registrar(ok, gol, #{partido => maps:get(id, D), lado => Lado, minuto => Minuto,
                                    marcador => marcador(maps:get(eventos, D1))}),
  {keep_state, D1, [{reply, From, {ok, N}}]};
en_vivo({call, From}, {anular_gol, N}, D) -> anular(From, N, en_vivo, D);
en_vivo({call, From}, {finalizar, Penales}, D) ->
  D1 = D#{penales := Penales},
  cambiar(finalizado, D1),
  p73_bitacora:registrar(ok, partido_final, #{partido => maps:get(id, D), marcador => marcador(maps:get(eventos, D1))}),
  {next_state, finalizado, D1, [{reply, From, ok}]};
en_vivo(Tipo, Ev, D) -> comunes(Tipo, Ev, en_vivo, D).

%% Correccion tardia del VAR: se permite tambien despues del silbatazo final.
finalizado({call, From}, {anular_gol, N}, D) -> anular(From, N, finalizado, D);
finalizado(Tipo, Ev, D) -> comunes(Tipo, Ev, finalizado, D).

comunes({call, From}, snapshot, Estado, D) ->
  {keep_state_and_data, [{reply, From, snapshot_de_datos(Estado, D)}]};
comunes({call, From}, detalle, Estado, #{id := Id, eventos := Ev} = D) ->
  Pron = ets:select_count(p73_pronosticos, [{{{Id, '_'}, '_', '_', '_'}, [], [true]}]),
  {keep_state_and_data, [{reply, From, #{partido => snapshot_de_datos(Estado, D), eventos => Ev, pronosticos => Pron}}]};
comunes({call, From}, {pronosticar, _, _, _}, _Estado, #{id := Id, inicio := Inicio}) ->
  rechazar(From, Id, p73_reloj:ahora(), Inicio);
comunes({call, From}, _Otro, Estado, _D) ->
  {keep_state_and_data, [{reply, From, {error, {estado_invalido, Estado}}}]};
comunes(info, _, _, _) -> keep_state_and_data.

%% ---- internos ----
arrancar(D) ->
  cambiar(en_vivo, D),
  p73_bitacora:registrar(ok, partido_inicio, #{partido => maps:get(id, D), local => maps:get(local, D),
                                               visitante => maps:get(visitante, D)}),
  D.

anular(From, N, Estado, #{eventos := Ev} = D) ->
  case [E || #{n := M, anulado := false} = E <- Ev, M =:= N] of
    [] -> {keep_state_and_data, [{reply, From, {error, evento_inexistente}}]};
    [_] ->
      Antes = marcador(Ev),
      Ev1 = [case E of #{n := N} -> E#{anulado := true}; _ -> E end || E <- Ev],
      D1 = D#{eventos := Ev1},
      cambiar(Estado, D1),
      p73_metricas:inc(anulaciones_var),
      p73_bitacora:registrar(alerta, gol_anulado_var, #{partido => maps:get(id, D), evento => N,
                                                        antes => Antes, despues => marcador(Ev1)}),
      {keep_state, D1, [{reply, From, ok}]}
  end.

rechazar(From, Id, Ahora, Inicio) ->
  p73_metricas:inc(predicciones_rechazadas),
  %% Solo la primera por partido va a la bitacora (miles de rechazos en el limite saturarian el log).
  case p73_metricas:inc({rechazos_partido, Id}) of
    1 -> p73_bitacora:registrar(alerta, pronostico_rechazado,
                                #{partido => Id, ahora => Ahora, inicio => Inicio, tarde_ms => Ahora - Inicio});
    _ -> ok
  end,
  {keep_state_and_data, [{reply, From, {error, cerrado}}]}.

cambiar(Estado, #{id := Id} = D) ->
  true = ets:insert(p73_partidos, {Id, Estado, D}),
  notificar(Estado, D).

notificar(Estado, D) ->
  Snap = snapshot_de_datos(Estado, D),
  [Pid ! {partido_actualizado, Snap} || Pid <- p73_reg:miembros(quinielas)],
  p73_bitacora:difundir(#{tipo => partido, partido => Snap}),
  ok.

%% En modo real, el temporizador (monotonico) cierra el partido aunque nadie llame `iniciar`.
armar_temporizador(programado, #{inicio := Inicio}) ->
  case p73_reloj:modo() of
    real ->
      Falta = Inicio - p73_reloj:ahora(),
      case Falta > 0 andalso Falta < 4000000000 of
        true -> erlang:send_after(Falta, self(), hora_de_inicio), ok;
        false -> ok
      end;
    simulado -> ok
  end;
armar_temporizador(_, _) -> ok.
