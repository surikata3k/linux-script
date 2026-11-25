#!/usr/bin/env bash
#
# install.sh — Configuración inicial de Debian (openssh-server, curl, sudo, git y prompt de root en rojo)
#
# Ejecución en una línea:
#   curl -fsSL https://raw.githubusercontent.com/surikata3k/linux-script/main/install.sh | sudo bash
#
# o con wget:
#   wget -qO- https://raw.githubusercontent.com/surikata3k/linux-script/main/install.sh | bash        (como root: su -)
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
    error "Este script debe ejecutarse como root (usa su - o sudo)."
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

# ---------- Configuración ----------
PAQUETES=(openssh-server curl sudo git)

# ---------- Tareas ----------
instalar_paquetes() {
  info "Actualizando la lista de paquetes..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y

  info "Instalando: ${PAQUETES[*]}"
  apt-get install -y "${PAQUETES[@]}"
}

activar_ssh() {
  if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    info "Activando el servicio SSH..."
    systemctl enable --now ssh
  else
    aviso "systemd no está activo; no se ha podido arrancar el servicio SSH."
  fi
}

prompt_root_rojo() {
  local bashrc=/root/.bashrc
  local inicio='# >>> linux-script: prompt root rojo >>>'
  local fin='# <<< linux-script: prompt root rojo <<<'

  info "Configurando el prompt de root en rojo..."
  touch "$bashrc"
  # Elimina un bloque anterior para no duplicarlo si el script se ejecuta varias veces
  sed -i "/^${inicio}\$/,/^${fin}\$/d" "$bashrc"

  cat >> "$bashrc" <<EOF
${inicio}
PS1='\${debian_chroot:+(\$debian_chroot)}\[\e[1;31m\]\u@\h\[\e[0m\]:\[\e[1;34m\]\w\[\e[1;31m\]\\\$\[\e[0m\] '
${fin}
EOF
}

principal() {
  instalar_paquetes
  activar_ssh
  prompt_root_rojo
}

main() {
  comprobar_root
  comprobar_debian
  principal
  info "¡Terminado! Abre una nueva sesión de root (o ejecuta: source /root/.bashrc) para ver el prompt rojo."
}

main "$@"
