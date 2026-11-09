#!/usr/bin/env bash
# Construye el release OTP (relx) y lo instala como servicio systemd en /opt/p73.
# Uso: sudo scripts/instalar_servicio.sh        (desde la carpeta del proyecto)
# Despues: systemctl status p73-quiniela | journalctl -u p73-quiniela -f
set -euo pipefail
cd "$(dirname "$0")/.."
USUARIO_BUILD="${SUDO_USER:-$USER}"

sudo -u "$USUARIO_BUILD" rebar3 release
id p73 >/dev/null 2>&1 || useradd --system --home /opt/p73 --shell /usr/sbin/nologin p73

systemctl stop p73-quiniela 2>/dev/null || true
rm -rf /opt/p73
cp -r _build/default/rel/p73_quiniela_del_mundial /opt/p73
chown -R p73:p73 /opt/p73

cp deploy/p73-quiniela.service /etc/systemd/system/p73-quiniela.service
systemctl daemon-reload
systemctl enable --now p73-quiniela

PUERTO=$(grep -oP '\{port,\s*\K[0-9]+' config/sys.config)
for _ in $(seq 1 20); do
  curl -s -o /dev/null "http://localhost:${PUERTO}/api/estado" && break
  sleep 1
done
systemctl --no-pager status p73-quiniela | head -5
echo "Quiniela en http://localhost:${PUERTO}  (diagnostico: /api/diagnostico, metricas: /metrics, WebSocket: /ws)"
