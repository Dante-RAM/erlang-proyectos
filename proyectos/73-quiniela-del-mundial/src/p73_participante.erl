%% Un proceso por participante: su "sesion". Valida el marcador, reenvia el pronostico al partido
%% (que es quien decide si sigue abierto) y guarda su vista de lo aceptado.
%% Si muere, se reconstruye desde ETS (pronosticos y membresias), no se pierde nada.
-module(p73_participante).
-behaviour(gen_server).

-export([start_link/1, via/1, pronosticar/4, elegir_campeon/2, info/1]).
-export([init/1, handle_call/3, handle_cast/2]).

via(Id) -> {via, p73_reg, {participante, Id}}.

start_link(Id) -> gen_server:start_link(via(Id), ?MODULE, Id, []).

-spec pronosticar(binary(), integer(), integer(), integer()) -> ok | {error, term()}.
pronosticar(Id, Partido, L, V) -> llamar(Id, {pronosticar, Partido, L, V}).

elegir_campeon(Id, Equipo) -> llamar(Id, {campeon, Equipo}).

info(Id) -> llamar(Id, info).

llamar(Id, Req) ->
  try gen_server:call(via(Id), Req, 15000)
  catch
    exit:{timeout, _} -> {error, timeout};
    exit:_ -> {error, no_disponible}
  end.

init(Id) ->
  case ets:lookup(p73_participantes, Id) of
    [{Id, Nombre, Quinielas}] ->
      {ok, #{id => Id, nombre => Nombre, quinielas => Quinielas, pronosticos => cargar(Id)}};
    [] -> {stop, {no_registrado, Id}}
  end.

%% Recuperacion tras caida: el indice ordenado por participante evita barrer toda la tabla.
cargar(Id) ->
  maps:from_list(ets:select(p73_pron_usuario, [{{{Id, '$1'}, '$2', '$3'}, [], [{{'$1', {{'$2', '$3'}}}}]}])).

handle_call({pronosticar, Partido, L, V}, _From, #{id := Id, pronosticos := P} = S) ->
  case p73_puntos:valido({L, V}) of
    false -> {reply, {error, marcador_invalido}, S};
    true ->
      case p73_partido:pronosticar(Partido, Id, L, V) of
        ok -> {reply, ok, S#{pronosticos := P#{Partido => {L, V}}}};
        Otro -> {reply, Otro, S}
      end
  end;
handle_call({campeon, Equipo}, _From, #{id := Id} = S) ->
  case {lists:member(Equipo, p73_torneo:equipos()), p73_reloj:ahora() < p73_torneo:primer_inicio()} of
    {true, true} -> true = ets:insert(p73_campeones, {Id, Equipo}), {reply, ok, S};
    {false, _} -> {reply, {error, equipo_invalido}, S};
    {_, false} -> {reply, {error, cerrado}, S}
  end;
handle_call(info, _From, #{id := Id, nombre := N, quinielas := Q, pronosticos := P} = S) ->
  Campeon = case ets:lookup(p73_campeones, Id) of [{_, E}] -> E; [] -> undefined end,
  {reply, #{id => Id, nombre => N, quinielas => Q, pronosticos => maps:size(P), campeon => Campeon}, S}.

handle_cast(_, S) -> {noreply, S}.
