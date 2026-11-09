-module(p73_h_metrics).
-export([init/2]).

init(Req0, State) ->
  Req = cowboy_req:reply(200, #{<<"content-type">> => <<"text/plain; version=0.0.4; charset=utf-8">>},
                         p73_metricas:prometheus(), Req0),
  {ok, Req, State}.
