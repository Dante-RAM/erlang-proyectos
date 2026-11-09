%% Inyeccion de fallas: mata un proceso y mide cuanto tarda el supervisor en dejarlo operando de nuevo.
-module(p73_caos).
-export([matar/2, aleatorio/1]).

-type tipo() :: partido | quiniela | participante.

%% Mata el proceso (kill = sin cleanup, la peor caida posible) y espera a que reaparezca uno nuevo.
-spec matar(tipo(), term()) -> {ok, map()} | {error, term()}.
matar(Tipo, Id) ->
  Nombre = {Tipo, Id},
  case p73_reg:buscar(Nombre) of
    {error, _} = E -> E;
    {ok, Pid} ->
      T0 = erlang:monotonic_time(microsecond),
      exit(Pid, kill),
      p73_metricas:inc(fallas_inyectadas),
      p73_bitacora:registrar(falla, proceso_muerto, #{tipo => Tipo, id => Id}),
      case esperar(Nombre, Pid, T0 + 5000000) of
        ok ->
          Dt = (erlang:monotonic_time(microsecond) - T0) / 1000,
          p73_bitacora:registrar(ok, proceso_recuperado, #{tipo => Tipo, id => Id, recuperado_ms => Dt}),
          {ok, #{tipo => Tipo, id => Id, recuperado_ms => Dt}};
        timeout ->
          {error, no_se_recupero}
      end
  end.

esperar(Nombre, Viejo, Limite) ->
  case p73_reg:buscar(Nombre) of
    {ok, Nuevo} when Nuevo =/= Viejo -> ok;
    _ ->
      case erlang:monotonic_time(microsecond) > Limite of
        true -> timeout;
        false -> timer:sleep(1), esperar(Nombre, Viejo, Limite)
      end
  end.

%% Id al azar de un proceso existente (para "inyectar falla" desde la UI sin elegir uno).
-spec aleatorio(tipo()) -> {ok, term()} | {error, vacio}.
aleatorio(Tipo) ->
  Tabla = case Tipo of partido -> p73_partidos; quiniela -> p73_quinielas; participante -> p73_participantes end,
  case ets:select(Tabla, [{'$1', [], [{element, 1, '$1'}]}]) of
    [] -> {error, vacio};
    Ids -> {ok, lists:nth(rand:uniform(length(Ids)), Ids)}
  end.
