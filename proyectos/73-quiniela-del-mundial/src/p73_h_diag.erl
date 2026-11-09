%% GET /api/diagnostico: diagnostico en caliente del nodo con recon (sin detenerlo ni conectarse con remsh).
%%  - top 5 procesos por memoria, por cola de mensajes y por reducciones (recon:proc_count/2)
%%  - memoria del asignador (recon_alloc) y conteos del nodo
%% Util durante la simulacion o tras inyectar fallas para ver que nada se queda acumulando.
-module(p73_h_diag).

-export([init/2, diagnostico/0]).

init(Req0, Estado) ->
  Req = cowboy_req:reply(200, #{<<"content-type">> => <<"application/json">>},
                         p73_json:codificar(diagnostico()), Req0),
  {ok, Req, Estado}.

diagnostico() ->
  #{nodo => atom_to_binary(node(), utf8),
    otp => list_to_binary(erlang:system_info(otp_release)),
    procesos => erlang:system_info(process_count),
    limite_procesos => erlang:system_info(process_limit),
    puertos => erlang:system_info(port_count),
    tablas_ets => length(ets:all()),
    memoria_mb => #{total => mb(erlang:memory(total)), procesos => mb(erlang:memory(processes)),
                    ets => mb(erlang:memory(ets)), binarios => mb(erlang:memory(binary)),
                    asignada_alloc => mb(recon_alloc:memory(allocated)),
                    usada_alloc => mb(recon_alloc:memory(used))},
    top_memoria => top(memory),
    top_cola_mensajes => top(message_queue_len),
    top_reducciones => top(reductions)}.

top(Atributo) ->
  [#{pid => list_to_binary(pid_to_list(Pid)), valor => Valor, proceso => nombre(Info)}
   || {Pid, Valor, Info} <- recon:proc_count(Atributo, 5)].

%% recon devuelve el nombre registrado o la llamada inicial / actual del proceso.
nombre(Info) ->
  case [N || N <- Info, is_atom(N)] of
    [Nombre | _] -> atom_to_binary(Nombre, utf8);
    [] ->
      case lists:keyfind(current_function, 1, Info) of
        {_, {M, F, A}} -> iolist_to_binary(io_lib:format("~s:~s/~b", [M, F, A]));
        _ -> <<"?">>
      end
  end.

mb(Bytes) -> round(Bytes / 1048576 * 10) / 10.
