# Instalación

Esta guía deja un PC con Windows listo para usar este proyecto, partiendo de un equipo sin WSL.

Ansible no funciona de forma nativa en Windows, así que se instala dentro de WSL (Linux en Windows). La instalación se hace una sola vez. Después, los comandos del día a día se ejecutan desde PowerShell.

Cada paso indica dónde ejecutar los comandos:

- **PowerShell:** la terminal de Windows.
- **Ubuntu:** la terminal de Linux que se abre con `wsl -d Ubuntu-24.04`. Para salir de ella, usa `exit`.

Los valores en mayúsculas, como `TU_USUARIO`, hay que sustituirlos por los tuyos.

## Requisitos

- Windows 10 versión 2004 o posterior, o Windows 11.
- Permisos de administrador en el PC.
- Virtualización activada en la BIOS.
- La carpeta de este proyecto copiada en tu PC.
- Un servidor con Ubuntu 24.04 y acceso a su configuración de claves SSH.

## 1. Instalar WSL y Ubuntu

En **PowerShell, abierto como administrador**:

```powershell
wsl --install -d Ubuntu-24.04
```

Si Windows lo pide, reinicia el PC.

Abre Ubuntu desde **PowerShell**:

```powershell
wsl -d Ubuntu-24.04
```

La primera vez te pedirá crear un usuario y una contraseña de Linux. Los necesitarás para los comandos con `sudo`.

## 2. Configurar los permisos de los discos de Windows

Por defecto, Linux ve los archivos de Windows como modificables por cualquiera. En ese caso, Ansible ignora el `ansible.cfg` del proyecto.

En **Ubuntu**:

```bash
printf '\n[automount]\noptions = "metadata,umask=022,fmask=111"\n' | sudo tee -a /etc/wsl.conf
exit
```

Reinicia WSL desde **PowerShell**. Esto también detiene Docker Desktop, si lo usas:

```powershell
wsl --shutdown
```

Comprueba el cambio desde **PowerShell**:

```powershell
wsl -d Ubuntu-24.04 -- mount
```

La línea de tu disco, por ejemplo `C:\ on /mnt/c`, debe incluir `metadata;umask=022;fmask=111`.

## 3. Instalar Ansible

Vuelve a abrir Ubuntu desde **PowerShell**:

```powershell
wsl -d Ubuntu-24.04
```

En **Ubuntu**:

```bash
sudo apt update
sudo apt install -y pipx
pipx ensurepath
source ~/.bashrc
pipx install --include-deps ansible
ansible --version
```

El último comando debe mostrar `ansible [core ...]`.

Sal de Ubuntu con `exit`. A partir de aquí todo se hace desde **PowerShell**, sin entrar a WSL.

## 4. Instalar las dependencias del proyecto

En **PowerShell**, dentro de la carpeta del proyecto (cambia la ruta si la tuya es otra):

```powershell
cd D:\Kais\infraestructura
.\ansible instalar
```

Si ya están instaladas, verás `Nothing to do`.

## 5. Conectar con el servidor de test

Crea la VM en Google Cloud con **Ubuntu 24.04 LTS** y anota su IP externa. Después, en **PowerShell**:

```powershell
.\ansible test conectar IP_DEL_SERVIDOR TU_USUARIO
```

Este comando crea tu clave SSH si no existe, guarda los datos en `inventory/test/hosts.ini` y prueba la conexión. Si la clave es nueva, te pedirá una passphrase; se recomienda ponerla.

Google Cloud no acepta contraseñas, así que la primera vez el comando te mostrará la clave pública y la copiará al portapapeles:

1. Ve a **Compute Engine > Instancias de VM > tu VM > Editar > Claves SSH > Agregar elemento**.
2. Pega la clave y guarda.
3. Vuelve a ejecutar el mismo comando. Debe indicar **Conexión correcta**.

Google Cloud crea el usuario con el nombre que aparece al final de la clave. Si no coincide con `TU_USUARIO`, el comando te avisa.

Las claves se guardan dentro de WSL, nunca en el disco de Windows ni en el proyecto. Comparte solo la clave **pública**.

Para entrar al servidor en cualquier momento, usa `.\ansible test ssh`.

## 6. Abrir los puertos del servidor

Caddy necesita recibir tráfico en los puertos 80 y 443 para obtener los certificados HTTPS. En Google Cloud, ve a **tu VM > Editar > Firewalls** y marca **Permitir tráfico HTTP** y **Permitir tráfico HTTPS**.

Limita el puerto 22 (SSH) a tu IP.

Para la VPN, crea una regla en **Red de VPC > Firewall > Crear regla de firewall** que permita entrada por **UDP 51820** a tu VM. No abras otros puertos.

## 7. Crear los secretos

Las contraseñas (Grafana, backups, bases de datos) se guardan cifradas con Ansible Vault.

En **PowerShell**, dentro de la carpeta del proyecto:

```powershell
.\ansible test secretos
```

La primera vez:

1. Crea una contraseña para el Vault y la muestra en pantalla. **Guárdala en un gestor de contraseñas**: sin ella no se pueden abrir los secretos. Se guarda en `~/.ansible-vault/test`, dentro de WSL.
2. Crea `inventory/test/group_vars/servidores/vault.yml`, cifrado y con valores aleatorios.
3. Lo abre en el editor `nano`. Si no necesitas cambiar nada, sal con `Ctrl+X`.

## 8. Revisar la configuración de test

Antes de aplicar nada, revisa estos archivos:

| Archivo | Qué revisar |
|---|---|
| `inventory/test/group_vars/servidores/caddy.yml` | `dominio_web` debe apuntar a la IP de tu servidor |
| `inventory/test/group_vars/servidores/usuarios.yml` | Los usuarios y sus claves públicas. En `administradores_existentes`, pon tu usuario |
| `inventory/test/group_vars/servidores/acceso.yml` | Desde dónde se permite SSH |
| `inventory/test/group_vars/servidores/postgres.yml` | Las bases de datos |

Si un nombre de `administradores_existentes` no existe en el servidor, el playbook se detiene con un error.

## 9. Aplicar la configuración

En **PowerShell**, dentro de la carpeta del proyecto:

```powershell
.\ansible test apply
.\ansible test apply
```

- El primer `apply` instala y configura todo. Puede tardar varios minutos.
- El segundo debe terminar con `changed=0`, lo que indica que no quedan cambios pendientes.

Si tu clave tiene passphrase, te la pedirá la primera vez.

A partir de aquí, usa `.\ansible test plan` antes de cada `apply` para ver qué cambiaría. **En la primera instalación, `plan` falla** al llegar a lo que aún no está instalado, por eso se empieza con `apply`.

## 10. Conectarte a la VPN y a Grafana

Grafana solo es accesible por la VPN. Sigue [Añadir una persona a la VPN](docs/seguridad.md#añadir-una-persona-a-la-vpn) para añadirte, y después abre `http://10.60.0.1:3000`.

La guía [docs/seguridad.md](docs/seguridad.md) explica qué hace cada pieza y cómo hacer las tareas habituales. Lo que aún falta está en [docs/pendientes.md](docs/pendientes.md).

## Usar producción

Pruébalo antes en una VM limpia. **Lee primero [docs/pendientes.md](docs/pendientes.md)**: mientras los backups estén en el propio servidor, perderlo significa perder los datos.

1. **Prepara el servidor**, con teclado y monitor. Comprueba que SSH funciona y anota la IP:

   ```bash
   sudo apt update
   sudo apt install -y openssh-server
   ip -4 addr
   ```

   Reserva esa IP en tu router. Conserva la contraseña de tu usuario: es tu forma de entrar por consola si algo falla.

2. **Conéctate** desde **PowerShell**. Crea tu clave y te pide la contraseña de tu usuario una vez para copiarla al servidor:

   ```powershell
   .\ansible produccion conectar IP_DEL_SERVIDOR TU_USUARIO
   ```

3. **Completa los archivos de `inventory/produccion/`:**

   | Archivo | Qué cambiar |
   |---|---|
   | `group_vars/servidores/usuarios.yml` | Añade tu usuario a `administradores_existentes`, y los `usuarios` que necesites |
   | `group_vars/servidores/acceso.yml` | Sustituye `RED_LOCAL` por tu red, por ejemplo `192.168.1.0/24` |
   | `group_vars/servidores/caddy.yml` | Define `dominio_web` y tus `sitios` |
   | `group_vars/servidores/postgres.yml` | Define tus bases de datos |

4. **Crea los secretos de producción.** Tienen su propia contraseña de Vault:

   ```powershell
   .\ansible produccion secretos
   ```

5. **Aplica.** Te pedirá la contraseña de `sudo` de tu usuario, y que escribas `produccion` para confirmar:

   ```powershell
   .\ansible produccion apply --ask-become-pass
   ```

6. **Abre los puertos en el router** hacia el servidor: UDP 51820 para la VPN, y TCP 80 y 443 si vas a publicar sitios. No redirijas el 22.

7. **Pasa a "SSH solo por VPN"** cuando hayas comprobado que entras por ella. Sigue [estos pasos](docs/seguridad.md#pasar-a-ssh-solo-por-vpn).

## Comandos del día a día

Se ejecutan en **PowerShell**, dentro de la carpeta del proyecto. El `.\` es obligatorio.

| Comando | Qué hace |
|---|---|
| `.\ansible instalar` | Instala las colecciones de `requirements.yml` |
| `.\ansible test conectar IP USUARIO` | Crea la clave si hace falta, guarda los datos del servidor y prueba la conexión |
| `.\ansible test ssh` | Entra al servidor de test. Con `produccion`, al de producción |
| `.\ansible test plan` | Simula los cambios en test |
| `.\ansible test apply` | Aplica los cambios en test |
| `.\ansible produccion plan` | Simula los cambios en producción |
| `.\ansible produccion apply` | Aplica los cambios en producción, tras pedir confirmación |
| `.\ansible test secretos` | Crea o edita los secretos de test. Con `produccion`, los de producción |

## Solución de problemas

| Problema | Causa probable | Solución |
|---|---|---|
| `Unable to locate package pipx` | La lista de paquetes de Ubuntu está vacía | Ejecuta `sudo apt update` en Ubuntu |
| `ansible` o `.\ansible` no se reconoce en PowerShell | Falta el `.\` o estás en otra carpeta | Entra en la carpeta del proyecto y usa `.\ansible` |
| `Este entorno aún no está conectado` | Falta preparar la conexión | Ejecuta `.\ansible <entorno> conectar IP USUARIO` |
| `Permission denied (publickey)` | La clave o el usuario no coinciden con los del servidor | Ejecuta `.\ansible <entorno> conectar IP USUARIO` y sigue sus indicaciones |
| `REMOTE HOST IDENTIFICATION HAS CHANGED` | El servidor se recreó o reinstaló | Ejecuta `.\ansible <entorno> conectar IP USUARIO` y confirma si lo acabas de crear |
| `UNPROTECTED PRIVATE KEY FILE` | La clave está en el disco de Windows | Muévela a `~/.ssh/` en Ubuntu y ejecuta `chmod 600` sobre ella |
| Aviso de `world writable directory` y `ansible.cfg` ignorado | Falta el ajuste del paso 2 | Repite el paso 2 y ejecuta `wsl --shutdown` |
| `Permission denied` al usar `./ansible` en Ubuntu | Se editó el archivo desde Windows | Ejecuta `chmod +x ansible`, o usa `.\ansible` desde PowerShell |
| `Missing sudo password` | Tu usuario necesita contraseña para `sudo` | Añade `--ask-become-pass` al final del comando |
| El certificado HTTPS no se emite | El DNS no apunta al servidor o los puertos 80 y 443 están cerrados | Revisa el DNS y el paso 6 |
| `'vault_...' is undefined` o `Falta vault_...` | Faltan los secretos, o una contraseña de una base nueva | Ejecuta `.\ansible <entorno> secretos` |
| `Attempting to decrypt but no vault secrets found` | Falta la contraseña del Vault en este PC | Guárdala de nuevo en `~/.ansible-vault/<entorno>`, en Ubuntu, con `chmod 600` |
| `Te quedarías fuera` | Tu usuario no está en `ssh-access` o no tiene clave autorizada | Añádelo a `administradores_existentes` y usa `ssh-copy-id` |
| `Bad source address` o error similar en UFW | Sigue sin sustituirse `RED_LOCAL` en `acceso.yml` | Pon tu red, por ejemplo `192.168.1.0/24` |
| No puedes entrar por SSH después de aplicar | Un cambio en el firewall o en SSH te bloqueó | Sigue [Recuperar el acceso](docs/seguridad.md#recuperar-el-acceso-si-te-quedas-fuera) |
| `http://10.60.0.1:3000` no abre | La VPN no está conectada | Activa el túnel en la app de WireGuard y revisa que el servidor te tenga como cliente con `sudo wg show` |
