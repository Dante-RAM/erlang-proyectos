%% Registro y arranque de la "poblacion" (partidos, quinielas, participantes).
%% Fuente de verdad = ETS (p73_almacen). `asegurar/0` arranca los procesos que falten, asi que si un
%% supervisor dinamico cae y el arbol (rest_for_one) lo reinicia, este proceso repuebla todo desde ETS.
-module(p73_poblacion).
-behaviour(gen_server).

-export([start_link/0, asegurar/0, limpiar/0]).
-export([registrar_partido/1, registrar_quiniela/3, registrar_participante/3]).
-export([init/1, handle_call/3, handle_cast/2, handle_continue/2]).

start_link() -> gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% ---- registro (solo ETS; los procesos se arrancan con asegurar/0) ----
registrar_partido(#{id := Id} = Datos) ->
  true = ets:insert_new(p73_partidos, {Id, programado, Datos#{eventos => [], sig => 1, penales => undefined}}),
  ok.

registrar_quiniela(Id, Nombre, ReglasParciales) ->
  true = ets:insert(p73_quinielas, {Id, Nombre, p73_puntos:reglas(ReglasParciales)}),
  ok.

registrar_participante(Id, Nombre, Quinielas) ->
  true = ets:insert(p73_participantes, {Id, Nombre, Quinielas}),
  true = ets:insert(p73_miembros, [{Q, Id} || Q <- Quinielas]),
  ok.

%% ---- arranque ----
-spec asegurar() -> #{partidos := integer(), quinielas := integer(), participantes := integer()}.
asegurar() ->
  Ps = ets:select(p73_partidos, [{{'$1', '_', '_'}, [], ['$1']}]),
  Qs = ets:select(p73_quinielas, [{{'$1', '_', '_'}, [], ['$1']}]),
  Us = ets:select(p73_participantes, [{{'$1', '_', '_'}, [], ['$1']}]),
  #{partidos => arrancar(p73_partidos_sup, partido, Ps),
    quinielas => arrancar(p73_quinielas_sup, quiniela, Qs),
    participantes => arrancar(p73_participantes_sup, participante, Us)}.

arrancar(Sup, Tipo, Ids) ->
  lists:foldl(fun(Id, N) ->
                  case p73_reg:buscar({Tipo, Id}) of
                    {ok, _} -> N;
                    {error, _} ->
                      case supervisor:start_child(Sup, [Id]) of
                        {ok, _} -> N + 1;
                        {error, {already_started, _}} -> N;
                        {error, _} -> N
                      end
                  end
              end, 0, Ids).

%% Detiene todo y vacia las tablas (el simulador arranca cada escenario desde cero).
limpiar() -> gen_server:call(?MODULE, limpiar, 120000).

init([]) -> {ok, #{}, {continue, asegurar}}.

handle_continue(asegurar, S) -> asegurar(), {noreply, S}.

handle_call(limpiar, _From, S) ->
  [terminar(Sup) || Sup <- [p73_quinielas_sup, p73_participantes_sup, p73_partidos_sup]],
  ok = p73_almacen:limpiar(),
  {reply, ok, S}.

handle_cast(_, S) -> {noreply, S}.

terminar(Sup) ->
  [supervisor:terminate_child(Sup, Pid) || {_, Pid, _, _} <- supervisor:which_children(Sup), is_pid(Pid)],
  ok.
