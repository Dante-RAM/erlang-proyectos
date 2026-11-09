%% Dueno de las tablas ETS. Es un proceso que NO hace nada mas: asi las tablas sobreviven a la
%% caida de cualquier partido/quiniela/participante (que solo las usan), que es lo que permite
%% reiniciarlos y reconstruir su estado de forma determinista.
-module(p73_almacen).
-behaviour(gen_server).

-export([start_link/0, limpiar/0]).
-export([init/1, handle_call/3, handle_cast/2]).

-define(TABLAS_VOLATILES, [p73_pronosticos, p73_campeones, p73_partidos, p73_quinielas,
                           p73_miembros, p73_participantes, p73_bitacora, p73_pron_usuario, p73_metricas]).

start_link() -> gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% Vacia todo menos reloj y metricas acumuladas (lo usa el simulador al reiniciar escenario).
limpiar() -> gen_server:call(?MODULE, limpiar, 30000).

init([]) ->
  Rapida = [named_table, public, {read_concurrency, true}, {write_concurrency, true}],
  ets:new(p73_pronosticos, [set | Rapida]),       %% {{Partido, Participante}, L, V, TsServidor}
  ets:new(p73_pron_usuario, [ordered_set | Rapida]), %% {{Participante, Partido}, L, V}  (indice para recuperar un participante)
  ets:new(p73_campeones, [set | Rapida]),         %% {Participante, Equipo}
  ets:new(p73_partidos, [set | Rapida]),          %% {Id, Estado, Datos}  (estado durable del partido)
  ets:new(p73_quinielas, [set | Rapida]),         %% {Id, Nombre, Reglas}
  ets:new(p73_miembros, [bag | Rapida]),          %% {Quiniela, Participante}
  ets:new(p73_participantes, [set | Rapida]),     %% {Id, Nombre, [Quinielas]}
  ets:new(p73_metricas, [set | Rapida]),          %% {Nombre, Valor}
  ets:new(p73_bitacora, [ordered_set | Rapida]),  %% {N, Entrada}
  ets:new(p73_reloj, [set, named_table, public, {read_concurrency, true}]),
  iniciar_reloj(),
  {ok, #{}}.

%% Por defecto el reloj es simulado y arranca 2 dias antes del primer partido del Mundial 2026
%% (el torneo ya se jugo: en modo real todos los partidos estarian en el pasado).
iniciar_reloj() ->
  case application:get_env(p73_quiniela_del_mundial, reloj, simulado) of
    real -> p73_reloj:usar_real();
    simulado -> p73_reloj:usar_simulado(p73_torneo:primer_inicio() - 2 * 86400 * 1000)
  end.

handle_call(limpiar, _From, S) ->
  [ets:delete_all_objects(T) || T <- ?TABLAS_VOLATILES],
  {reply, ok, S}.

handle_cast(_, S) -> {noreply, S}.
