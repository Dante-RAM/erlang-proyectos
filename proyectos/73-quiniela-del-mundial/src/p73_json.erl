%% JSON minimo (codificar/decodificar) sin dependencias: OTP 27 trae `json`, pero asi el
%% mismo codigo compila en OTP 25/26 y el stack del repo no crece.
-module(p73_json).
-export([codificar/1, decodificar/1]).

-spec codificar(term()) -> binary().
codificar(Termino) -> iolist_to_binary(enc(Termino)).

-spec decodificar(binary()) -> {ok, term()} | {error, json_invalido}.
decodificar(Bin) when is_binary(Bin) ->
  try
    {V, Resto} = val(ws(Bin)),
    <<>> = ws(Resto),
    {ok, V}
  catch _:_ -> {error, json_invalido}
  end.

%% ---- codificar ----
enc(null) -> <<"null">>;
enc(true) -> <<"true">>;
enc(false) -> <<"false">>;
enc(undefined) -> <<"null">>;
enc(A) when is_atom(A) -> enc_str(atom_to_binary(A, utf8));
enc(B) when is_binary(B) -> enc_str(B);
enc(I) when is_integer(I) -> integer_to_binary(I);
enc(F) when is_float(F) -> float_to_binary(F, [{decimals, 4}, compact]);
enc(L) when is_list(L) -> [$[, lists:join($,, [enc(X) || X <- L]), $]];
enc(M) when is_map(M) ->
  [${, lists:join($,, [[enc_str(llave(K)), $:, enc(V)] || {K, V} <- maps:to_list(M)]), $}].

llave(K) when is_binary(K) -> K;
llave(K) when is_atom(K) -> atom_to_binary(K, utf8);
llave(K) when is_integer(K) -> integer_to_binary(K).

enc_str(B) -> [$", esc(B), $"].
esc(<<>>) -> [];
esc(<<$", R/binary>>) -> [<<"\\\"">> | esc(R)];
esc(<<$\\, R/binary>>) -> [<<"\\\\">> | esc(R)];
esc(<<$\n, R/binary>>) -> [<<"\\n">> | esc(R)];
esc(<<$\r, R/binary>>) -> [<<"\\r">> | esc(R)];
esc(<<$\t, R/binary>>) -> [<<"\\t">> | esc(R)];
esc(<<C, R/binary>>) when C < 32 -> [io_lib:format("\\u~4.16.0b", [C]) | esc(R)];
esc(<<C, R/binary>>) -> [C | esc(R)].

%% ---- decodificar ----
ws(<<C, R/binary>>) when C =:= $\s; C =:= $\t; C =:= $\n; C =:= $\r -> ws(R);
ws(B) -> B.

val(<<"{", R/binary>>) ->
  case ws(R) of
    <<"}", R1/binary>> -> {#{}, R1};
    R2 -> obj(R2, #{})
  end;
val(<<"[", R/binary>>) ->
  case ws(R) of
    <<"]", R1/binary>> -> {[], R1};
    R2 -> arr(R2, [])
  end;
val(<<"\"", R/binary>>) -> str(R, <<>>);
val(<<"true", R/binary>>) -> {true, R};
val(<<"false", R/binary>>) -> {false, R};
val(<<"null", R/binary>>) -> {null, R};
val(B) -> num(B).

obj(<<"\"", R0/binary>>, Acc) ->
  {K, R1} = str(R0, <<>>),
  <<":", R2/binary>> = ws(R1),
  {V, R3} = val(ws(R2)),
  case ws(R3) of
    <<",", R4/binary>> -> obj(ws(R4), Acc#{K => V});
    <<"}", R4/binary>> -> {Acc#{K => V}, R4}
  end.

arr(B, Acc) ->
  {V, R1} = val(B),
  case ws(R1) of
    <<",", R2/binary>> -> arr(ws(R2), [V | Acc]);
    <<"]", R2/binary>> -> {lists:reverse([V | Acc]), R2}
  end.

str(<<"\"", R/binary>>, Acc) -> {Acc, R};
str(<<"\\", E, R/binary>>, Acc) when E =:= $"; E =:= 92; E =:= $/ -> str(R, <<Acc/binary, E>>);
str(<<"\\n", R/binary>>, Acc) -> str(R, <<Acc/binary, $\n>>);
str(<<"\\r", R/binary>>, Acc) -> str(R, <<Acc/binary, $\r>>);
str(<<"\\t", R/binary>>, Acc) -> str(R, <<Acc/binary, $\t>>);
str(<<"\\b", R/binary>>, Acc) -> str(R, <<Acc/binary, $\b>>);
str(<<"\\f", R/binary>>, Acc) -> str(R, <<Acc/binary, $\f>>);
str(<<"\\u", H:4/binary, R/binary>>, Acc) ->
  Cp = binary_to_integer(H, 16),
  str(R, <<Acc/binary, Cp/utf8>>);
str(<<C, R/binary>>, Acc) when C >= 32 -> str(R, <<Acc/binary, C>>).

num(B) ->
  {Tok, Resto} = split_num(B, <<>>),
  <<_, _/binary>> = Tok,
  case binary:match(Tok, [<<".">>, <<"e">>, <<"E">>]) of
    nomatch -> {binary_to_integer(Tok), Resto};
    _ -> {to_float(Tok), Resto}
  end.

split_num(<<C, R/binary>>, Acc) when (C >= $0 andalso C =< $9); C =:= $-; C =:= $+; C =:= $.; C =:= $e; C =:= $E ->
  split_num(R, <<Acc/binary, C>>);
split_num(R, Acc) -> {Acc, R}.

to_float(Tok) ->
  try binary_to_float(Tok)
  catch error:badarg ->
    %% "1e5" no es float valido para Erlang; se normaliza a "1.0e5".
    [M, E] = binary:split(Tok, [<<"e">>, <<"E">>]),
    binary_to_float(<<M/binary, ".0e", E/binary>>)
  end.
