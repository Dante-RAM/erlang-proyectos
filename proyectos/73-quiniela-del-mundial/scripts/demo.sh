#!/usr/bin/env bash
# Demo para asciinema: requiere el nodo corriendo (rebar3 shell) en localhost:8080.
H=${HOST:-localhost:8080}; T=demo-token
say(){ echo; echo "### $*"; sleep 1; }
say "Estado inicial"; curl -s $H/api/estado; echo
say "Simulacion: 300 participantes, 10 quinielas, 24 partidos, con caos y VAR"
curl -s -X POST $H/api/simulacion -H "x-admin-token: $T" -d '{"participantes":300,"quinielas":10,"partidos":24}'; echo
until curl -s $H/api/simulacion | grep -q '"estado":"terminado"'; do sleep 2; done
say "Reporte (caos, consistencia, rafaga)"; curl -s $H/api/simulacion | head -c 1500; echo
say "Metricas Prometheus"; curl -s $H/metrics | head -20
