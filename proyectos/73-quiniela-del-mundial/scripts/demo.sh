#!/usr/bin/env bash
# Demo de terminal para asciinema (proyecto 73, Quiniela del Mundial).
#   asciinema rec demo.cast -c scripts/demo.sh
# Corre las pruebas, arranca el nodo si no responde y recorre el escenario del enunciado:
# 5,000 participantes, 50 quinielas, 64 partidos (4 simultaneos), rafaga de 2,000, VAR, caos.
cd "$(dirname "$0")/.." || exit 1
PUERTO=$(grep -oP '\{port,\s*\K[0-9]+' config/sys.config); H=localhost:$PUERTO; T=demo-token
say(){ echo; printf '\033[1;36m### %s\033[0m\n' "$*"; sleep 2; }
py(){ python3 -c "import json,sys; d=json.load(sys.stdin); $1"; }

say "1. Pruebas automaticas (EUnit)"
rebar3 eunit 2>&1 | grep -aE "tests,|Failed"

say "2. Nodo OTP en el puerto $PUERTO"
if ! curl -s -o /dev/null "$H/api/estado"; then
  rebar3 compile >/dev/null 2>&1
  (nohup setsid erl -noshell -config config/sys.config -pa _build/default/lib/*/ebin \
     -eval '{ok,_}=application:ensure_all_started(p73_quiniela_del_mundial)' > /tmp/nodo.log 2>&1 < /dev/null &)
  until curl -s -o /dev/null "$H/api/estado"; do sleep 1; done
fi
curl -s "$H/api/diagnostico" | py 'print("nodo", d["nodo"], " OTP", d["otp"], " procesos", d["procesos"], " memoria", d["memoria_mb"]["total"], "MB")'

say "3. Escenario del enunciado: 5000 participantes, 50 quinielas, 64 partidos, VAR y caos"
curl -s -X POST "$H/api/simulacion" -H "x-admin-token: $T" -H 'content-type: application/json' \
  -d '{"participantes":5000,"quinielas":50,"partidos":64}' | py 'print("aceptada:", d["aceptada"], d["opciones"])'
until curl -s "$H/api/simulacion" | grep -q '"estado":"terminado"'; do
  curl -s "$H/api/simulacion" | py 'p=d.get("progreso",{}); print("  ", p.get("fase",""), " ", p.get("partidos_hechos",0), "/", p.get("partidos_total",0), "partidos     ", end="\r", flush=True)'
  sleep 1
done
echo
curl -s "$H/api/simulacion" > /tmp/reporte.json

say "4. Rafaga de 2,000 pronosticos en los 60 s previos y casos limite del cierre"
py 'r=d["reporte"]["rafaga"]; b=r["borde_inicio_menos_1ms"]; e=r["tarde_en_inicio_exacto"]; a=r["tarde_con_reloj_atrasado"]
print("rafaga en el ultimo minuto: %d/%d aceptadas en %d ms (%d por s)" % (r["aceptadas"], r["intentos"], r["duracion_real_ms"], r["tasa_por_s"]))
print("1 ms antes del inicio:      %d/%d aceptadas" % (b["aceptadas"], b["intentos"]))
print("en el inicio exacto:        %d/%d rechazadas" % (e["rechazadas"], e["intentos"]))
print("cliente con reloj atrasado: %d/%d rechazadas" % (a["rechazadas"], a["intentos"]))' < /tmp/reporte.json

say "5. 4 partidos en simultaneo, VAR y reglas distintas por quiniela"
py 'r=d["reporte"]; m=r["metricas"]
print("partidos simultaneos (max):", r["simultaneos_max"])
print("goles anulados por VAR:", m["anulaciones_var"], "| recalculos de quiniela:", m["recalculos_quiniela"])
print("pronosticos aceptados:", m["predicciones_aceptadas"], "| rechazados por tarde:", m["predicciones_rechazadas"])' < /tmp/reporte.json
curl -s "$H/api/quinielas" | py 'qs=d["quinielas"][:3]
[print(" ", q["id"], q["nombre"], "->", {k: q["reglas"][k] for k in ("exacto","diferencia","ganador")}) for q in qs]'

say "6. Recalculo completo tras la correccion: incremental vs desde cero vs oraculo"
py 'print(json.dumps(d["reporte"]["consistencia"], indent=2))' < /tmp/reporte.json

say "7. Caos: procesos matados durante el torneo y su recuperacion"
py 'c=d["reporte"]["caos"]
for x in c[:4]: print("  ronda %d: quiniela %s revivio en %s ms, ranking identico=%s; partido %s identico=%s" % (x["n"], x["quiniela_muerta"], x["quiniela_recuperada_ms"], x["ranking_identico_tras_reiniciar"], x["partido_muerto"], x["partido_estado_identico"]))
print("  ...", len(c), "rondas, fallas inyectadas:", d["reporte"]["metricas"]["fallas_inyectadas"])' < /tmp/reporte.json
curl -s -X POST "$H/api/falla" -H "x-admin-token: $T" -H 'content-type: application/json' -d '{"objetivo":"quiniela"}' | py 'print("  falla manual:", d)'

say "8. Pronostico por HTTP: partido abierto (200) y partido ya jugado (409)"
curl -s -w '  -> HTTP %{http_code}\n' -X POST "$H/api/predicciones" -H 'content-type: application/json' \
  -d '{"participante":"U0001","partido":1001,"local":2,"visitante":1}'
curl -s -w '  -> HTTP %{http_code}\n' -X POST "$H/api/predicciones" -H 'content-type: application/json' \
  -d '{"participante":"U0001","partido":1,"local":2,"visitante":1,"ts_cliente":1}'

say "9. WebSocket /ws: pronostico por el socket"
python3 - "$PUERTO" <<'PY'
import base64, json, os, socket, struct, sys
s = socket.create_connection(("localhost", int(sys.argv[1])))
s.sendall(b"GET /ws?quiniela=Q01 HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
          b"Sec-WebSocket-Key: " + base64.b64encode(os.urandom(16)) + b"\r\nSec-WebSocket-Version: 13\r\n\r\n")
buf = b""
while b"\r\n\r\n" not in buf: buf += s.recv(4096)
print("  ", buf.split(b"\r\n")[0].decode())
buf = buf.split(b"\r\n\r\n", 1)[1]
def leer():
    global buf
    while True:
        if len(buf) >= 2:
            n, i = buf[1] & 127, 2
            if n == 126 and len(buf) >= 4: n, i = struct.unpack(">H", buf[2:4])[0], 4
            if len(buf) >= i + n: t, buf = buf[i:i+n], buf[i+n:]; return json.loads(t)
        buf += s.recv(4096)
def enviar(obj):
    d, m = json.dumps(obj).encode(), os.urandom(4)
    s.sendall(bytes([0x81, 0x80 | len(d)]) + m + bytes(b ^ m[i % 4] for i, b in enumerate(d)))
print("  <-", leer())
enviar({"tipo": "pronostico", "participante": "U0002", "partido": 1002, "local": 1, "visitante": 1})
while True:
    r = leer()
    if r.get("tipo") == "pronostico_resultado": print("  <-", r); break
PY

say "10. Metricas Prometheus (/metrics) y diagnostico con recon"
curl -s "$H/metrics" | grep -E "^p73_(predicciones|anulaciones|fallas|procesos)" | head -8
curl -s "$H/api/diagnostico" | py 'print("top memoria:", [(p["proceso"], p["valor"]) for p in d["top_memoria"][:3]])'

say "Fin de la demo. UI en http://localhost:$PUERTO"
