#!/usr/bin/env bash
# Configura las "Base URL" / "UrlBase" de cada app para que matcheen
# los subpaths de Traefik (/jellyfin, /sonarr, /radarr, etc.).
#
# Después de esto, cada app responde SOLO en su subpath:
#   http://<IP>/jellyfin   → Jellyfin (con BaseUrl=/jellyfin)
#   http://<IP>/sonarr     → Sonarr (con UrlBase=/sonarr)
#   etc.
#
# Idempotente: si el valor ya está seteado, no hace nada.
#
# Apps que NO soportan subpath fácilmente y quedan con un warning:
#   - jellyseerr: depende de la versión, intentamos APP_BASE_URL como env var
#   - wizarr: se configura via web UI en el primer login
#
# Uso:
#   ./scripts/configure-base-urls.sh
#
# Requiere:
#   - El stack ya levantado (docker compose up -d)
#   - Los containers ya booteados al menos una vez (para que exista config.xml)

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { printf "${GREEN}[+]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[!]${NC} %s\n" "$*"; }
err()  { printf "${RED}[x]${NC} %s\n" "$*"; }

wait_for_config() {
  local container="$1"
  local path="$2"
  local timeout="${3:-120}"
  log "Esperando que ${container} genere ${path}..."
  for i in $(seq 1 "$timeout"); do
    if docker exec "$container" test -f "$path" 2>/dev/null; then
      log "  ${container}: ${path} listo (${i}s)"
      return 0
    fi
    sleep 1
  done
  err "  ${container}: TIMEOUT esperando ${path}"
  return 1
}

set_urlbase_xml() {
  # Apps *arr: edita <UrlBase></UrlBase> en config.xml
  local container="$1"
  local path="$2"
  local value="$3"
  docker exec "$container" bash -c "
    if grep -q '<UrlBase></UrlBase>' '${path}'; then
      sed -i 's|<UrlBase></UrlBase>|<UrlBase>${value}</UrlBase>|' '${path}'
      echo '  UrlBase actualizado a ${value}'
    elif grep -q '<UrlBase>${value}</UrlBase>' '${path}'; then
      echo '  UrlBase ya estaba en ${value} (no-op)'
    else
      echo '  WARN: no se encontró <UrlBase></UrlBase> en ${path}; revisar manualmente'
    fi
  "
}

set_baseurl_jellyfin() {
  # Jellyfin: <BaseUrl> puede no existir en network.xml, hay que insertarlo antes del cierre
  local container="$1"
  local path="$2"
  local value="$3"
  docker exec "$container" bash -c "
    if grep -q '<BaseUrl>${value}</BaseUrl>' '${path}'; then
      echo '  BaseUrl ya estaba en ${value} (no-op)'
    elif grep -q '<BaseUrl></BaseUrl>' '${path}'; then
      sed -i 's|<BaseUrl></BaseUrl>|<BaseUrl>${value}</BaseUrl>|' '${path}'
      echo '  BaseUrl actualizado a ${value}'
    else
      # No existe el tag — insertarlo antes de </NetworkConfiguration>
      sed -i 's|</NetworkConfiguration>|  <BaseUrl>${value}</BaseUrl>\n</NetworkConfiguration>|' '${path}'
      echo '  BaseUrl insertado en ${value} (no existía el tag)'
    fi
  "
}

set_urlbase_bazarr() {
  # Bazarr: usa config.yaml, la key url_base puede no existir
  local container="$1"
  local path="$2"
  local value="$3"
  docker exec "$container" bash -c "
    if grep -qE '^url_base:[[:space:]]*${value}' '${path}'; then
      echo '  Bazarr url_base ya estaba en ${value} (no-op)'
    elif grep -qE '^url_base:' '${path}'; then
      sed -i 's|^url_base:.*|url_base: ${value}|' '${path}'
      echo '  Bazarr url_base actualizado'
    else
      # No existe — agregar al final del archivo (Bazarr acepta YAML top-level)
      echo 'url_base: ${value}' >> '${path}'
      echo '  Bazarr url_base agregado al final del YAML'
    fi
  "
}

restart_apps() {
  log "Reiniciando apps para que apliquen los nuevos URL Base..."
  for c in "$@"; do
    if docker ps -q -f name="^/${c}\$" >/dev/null 2>&1; then
      docker restart "$c" >/dev/null
      log "  ${c}: reiniciado"
    else
      warn "  ${c}: no estaba corriendo, skip"
    fi
  done
}

main() {
  log "============================================"
  log "  Configurando URL Base del *arr stack"
  log "============================================"
  echo

  # *arr apps (config.xml con <UrlBase></UrlBase>)
  wait_for_config sonarr /config/config.xml 180
  set_urlbase_xml sonarr /config/config.xml /sonarr
  echo

  wait_for_config radarr /config/config.xml 180
  set_urlbase_xml radarr /config/config.xml /radarr
  echo

  # Bazarr (config.yaml en /config/config/config.yaml por la imagen LSIO)
  wait_for_config bazarr /config/config/config.yaml 180
  set_urlbase_bazarr bazarr /config/config/config.yaml /bazarr
  echo

  # Jellyfin (network.xml — puede no tener <BaseUrl>)
  wait_for_config jellyfin /config/network.xml 180
  set_baseurl_jellyfin jellyfin /config/network.xml /jellyfin
  echo

  # Jellyseerr: depende de la versión. Si soporta APP_BASE_URL como env var,
  # hay que setearlo en el compose antes del primer boot. Si no, queda en root.
  warn "Jellyseerr: verificar si soporta APP_BASE_URL como env var. Si no, queda accesible solo en root"
  echo

  # Wizarr: usa SQLite, no se puede editar fácil
  warn "Wizarr: configurar URL base manualmente en el primer login (Settings → General → Application URL)"
  echo

  # Restart apps para que apliquen cambios
  restart_apps sonarr radarr bazarr jellyfin

  echo
  log "============================================"
  log "  Listo. URLs de acceso:"
  log "    http://<IP>/jellyfin    → Media server"
  log "    http://<IP>/sonarr      → TV shows"
  log "    http://<IP>/radarr      → Movies"
  log "    http://<IP>/bazarr      → Subtitles"
  log "    http://<IP>/jellyseerr  → Requests (si soporta subpath)"
  log "    http://<IP>/wizarr      → Invitations (configurar manualmente)"
  log "    http://<IP>:8080        → qBittorrent (puerto dedicado)"
  log "    http://<IP>:9117        → Jackett (puerto dedicado)"
  log "    http://<IP>:8191        → FlareSolverr (puerto dedicado)"
  log "============================================"
}

main "$@"
