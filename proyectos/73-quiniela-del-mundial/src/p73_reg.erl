%% Registro de procesos sobre `pg` (OTP), usable como {via, p73_reg, Nombre}.
%% Por que no atomos registrados: hay miles de participantes y decenas de quinielas/partidos con
%% nombres dinamicos; crear atomos desde datos externos agota la tabla de atomos (no se recolecta).
-module(p73_reg).
-export([register_name/2, unregister_name/1, whereis_name/1, send/2]).
-export([buscar/1, miembros/1, unir/2]).

-define(SCOPE, p73).

register_name(Nombre, Pid) ->
  case vivos(Nombre) of
    [] -> ok = pg:join(?SCOPE, Nombre, Pid), yes;
    _ -> no
  end.

unregister_name(Nombre) ->
  _ = pg:leave(?SCOPE, Nombre, pg:get_local_members(?SCOPE, Nombre)),
  ok.

whereis_name(Nombre) ->
  case vivos(Nombre) of
    [Pid | _] -> Pid;
    [] -> undefined
  end.

send(Nombre, Msg) ->
  case whereis_name(Nombre) of
    undefined -> exit({badarg, {Nombre, Msg}});
    Pid -> Pid ! Msg, Pid
  end.

-spec buscar(term()) -> {ok, pid()} | {error, no_disponible}.
buscar(Nombre) ->
  case whereis_name(Nombre) of
    undefined -> {error, no_disponible};
    Pid -> {ok, Pid}
  end.

%% Miembros vivos de un grupo (se usa para difusion: quinielas, suscriptores SSE, ...).
miembros(Grupo) -> vivos(Grupo).

unir(Grupo, Pid) -> pg:join(?SCOPE, Grupo, Pid).

%% pg limpia los muertos de forma asincrona; si un hijo se reinicia de inmediato, el pid viejo
%% todavia podria aparecer y el nuevo recibiria `no`. Filtrar por is_process_alive evita ese bucle.
vivos(Nombre) ->
  [P || P <- pg:get_local_members(?SCOPE, Nombre), is_process_alive(P)].
