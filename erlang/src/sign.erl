-module(sign).
-export([test/0,new_key/0,verify_1/2,verify_2/2,verify_both/3,sign_tx/3,sign/2,verify_sig/3,shared_secret/2]).

-record(signed, {data="", sig="", sig2="", revealed=[]}).
en(X) -> base64:encode(X).
de(X) -> base64:decode(X).
params() -> crypto:ec_curve(secp256k1).
shared_secret(Pub, Priv) -> en(crypto:compute_key(ecdh, de(Pub), de(Priv), params())).
new_key() -> 
    {Pub, Priv} = crypto:generate_key(ecdh, params()),
    {en(Pub), en(Priv)}.
sign(S, Priv) -> 
    en(crypto:sign(ecdsa, sha256, packer:pack(S), [de(Priv), params()])).
verify_sig(S, Sig, Pub) -> 
    crypto:verify(ecdsa, sha256, packer:pack(S), de(Sig), [de(Pub), params()]).
verify_1(Tx, Pub) ->
    Data = Tx#signed.data,
    (Pub == element(2, Data)) and
    verify_sig(Data, Tx#signed.sig, Pub).
verify_2(Tx, Pub) ->
    Data = Tx#signed.data,
    (Pub == element(3, Data)) and
    verify_sig(Data, Tx#signed.sig2, Pub).
verify_both(Tx, Pub1, Pub2) ->
    X = verify_1(Tx, Pub1),
    Y = verify_2(Tx, Pub1),
    if
        X -> verify_2(Tx, Pub2);
        Y -> verify_1(Tx, Pub2);
        true -> false
    end.
sign_tx(S, Pub, Priv) when element(1, S) == signed ->
    T = S#signed.data,
    V = S#signed.revealed,
    Sig = sign(T, Priv),
    if
        Pub == element(2, T) -> #signed{data=T, sig=Sig, sig2=S#signed.sig2, revealed=V};
        Pub == element(3, T) -> #signed{data=T, sig=S#signed.sig, sig2=Sig, revealed=V}
    end;
sign_tx(S, Pub, Priv) ->
    Sig = sign(S, Priv),
    if
        Pub == element(2, S) -> #signed{data=S, sig=Sig};
        Pub == element(3, S) -> #signed{data=S, sig2=Sig}
    end.
test() ->
    {Pub, Priv} = new_key(),
    {Pub2, Priv2} = new_key(),
    Tx = {"", Pub, Pub2},
    Signed = sign_tx(sign_tx(Tx, Pub, Priv), Pub2, Priv2),
    verify_both(Signed, Pub2, Pub) 
        and verify_both(Signed, Pub, Pub2)
        and not verify_both(Signed, Pub, Pub).