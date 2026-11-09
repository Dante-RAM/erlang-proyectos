-module(p73_quiniela_del_mundial_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

start_link() ->
  supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% rest_for_one: el orden ES la dependencia.
%%   pg (registro/difusion) <- almacen (ETS) <- supervisores dinamicos <- poblacion (repuebla desde ETS)
%% Si cae `pg` o `almacen` todo lo que depende de ellos se reinicia (con ETS nueva); si cae un
%% supervisor dinamico, `poblacion` (que va despues) vuelve a arrancar a sus hijos desde ETS.
%% Cada partido/quiniela/participante cuelga de su supervisor dinamico con one_for_one (simple_one_for_one):
%% la caida de uno no toca a los demas. `server` va al final: su caida no reinicia nada.
init([]) ->
  Trab = fun(Id, Mod) -> #{id => Id, start => {Mod, start_link, []}, restart => permanent,
                           shutdown => 5000, type => worker} end,
  Sup = fun(Nombre, Mod, Intensidad) ->
            #{id => Nombre, start => {p73_hijos_sup, start_link, [Nombre, Mod, Intensidad]},
              restart => permanent, shutdown => infinity, type => supervisor} end,
  Hijos = [
    #{id => pg, start => {pg, start_link, [p73]}, restart => permanent, shutdown => 5000, type => worker},
    Trab(p73_almacen, p73_almacen),
    Sup(p73_partidos_sup, p73_partido, {100, 10}),
    Sup(p73_quinielas_sup, p73_quiniela, {100, 10}),
    Sup(p73_participantes_sup, p73_participante, {5000, 10}),
    Trab(p73_poblacion, p73_poblacion),
    Trab(p73_simulador, p73_simulador),
    Trab(p73_quiniela_del_mundial_server, p73_quiniela_del_mundial_server)
  ],
  {ok, {#{strategy => rest_for_one, intensity => 10, period => 60}, Hijos}}.
