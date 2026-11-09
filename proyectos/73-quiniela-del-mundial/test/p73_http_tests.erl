%% Pruebas de la API HTTP real (cowboy en puerto efimero) y del canal SSE.
-module(p73_http_tests).
-include_lib("eunit/include/eunit.hrl").

http_test_() ->
  {setup, fun arrancar/0, fun parar/1,
   fun(#{inicio := I}) ->
       [{"pronostico acepta, rechaza al inicio e ignora ts_cliente falso", fun() -> pronostico(I) end},
        {"errores: json roto, campos faltantes, inexistentes", fun errores/0},
        {"operaciones administrativas exigen token", fun admin/0},
        {"ranking, partidos, quinielas y bitacora devuelven JSON", fun lecturas/0},
        {"/metrics expone contadores en formato Prometheus", fun metricas/0},
        {"SSE: hola + eventos de partido en vivo", fun() -> sse(I) end},
        {"WebSocket: hola, ping/pong, pronostico por el socket y eventos en vivo", fun ws/0},
        {"/api/diagnostico (recon): top de procesos y memoria", fun diagnostico/0}]
   end}.

arrancar() ->
  {ok, _} = application:ensure_all_started(inets),
  {ok, _} = application:ensure_all_started(cowboy),
  application:set_env(p73_quiniela_del_mundial, admin_token, <<"token-de-prueba">>),
  Sup = p73_test_util:arrancar(),
  #{inicio := I} = p73_test_util:escenario(),
  {ok, _} = p73_http:iniciar(0),
  #{sup => Sup, inicio => I}.

parar(#{sup := Sup}) ->
  p73_http:detener(),
  p73_test_util:parar(Sup).

url(Ruta) -> "http://127.0.0.1:" ++ integer_to_list(p73_http:puerto()) ++ Ruta.

post(Ruta, Cuerpo) -> post(Ruta, Cuerpo, []).
post(Ruta, Cuerpo, Cab) ->
  {ok, {{_, Codigo, _}, _, Resp}} =
    httpc:request(post, {url(Ruta), Cab, "application/json", Cuerpo}, [], [{body_format, binary}]),
  {Codigo, decodificar(Resp)}.

consultar(Ruta) ->
  {ok, {{_, Codigo, _}, Cab, Resp}} = httpc:request(get, {url(Ruta), []}, [], [{body_format, binary}]),
  {Codigo, Cab, Resp}.

decodificar(Bin) -> case p73_json:decodificar(Bin) of {ok, M} -> M; _ -> Bin end.

pronostico(I) ->
  p73_reloj:usar_simulado(I - 1000),
  ?assertMatch({200, #{<<"ok">> := true}},
               post("/api/predicciones", <<"{\"participante\":\"U1\",\"partido\":1,\"local\":2,\"visitante\":0}">>)),
  p73_reloj:usar_simulado(I),
  %% El cliente jura que son las 00:00 de 1970 (ts_cliente=1): el servidor lo ignora y cierra igual.
  {409, R} = post("/api/predicciones",
                  <<"{\"participante\":\"U2\",\"partido\":1,\"local\":1,\"visitante\":0,\"ts_cliente\":1}">>),
  ?assertMatch(#{<<"error">> := <<"cerrado">>, <<"ok">> := false}, R),
  ?assertEqual(I, maps:get(<<"servidor_ms">>, R)),
  %% Y un cliente adelantado (ts_cliente en el futuro lejano) tampoco abre un partido ya cerrado.
  ?assertMatch({409, _}, post("/api/predicciones",
                              <<"{\"participante\":\"U2\",\"partido\":1,\"local\":1,\"visitante\":0,\"ts_cliente\":99999999999999}">>)),
  %% El partido 2 esta en la misma ventana horaria, tambien cerrado; el 104 (julio) sigue abierto.
  ?assertMatch({409, _}, post("/api/predicciones", <<"{\"participante\":\"U2\",\"partido\":2,\"local\":1,\"visitante\":0}">>)),
  ?assertMatch({200, #{<<"ts_cliente_ignorado">> := true}},
               post("/api/predicciones", <<"{\"participante\":\"U2\",\"partido\":104,\"local\":1,\"visitante\":0,\"ts_cliente\":5}">>)).

errores() ->
  ?assertMatch({400, #{<<"error">> := <<"json_invalido">>}}, post("/api/predicciones", <<"{no">>)),
  ?assertMatch({400, #{<<"error">> := <<"campos_requeridos">>}}, post("/api/predicciones", <<"{\"participante\":\"U1\"}">>)),
  ?assertMatch({404, #{<<"error">> := <<"participante_inexistente">>}},
               post("/api/predicciones", <<"{\"participante\":\"NADIE\",\"partido\":1,\"local\":1,\"visitante\":0}">>)),
  ?assertMatch({404, #{<<"error">> := <<"partido_inexistente">>}},
               post("/api/predicciones", <<"{\"participante\":\"U1\",\"partido\":777,\"local\":1,\"visitante\":0}">>)),
  ?assertMatch({400, #{<<"error">> := <<"marcador_invalido">>}},
               post("/api/predicciones", <<"{\"participante\":\"U1\",\"partido\":104,\"local\":-4,\"visitante\":0}">>)),
  ?assertMatch({404, _, _}, consultar("/api/partidos/777")),
  ?assertMatch({400, _, _}, consultar("/api/partidos/abc")),
  ?assertMatch({404, _, _}, consultar("/api/ranking?quiniela=NOEXISTE")),
  ?assertMatch({400, _, _}, consultar("/api/ranking")),
  %% Cuerpo gigante: se rechaza sin tumbar nada.
  Grande = binary:copy(<<"x">>, 20000),
  ?assertMatch({400, _}, post("/api/predicciones", Grande)).

admin() ->
  ?assertMatch({401, _}, post("/api/falla", <<"{\"objetivo\":\"quiniela\"}">>)),
  ?assertMatch({401, _}, post("/api/falla", <<"{\"objetivo\":\"quiniela\"}">>, [{"x-admin-token", "otro"}])),
  ?assertMatch({401, _}, post("/api/simulacion", <<"{}">>)),
  ?assertMatch({401, _}, post("/api/admin/evento", <<"{}">>)),
  Cab = [{"x-admin-token", "token-de-prueba"}],
  ?assertMatch({200, #{<<"resultado">> := #{<<"tipo">> := <<"quiniela">>, <<"recuperado_ms">> := _}}},
               post("/api/falla", <<"{\"objetivo\":\"quiniela\"}">>, Cab)),
  ?assertMatch({400, #{<<"error">> := <<"objetivo_invalido">>}}, post("/api/falla", <<"{\"objetivo\":\"todo\"}">>, Cab)),
  ?assertMatch({409, _}, post("/api/admin/evento", <<"{\"partido\":2,\"accion\":\"gol\",\"lado\":\"local\"}">>, Cab)),   %% aun no inicia
  ?assertMatch({200, _}, post("/api/admin/evento", <<"{\"partido\":2,\"accion\":\"iniciar\"}">>, Cab)),
  ?assertMatch({200, #{<<"resultado">> := 1}}, post("/api/admin/evento", <<"{\"partido\":2,\"accion\":\"gol\",\"lado\":\"visitante\",\"minuto\":9}">>, Cab)),
  ?assertMatch({200, _}, post("/api/admin/evento", <<"{\"partido\":2,\"accion\":\"anular\",\"evento\":1}">>, Cab)).

lecturas() ->
  {200, _, P} = consultar("/api/partidos"),
  #{<<"partidos">> := Ps} = decodificar(P),
  ?assertEqual(3, length(Ps)),
  {200, _, Q} = consultar("/api/quinielas"),
  ?assertMatch(#{<<"quinielas">> := [#{<<"id">> := <<"Q1">>, <<"miembros">> := 3}, #{<<"id">> := <<"Q2">>, <<"miembros">> := 2}]}, decodificar(Q)),
  {200, _, R} = consultar("/api/ranking?quiniela=Q1&top=2"),
  ?assertMatch(#{<<"quiniela">> := <<"Q1">>, <<"total">> := 3, <<"filas">> := [_, _]}, decodificar(R)),
  {200, _, D} = consultar("/api/partidos/2"),
  ?assertMatch(#{<<"partido">> := #{<<"estado">> := <<"en_vivo">>, <<"marcador">> := [0, 0]}}, decodificar(D)),
  {200, _, B} = consultar("/api/bitacora?n=5"),
  #{<<"entradas">> := E} = decodificar(B),
  ?assert(length(E) >= 1),
  {200, _, S} = consultar("/api/estado"),
  ?assertMatch(#{<<"quinielas">> := 2, <<"participantes">> := 4, <<"reloj">> := #{<<"modo">> := <<"simulado">>}}, decodificar(S)).

metricas() ->
  {200, Cab, Cuerpo} = consultar("/metrics"),
  ?assertMatch("text/plain" ++ _, proplists:get_value("content-type", Cab)),
  ?assertNotEqual(nomatch, binary:match(Cuerpo, <<"p73_predicciones_aceptadas ">>)),
  ?assertNotEqual(nomatch, binary:match(Cuerpo, <<"p73_predicciones_rechazadas ">>)),
  ?assertNotEqual(nomatch, binary:match(Cuerpo, <<"p73_procesos_quinielas 2">>)).

sse(_I) ->
  {ok, S} = gen_tcp:connect({127, 0, 0, 1}, p73_http:puerto(), [binary, {active, false}]),
  ok = gen_tcp:send(S, <<"GET /api/eventos?quiniela=Q1 HTTP/1.1\r\nHost: x\r\nAccept: text/event-stream\r\n\r\n">>),
  Hola = leer_hasta(S, <<"event: hola">>, <<>>),
  ?assertNotEqual(nomatch, binary:match(Hola, <<"text/event-stream">>)),
  ?assertEqual(ok, p73_test_util:esperar(fun() -> length(p73_reg:miembros(eventos)) =:= 1 end, 50)),
  Cab = [{"x-admin-token", "token-de-prueba"}],
  {200, _} = post("/api/admin/evento", <<"{\"partido\":2,\"accion\":\"gol\",\"lado\":\"local\",\"minuto\":33}">>, Cab),
  Ev = leer_hasta(S, <<"\"tipo\":\"gol\"">>, <<>>),
  ?assertNotEqual(nomatch, binary:match(Ev, <<"event: bitacora">>)),
  gen_tcp:close(S),
  %% Al cerrarse el cliente, pg lo saca del grupo: no quedan conexiones colgadas.
  ?assertEqual(ok, p73_test_util:esperar(fun() -> p73_reg:miembros(eventos) =:= [] end, 100)).

leer_hasta(S, Buscado, Acc) ->
  case binary:match(Acc, Buscado) of
    nomatch ->
      {ok, Datos} = gen_tcp:recv(S, 0, 5000),
      leer_hasta(S, Buscado, <<Acc/binary, Datos/binary>>);
    _ -> Acc
  end.

%% ---- WebSocket (/ws) con un cliente minimo sobre gen_tcp (RFC 6455) ----
ws() ->
  {ok, S} = gen_tcp:connect({127, 0, 0, 1}, p73_http:puerto(), [binary, {active, false}]),
  ok = gen_tcp:send(S, <<"GET /ws?quiniela=Q1 HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                         "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n">>),
  {Cab, Resto} = leer_cabecera(S, <<>>),
  ?assertNotEqual(nomatch, binary:match(Cab, <<"101">>)),
  {Hola, R1} = leer_trama(S, Resto),
  ?assertMatch(#{<<"tipo">> := <<"hola">>, <<"canal">> := <<"websocket">>}, decodificar(Hola)),
  ok = enviar_trama(S, <<"{\"tipo\":\"ping\"}">>),
  {Pong, R2} = leer_trama(S, R1),
  ?assertMatch(#{<<"tipo">> := <<"pong">>}, decodificar(Pong)),
  %% Pronostico por el socket: el partido 104 sigue abierto (reloj del servidor antes de su inicio).
  ok = enviar_trama(S, <<"{\"tipo\":\"pronostico\",\"participante\":\"U3\",\"partido\":104,\"local\":1,\"visitante\":1}">>),
  {Ok, R3} = leer_hasta_tipo(S, R2, <<"pronostico_resultado">>),
  ?assertMatch(#{<<"ok">> := true, <<"partido">> := 104}, Ok),
  %% El partido 1 ya cerro: el socket tambien lo rechaza.
  ok = enviar_trama(S, <<"{\"tipo\":\"pronostico\",\"participante\":\"U3\",\"partido\":1,\"local\":1,\"visitante\":1}">>),
  {Rech, R4} = leer_hasta_tipo(S, R3, <<"pronostico_resultado">>),
  ?assertMatch(#{<<"ok">> := false, <<"error">> := <<"cerrado">>}, Rech),
  ok = enviar_trama(S, <<"no es json">>),
  {Err, _} = leer_hasta_tipo(S, R4, <<"error">>),
  ?assertMatch(#{<<"error">> := <<"json_invalido">>}, Err),
  gen_tcp:close(S),
  ?assertEqual(ok, p73_test_util:esperar(fun() -> p73_reg:miembros(eventos) =:= [] end, 100)).

diagnostico() ->
  {200, _, Cuerpo} = consultar("/api/diagnostico"),
  D = decodificar(Cuerpo),
  ?assertMatch(#{<<"procesos">> := N, <<"memoria_mb">> := #{<<"total">> := _}} when N > 0, D),
  ?assertEqual(5, length(maps:get(<<"top_memoria">>, D))),
  ?assertMatch([#{<<"pid">> := _, <<"valor">> := _, <<"proceso">> := _} | _], maps:get(<<"top_cola_mensajes">>, D)).

leer_cabecera(S, Acc) ->
  case binary:split(Acc, <<"\r\n\r\n">>) of
    [C, Resto] -> {C, Resto};
    _ -> {ok, D} = gen_tcp:recv(S, 0, 5000), leer_cabecera(S, <<Acc/binary, D/binary>>)
  end.

%% Trama de texto del servidor (sin mascara).
leer_trama(S, <<_:4, 1:4, 0:1, 126:7, Len:16, Datos:Len/binary, Resto/binary>>) -> _ = S, {Datos, Resto};
leer_trama(S, <<_:4, 1:4, 0:1, Len:7, Datos:Len/binary, Resto/binary>>) when Len < 126 -> _ = S, {Datos, Resto};
leer_trama(S, Acc) -> {ok, D} = gen_tcp:recv(S, 0, 5000), leer_trama(S, <<Acc/binary, D/binary>>).

%% Salta eventos de partido intercalados hasta el mensaje del tipo buscado.
leer_hasta_tipo(S, Acc, Tipo) ->
  {T, Resto} = leer_trama(S, Acc),
  case decodificar(T) of
    #{<<"tipo">> := Tipo} = M -> {M, Resto};
    _ -> leer_hasta_tipo(S, Resto, Tipo)
  end.

%% Trama de texto del cliente (con mascara, obligatoria por RFC 6455).
enviar_trama(S, Datos) ->
  Mascara = crypto:strong_rand_bytes(4),
  gen_tcp:send(S, [<<1:1, 0:3, 1:4, 1:1, (byte_size(Datos)):7>>, Mascara, enmascarar(Datos, Mascara)]).

enmascarar(Datos, <<M:32>>) ->
  << <<(B bxor ((M bsr (8 * (3 - (I rem 4)))) band 255))>> || {I, B} <- lists:zip(lists:seq(0, byte_size(Datos) - 1), binary_to_list(Datos)) >>.
