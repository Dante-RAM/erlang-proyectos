-module(p73_quiniela_del_mundial_app).
-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
  {ok, Sup} = p73_quiniela_del_mundial_sup:start_link(),
  Puerto = application:get_env(p73_quiniela_del_mundial, port, 8080),
  case p73_http:iniciar(Puerto) of
    {ok, _} -> logger:info("quiniela escuchando", #{puerto => Puerto});
    {error, Razon} -> logger:error("no se pudo abrir el puerto ~p: ~p", [Puerto, Razon])
  end,
  {ok, Sup}.

stop(_State) ->
  p73_http:detener().
