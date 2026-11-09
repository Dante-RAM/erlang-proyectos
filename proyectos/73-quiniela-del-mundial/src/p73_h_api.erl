%% API JSON. Un solo handler con la operacion en el estado (ver p73_http:dispatch/0).
%% Las operaciones que cambian el sistema (simulacion, fallas, eventos, reloj) exigen el
%% encabezado x-admin-token; el pronostico de un participante NO es administrativo.
-module(p73_h_api).
-export([init/2, jsonable/1]).

init(Req0, Op) ->
  Req = try manejar(Op, cowboy_req:method(Req0), Req0)
        catch Clase:Razon:Pila ->
          logger:error("api ~p fallo: ~p:~p ~p", [Op, Clase, Razon, Pila]),
          responder(500, #{error => <<"error_interno">>}, Req0)
        end,
  {ok, Req, Op}.

%% ---- lectura ----
manejar(estado, <<"GET">>, Req) -> responder(200, estado(), Req);
manejar(partidos, <<"GET">>, Req) ->
  Filtro = proplists:get_value(<<"estado">>, cowboy_req:parse_qs(Req)),
  Snaps = lists:sort(fun(A, B) -> {maps:get(inicio, A), maps:get(id, A)} =< {maps:get(inicio, B), maps:get(id, B)} end,
                     p73_partido:snapshots_persistidos()),
  Lista = case Filtro of
            undefined -> Snaps;
            F -> [S || #{estado := E} = S <- Snaps, atom_to_binary(E, utf8) =:= F]
          end,
  responder(200, #{partidos => Lista}, Req);
manejar(partido, <<"GET">>, Req) ->
  case entero(cowboy_req:binding(id, Req)) of
    {ok, Id} ->
      case ets:member(p73_partidos, Id) of
        false -> responder(404, #{error => <<"partido_inexistente">>}, Req);
        true -> responder_resultado(p73_partido:detalle(Id), Req)
      end;
    error -> responder(400, #{error => <<"id_invalido">>}, Req)
  end;
manejar(quinielas, <<"GET">>, Req) ->
  Qs = [#{id => Id, nombre => N, reglas => R, miembros => length(ets:lookup(p73_miembros, Id))}
        || {Id, N, R} <- lists:sort(ets:tab2list(p73_quinielas))],
  responder(200, #{quinielas => Qs}, Req);
manejar(ranking, <<"GET">>, Req) ->
  Qs = cowboy_req:parse_qs(Req),
  case proplists:get_value(<<"quiniela">>, Qs) of
    undefined -> responder(400, #{error => <<"falta_quiniela">>}, Req);
    Q ->
      case ets:member(p73_quinielas, Q) of
        false -> responder(404, #{error => <<"quiniela_inexistente">>}, Req);
        true ->
          Top = limitar(proplists:get_value(<<"top">>, Qs), 20, 500),
          case proplists:get_value(<<"participante">>, Qs) of
            undefined -> responder_resultado(p73_quiniela:ranking(Q, Top), Req);
            U -> responder_resultado(p73_quiniela:posicion(Q, U), Req)
          end
      end
  end;
manejar(participante, <<"GET">>, Req) ->
  Id = cowboy_req:binding(id, Req),
  case ets:member(p73_participantes, Id) of
    false -> responder(404, #{error => <<"participante_inexistente">>}, Req);
    true -> responder_resultado(p73_participante:info(Id), Req)
  end;
manejar(bitacora, <<"GET">>, Req) ->
  N = limitar(proplists:get_value(<<"n">>, cowboy_req:parse_qs(Req)), 50, 500),
  responder(200, #{entradas => p73_bitacora:ultimos(N)}, Req);
manejar(simulacion, <<"GET">>, Req) -> responder(200, p73_simulador:estado(), Req);
manejar(reloj, <<"GET">>, Req) ->
  responder(200, #{modo => p73_reloj:modo(), ahora_ms => p73_reloj:ahora()}, Req);

%% ---- pronostico (publico) ----
manejar(prediccion, <<"POST">>, Req0) ->
  case leer_json(Req0) of
    {ok, #{<<"participante">> := U, <<"partido">> := P, <<"local">> := L, <<"visitante">> := V} = Cuerpo, Req}
      when is_binary(U), is_integer(P), is_integer(L), is_integer(V) ->
      Res = case {ets:member(p73_participantes, U), ets:member(p73_partidos, P)} of
              {false, _} -> {error, participante_inexistente};
              {_, false} -> {error, partido_inexistente};
              _ -> p73_participante:pronosticar(U, P, L, V)
            end,
      responder_prediccion(Res, Cuerpo, Req);
    {ok, _, Req} -> responder(400, #{error => <<"campos_requeridos">>,
                                     campos => [<<"participante">>, <<"partido">>, <<"local">>, <<"visitante">>]}, Req);
    {error, Req} -> responder(400, #{error => <<"json_invalido">>}, Req)
  end;

%% ---- administrativas ----
manejar(Op, <<"POST">>, Req0) when Op =:= simulacion; Op =:= falla; Op =:= evento; Op =:= reloj ->
  case admin(Req0) of
    false -> responder(401, #{error => <<"admin_token_invalido">>}, Req0);
    true ->
      case leer_json(Req0, #{}) of
        {ok, Cuerpo, Req} -> admin(Op, Cuerpo, Req);
        {error, Req} -> responder(400, #{error => <<"json_invalido">>}, Req)
      end
  end;
manejar(_, _, Req) -> responder(405, #{error => <<"metodo_no_permitido">>}, Req).

admin(simulacion, C, Req) ->
  Opts = #{participantes => acotado(C, <<"participantes">>, 1, 20000, 5000),
           quinielas => acotado(C, <<"quinielas">>, 1, 200, 50),
           partidos => acotado(C, <<"partidos">>, 1, 104, 104),
           abiertos => acotado(C, <<"abiertos">>, 0, 20, 6),
           pausa_ms => acotado(C, <<"pausa_ms">>, 0, 30000, 0),
           caos => maps:get(<<"caos">>, C, true) =/= false,
           var => maps:get(<<"var">>, C, true) =/= false},
  case p73_simulador:iniciar(Opts) of
    ok -> responder(202, #{aceptada => true, opciones => Opts}, Req);
    {error, ocupado} -> responder(409, #{error => <<"simulacion_en_curso">>}, Req)
  end;
admin(falla, C, Req) ->
  case tipo_proceso(maps:get(<<"objetivo">>, C, undefined)) of
    error -> responder(400, #{error => <<"objetivo_invalido">>, validos => [<<"quiniela">>, <<"partido">>, <<"participante">>]}, Req);
    {ok, Tipo} ->
      Id = case maps:get(<<"id">>, C, undefined) of
             undefined -> p73_caos:aleatorio(Tipo);
             I -> {ok, I}
           end,
      case Id of
        {ok, X} -> responder_resultado(p73_caos:matar(Tipo, X), Req);
        {error, _} -> responder(404, #{error => <<"sin_procesos">>}, Req)
      end
  end;
admin(evento, C, Req) ->
  Id = maps:get(<<"partido">>, C, undefined),
  Res = case {is_integer(Id), maps:get(<<"accion">>, C, undefined)} of
          {true, <<"iniciar">>} -> p73_partido:iniciar(Id);
          {true, <<"gol">>} -> case lado(maps:get(<<"lado">>, C, undefined)) of
                                 {ok, L} -> p73_partido:gol(Id, L, maps:get(<<"minuto">>, C, 0));
                                 error -> {error, lado_invalido}
                               end;
          {true, <<"anular">>} -> p73_partido:anular_gol(Id, maps:get(<<"evento">>, C, 0));
          {true, <<"finalizar">>} -> p73_partido:finalizar(Id, penales(maps:get(<<"penales">>, C, undefined)));
          _ -> {error, parametros_invalidos}
        end,
  responder_resultado(Res, Req);
admin(reloj, C, Req) ->
  case C of
    #{<<"modo">> := <<"real">>} -> p73_reloj:usar_real();
    #{<<"ms">> := Ms} when is_integer(Ms) -> p73_reloj:usar_simulado(Ms);
    #{<<"avanzar_ms">> := D} when is_integer(D) -> p73_reloj:avanzar(D);
    _ -> ok
  end,
  responder(200, #{modo => p73_reloj:modo(), ahora_ms => p73_reloj:ahora()}, Req).

%% ---- respuestas ----
responder_prediccion(ok, Cuerpo, Req) ->
  %% ts_cliente se acepta pero se IGNORA: el cierre lo decide solo el reloj del servidor.
  responder(200, #{ok => true, servidor_ms => p73_reloj:ahora(),
                   ts_cliente_ignorado => maps:is_key(<<"ts_cliente">>, Cuerpo)}, Req);
responder_prediccion({error, cerrado}, _, Req) ->
  responder(409, #{ok => false, error => <<"cerrado">>, servidor_ms => p73_reloj:ahora(),
                   mensaje => <<"El partido ya inicio o esta por iniciar; el cierre lo decide el reloj del servidor.">>}, Req);
responder_prediccion({error, marcador_invalido}, _, Req) -> responder(400, #{ok => false, error => <<"marcador_invalido">>}, Req);
responder_prediccion({error, participante_inexistente}, _, Req) -> responder(404, #{ok => false, error => <<"participante_inexistente">>}, Req);
responder_prediccion({error, partido_inexistente}, _, Req) -> responder(404, #{ok => false, error => <<"partido_inexistente">>}, Req);
responder_prediccion({error, _}, _, Req) ->
  responder(503, #{ok => false, error => <<"no_disponible">>, mensaje => <<"Reintenta en un momento.">>}, Req).

responder_resultado({error, no_disponible}, Req) -> responder(503, #{error => <<"no_disponible">>}, Req);
responder_resultado({error, E}, Req) -> responder(409, #{error => E}, Req);
responder_resultado({ok, X}, Req) -> responder(200, #{resultado => X}, Req);
responder_resultado(undefined, Req) -> responder(404, #{error => <<"no_encontrado">>}, Req);
responder_resultado(ok, Req) -> responder(200, #{ok => true}, Req);
responder_resultado(X, Req) -> responder(200, X, Req).

responder(Estado, Termino, Req) ->
  cowboy_req:reply(Estado, #{<<"content-type">> => <<"application/json; charset=utf-8">>,
                             <<"cache-control">> => <<"no-store">>,
                             <<"x-content-type-options">> => <<"nosniff">>},
                   p73_json:codificar(jsonable(Termino)), Req).

%% Tuplas -> listas, atomos/binarios intactos (p73_json maneja el resto).
jsonable(T) when is_map(T) -> maps:map(fun(_, V) -> jsonable(V) end, T);
jsonable(T) when is_list(T) -> [jsonable(X) || X <- T];
jsonable(T) when is_tuple(T) -> [jsonable(X) || X <- tuple_to_list(T)];
jsonable(T) -> T.

%% ---- utilidades ----
estado() ->
  Snaps = p73_partido:snapshots_persistidos(),
  PorEstado = lists:foldl(fun(#{estado := E}, M) -> maps:update_with(E, fun(N) -> N + 1 end, 1, M) end,
                          #{programado => 0, en_vivo => 0, finalizado => 0}, Snaps),
  Sim = maps:with([estado, progreso], p73_simulador:estado()),
  #{reloj => #{modo => p73_reloj:modo(), ahora_ms => p73_reloj:ahora()},
    partidos => PorEstado,
    quinielas => ets:info(p73_quinielas, size),
    participantes => ets:info(p73_participantes, size),
    pronosticos => ets:info(p73_pronosticos, size),
    procesos => #{partidos => cuenta(p73_partidos_sup), quinielas => cuenta(p73_quinielas_sup),
                  participantes => cuenta(p73_participantes_sup)},
    sse_conectados => length(p73_reg:miembros(eventos)),
    simulacion => Sim,
    metricas => maps:from_list([{K, V} || {K, V} <- p73_metricas:todas(), is_atom(K)])}.

cuenta(Sup) -> proplists:get_value(active, supervisor:count_children(Sup), 0).

leer_json(Req) -> leer_json(Req, undefined).
leer_json(Req0, Vacio) ->
  case cowboy_req:read_body(Req0, #{length => 8192, period => 5000}) of
    {ok, <<>>, Req} when Vacio =/= undefined -> {ok, Vacio, Req};
    {ok, Bin, Req} ->
      case p73_json:decodificar(Bin) of
        {ok, M} when is_map(M) -> {ok, M, Req};
        _ -> {error, Req}
      end;
    {more, _, Req} -> {error, Req}
  end.

admin(Req) ->
  case {application:get_env(p73_quiniela_del_mundial, admin_token, undefined),
        cowboy_req:header(<<"x-admin-token">>, Req)} of
    {undefined, _} -> false;
    {_, undefined} -> false;
    {Esperado, Recibido} ->
      %% Comparacion en tiempo constante sobre hashes (misma longitud).
      crypto:hash_equals(crypto:hash(sha256, iolist_to_binary([Esperado])), crypto:hash(sha256, Recibido))
  end.

tipo_proceso(<<"quiniela">>) -> {ok, quiniela};
tipo_proceso(<<"partido">>) -> {ok, partido};
tipo_proceso(<<"participante">>) -> {ok, participante};
tipo_proceso(_) -> error.

lado(<<"local">>) -> {ok, local};
lado(<<"visitante">>) -> {ok, visitante};
lado(_) -> error.

penales([A, B]) when is_integer(A), is_integer(B) -> {A, B};
penales(_) -> undefined.

entero(B) when is_binary(B) -> try {ok, binary_to_integer(B)} catch error:badarg -> error end;
entero(_) -> error.

limitar(undefined, Def, _) -> Def;
limitar(B, Def, Max) ->
  case entero(B) of
    {ok, N} when N >= 1 -> min(N, Max);
    _ -> Def
  end.

acotado(C, Llave, Min, Max, Def) ->
  case maps:get(Llave, C, Def) of
    N when is_integer(N), N >= Min, N =< Max -> N;
    _ -> Def
  end.
