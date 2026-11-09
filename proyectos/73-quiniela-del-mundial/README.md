# #73 — Quiniela del Mundial 2026

**Dominio:** Entretenimiento y juegos · Erlang/OTP · cowboy · SSE · UI diseñada en Google Stitch (`design/stitch/`) e integrada en `priv/web`

Quiniela del Mundial FIFA 2026 (48 equipos, 104 partidos) con predicciones, puntos y ranking en vivo.
El servidor decide el cierre de predicciones con su propio reloj; el reloj del cliente se ignora.

## Equipo

| Rol | Integrante |
|---|---|
| Backend (OTP), Frontend, Ops/QA | Andres (proyecto individual) |

## Arranque

```bash
rebar3 compile
rebar3 eunit          # 70 pruebas
rebar3 shell          # http://localhost:8080
```

Nota: en entornos sin acceso a hex.pm, cowboy/cowlib/ranch/recon se colocan en `_checkouts/` (clonados de GitHub).
Desarrollado y probado en OTP 25; objetivo de despliegue OTP 27 (`scripts/aws_setup.sh`).

## Diseno OTP

```
p73_quiniela_del_mundial_sup  (rest_for_one)
├─ pg                      registro/difusion de eventos
├─ p73_almacen             dueno de las tablas ETS (estado durable y reconstruible)
├─ p73_partidos_sup        simple_one_for_one -> p73_partido (gen_statem: programado -> en_vivo -> finalizado)
├─ p73_quinielas_sup       simple_one_for_one -> p73_quiniela (puntos y ranking incremental)
├─ p73_participantes_sup   simple_one_for_one -> p73_participante
├─ p73_poblacion           crea participantes/quinielas
├─ p73_simulador           gen_server del escenario de carga
└─ p73_server              cowboy (API REST, SSE, /metrics, UI estatica)
```

- **Quien reinicia a quien:** `rest_for_one` — si cae `p73_almacen` se reinician todos los hijos posteriores; los procesos de partido/quiniela/participante se reinician individualmente y reconstruyen su estado desde ETS.
- **Cierre de predicciones:** el proceso del partido acepta solo si `estado = programado` y `Ahora < Inicio` segun `p73_reloj` (reloj del servidor). `ts_cliente` se ignora. Al pasar a `en_vivo` es irreversible (doble guarda), aun con relojes desfasados.
- **Puntos:** exacto 3, diferencia de goles 0 (regla simplificada), ganador/empate 1, bono campeon 5. Se recalcula de forma incremental por partido con deltas en cada quiniela; `verificar/1` recalcula desde cero y un oraculo independiente lo contrasta.
- **Ranking:** puntos, exactos, ganadores; los empates comparten posicion.
- **VAR:** un gol anulado revierte el marcador y recalcula los puntos del partido.
- **Difusion:** SSE con limitacion de 200 ms y `max_heap_size` por conexion.

## Supuestos

- Los horarios `inicio` los asigna `p73_torneo`: 16:00 UTC, ventanas de maximo 4 partidos cada 3 h por dia (supuesto de simulacion, no el calendario oficial por sede).
- Equipos, grupos y partidos en `src/p73_mundial2026.erl` (generado con `/home/claude/gen/gen_datos.py` a partir de fuentes publicas); si el calendario oficial difiere en fechas, ajustar ese archivo. Verifica las fechas contra FIFA antes de presentar.
- Reloj simulado por defecto (`config/sys.config`); token admin de ejemplo `demo-token` (cambiar en produccion).

## Cifras verificadas (corrida local, OTP 25)

| Escenario | Resultado |
|---|---|
| 5,000 participantes, 50 quinielas, 104 partidos | ~14 s, 520,000 pronosticos |
| Rafaga: 2,000 pronosticos en los ultimos 60 s | 2000/2000 aceptados |
| Pronosticos tardios (hora exacta de inicio y reloj atrasado 1 h) | 200/200 rechazados |
| Prueba de caos (12 rondas `exit(Pid, kill)`) | 12/12 recuperadas, ranking identico |
| Incremental vs desde cero vs oraculo | 0 diferencias |
| `rebar3 eunit` | 70 pruebas, 0 fallos (3 corridas seguidas) |

## Endpoints

`GET /api/estado` · `/api/partidos` · `/api/partidos/:id` · `/api/quinielas` · `/api/ranking?quiniela=` · `/api/participantes/:id` · `/api/bitacora` · `/api/simulacion` · `/api/eventos` (SSE) · `/metrics` (Prometheus)  
`POST /api/predicciones` · `/api/simulacion` · `/api/falla` · `/api/admin/evento` · `/api/admin/reloj` (los de admin requieren `x-admin-token`).

## Demo (AWS + asciinema)

```bash
scripts/aws_setup.sh        # en una instancia Ubuntu: instala OTP 27 + rebar3 y compila
scripts/demo.sh             # simulacion + caos + prueba de cierre
asciinema rec demo.cast -c scripts/demo.sh
```
Abrir el puerto 8080 en el Security Group de la instancia.

## Entregables y pendientes

- [x] Dominio OTP, API, SSE, metricas, simulacion, caos, pruebas
- [x] UI de Google Stitch (3 pantallas: Dashboard Principal, Detalle de Partido, Bitácora & Alertas) integrada al backend en `priv/web`. Exports originales en `design/stitch/` (`*.html`, `*.png`, `DESIGN.md`); prompt en `design/PROMPT_STITCH.md`. Se conservó el marcado y estilo de Stitch; los datos de ejemplo de los diseños (nombres, pods de Kubernetes, etc.) se reemplazaron por datos reales del backend. Tailwind se compila a `priv/web/tailwind.css` con `design/stitch/tailwind.config.js` y las fuentes (Arimo/Arial, Material Symbols) van locales en `priv/web/fonts/` (sin CDN). Capturas en `docs/capturas/`.
- [ ] Grabar el asciinema en la VM de AWS y publicar el Gist del manual (`docs/MANUAL_USUARIO.md`)
- [ ] Probar en OTP 27 en la VM
