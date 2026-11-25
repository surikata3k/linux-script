#!/usr/bin/env bash
#
# install.sh — Configuración inicial de Debian (openssh-server, curl, sudo, git,
#              usuario en sudo y prompt de root en rojo)
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

# Primer usuario real (que existe en el sistema) con carpeta en /home
primer_usuario_home() {
  local dir usuario
  for dir in /home/*/; do
    [ -d "$dir" ] || continue
    usuario=$(basename "$dir")
    if getent passwd "$usuario" >/dev/null; then
      echo "$usuario"
      return
    fi
  done
}

# Pregunta qué usuario añadir a sudo. Se lee de /dev/tty porque, al ejecutar
# con "wget ... | bash", la entrada estándar es el propio script.
USUARIO_SUDO=""
preguntar_usuario_sudo() {
  local propuesto respuesta
  propuesto=$(primer_usuario_home)

  if ! { : </dev/tty; } 2>/dev/null; then
    USUARIO_SUDO="$propuesto"
    if [ -n "$USUARIO_SUDO" ]; then
      aviso "Sin terminal interactiva: se usará el usuario propuesto '$USUARIO_SUDO'."
    else
      aviso "Sin terminal interactiva y sin usuarios en /home: no se añadirá nadie a sudo."
    fi
    return
  fi

  while true; do
    if [ -n "$propuesto" ]; then
      printf '¿Qué usuario quieres añadir a sudo? [%s] (escribe "-" para ninguno): ' "$propuesto" >/dev/tty
    else
      printf '¿Qué usuario quieres añadir a sudo? (Intro para ninguno): ' >/dev/tty
    fi
    IFS= read -r respuesta </dev/tty || respuesta=""
    respuesta="${respuesta:-$propuesto}"

    if [ -z "$respuesta" ] || [ "$respuesta" = "-" ]; then
      USUARIO_SUDO=""
      aviso "No se añadirá ningún usuario a sudo."
      return
    fi
    if getent passwd "$respuesta" >/dev/null; then
      USUARIO_SUDO="$respuesta"
      return
    fi
    error "El usuario '$respuesta' no existe. Inténtalo de nuevo."
  done
}

anadir_usuario_sudo() {
  [ -n "$USUARIO_SUDO" ] || return 0
  if id -nG "$USUARIO_SUDO" | tr ' ' '\n' | grep -qx sudo; then
    info "El usuario '$USUARIO_SUDO' ya está en el grupo sudo."
  else
    info "Añadiendo '$USUARIO_SUDO' al grupo sudo..."
    usermod -aG sudo "$USUARIO_SUDO"
    aviso "'$USUARIO_SUDO' tendrá permisos de sudo a partir de su próximo inicio de sesión."
  fi
}

principal() {
  preguntar_usuario_sudo   # se pregunta al principio para no esperar a que acabe apt
  instalar_paquetes
  anadir_usuario_sudo
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
