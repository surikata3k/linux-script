#!/usr/bin/env bash
#
# install.sh — Configuración inicial de Debian (openssh-server, curl, sudo, git,
#              nombre del equipo, usuario en sudo y prompt de root en rojo)
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

# ---------- Nombre del equipo ----------
DOMINIO_LOCAL="home.arpa"
FICHERO_HOSTS="/etc/hosts"
FICHERO_HOSTNAME="/etc/hostname"
NOMBRE_EQUIPO=""

nombre_valido() {
  # RFC 1123: letras, números y guiones; 1-63 caracteres; sin guion al principio ni al final
  [[ "$1" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]]
}

preguntar_nombre_equipo() {
  local actual respuesta
  actual=$(hostname -s 2>/dev/null || cat "$FICHERO_HOSTNAME")

  if ! { : </dev/tty; } 2>/dev/null; then
    NOMBRE_EQUIPO="$actual"
    aviso "Sin terminal interactiva: se mantiene el nombre del equipo '$NOMBRE_EQUIPO'."
    return
  fi

  while true; do
    printf '¿Nombre del equipo? [%s] (Intro para mantenerlo): ' "$actual" >/dev/tty
    IFS= read -r respuesta </dev/tty || respuesta=""
    respuesta="${respuesta:-$actual}"
    respuesta="${respuesta,,}"   # a minúsculas
    if nombre_valido "$respuesta"; then
      NOMBRE_EQUIPO="$respuesta"
      return
    fi
    error "Nombre no válido: usa solo letras, números y guiones (máx. 63, sin guion al principio ni al final)."
  done
}

configurar_nombre_equipo() {
  local fqdn="${NOMBRE_EQUIPO}.${DOMINIO_LOCAL}"
  local linea="127.0.1.1	${fqdn} ${NOMBRE_EQUIPO}"

  # /etc/hosts: sustituye la línea 127.0.1.1 (la que usa Debian para el nombre del equipo)
  # y la coloca justo después de la de 127.0.0.1; si no existe ésta, la añade al final.
  info "Actualizando $FICHERO_HOSTS: $fqdn"
  touch "$FICHERO_HOSTS"
  awk -v linea="$linea" '
    $1 == "127.0.1.1" { next }
    { print }
    !hecho && $1 == "127.0.0.1" { print linea; hecho = 1 }
    END { if (!hecho) print linea }
  ' "$FICHERO_HOSTS" > "$FICHERO_HOSTS.tmp"
  cat "$FICHERO_HOSTS.tmp" > "$FICHERO_HOSTS"   # conserva permisos y propietario
  rm -f "$FICHERO_HOSTS.tmp"

  if [ "$(hostname -s 2>/dev/null)" = "$NOMBRE_EQUIPO" ]; then
    info "El nombre del equipo ya es '$NOMBRE_EQUIPO'."
    return
  fi

  info "Cambiando el nombre del equipo a '$NOMBRE_EQUIPO'..."
  if command -v hostnamectl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    hostnamectl set-hostname "$NOMBRE_EQUIPO"
  else
    echo "$NOMBRE_EQUIPO" > "$FICHERO_HOSTNAME"
    hostname "$NOMBRE_EQUIPO"
  fi
}

principal() {
  # Las preguntas van al principio para no tener que esperar a que acabe apt
  preguntar_nombre_equipo
  preguntar_usuario_sudo
  configurar_nombre_equipo
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
