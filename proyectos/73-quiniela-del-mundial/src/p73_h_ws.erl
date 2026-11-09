%% WebSocket (cowboy_websocket) en /ws: canal BIDIRECCIONAL, complemento del SSE.
%%  - Servidor -> cliente: los mismos eventos del grupo pg `eventos` (goles, VAR, estados, ranking
%%    de la quiniela elegida con ?quiniela=Q01).
%%  - Cliente -> servidor: {"tipo":"pronostico","participante":"U0001","partido":5,"local":2,"visitante":1}
%%    responde {"tipo":"pronostico_resultado","ok":true|false,...}; {"tipo":"ping"} responde "pong".
%%    El cierre lo decide el reloj del servidor igual que en POST /api/predicciones.
-module(p73_h_ws).
-behaviour(cowboy_websocket).

-export([init/2, websocket_init/1, websocket_handle/2, websocket_info/2]).

init(Req, _) ->
  Quiniela = proplists:get_value(<<"quiniela">>, cowboy_req:parse_qs(Req), undefined),
  {cowboy_websocket, Req, #{quiniela => Quiniela}, #{idle_timeout => 120000, max_frame_size => 65536}}.

websocket_init(S) ->
  %% Igual que en SSE: un cliente lento no puede inflar la memoria del nodo.
  process_flag(max_heap_size, #{size => 4 * 1024 * 1024, kill => true, error_logger => false}),
  ok = p73_reg:unir(eventos, self()),
  {[texto(#{tipo => hola, canal => websocket, reloj => p73_reloj:ahora(), quiniela => maps:get(quiniela, S)})], S}.

websocket_handle({text, Datos}, S) ->
  Resp = try p73_json:decodificar(Datos) of
           {ok, #{<<"tipo">> := <<"ping">>}} -> #{tipo => pong, reloj => p73_reloj:ahora()};
           {ok, #{<<"tipo">> := <<"pronostico">>, <<"participante">> := U, <<"partido">> := P,
             <<"local">> := L, <<"visitante">> := V}}
             when is_binary(U), is_integer(P), is_integer(L), is_integer(V) -> pronostico(U, P, L, V);
           {ok, _} -> #{tipo => error, error => <<"mensaje_desconocido">>};
           _ -> #{tipo => error, error => <<"json_invalido">>}
         catch _:_ -> #{tipo => error, error => <<"json_invalido">>}
         end,
  {[texto(Resp)], S};
websocket_handle(_, S) -> {[], S}.

websocket_info({evento, #{tipo := ranking, quiniela := Q} = E}, #{quiniela := Q} = S) -> {[texto(E)], S};
websocket_info({evento, #{tipo := ranking}}, S) -> {[], S};
websocket_info({evento, E}, S) -> {[texto(E)], S};
websocket_info(_, S) -> {[], S}.

pronostico(U, P, L, V) ->
  Res = case {ets:member(p73_participantes, U), ets:member(p73_partidos, P)} of
          {false, _} -> {error, participante_inexistente};
          {_, false} -> {error, partido_inexistente};
          _ -> p73_participante:pronosticar(U, P, L, V)
        end,
  Base = #{tipo => pronostico_resultado, participante => U, partido => P, reloj_servidor => p73_reloj:ahora()},
  case Res of
    ok -> Base#{ok => true};
    {error, Motivo} -> Base#{ok => false, error => Motivo}
  end.

texto(Termino) -> {text, p73_json:codificar(p73_h_api:jsonable(Termino))}.
