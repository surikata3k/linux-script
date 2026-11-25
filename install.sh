#!/usr/bin/env bash
#
# install.sh — Plantilla de script para Debian
#
# Ejecución en una línea:
#   curl -fsSL https://raw.githubusercontent.com/surikata3k/linux-script/main/install.sh | sudo bash
#
# o con wget:
#   wget -qO- https://raw.githubusercontent.com/surikata3k/linux-script/main/install.sh | sudo bash
#
set -euo pipefail

# ---------- Colores y mensajes ----------
if [ -t 1 ]; then
  VERDE='\033[0;32m'; AMARILLO='\033[1;33m'; ROJO='\033[0;31m'; NC='\033[0m'
else
  VERDE=''; AMARILLO=''; ROJO=''; NC=''
fi
info()  { echo -e "${VERDE}[INFO]${NC}  $*"; }
aviso() { echo -e "${AMARILLO}[AVISO]${NC} $*"; }
error() { echo -e "${ROJO}[ERROR]${NC} $*" >&2; }

trap 'error "Fallo en la línea $LINENO. Abortando."' ERR

# ---------- Comprobaciones previas ----------
comprobar_root() {
  if [ "$(id -u)" -ne 0 ]; then
    error "Este script debe ejecutarse como root (usa sudo)."
    exit 1
  fi
}

comprobar_debian() {
  if [ ! -f /etc/debian_version ]; then
    error "Este script solo está pensado para Debian o derivadas."
    exit 1
  fi
  # shellcheck disable=SC1091
  . /etc/os-release
  info "Sistema detectado: ${PRETTY_NAME:-Debian $(cat /etc/debian_version)}"
}

# ---------- Tu lógica aquí ----------
principal() {
  info "Actualizando la lista de paquetes..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y

  # TODO: añade aquí lo que quieras que haga el script. Ejemplos:
  # apt-get install -y curl git vim
  # systemctl enable --now ssh

  info "Aquí va tu código."
}

main() {
  comprobar_root
  comprobar_debian
  principal
  info "¡Terminado!"
}

main "$@"
