#!/usr/bin/env bash
#
# install.sh — Configuración inicial de Debian (openssh-server, curl, sudo, git,
#              nombre del equipo, usuario en sudo, red, DNS, GRUB y prompt de root en rojo)
#
# Ejecución en una línea:
#   curl -fsSL https://raw.githubusercontent.com/surikata3k/linux-script/main/install.sh | sudo bash
#
# o con wget:
#   wget -qO- https://raw.githubusercontent.com/surikata3k/linux-script/main/install.sh | bash        (como root: su -)
#
set -Eeuo pipefail

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

# ¿Hay una terminal para preguntar? Se usa /dev/tty porque, al ejecutar con
# "wget ... | bash", la entrada estándar es el propio script.
hay_tty() { { : </dev/tty; } 2>/dev/null; }

# ---------- Tareas ----------
actualizar_lista_paquetes() {
  info "Actualizando la lista de paquetes (apt update)..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
}

PAQUETES=()   # se rellena según lo elegido en el menú
instalar_paquetes() {
  [ "${#PAQUETES[@]}" -gt 0 ] || return 0
  info "Instalando: ${PAQUETES[*]}"
  apt-get install -y "${PAQUETES[@]}"
}

activar_ssh() {
  if ! dpkg -s openssh-server >/dev/null 2>&1; then
    aviso "openssh-server no está instalado; no se puede activar el servicio SSH."
    return 0
  fi
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

# Pregunta qué usuario añadir a sudo
USUARIO_SUDO=""
preguntar_usuario_sudo() {
  local propuesto respuesta
  propuesto=$(primer_usuario_home)

  if ! hay_tty; then
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
  if ! getent group sudo >/dev/null; then
    aviso "El grupo sudo no existe; no se puede añadir '$USUARIO_SUDO'."
    return 0
  fi
  if ! command -v sudo >/dev/null 2>&1; then
    aviso "El paquete sudo no está instalado: '$USUARIO_SUDO' estará en el grupo, pero no podrá usar sudo hasta instalarlo."
  fi
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

  if ! hay_tty; then
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

# ---------- Utilidades de red ----------
SELLO=$(date +%Y%m%d-%H%M%S)
copia_seguridad() {   # copia el fichero (si existe) a fichero.bak-FECHA y muestra la ruta
  local f="$1" copia="$1.bak-$SELLO"
  [ -e "$f" ] || return 0
  cp -aL "$f" "$copia"
  info "Copia de seguridad: $copia"
}

ip_valida() {   # IPv4 a.b.c.d con cada número entre 0 y 255
  local IFS=. o
  [[ "$1" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || return 1
  for o in $1; do [ "$o" -le 255 ] || return 1; done
}

ip_cidr_valida() {   # a.b.c.d/prefijo
  [[ "$1" == */* ]] || return 1
  local p="${1#*/}"
  ip_valida "${1%/*}" && [[ "$p" =~ ^[0-9]{1,2}$ ]] && [ "$p" -ge 1 ] && [ "$p" -le 32 ]
}

mascara_a_prefijo() {   # 255.255.255.0 -> 24
  local IFS=. o n=0 b
  for o in $1; do
    for b in 128 64 32 16 8 4 2 1; do
      [ $((o & b)) -ne 0 ] && n=$((n + 1))
    done
  done
  echo "$n"
}

# ---------- Desactivar el DNS del DHCP (dhcpcd) ----------
FICHERO_DHCPCD="/etc/dhcpcd.conf"
desactivar_dns_dhcp() {
  info "Desactivando el DNS del DHCP en $FICHERO_DHCPCD (nohook resolv.conf)..."
  if [ -f "$FICHERO_DHCPCD" ] && grep -qE '^[[:space:]]*nohook[[:space:]].*resolv\.conf' "$FICHERO_DHCPCD"; then
    info "$FICHERO_DHCPCD ya contiene 'nohook resolv.conf'."
  else
    copia_seguridad "$FICHERO_DHCPCD"
    printf '\n# linux-script: no sobrescribir /etc/resolv.conf con los DNS del DHCP\nnohook resolv.conf\n' >> "$FICHERO_DHCPCD"
  fi
  if ! command -v dhcpcd >/dev/null 2>&1; then
    aviso "dhcpcd no está instalado: esta opción solo tiene efecto si el cliente DHCP es dhcpcd."
  fi
}

# ---------- DNS en /etc/resolv.conf ----------
FICHERO_RESOLV="/etc/resolv.conf"
DNS_POR_DEFECTO="1.1.1.1"
DNS_SERVIDORES=()

dns_actuales() {
  [ -f "$FICHERO_RESOLV" ] && awk '$1 == "nameserver" { printf "%s%s", s, $2; s = " " }' "$FICHERO_RESOLV" || true
}

preguntar_dns() {
  local respuesta d ok
  if ! hay_tty; then
    DNS_SERVIDORES=("$DNS_POR_DEFECTO")
    aviso "Sin terminal interactiva: se usará el DNS $DNS_POR_DEFECTO."
    return
  fi
  printf 'Servidores DNS actuales: %s\n' "$(dns_actuales)" >/dev/tty
  while true; do
    printf 'Servidores DNS separados por espacios [%s]: ' "$DNS_POR_DEFECTO" >/dev/tty
    IFS= read -r respuesta </dev/tty || respuesta=""
    respuesta="${respuesta:-$DNS_POR_DEFECTO}"
    read -r -a DNS_SERVIDORES <<< "${respuesta//,/ }"
    [ "${#DNS_SERVIDORES[@]}" -gt 0 ] || { error "Indica al menos un servidor DNS."; continue; }
    ok=1
    for d in "${DNS_SERVIDORES[@]}"; do
      ip_valida "$d" || { error "Dirección IPv4 no válida: $d"; ok=0; }
    done
    if [ "${#DNS_SERVIDORES[@]}" -gt 3 ]; then
      aviso "Linux solo usa los 3 primeros servidores DNS."
    fi
    [ "$ok" = 1 ] && return
  done
}

configurar_dns() {
  local d otras
  info "Configurando $FICHERO_RESOLV: ${DNS_SERVIDORES[*]}"
  copia_seguridad "$FICHERO_RESOLV"
  # Se conservan las líneas search/domain/options que hubiera
  otras=$( [ -f "$FICHERO_RESOLV" ] && grep -E '^[[:space:]]*(search|domain|options)[[:space:]]' "$FICHERO_RESOLV" || true)
  if [ -L "$FICHERO_RESOLV" ]; then
    aviso "$FICHERO_RESOLV era un enlace a $(readlink "$FICHERO_RESOLV"); se sustituye por un fichero normal."
    rm -f "$FICHERO_RESOLV"
  fi
  {
    echo "# Generado por linux-script ($SELLO)"
    [ -n "$otras" ] && echo "$otras"
    for d in "${DNS_SERVIDORES[@]}"; do echo "nameserver $d"; done
  } > "$FICHERO_RESOLV"
}

# ---------- Interfaces de red IPv4 (ifupdown: /etc/network/interfaces) ----------
FICHERO_INTERFACES="/etc/network/interfaces"
DIR_SYS_NET="/sys/class/net"
INTERFACES=()
declare -A RED_METODO=() RED_IP=() RED_GW=()   # metodo: dhcp | static | off

listar_interfaces() {   # interfaces físicas (con dispositivo); si no hay, todas menos lo
  local d n fisicas=() todas=()
  for d in "$DIR_SYS_NET"/*; do
    n=$(basename "$d")
    [ "$n" = lo ] && continue
    todas+=("$n")
    [ -e "$d/device" ] && fisicas+=("$n")
  done
  if [ "${#fisicas[@]}" -gt 0 ]; then printf '%s\n' "${fisicas[@]}"
  elif [ "${#todas[@]}" -gt 0 ]; then printf '%s\n' "${todas[@]}"; fi
}

# Lee la configuración IPv4 actual de una interfaz: "metodo ip/prefijo puerta"
config_actual_interfaz() {
  [ -f "$FICHERO_INTERFACES" ] || { echo "off - -"; return; }
  awk -v ifc="$1" '
    $1 == "iface" { dentro = 0; if ($2 == ifc && $3 == "inet") { dentro = 1; metodo = $4 }; next }
    $1 ~ /^(auto|allow-|source|mapping)/ { dentro = 0; next }
    dentro && $1 == "address" { ip = $2 }
    dentro && $1 == "netmask" { mascara = $2 }
    dentro && $1 == "gateway" { gw = $2 }
    END {
      if (metodo == "") metodo = "off"
      print metodo, (ip == "" ? "-" : ip), (gw == "" ? "-" : gw), (mascara == "" ? "-" : mascara)
    }
  ' "$FICHERO_INTERFACES"
}

preguntar_red() {
  local ifc metodo ip gw mascara def respuesta
  if ! hay_tty; then
    aviso "Sin terminal interactiva: no se modifica la configuración de red."
    return
  fi
  mapfile -t INTERFACES < <(listar_interfaces)
  if [ "${#INTERFACES[@]}" -eq 0 ]; then
    aviso "No se han encontrado interfaces de red."
    return
  fi
  for ifc in "${INTERFACES[@]}"; do
    read -r metodo ip gw mascara <<< "$(config_actual_interfaz "$ifc")"
    [ "$ip" != "-" ] && [[ "$ip" != */* ]] && [ "$mascara" != "-" ] && ip="$ip/$(mascara_a_prefijo "$mascara")"
    [ "$ip" = "-" ] && ip=""
    [ "$gw" = "-" ] && gw=""
    case "$metodo" in
      static) def=m ;;
      off|manual) def=x ;;
      *) def=d ;;
    esac

    while true; do
      printf '\nInterfaz %s (actual: %s%s)\n' "$ifc" "$metodo" "${ip:+ $ip}" >/dev/tty
      printf '  [d] DHCP, [m] manual (IP fija), [x] desactivar [%s]: ' "$def" >/dev/tty
      IFS= read -r respuesta </dev/tty || respuesta=""
      respuesta="${respuesta:-$def}"
      case "${respuesta,,}" in
        d|m|x) def="${respuesta,,}"; break ;;
        *) error "Opción no válida: $respuesta" ;;
      esac
    done
    if [ "$def" = m ]; then
      while true; do
        printf '  IP/prefijo (p. ej. 192.168.1.10/24)%s: ' "${ip:+ [$ip]}" >/dev/tty
        IFS= read -r respuesta </dev/tty || respuesta=""
        respuesta="${respuesta:-$ip}"
        ip_cidr_valida "$respuesta" && { ip="$respuesta"; break; }
        error "Formato no válido. Usa IP/prefijo, por ejemplo 192.168.1.10/24."
      done
      while true; do
        printf '  Puerta de enlace (Intro = %s, "-" = ninguna): ' "${gw:-ninguna}" >/dev/tty
        IFS= read -r respuesta </dev/tty || respuesta=""
        respuesta="${respuesta:-${gw:--}}"
        [ "$respuesta" = "-" ] && { gw=""; break; }
        ip_valida "$respuesta" && { gw="$respuesta"; break; }
        error "Dirección IPv4 no válida: $respuesta"
      done
    fi

    case "$def" in
      d) RED_METODO[$ifc]=dhcp ;;
      m) RED_METODO[$ifc]=static; RED_IP[$ifc]="$ip"; RED_GW[$ifc]="$gw" ;;
      x) RED_METODO[$ifc]=off ;;
    esac
  done
}

resumen_red() {
  local ifc
  for ifc in "${INTERFACES[@]}"; do
    case "${RED_METODO[$ifc]}" in
      dhcp)   echo "      $ifc: DHCP" ;;
      static) echo "      $ifc: manual ${RED_IP[$ifc]}${RED_GW[$ifc]:+, puerta de enlace ${RED_GW[$ifc]}}" ;;
      off)    echo "      $ifc: desactivada" ;;
    esac
  done
}

configurar_red() {
  local ifc
  [ "${#INTERFACES[@]}" -gt 0 ] || return 0
  info "Escribiendo $FICHERO_INTERFACES..."
  copia_seguridad "$FICHERO_INTERFACES"
  mkdir -p "$(dirname "$FICHERO_INTERFACES")"
  {
    echo "# Generado por linux-script ($SELLO)"
    echo
    [ -d "$(dirname "$FICHERO_INTERFACES")/interfaces.d" ] && echo "source $(dirname "$FICHERO_INTERFACES")/interfaces.d/*" && echo
    echo "auto lo"
    echo "iface lo inet loopback"
    for ifc in "${INTERFACES[@]}"; do
      echo
      case "${RED_METODO[$ifc]}" in
        dhcp)
          echo "# $ifc: DHCP"
          echo "allow-hotplug $ifc"
          echo "iface $ifc inet dhcp" ;;
        static)
          echo "# $ifc: IP fija"
          echo "auto $ifc"
          echo "iface $ifc inet static"
          echo "    address ${RED_IP[$ifc]}"
          if [ -n "${RED_GW[$ifc]}" ]; then echo "    gateway ${RED_GW[$ifc]}"; fi ;;
        off)
          echo "# $ifc: desactivada (sin configuración)" ;;
      esac
    done
  } > "$FICHERO_INTERFACES"
  aviso "La nueva configuración de red se aplicará al reiniciar el equipo."
}

# ---------- GRUB ----------
FICHERO_GRUB="/etc/default/grub"
GRUB_TIMEOUT_NUEVO=0
configurar_grub() {
  if [ ! -f "$FICHERO_GRUB" ]; then
    aviso "No existe $FICHERO_GRUB; no se modifica GRUB."
    return 0
  fi
  info "Poniendo GRUB_TIMEOUT=$GRUB_TIMEOUT_NUEVO en $FICHERO_GRUB..."
  copia_seguridad "$FICHERO_GRUB"
  if grep -qE '^[[:space:]]*GRUB_TIMEOUT=' "$FICHERO_GRUB"; then
    sed -i -E "s/^[[:space:]]*GRUB_TIMEOUT=.*/GRUB_TIMEOUT=$GRUB_TIMEOUT_NUEVO/" "$FICHERO_GRUB"
  else
    echo "GRUB_TIMEOUT=$GRUB_TIMEOUT_NUEVO" >> "$FICHERO_GRUB"
  fi
  if command -v update-grub >/dev/null 2>&1; then
    info "Ejecutando update-grub..."
    update-grub
  else
    aviso "update-grub no está disponible; ejecútalo cuando GRUB esté instalado."
  fi
}

# ---------- Menú de selección ----------
# Cada cambio tiene un identificador, una descripción y si está marcado (1) o no (0).
TAREAS=(nombre pkg:openssh-server pkg:curl pkg:sudo pkg:git ssh usuario_sudo red dns_dhcp dns grub prompt)
SELECCION=(1   1                  1        1        1       1   1            1   1        1   1    1)
descripcion_tarea() {
  case "$1" in
    nombre)       echo "Cambiar el nombre del equipo y añadirlo a /etc/hosts como nombre.${DOMINIO_LOCAL}" ;;
    pkg:*)        local p="${1#pkg:}"
                  if dpkg -s "$p" >/dev/null 2>&1; then echo "Instalar $p (ya instalado)"
                  else echo "Instalar $p"; fi ;;
    ssh)          echo "Activar y arrancar el servicio SSH" ;;
    usuario_sudo) echo "Añadir un usuario al grupo sudo" ;;
    red)          echo "Configurar las interfaces de red IPv4 (DHCP, manual o desactivada)" ;;
    dns_dhcp)     echo "Desactivar el DNS del DHCP (nohook resolv.conf en $FICHERO_DHCPCD)" ;;
    dns)          echo "Configurar los servidores DNS de $FICHERO_RESOLV (por defecto $DNS_POR_DEFECTO)" ;;
    grub)         local t; t=$( [ -f "$FICHERO_GRUB" ] && sed -n -E 's/^[[:space:]]*GRUB_TIMEOUT=//p' "$FICHERO_GRUB" | tail -1 )
                  echo "Poner GRUB_TIMEOUT=$GRUB_TIMEOUT_NUEVO en $FICHERO_GRUB (actual: ${t:-?}) y ejecutar update-grub" ;;
    prompt)       echo "Poner el prompt de root en rojo" ;;
  esac
}
seleccionada() {   # ¿está marcada la tarea con este identificador?
  local i
  for i in "${!TAREAS[@]}"; do
    [ "${TAREAS[$i]}" = "$1" ] && { [ "${SELECCION[$i]}" = 1 ]; return; }
  done
  return 1
}

mostrar_menu() {
  local i marca
  {
    echo
    echo "Cambios que puede hacer el script:"
    for i in "${!TAREAS[@]}"; do
      if [ "${SELECCION[$i]}" = 1 ]; then marca="[x]"; else marca="[ ]"; fi
      printf '  %d) %s %s\n' "$((i + 1))" "$marca" "$(descripcion_tarea "${TAREAS[$i]}")"
    done
    echo
    echo "Escribe los números para marcar/desmarcar (p. ej.: 2 5), \"t\" = todos, \"n\" = ninguno,"
    echo "Intro = continuar, \"q\" = salir sin hacer nada."
  } >/dev/tty
}

elegir_tareas() {
  local respuesta n i
  if ! hay_tty; then
    aviso "Sin terminal interactiva: se aplicarán todos los cambios."
    return
  fi
  while true; do
    mostrar_menu
    printf '> ' >/dev/tty
    IFS= read -r respuesta </dev/tty || respuesta=""
    case "$respuesta" in
      "")      return ;;
      q|Q)     info "Saliendo sin hacer cambios."; exit 0 ;;
      t|T)     for i in "${!SELECCION[@]}"; do SELECCION[$i]=1; done ;;
      n|N)     for i in "${!SELECCION[@]}"; do SELECCION[$i]=0; done ;;
      *)       for n in ${respuesta//,/ }; do
                 if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le "${#TAREAS[@]}" ]; then
                   i=$((n - 1)); SELECCION[$i]=$((1 - SELECCION[$i]))
                 else
                   error "Opción no válida: $n"
                 fi
               done ;;
    esac
  done
}

confirmar() {
  local respuesta
  hay_tty || return 0
  {
    echo
    echo "Se va a aplicar:"
    seleccionada nombre       && echo "  - Nombre del equipo: $NOMBRE_EQUIPO ($NOMBRE_EQUIPO.$DOMINIO_LOCAL en $FICHERO_HOSTS)"
    [ "${#PAQUETES[@]}" -gt 0 ] && echo "  - Instalar: ${PAQUETES[*]}"
    seleccionada ssh          && echo "  - Activar y arrancar el servicio SSH"
    seleccionada usuario_sudo && [ -n "$USUARIO_SUDO" ] && echo "  - Añadir '$USUARIO_SUDO' al grupo sudo"
    if seleccionada red && [ "${#INTERFACES[@]}" -gt 0 ]; then
      echo "  - Red IPv4 ($FICHERO_INTERFACES, se aplica al reiniciar):"
      resumen_red
    fi
    seleccionada dns_dhcp     && echo "  - Añadir 'nohook resolv.conf' a $FICHERO_DHCPCD"
    seleccionada dns          && echo "  - DNS en $FICHERO_RESOLV: ${DNS_SERVIDORES[*]}"
    seleccionada grub         && echo "  - GRUB_TIMEOUT=$GRUB_TIMEOUT_NUEVO y update-grub"
    seleccionada prompt       && echo "  - Prompt de root en rojo"
    if seleccionada dns && ! seleccionada dns_dhcp && hay_dhcp; then
      echo "  ! Aviso: alguna interfaz usa DHCP y no has marcado desactivar su DNS:"
      echo "    el cliente DHCP podría sobrescribir $FICHERO_RESOLV."
    fi
    printf '¿Continuar? [S/n]: '
  } >/dev/tty
  IFS= read -r respuesta </dev/tty || respuesta=""
  case "$respuesta" in
    ""|s|S|si|SI|sí|Sí|y|Y) return 0 ;;
    *) info "Cancelado. No se ha hecho ningún cambio."; exit 0 ;;
  esac
}

# Ejecuta la función $2 si la tarea $1 está marcada. Se usa "if" y no "&&"
# para que "set -e" siga deteniendo el script si la función falla.
si_marcada() {
  if seleccionada "$1"; then "$2"; fi
}

principal() {
  local t
  elegir_tareas

  PAQUETES=()
  for t in "${TAREAS[@]}"; do
    [[ "$t" == pkg:* ]] && seleccionada "$t" && PAQUETES+=("${t#pkg:}")
  done
  if [[ " ${SELECCION[*]} " != *" 1 "* ]]; then
    info "No has seleccionado ningún cambio."
    exit 0
  fi

  # Las preguntas van antes de instalar para no tener que esperar a que acabe apt
  si_marcada nombre       preguntar_nombre_equipo
  si_marcada usuario_sudo preguntar_usuario_sudo
  si_marcada red          preguntar_red
  si_marcada dns          preguntar_dns
  confirmar

  si_marcada nombre       configurar_nombre_equipo
  instalar_paquetes
  si_marcada usuario_sudo anadir_usuario_sudo
  si_marcada ssh          activar_ssh
  si_marcada dns_dhcp     desactivar_dns_dhcp
  si_marcada dns          configurar_dns
  si_marcada red          configurar_red   # al final: no se aplica hasta reiniciar
  si_marcada grub         configurar_grub
  si_marcada prompt       prompt_root_rojo
  return 0
}

# ¿Alguna interfaz usa DHCP (según lo elegido o, si no se configura la red, el fichero actual)?
hay_dhcp() {
  local ifc
  if seleccionada red && [ "${#INTERFACES[@]}" -gt 0 ]; then
    for ifc in "${INTERFACES[@]}"; do [ "${RED_METODO[$ifc]}" = dhcp ] && return 0; done
    return 1
  fi
  [ -f "$FICHERO_INTERFACES" ] && grep -qE '^[[:space:]]*iface[[:space:]].*inet[[:space:]]+dhcp' "$FICHERO_INTERFACES"
}

main() {
  comprobar_root
  comprobar_debian
  actualizar_lista_paquetes
  principal
  info "¡Terminado!"
  if seleccionada prompt; then
    info "Abre una nueva sesión de root (o ejecuta: source /root/.bashrc) para ver el prompt rojo."
  fi
}

main "$@"
