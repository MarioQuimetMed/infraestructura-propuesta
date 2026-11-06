# Seguridad del servidor

Esta guía explica qué instala cada playbook y por qué, y cómo hacer las tareas habituales. Lo que aún falta está en [pendientes.md](pendientes.md).

## Cómo se protege el servidor

Hay tres capas, y cada una cubre lo que la anterior no puede:

1. **Impedir la entrada:** VPN, firewall y SSH solo con claves.
2. **Registrar lo que pasa:** auditd, Laurel y logs de SSH y `sudo`.
3. **Poder recuperarse:** backups cifrados.

## Qué hace cada playbook

Se ejecutan en este orden al usar `.\ansible <entorno> apply`:

| Playbook | Qué hace | Por qué |
|---|---|---|
| `base.yml` | Instala paquetes base y activa los parches de seguridad automáticos | La mayoría de los ataques aprovechan fallos ya corregidos |
| `usuarios.yml` | Crea cuentas, grupos y claves SSH | Cada persona tiene su cuenta, así se sabe quién hizo qué |
| `wireguard.yml` | Crea la VPN `10.60.0.0/24` | La administración queda fuera de Internet |
| `acceso.yml` | Activa el firewall y limita SSH | Solo quedan abiertos los puertos necesarios |
| `auditoria.yml` | Registra los programas ejecutados y los cambios en archivos importantes | El historial de bash se puede borrar; este registro, no tan fácilmente |
| `docker.yml` | Instala Docker y publica puertos solo en `127.0.0.1` por defecto | Docker abre puertos sin pasar por el firewall |
| `postgres.yml` | Instala PostgreSQL y crea bases y usuarios | Solo es accesible desde el propio servidor |
| `backups.yml` | Hace un backup cifrado cada día | Ansible reconstruye la configuración, pero no los datos |
| `caddy.yml` | Publica los sitios con HTTPS | Es lo único abierto al público |
| `monitoreo.yml` | Instala Grafana, Loki, Alloy y Prometheus | Permite verlo todo desde la web |

## Qué queda abierto

| Puerto | Desde dónde | Para qué |
|---|---|---|
| 80 y 443 TCP | Internet | Sitios web (Caddy) |
| 51820 UDP | Internet | Conectarse a la VPN. No responde a quien no tenga una clave válida |
| 22 TCP | La VPN y `acceso_ssh_origenes` | SSH. Solo por la VPN con `acceso_ssh_solo_vpn: true` |
| 3000 TCP | Solo la VPN | Grafana |

PostgreSQL, Loki, Prometheus y `node_exporter` escuchan en `127.0.0.1`, así que no son accesibles desde fuera.

## Cómo llega un comando a Grafana

```text
Alguien ejecuta "cat /etc/shadow"
  → auditd lo registra en el kernel, con el usuario que inició la sesión
  → Laurel lo convierte a JSON en /var/log/laurel/audit.log
  → Alloy lee ese archivo y lo envía a Loki
  → Grafana lo muestra: mario [sesión 7] cat /etc/shadow
```

Aunque esa persona use `sudo`, el registro sigue mostrando quién inició la sesión.

## Ver la actividad en Grafana

1. Conéctate a la VPN.
2. Abre `http://10.60.0.1:3000` e inicia sesión con el usuario `admin`. La contraseña es `vault_grafana_admin`, que puedes ver con `.\ansible <entorno> secretos`.
3. Entra en **Dashboards**:

| Panel | Qué muestra |
|---|---|
| **Actividad de usuarios** | Cuentas y grupos, accesos SSH con IP y clave, comandos, `sudo` y cambios en archivos importantes |
| **Servidor** | CPU, RAM, disco, errores, contenedores, peticiones web, conexiones a PostgreSQL y backups |

**Dos paneles de comandos:** auditd registra cada programa que se ejecuta, no lo que se escribe, así que un solo inicio de sesión genera decenas de líneas.

| Panel | Qué muestra | Cuándo usarlo |
|---|---|---|
| **Comandos en terminal** | Programas ejecutados en una terminal: lo escrito y unas pocas líneas del arranque de bash (`groups`, `lesspipe`, `dircolors`...) | Para la consulta diaria |
| **Todos los programas** | Todo, también lo que se ejecuta sin terminal: mensaje de bienvenida, systemd, Ansible y `ssh servidor "comando"` | Para investigar un incidente |

**No te fíes solo del primero:** quien lance un comando con `ssh servidor "comando"` no aparece ahí, pero sí en **Todos los programas**.

**Cómo saber la IP de un comando:** los paneles de comandos muestran el usuario y la sesión. La IP aparece en el panel de accesos SSH, así que hay que relacionarlos por usuario y hora.

**Ruido de Ansible:** lo que ejecuta Ansible aparece en **Todos los programas**, con el usuario que lo lanza.

## Tareas habituales

### Añadir una persona a la VPN

1. La persona instala [WireGuard](https://www.wireguard.com/install/). En la app de Windows, elige **Add Tunnel > Add empty tunnel**. Se genera una clave privada, y la app muestra la pública.
2. La persona te envía solo la clave **pública**.
3. Añádela a `inventory/<entorno>/group_vars/servidores/wireguard.yml`, con una IP que no esté en uso:

   ```yaml
   wireguard_clientes:
     - nombre: mario-pc
       ip: 10.60.0.2
       clave_publica: "LA_CLAVE_PUBLICA="
   ```

4. Ejecuta `.\ansible <entorno> apply`. Al terminar, muestra la clave pública del servidor.
5. La persona completa su túnel, debajo de la línea `PrivateKey` que generó la app:

   ```ini
   Address = 10.60.0.2/32

   [Peer]
   PublicKey = CLAVE_PUBLICA_DEL_SERVIDOR
   Endpoint = IP_PUBLICA_DEL_SERVIDOR:51820
   AllowedIPs = 10.60.0.1/32
   PersistentKeepalive = 25
   ```

Con `AllowedIPs = 10.60.0.1/32`, solo el tráfico hacia el servidor pasa por la VPN. El resto de su conexión a Internet no cambia.

Para dar de baja a alguien, borra su entrada y aplica.

### Pasar a "SSH solo por VPN"

Hazlo después de comprobar que entras por la VPN, y en este orden:

1. Conéctate a la VPN y ejecuta `.\ansible <entorno> conectar 10.60.0.1 TU_USUARIO`. Debe indicar **Conexión correcta**.
2. Ejecuta `.\ansible <entorno> apply`. Debe seguir funcionando.
3. Cambia `acceso_ssh_solo_vpn` a `true` en `acceso.yml` y vuelve a aplicar.

Si no estás conectado por la VPN, el playbook se detiene antes de cambiar nada.

### Añadir una base de datos

1. Añádela a `inventory/<entorno>/group_vars/servidores/postgres.yml`:

   ```yaml
   postgres_bases:
     - nombre: ventas
       usuario: ventas_app
       contrasena: "{{ vault_pg_ventas }}"
   ```

2. Ejecuta `.\ansible <entorno> secretos` y añade esta línea con un valor largo y aleatorio. Puedes generarlo con `openssl rand -hex 24`:

   ```yaml
   vault_pg_ventas: "VALOR_ALEATORIO"
   ```

3. Ejecuta `.\ansible <entorno> apply`.

Quitar una base de la lista no la borra, para que un error en el archivo no elimine datos. Para borrarla: `sudo -u postgres dropdb NOMBRE`.

### Lanzar y revisar un backup

```bash
sudo systemctl start backup-servidor
journalctl -u backup-servidor -n 20
```

### Restaurar un backup

Primero prepara las variables y mira las copias disponibles, en el servidor:

```bash
sudo -i
export RESTIC_REPOSITORY=/var/backups/restic
export RESTIC_PASSWORD_FILE=/etc/restic/contrasena
restic snapshots
```

Restaura en una carpeta temporal, sin tocar los archivos en uso:

```bash
restic restore latest --target /root/restaurado
```

Para recuperar una base en otra distinta y revisarla antes de usarla:

```bash
sudo -u postgres createdb restaurada
sudo -u postgres pg_restore -d restaurada --no-owner < /root/restaurado/var/backups/postgres/NOMBRE.dump
```

Si perdiste el servidor, la contraseña de los backups está en `vault_restic`, dentro de tu Vault.

### Cambiar la contraseña de Grafana

Grafana solo lee la contraseña del archivo al crearse por primera vez. Para cambiarla:

1. En Grafana, ve a tu perfil y cámbiala en **Change password**.
2. Actualiza `vault_grafana_admin` con `.\ansible <entorno> secretos`, para que coincida.

### Recuperar el acceso si te quedas fuera

**Servidor físico:** conecta teclado y monitor e inicia sesión con tu usuario y su contraseña. Después:

```bash
# Desactiva el firewall temporalmente
sudo ufw disable

# Quita las restricciones de SSH
sudo rm /etc/ssh/sshd_config.d/00-seguridad.conf
sudo systemctl reload ssh
```

Corrige el error en el proyecto y vuelve a ejecutar `apply`, que restaurará ambos.

**Conserva la contraseña del usuario de instalación:** es la única forma de entrar por consola, porque las cuentas creadas por Ansible no tienen contraseña.

**VM de test:** lo más rápido es recrearla. La consola serie de Google Cloud solo sirve si antes activaste ese acceso y el usuario tiene contraseña.

## Comprobar que todo está bien

Ejecuta estos comandos en el servidor:

```bash
# Puertos abiertos. Solo deben aparecer en público 80, 443 y 51820, y 22 si no usas solo VPN
sudo ss -lntup

# Reglas del firewall
sudo ufw status verbose

# Reglas de auditoría activas
sudo auditctl -l

# Nadie debe aparecer al final de esta línea
getent group docker

# Clientes de la VPN y su última conexión
sudo wg show

# Próximo backup y actualización de usuarios
systemctl list-timers backup-servidor usuarios-linux
```

Para entrar al servidor desde PowerShell, usa `.\ansible <entorno> ssh`.

Para comprobar que SSH rechaza lo que debe, desde PowerShell:

```powershell
# Ambos deben dar "Permission denied"
wsl -d Ubuntu-24.04 -- ssh root@IP_DEL_SERVIDOR
wsl -d Ubuntu-24.04 -- ssh -o PubkeyAuthentication=no USUARIO@IP_DEL_SERVIDOR
```
