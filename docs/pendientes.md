# Pendientes y limitaciones

Lo que este proyecto todavía no hace, y qué implica cada punto.

## Antes de usar producción

**Producción no está completa hasta resolver estos dos puntos:**

| Pendiente | Riesgo actual | Qué hace falta |
|---|---|---|
| **Backups fuera del servidor** | Se guardan en `/var/backups/restic`, en el mismo disco. **Si se pierde el servidor, se pierden también** | Elegir un destino (por ejemplo, un bucket S3 compatible o un NAS en otro lugar) y probar una restauración |
| **Copia de logs fuera del servidor** | Quien consiga root puede borrar los logs y ocultar lo que hizo | Elegir un destino (por ejemplo, un VPS con Loki) y que el servidor solo pueda enviarle datos |

## Para cuando llegue el primer backend

| Pendiente | Situación | Qué hace falta |
|---|---|---|
| **Conexión de contenedores a PostgreSQL** | PostgreSQL solo escucha en `localhost`, así que un contenedor no puede conectarse | Crear una red de Docker, hacer que PostgreSQL escuche en ella y abrirla en `pg_hba` y UFW |
| **CI/CD** | No hay despliegues automáticos | Definir el flujo cuando exista el primer proyecto |

## Simplificaciones que se pueden mejorar

| Se dejó fuera | Qué implica | Cuándo conviene añadirlo |
|---|---|---|
| Recuperar a un momento exacto (pgBackRest) | Puedes perder los datos desde el último backup, hasta 24 horas | Cuando esa pérdida no sea aceptable |
| Usuarios separados para migraciones y aplicación | La aplicación puede cambiar o borrar tablas de su base | En bases con datos importantes |
| pgAudit | Se ven las conexiones a PostgreSQL, pero no qué SQL se ejecutó | Si necesitas auditar el acceso a los datos |
| Reglas de auditd inmutables (`-e 2`) | Un root puede desactivar la auditoría sin reiniciar | Cuando las reglas estén estables. Cambiarlas requerirá reiniciar |
| Temporizador de rescate para SSH | Si te bloqueas, necesitas la consola física | Si el servidor pasa a estar lejos de ti |
| Métricas de contenedores (cAdvisor) | Ves sus logs, pero no su CPU ni RAM | Cuando haya contenedores en producción |
| Alertas de Grafana | Hay que entrar a mirar los paneles para enterarse de algo | Cuando elijas un canal de aviso, como correo o Telegram |
| Métrica de último backup | Un backup fallido aparece en los logs, pero nada te avisa | Junto con las alertas |
| Un registro de IP en cada comando | El panel de comandos muestra la sesión; la IP está en el de accesos | Si necesitas relacionarlos automáticamente |
| Limpieza de reglas de firewall | Quitar un origen de `acceso_ssh_origenes` no borra su regla | Hasta entonces, se borra con `sudo ufw delete` |
| Roles de Ansible | Todo son playbooks sencillos, lo que es más fácil de aprender | Si el proyecto crece mucho |

## Decisiones tomadas

| Decisión | Qué implica |
|---|---|
| Sin cifrado de disco | Si roban el disco, los datos son legibles, salvo los backups, que van cifrados. Añadirlo suele requerir reinstalar Ubuntu |
| `sudo` sin contraseña para el grupo `admins` | Una clave de administrador robada da root de inmediato. Protege esas claves con una passphrase |
| Recursos sin dimensionar | Grafana, Loki y PostgreSQL consumen memoria y disco. Vigila el panel **Servidor** |

## Lo que la auditoría no puede ver

Incluso funcionando bien, estos casos no quedan registrados:

- **Comandos internos de bash:** `cd`, `export` o `echo x > archivo`, porque no ejecutan un programa. Los cambios en archivos importantes sí se registran con otra regla.
- **Dentro de otro programa:** se ve que alguien abrió `psql` o `python`, pero no lo que hizo dentro.
- **Dentro de un contenedor:** se ve el `docker exec`, pero no lo que ocurre dentro.

Además, si alguien escribe una contraseña como argumento de un comando, queda en los logs. Hay que evitarlo.

## Qué se ha probado y qué no

### Probado en una VM limpia con Ubuntu 24.04

- Instalación completa desde cero, y repetición sin cambios (`changed=0`).
- `plan` sobre lo ya instalado: sin cambios, sin errores y sin secretos en su salida.
- SSH rechaza a root, las contraseñas, los usuarios inexistentes y a un usuario con clave válida fuera de `ssh-access`.
- `dev_quimet` entra por SSH, pero no tiene `sudo`, Docker ni acceso a `/etc/shadow`.
- Puertos: desde fuera solo responden 22, 80 y 443 de los TCP comprobados (22, 80, 443, 3000, 3001, 3100, 5432, 9090, 9100 y 12345). PostgreSQL, Loki y Prometheus escuchan solo en `127.0.0.1`.
- Docker, con Compose y con `docker run`: un puerto publicado sin IP queda solo en `127.0.0.1`.
- Auditoría: los comandos reales llegan a Grafana con su usuario, también con `sudo`.
- Grafana rechaza el acceso anónimo y sus paneles reciben datos reales.
- Backup real y restauración de una base.
- Ninguna contraseña del Vault aparece en `/var/log`, en el journal ni en el log de Laurel.
- Tras reiniciar, vuelven el firewall, la VPN, Grafana, Laurel y las reglas de auditoría.

### Sin probar todavía

- **Aislamiento de la VPN:** comprobar que un cliente no llegue a otras redes. La conexión desde un PC y el acceso a Grafana por el navegador ya funcionan.
- **Pasar a "SSH solo por VPN"** (`acceso_ssh_solo_vpn: true`).
- **Un usuario que pida contraseña para `sudo`** (`--ask-become-pass`) y la copia real de la clave con `ssh-copy-id`. Son los casos de tu servidor físico.
- **`sitios: []` en un `apply` completo:** Caddy lo acepta al validar, pero falta ejecutarlo.

### Detalles conocidos

- **`openipmi.service` aparece como fallido** en la VM de test porque no tiene ese hardware. Lo instala una dependencia de los paquetes de monitoreo, y no afecta al resto.
- **Crecimiento de Loki:** sus datos solo se limitan por antigüedad (90 días), no por tamaño. Vigila el disco en el panel **Servidor**.
