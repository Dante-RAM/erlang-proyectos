%% Contadores y gauges en ETS (escritura concurrente sin pasar por un proceso) y exposicion en
%% formato Prometheus para GET /metrics. No usa prometheus.erl para no agregar dependencias.
-module(p73_metricas).
-export([inc/1, inc/2, poner/2, leer/1, todas/0, prometheus/0]).

inc(Nombre) -> inc(Nombre, 1).
inc(Nombre, N) -> ets:update_counter(p73_metricas, Nombre, N, {Nombre, 0}).

poner(Nombre, V) -> true = ets:insert(p73_metricas, {Nombre, V}), ok.

leer(Nombre) ->
  case ets:lookup(p73_metricas, Nombre) of
    [{_, V}] -> V;
    [] -> 0
  end.

todas() -> lists:sort(ets:tab2list(p73_metricas)).

prometheus() ->
  Propias = [linea(K, V) || {K, V} <- todas()],
  Vivas = [
    linea(procesos_partidos, cuenta(p73_partidos_sup)),
    linea(procesos_quinielas, cuenta(p73_quinielas_sup)),
    linea(procesos_participantes, cuenta(p73_participantes_sup)),
    linea(usuarios_activos, cuenta(p73_participantes_sup)),
    linea(sse_conectados, length(p73_reg:miembros(eventos))),
    linea(procesos_vm, erlang:system_info(process_count)),
    linea(memoria_bytes, erlang:memory(total)),
    linea(cola_run_queue, erlang:statistics(run_queue))
  ],
  iolist_to_binary(Propias ++ Vivas).

cuenta(Sup) ->
  try proplists:get_value(active, supervisor:count_children(Sup), 0)
  catch _:_ -> 0
  end.

linea({Nombre, Etiqueta}, V) ->
  io_lib:format("p73_~s{id=\"~s\"} ~p~n", [Nombre, to_s(Etiqueta), V]);
linea(Nombre, V) ->
  io_lib:format("# TYPE p73_~s ~s~np73_~s ~p~n", [Nombre, tipo(Nombre), Nombre, V]).

%% Lo acumulado en ETS solo crece (counter); lo medido al vuelo sube y baja (gauge).
tipo(procesos_partidos) -> gauge;
tipo(procesos_quinielas) -> gauge;
tipo(procesos_participantes) -> gauge;
tipo(usuarios_activos) -> gauge;
tipo(sse_conectados) -> gauge;
tipo(procesos_vm) -> gauge;
tipo(memoria_bytes) -> gauge;
tipo(cola_run_queue) -> gauge;
tipo(_) -> counter.

to_s(X) when is_binary(X) -> X;
to_s(X) when is_integer(X) -> integer_to_list(X);
to_s(X) when is_atom(X) -> atom_to_list(X).
