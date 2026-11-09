%% Reglas de puntos: modulo PURO (sin procesos ni estado) => determinista y facil de probar.
%% Cada quiniela trae sus propias reglas (caso dificil: "reglas de puntos que cambian entre quinielas").
-module(p73_puntos).
-export([reglas/1, reglas_base/0, resultado/1, puntos/4, bono_campeon/2, valido/1]).

-type marcador() :: {non_neg_integer(), non_neg_integer()}.
-type tipo() :: exacto | diferencia | ganador | nada.
-export_type([marcador/0, tipo/0]).

%% Reglas comunes del enunciado: 3 por marcador exacto, 1 por acertar ganador/empate.
reglas_base() ->
  #{exacto => 3, diferencia => 0, ganador => 1, bono_campeon => 5,
    multiplicador => #{grupos => 1, dieciseisavos => 1, octavos => 1, cuartos => 1,
                       semifinales => 1, tercer_puesto => 1, final => 1}}.

%% Mezcla reglas parciales con la base (una quiniela solo declara lo que cambia).
reglas(Parciales) ->
  Base = reglas_base(),
  Mult = maps:merge(maps:get(multiplicador, Base), maps:get(multiplicador, Parciales, #{})),
  maps:merge(Base, Parciales#{multiplicador => Mult}).

resultado({L, V}) when L > V -> local;
resultado({L, V}) when L < V -> visitante;
resultado({_, _}) -> empate.

valido({L, V}) when is_integer(L), is_integer(V), L >= 0, V >= 0, L =< 30, V =< 30 -> true;
valido(_) -> false.

%% Marcador = el vigente al terminar el juego (incluye tiempo extra, NO la tanda de penales).
-spec puntos(map(), atom(), marcador(), marcador()) -> {non_neg_integer(), tipo()}.
puntos(Reglas, Fase, Pron, Res) ->
  Mult = maps:get(Fase, maps:get(multiplicador, Reglas), 1),
  {PL, PV} = Pron,
  {RL, RV} = Res,
  {Base, Tipo} =
    case {Pron =:= Res, resultado(Pron) =:= resultado(Res)} of
      {true, _} -> {maps:get(exacto, Reglas), exacto};
      {false, true} ->
        case PL - PV =:= RL - RV andalso maps:get(diferencia, Reglas) > 0 of
          true -> {maps:get(diferencia, Reglas), diferencia};
          false -> {maps:get(ganador, Reglas), ganador}
        end;
      {false, false} -> {0, nada}
    end,
  case Base of
    0 -> {0, nada};
    _ -> {Base * Mult, Tipo}
  end.

bono_campeon(Reglas, Acierto) ->
  case Acierto of
    true -> maps:get(bono_campeon, Reglas);
    false -> 0
  end.
