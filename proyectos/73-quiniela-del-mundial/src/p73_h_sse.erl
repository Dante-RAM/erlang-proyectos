%% Server-Sent Events: empuja goles, anulaciones VAR, cambios de estado y el top del ranking
%% de UNA quiniela (?quiniela=Q01). Los rankings ya llegan limitados por p73_quiniela (maximo 5/s).
-module(p73_h_sse).
-behaviour(cowboy_loop).

-export([init/2, info/3]).

-define(LATIDO_MS, 15000).

init(Req0, _) ->
  %% Un cliente lento no debe inflar la memoria del nodo: si su mailbox crece demasiado, se mata ESTE proceso.
  process_flag(max_heap_size, #{size => 4 * 1024 * 1024, kill => true, error_logger => false}),
  Quiniela = proplists:get_value(<<"quiniela">>, cowboy_req:parse_qs(Req0), undefined),
  Req = cowboy_req:stream_reply(200, #{<<"content-type">> => <<"text/event-stream">>,
                                       <<"cache-control">> => <<"no-cache">>,
                                       <<"x-accel-buffering">> => <<"no">>}, Req0),
  cowboy_req:cast({set_options, #{idle_timeout => infinity}}, Req),
  ok = p73_reg:unir(eventos, self()),   %% pg lo saca del grupo cuando el proceso muere
  erlang:send_after(?LATIDO_MS, self(), latido),
  enviar(#{tipo => hola, reloj => p73_reloj:ahora(), quiniela => Quiniela}, Req),
  {cowboy_loop, Req, #{quiniela => Quiniela}}.

info({evento, #{tipo := ranking, quiniela := Q} = E}, Req, #{quiniela := Q} = S) ->
  enviar(E, Req), {ok, Req, S};
info({evento, #{tipo := ranking}}, Req, S) -> {ok, Req, S};
info({evento, E}, Req, S) -> enviar(E, Req), {ok, Req, S};
info(latido, Req, S) ->
  cowboy_req:stream_body(<<": latido\n\n">>, nofin, Req),
  erlang:send_after(?LATIDO_MS, self(), latido),
  {ok, Req, S};
info(_, Req, S) -> {ok, Req, S}.

enviar(#{tipo := Tipo} = E, Req) ->
  cowboy_req:stream_body(["event: ", atom_to_binary(Tipo, utf8), "\ndata: ",
                          p73_json:codificar(p73_h_api:jsonable(E)), "\n\n"], nofin, Req).
