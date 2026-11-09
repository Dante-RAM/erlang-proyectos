%% Supervisor dinamico generico (simple_one_for_one): uno para partidos, otro para quinielas y otro
%% para participantes. Un hijo que cae se reinicia solo (permanent); los hermanos no se enteran.
-module(p73_hijos_sup).
-behaviour(supervisor).

-export([start_link/3]).
-export([init/1]).

start_link(Nombre, Modulo, Intensidad) ->
  supervisor:start_link({local, Nombre}, ?MODULE, {Modulo, Intensidad}).

init({Modulo, {Max, Periodo}}) ->
  {ok, {#{strategy => simple_one_for_one, intensity => Max, period => Periodo},
        [#{id => Modulo, start => {Modulo, start_link, []}, restart => permanent,
           shutdown => 5000, type => worker}]}}.
