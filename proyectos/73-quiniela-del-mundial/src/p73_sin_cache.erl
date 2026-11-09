%% Middleware: la UI (html/js/css) no se guarda en cache del navegador, para que una
%% actualizacion del servidor se vea al recargar sin tener que limpiar la cache.
-module(p73_sin_cache).
-behaviour(cowboy_middleware).
-export([execute/2]).

execute(Req, Env) ->
  {ok, cowboy_req:set_resp_header(<<"cache-control">>, <<"no-store">>, Req), Env}.
