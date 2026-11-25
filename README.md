# linux-script

Plantilla de script para Debian que se descarga y ejecuta con un solo comando.

## Uso

Con `curl`:

```bash
curl -fsSL https://raw.githubusercontent.com/surikata3k/linux-script/main/install.sh | sudo bash
```

Con `wget` (viene instalado por defecto en Debian):

```bash
wget -qO- https://raw.githubusercontent.com/surikata3k/linux-script/main/install.sh | sudo bash
```

Si prefieres revisarlo antes de ejecutarlo:

```bash
wget https://raw.githubusercontent.com/surikata3k/linux-script/main/install.sh
less install.sh
sudo bash install.sh
```

## Personalizar

Edita la función `principal()` de `install.sh` y añade tus comandos.
