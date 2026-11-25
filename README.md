# linux-script

Script de configuración inicial para Debian que se descarga y ejecuta con un solo comando.

## Qué hace

Primero ejecuta `apt update`. Después muestra un menú con todos los cambios (todos marcados por
defecto) para que elijas cuáles aplicar: escribe los números para marcarlos o desmarcarlos,
`t` para todos, `n` para ninguno, Intro para continuar o `q` para salir. Antes de aplicar nada
muestra un resumen y pide confirmación. Sin terminal interactiva, aplica todos los cambios
excepto la configuración de red.

Antes de modificar un fichero de configuración guarda una copia como `fichero.bak-FECHA`.

Cambios disponibles:

- Pregunta el nombre del equipo (Intro mantiene el actual), lo cambia y lo añade a `/etc/hosts`
  como `127.0.1.1  nombre.home.arpa nombre`.
- Pregunta qué usuario añadir al grupo `sudo`. Propone el primer usuario con carpeta en `/home`
  (pulsa Intro para aceptarlo, escribe otro nombre o `-` para no añadir ninguno).
  Sin terminal interactiva, usa el usuario propuesto.
- Instala `openssh-server`, `curl`, `sudo` y `git` (cada paquete se puede elegir por separado).
- Activa y arranca el servicio SSH.
- Configura las interfaces de red IPv4 en `/etc/network/interfaces` (ifupdown): para cada
  interfaz física elige DHCP, manual (IP/prefijo y puerta de enlace opcional) o desactivada.
  El fichero se reescribe entero y los cambios se aplican al reiniciar el equipo.
- Desactiva el DNS del DHCP añadiendo `nohook resolv.conf` a `/etc/dhcpcd.conf`, para que el
  cliente DHCP (dhcpcd) no sobrescriba `/etc/resolv.conf`.
- Configura los servidores DNS de `/etc/resolv.conf` (propone `1.1.1.1`; se pueden poner varios
  separados por espacios). Conserva las líneas `search`, `domain` y `options`.
- Pone `GRUB_TIMEOUT=0` en `/etc/default/grub` y ejecuta `update-grub`.
- Añade `IP: \4` a `/etc/issue` para que la pantalla de login de la consola muestre la IPv4 del equipo.
- Pone el prompt de `root` en rojo (en `/root/.bashrc`; se puede ejecutar varias veces sin duplicarlo).
- Reinicia el equipo al terminar (siempre es la última opción y no está marcada por defecto;
  espera 10 segundos y se puede cancelar con Ctrl+C).

## Uso

En una instalación nueva de Debian puede que `sudo` y `curl` aún no estén instalados, así que
lo más seguro es hacerse root con `su -` y usar `wget`, que viene por defecto:

```bash
su -
wget -qO- https://raw.githubusercontent.com/surikata3k/linux-script/main/install.sh | bash
```

Si ya tienes `sudo` y `curl`:

```bash
curl -fsSL https://raw.githubusercontent.com/surikata3k/linux-script/main/install.sh | sudo bash
```

Si prefieres revisarlo antes de ejecutarlo:

```bash
wget https://raw.githubusercontent.com/surikata3k/linux-script/main/install.sh
less install.sh
bash install.sh   # como root
```

Al terminar, abre una nueva sesión de root (o ejecuta `source /root/.bashrc`) para ver el prompt en rojo.

## Personalizar

- Para añadir o quitar paquetes o tareas, edita las listas `TAREAS` y `SELECCION` (sección «Menú de selección») de `install.sh`; un paquete se añade como `pkg:nombre`.
- Para añadir otras tareas, crea una función y llámala desde `principal()`.
