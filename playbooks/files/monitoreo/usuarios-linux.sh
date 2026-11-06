#!/usr/bin/env bash
# Gestionado por Ansible. Los cambios hechos a mano se perderán.
#
# Grafana no puede ver los usuarios de Linux directamente. Este script escribe la
# lista en un archivo que node_exporter publica como métrica, por ejemplo:
#   linux_usuario{usuario="mario",uid="1000",shell="/bin/bash",grupos="mario,sudo"} 1
set -euo pipefail

destino=/var/lib/prometheus/node-exporter/usuarios_linux.prom

# Se escribe en un temporal y luego se renombra, para que node_exporter nunca lea
# un archivo a medias. No lee el temporal porque su nombre no termina en .prom.
temporal="$(mktemp "$destino.XXXXXX")"

{
  echo "# HELP linux_usuario Cuentas de personas en este servidor."
  echo "# TYPE linux_usuario gauge"
  # Los UID de 1000 a 65533 son personas; los demás son cuentas del sistema.
  getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 {print $1, $3, $7}' |
    while read -r usuario uid shell; do
      grupos="$(id -nG "$usuario" | tr ' ' ',')"
      printf 'linux_usuario{usuario="%s",uid="%s",shell="%s",grupos="%s"} 1\n' \
        "$usuario" "$uid" "$shell" "$grupos"
    done
} > "$temporal"

chmod 0644 "$temporal"
mv "$temporal" "$destino"
