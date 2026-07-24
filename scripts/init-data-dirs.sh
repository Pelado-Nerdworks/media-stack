#!/usr/bin/env bash
# Crea la estructura de directorios de data/ siguiendo la convención
# de TRaSH Guides (https://trash-guides.info/File-and-Folder-Structure/How-to-set-up/Docker/).
#
# Por qué existe este script: data/ está en .gitignore (los archivos de medios
# son grandes y personales), entonces la estructura no se puede clonar del repo.
# Este script la recrea de cero.
#
# Uso:
#   ./scripts/init-data-dirs.sh           # usa ./data (default)
#   DATA_DIR=/srv/media/data ./scripts/init-data-dirs.sh
#
# Idempotente: no rompe si las carpetas ya existen.

set -euo pipefail

DATA_DIR="${DATA_DIR:-./data}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { printf "${GREEN}[+]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[!]${NC} %s\n" "$*"; }

main() {
  log "Creando estructura de data/ en ${DATA_DIR} (layout TRaSH Guides)"

  # Torrents (staging): qBittorrent escribe acá, *arr mueven los archivos terminados a media/
  for kind in movies series music; do
    mkdir -p "${DATA_DIR}/torrents/${kind}"
  done

  # Media (biblioteca final): Jellyfin y Bazarr leen de acá
  for kind in movies series music; do
    mkdir -p "${DATA_DIR}/media/${kind}"
  done

  log "Estructura creada:"
  if command -v tree >/dev/null 2>&1; then
    tree -L 2 "${DATA_DIR}"
  else
    find "${DATA_DIR}" -type d | sort | sed 's/^/  /'
  fi

  echo
  warn "Próximo paso: docker compose up -d"
  warn "Luego: bash scripts/configure-base-urls.sh (para los subpaths)"
}

main "$@"
