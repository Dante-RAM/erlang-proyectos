%% Reloj autoritativo del servidor. Responde la pregunta guia 1: la hora de bloqueo la decide
%% SIEMPRE el servidor con este reloj; la hora que declare el cliente (ts_cliente) se ignora.
%% Modo `simulado` permite reproducir el torneo 2026 (ya jugado) y fijar instantes exactos en pruebas.
-module(p73_reloj).
-export([ahora/0, modo/0, usar_real/0, usar_simulado/1, avanzar/1]).

-spec ahora() -> integer().
ahora() ->
  case ets:lookup(p73_reloj, modo) of
    [{modo, simulado, T}] -> T;
    _ -> erlang:system_time(millisecond)
  end.

modo() ->
  case ets:lookup(p73_reloj, modo) of
    [{modo, simulado, _}] -> simulado;
    _ -> real
  end.

usar_real() -> true = ets:insert(p73_reloj, {modo, real, 0}), ok.

usar_simulado(Ms) when is_integer(Ms) -> true = ets:insert(p73_reloj, {modo, simulado, Ms}), ok.

avanzar(Delta) -> usar_simulado(ahora() + Delta).
