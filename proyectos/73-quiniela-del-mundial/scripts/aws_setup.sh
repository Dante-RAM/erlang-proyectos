#!/usr/bin/env bash
# Ubuntu 22.04/24.04 en AWS. Instala Erlang/OTP 27 (kerl) + rebar3 y compila el proyecto.
set -euo pipefail
sudo apt-get update
sudo apt-get install -y build-essential autoconf m4 libncurses-dev libssl-dev git curl unzip asciinema
if ! command -v erl >/dev/null || ! erl -noshell -eval 'io:format("~s",[erlang:system_info(otp_release)]),halt().' | grep -q '^27'; then
  curl -fsSLo /tmp/kerl https://raw.githubusercontent.com/kerl/kerl/master/kerl && chmod +x /tmp/kerl
  /tmp/kerl build 27.0 27.0 && /tmp/kerl install 27.0 "$HOME/otp-27"
  echo '. $HOME/otp-27/activate' >> "$HOME/.bashrc"; . "$HOME/otp-27/activate"
fi
command -v rebar3 >/dev/null || { curl -fsSLo /tmp/rebar3 https://s3.amazonaws.com/rebar3/rebar3 && sudo install /tmp/rebar3 /usr/local/bin/rebar3; }
rebar3 compile && rebar3 eunit
echo "Listo. Arranque: rebar3 shell   (puerto 8080 abierto en el Security Group)"
