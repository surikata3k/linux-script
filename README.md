# linux-script

Script de configuración inicial para Debian que se descarga y ejecuta con un solo comando.

## Qué hace

- Instala `openssh-server`, `curl`, `sudo` y `git`.
- Activa y arranca el servicio SSH.
- Pone el prompt de `root` en rojo (en `/root/.bashrc`; se puede ejecutar varias veces sin duplicarlo).

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

- Para añadir o quitar paquetes, edita la lista `PAQUETES` al principio de `install.sh`.
- Para añadir otras tareas, crea una función y llámala desde `principal()`.
