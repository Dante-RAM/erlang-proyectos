%% Una quiniela = un proceso con SUS reglas, SUS miembros y SU ranking (calculador reiniciable).
%%
%% Recalculo (pregunta guia 2): al cambiar un partido solo se recalcula la contribucion de ESE partido
%% para los miembros (O(miembros)), ajustando totales por diferencia ("delta"). Nunca se rehace el
%% torneo completo. El recalculo completo existe solo para (a) arrancar/reiniciar y (b) verificar
%% que lo incremental coincide con lo calculado desde cero (verificar/1).
%%
%% Determinista: el estado se deriva solo de ETS (pronosticos + estado de partidos), asi que un
%% proceso reiniciado converge al mismo ranking.
-module(p73_quiniela).
-behaviour(gen_server).

-export([start_link/1, via/1, unir/2, ranking/2, posicion/2, info/1, sincronizar/1, verificar/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-define(DIFUSION_MS, 200).

via(Id) -> {via, p73_reg, {quiniela, Id}}.

start_link(Id) -> gen_server:start_link(via(Id), ?MODULE, Id, []).

unir(Id, Participante) -> llamar(Id, {unir, Participante}).
ranking(Id, Top) -> llamar(Id, {ranking, Top}).
posicion(Id, Participante) -> llamar(Id, {posicion, Participante}).
info(Id) -> llamar(Id, info).
sincronizar(Id) -> llamar(Id, sincronizar).
verificar(Id) -> llamar(Id, verificar).

llamar(Id, Req) ->
  try gen_server:call(via(Id), Req, 30000)
  catch
    exit:{timeout, _} -> {error, timeout};
    exit:_ -> {error, no_disponible}
  end.

%% ---- gen_server ----
init(Id) ->
  case ets:lookup(p73_quinielas, Id) of
    [{Id, Nombre, Reglas}] ->
      ok = p73_reg:unir(quinielas, self()),   %% primero suscribirse, luego leer ETS: no se pierde ninguna actualizacion
      Miembros = [P || {_, P} <- ets:lookup(p73_miembros, Id)],
      Base = #{id => Id, nombre => Nombre, reglas => Reglas, miembros => maps:from_keys(Miembros, true),
               snaps => #{}, contrib => #{}, totales => #{}, ranking => undefined,
               top_prev => [], difusion => undefined, version => 0},
      {ok, desde_cero(Base)};
    [] -> {stop, {no_registrada, Id}}
  end.

handle_call({unir, P}, _From, #{id := Id, miembros := M, totales := T} = S) ->
  true = ets:insert(p73_miembros, {Id, P}),
  S1 = S#{miembros := M#{P => true}, totales := maps:merge(#{P => p73_ranking:nuevo_total()}, T), ranking := undefined},
  {reply, ok, S1};
handle_call({ranking, Top}, _From, S) ->
  {R, S1} = asegurar_ranking(S),
  #{id := Id, version := V} = S1,
  {reply, #{quiniela => Id, version => V, total => length(R), filas => lists:sublist(R, Top)}, S1};
handle_call({posicion, P}, _From, S) ->
  {R, S1} = asegurar_ranking(S),
  Fila = case [F || #{participante := Q} = F <- R, Q =:= P] of [F0] -> F0; [] -> undefined end,
  {reply, Fila, S1};
handle_call(info, _From, #{id := Id, nombre := N, reglas := Rg, miembros := M, snaps := Sn} = S) ->
  {reply, #{id => Id, nombre => N, reglas => Rg, miembros => maps:size(M), partidos_vistos => maps:size(Sn)}, S};
handle_call(sincronizar, _From, S) -> {reply, ok, S};
handle_call(verificar, _From, #{totales := T} = S) ->
  Limpio = desde_cero(S#{snaps := #{}, contrib := #{}, totales := reiniciar_totales(S)}),
  Dif = length([P || {P, Tot} <- maps:to_list(T), maps:get(P, maps:get(totales, Limpio), undefined) =/= Tot]),
  {reply, case Dif of 0 -> ok; _ -> {diferencias, Dif} end, S}.

handle_cast(_, S) -> {noreply, S}.

handle_info({partido_actualizado, #{id := PId} = Snap}, #{snaps := Sn, totales := T0} = S) ->
  p73_metricas:inc(recalculos_quiniela),
  S1 = aplicar_partido(Snap, S#{snaps := Sn#{PId => Snap}}),
  S2 = case maps:get(totales, S1) =:= T0 of
         true -> S1;
         false -> S1#{ranking := undefined, version := maps:get(version, S1) + 1}
       end,
  {noreply, programar_difusion(S2)};
handle_info(difundir, S) ->
  {R, S1} = asegurar_ranking(S),
  Top = lists:sublist(R, 10),
  Marca = [{P, Pts} || #{participante := P, pts := Pts} <- Top],
  S2 = case Marca =:= maps:get(top_prev, S1) of
         true -> S1;
         false ->
           p73_metricas:inc(cambios_ranking),
           p73_bitacora:difundir(#{tipo => ranking, quiniela => maps:get(id, S1), top => Top}),
           S1#{top_prev := Marca}
       end,
  {noreply, S2#{difusion := undefined}};
handle_info(_, S) -> {noreply, S}.

%% ---- calculo ----
reiniciar_totales(#{miembros := M}) -> maps:map(fun(_, _) -> p73_ranking:nuevo_total() end, M).

%% Recalculo completo: se aplica cada partido ya conocido desde ETS sobre totales en cero.
desde_cero(S0) ->
  S1 = S0#{totales := reiniciar_totales(S0), contrib := #{}, ranking := undefined},
  Snaps = p73_partido:snapshots_persistidos(),
  lists:foldl(fun(#{id := PId} = Snap, S) ->
                  aplicar_partido(Snap, S#{snaps := maps:put(PId, Snap, maps:get(snaps, S))})
              end, S1, Snaps).

%% Contribucion de UN partido: cambia solo lo que cambio (delta contra la contribucion anterior).
aplicar_partido(#{estado := programado}, S) -> S;
aplicar_partido(#{id := PId, fase := Fase, marcador := Res} = Snap, #{reglas := Reglas, miembros := M} = S) ->
  {Contrib, Totales} =
    maps:fold(fun(P, _, {C, T}) ->
                  Nuevo = case ets:lookup(p73_pronosticos, {PId, P}) of
                            [{_, L, V, _}] -> p73_puntos:puntos(Reglas, Fase, {L, V}, Res);
                            [] -> {0, nada}
                          end,
                  Viejo = maps:get({PId, P}, C, {0, nada}),
                  case Nuevo =:= Viejo of
                    true -> {C, T};
                    false ->
                      C1 = case Nuevo of {0, nada} -> maps:remove({PId, P}, C); _ -> C#{{PId, P} => Nuevo} end,
                      T1 = maps:update_with(P, fun(Tot) -> ajustar(ajustar(Tot, Viejo, -1), Nuevo, 1) end, T),
                      {C1, T1}
                  end
              end, {maps:get(contrib, S), maps:get(totales, S)}, M),
  aplicar_bono(Snap, S#{contrib := Contrib, totales := Totales}).

ajustar(Tot, {Pts, Tipo}, Signo) ->
  Tot1 = Tot#{pts := maps:get(pts, Tot) + Signo * Pts},
  case Tipo of
    exacto -> Tot1#{exactos := maps:get(exactos, Tot1) + Signo};
    nada -> Tot1;
    _ -> Tot1#{ganadores := maps:get(ganadores, Tot1) + Signo}   %% ganador | diferencia
  end.

%% Bono por campeon: se fija de forma absoluta (no acumulada) para que una correccion lo revierta.
aplicar_bono(#{fase := final, definitivo := true, ganador := Campeon}, #{reglas := Reglas, miembros := M, totales := T} = S) ->
  T1 = maps:fold(fun(P, _, Acc) ->
                     Acierto = case ets:lookup(p73_campeones, P) of [{_, E}] -> E =:= Campeon; [] -> false end,
                     maps:update_with(P, fun(Tot) -> Tot#{bonos := p73_puntos:bono_campeon(Reglas, Acierto)} end, Acc)
                 end, T, M),
  S#{totales := T1};
aplicar_bono(_, S) -> S.

asegurar_ranking(#{ranking := undefined, totales := T} = S) ->
  R = p73_ranking:ordenar(T),
  {R, S#{ranking := R}};
asegurar_ranking(#{ranking := R} = S) -> {R, S}.

%% Limita la difusion: miles de usuarios conectados no deben recibir un push por cada gol de cada partido.
programar_difusion(#{difusion := undefined} = S) ->
  S#{difusion := erlang:send_after(?DIFUSION_MS, self(), difundir)};
programar_difusion(S) -> S.
