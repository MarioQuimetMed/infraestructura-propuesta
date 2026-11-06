#!/usr/bin/env bash
# Gestionado por Ansible. Los cambios hechos a mano se perderán.
#
# Hace un backup del servidor. Si algo falla, se detiene y el servicio queda en
# estado "failed". Para ver el resultado: journalctl -u backup-servidor
set -euo pipefail

export RESTIC_REPOSITORY=/var/backups/restic
export RESTIC_PASSWORD_FILE=/etc/restic/contrasena
copias=/var/backups/postgres

# 1. Copia cada base en un archivo, porque copiar sus archivos con la base en
#    marcha podría dar datos inconsistentes. Se borran antes las copias anteriores
#    para no guardar bases que ya no existen.
rm -f "$copias"/*

consulta="SELECT datname FROM pg_database WHERE NOT datistemplate AND datname <> 'postgres'"
for base in $(runuser -u postgres -- psql -Atc "$consulta"); do
  runuser -u postgres -- pg_dump --format=custom "$base" > "$copias/$base.dump"
done

# Los usuarios y sus permisos no están dentro de las bases: se guardan aparte.
runuser -u postgres -- pg_dumpall --globals-only > "$copias/usuarios.sql"

# 2. Guarda todo en el repositorio, cifrado.
restic backup /etc /srv "$copias"

# 3. Borra las copias antiguas: conserva 7 diarias y 4 semanales.
restic forget --keep-daily 7 --keep-weekly 4 --prune
