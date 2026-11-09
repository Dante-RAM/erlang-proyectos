%% Bitacora de eventos (pantalla 3 de la UI) y canal de difusion para SSE.
%% Acotada: conserva las ultimas ~5000 entradas para no crecer sin limite.
-module(p73_bitacora).
-export([registrar/3, ultimos/1, difundir/1]).

-define(MAX, 5000).

%% Nivel: ok | alerta | falla  (colores de estado de la UI)
-spec registrar(ok | alerta | falla, atom(), map()) -> ok.
registrar(Nivel, Tipo, Datos) ->
  N = p73_metricas:inc(bitacora_seq),
  Entrada = #{n => N, ts => erlang:system_time(millisecond), reloj => p73_reloj:ahora(),
              nivel => Nivel, tipo => Tipo, datos => Datos},
  true = ets:insert(p73_bitacora, {N, Entrada}),
  case N rem 500 of
    0 -> ets:select_delete(p73_bitacora, [{{'$1', '_'}, [{'<', '$1', N - ?MAX}], [true]}]);
    _ -> ok
  end,
  difundir(#{tipo => bitacora, entrada => Entrada}).

ultimos(Max) -> ultimos(ets:last(p73_bitacora), Max, []).

ultimos('$end_of_table', _, Acc) -> lists:reverse(Acc);
ultimos(_, 0, Acc) -> lists:reverse(Acc);
ultimos(K, Max, Acc) ->
  [{_, E}] = ets:lookup(p73_bitacora, K),
  ultimos(ets:prev(p73_bitacora, K), Max - 1, [E | Acc]).

%% Envia un evento a todos los clientes SSE conectados.
difundir(Evento) ->
  [Pid ! {evento, Evento} || Pid <- p73_reg:miembros(eventos)],
  ok.
