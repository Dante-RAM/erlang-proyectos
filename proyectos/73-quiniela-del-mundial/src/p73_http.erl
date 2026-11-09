%% Rutas y arranque del listener HTTP (cowboy). API JSON bajo /api, SSE en /api/eventos,
%% metricas Prometheus en /metrics y la interfaz web estatica (priv/web) en /.
-module(p73_http).
-export([iniciar/1, detener/0, puerto/0, dispatch/0]).

-define(LISTENER, p73_http).
-define(APP, p73_quiniela_del_mundial).

iniciar(Puerto) ->
  cowboy:start_clear(?LISTENER,
                     [{port, Puerto}, {max_connections, 20000}],
                     #{env => #{dispatch => dispatch()}, middlewares => [cowboy_router, p73_sin_cache, cowboy_handler], idle_timeout => 120000, request_timeout => 15000}).

detener() ->
  case cowboy:stop_listener(?LISTENER) of
    ok -> ok;
    {error, not_found} -> ok
  end.

puerto() -> ranch:get_port(?LISTENER).

dispatch() ->
  cowboy_router:compile([{'_', [
    {"/api/estado", p73_h_api, estado},
    {"/api/partidos", p73_h_api, partidos},
    {"/api/partidos/:id", p73_h_api, partido},
    {"/api/quinielas", p73_h_api, quinielas},
    {"/api/ranking", p73_h_api, ranking},
    {"/api/predicciones", p73_h_api, prediccion},
    {"/api/participantes/:id", p73_h_api, participante},
    {"/api/bitacora", p73_h_api, bitacora},
    {"/api/simulacion", p73_h_api, simulacion},
    {"/api/falla", p73_h_api, falla},
    {"/api/admin/evento", p73_h_api, evento},
    {"/api/admin/reloj", p73_h_api, reloj},
    {"/api/eventos", p73_h_sse, []},
    {"/ws", p73_h_ws, []},
    {"/api/diagnostico", p73_h_diag, []},
    {"/metrics", p73_h_metrics, []},
    {"/", cowboy_static, {priv_file, ?APP, "web/index.html"}},
    {"/[...]", cowboy_static, {priv_dir, ?APP, "web"}}
  ]}]).
