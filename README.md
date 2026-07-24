# Media Stack — Jellyfin + *arr auto-hospedado

Stack completo en Docker para correr tu propio servidor de medios en casa: películas, series, música, subtítulos, descargas y una UI estilo Netflix para pedir contenido, todo detrás de un único reverse proxy con routing por path.

## ¿Qué incluye?

- **Caddy** — reverse proxy con routing automático por path (un dominio, muchas apps)
- **Jellyfin** — servidor de medios (películas, series, música)
- **Sonarr** / **Radarr** / **Lidarr** — automatización de bibliotecas (TV, películas, música)
- **Prowlarr** — gestor de indexers (un solo lugar para agregar trackers)
- **Bazarr** — subtítulos automáticos
- **qBittorrent** — cliente torrent
- **Jellyseerr** — UI de pedidos (un Netflix para tus usuarios)
- **Wizarr** — invitaciones de usuarios

Mirá [`architecture.excalidraw`](architecture.excalidraw) para el diagrama completo de topología (abrilo en <https://excalidraw.com>).

La estructura interna de carpetas sigue la convención de [TRaSH Guides](https://trash-guides.info/File-and-Folder-Structure/How-to-set-up/Docker/) para que los *arr puedan usar hardlinks y moves atómicos. Ver [docs/DATA_LAYOUT.md](docs/DATA_LAYOUT.md) para el detalle.

## Requisitos

- Servidor Linux (o VM) con **Docker 24+** y **Docker Compose v2**
- ~20 GB libres en disco para configs y descargas (más si vas a tener una biblioteca grande)
- Puertos **80** y **443** abiertos
- Un dominio público (recomendado para HTTPS) o entradas de DNS local — el stack funciona con `http://localhost` también, pero el HTTPS automático necesita un dominio real

## Inicio rápido

1. Cloná el repo:

   ```bash
   git clone https://github.com/Pelado-Nerdworks/media-stack.git
   cd media-stack
   ```

2. Copiá el archivo de ejemplo de variables de entorno:

   ```bash
   cp .env.example .env
   ```

   Por defecto, las configs se guardan en `./config/` y las descargas/bibliotecas en `./data/`. Editá `.env` si querés apuntarlas a otro lado (ver [Configuración](#configuración) más abajo).

3. Inicializá la estructura de `data/` (necesario una sola vez; `data/` está en `.gitignore` así que la tenés que crear vos):

   ```bash
   bash scripts/init-data-dirs.sh
   ```

   Esto crea `data/torrents/{movies,series,music}` (staging) y `data/media/{movies,series,music}` (biblioteca final) siguiendo la convención de TRaSH Guides. Es idempotente. Ver [docs/DATA_LAYOUT.md](docs/DATA_LAYOUT.md) para el detalle.

4. Levantá el stack:

   ```bash
   docker compose up -d
   ```

5. Esperá un minuto a que cada app genere su config inicial y corré el setup de subpaths:

   ```bash
   bash scripts/configure-base-urls.sh
   ```

   Esto configura la URL base interna de cada app para que responda bajo `/jellyfin`, `/sonarr`, etc. Es idempotente — se puede volver a correr sin problema.

6. Reiniciá las apps para que tomen las nuevas URLs:

   ```bash
   docker compose restart
   ```

7. Abrí las URLs en tu navegador:

   | App | URL |
   | --- | --- |
   | Jellyfin | `http://tu-servidor/jellyfin` |
   | Sonarr | `http://tu-servidor/sonarr` |
   | Radarr | `http://tu-servidor/radarr` |
   | Bazarr | `http://tu-servidor/bazarr` |
   | Prowlarr | `http://tu-servidor/prowlarr` |
   | Lidarr | `http://tu-servidor/lidarr` |
   | qBittorrent | `http://tu-servidor/qbittorrent` |
   | Jellyseerr | `http://tu-servidor/jellyseerr` |
   | Wizarr | `http://tu-servidor/wizarr` |

   La primera vez, cada app te pide crear una cuenta. Mirá [Configuración inicial](#configuración-inicial) más abajo.

## Configuración

### Rutas de almacenamiento

Por defecto, el stack guarda configs en `./config/` y medios/descargas en `./data/`, relativas al `docker-compose.yml`. Para moverlas a otro lado (por ejemplo `/srv/media-stack/`), editá `.env`:

```env
CONFIG_DIR=/srv/media-stack/config
DATA_DIR=/srv/media-stack/data
```

Después mové el contenido existente:

```bash
rsync -av ./config/ /srv/media-stack/config/
rsync -av ./data/ /srv/media-stack/data/
docker compose down
docker compose up -d
```

`./config/` y `./data/` están en `.gitignore`, así no se filtran datos personales al repo.

### Zona horaria

Todas las apps están configuradas con `America/Argentina/Mendoza`. Para cambiarla, editá las entradas `TZ=` de cada servicio en `docker-compose.yml`.

### Usuario / permisos

Las apps corren con `PUID=1000` / `PGID=1000` (típico del primer usuario en Ubuntu/Debian). Para que coincidan con tu usuario, corré `id -u` y `id -g`, y actualizá esos valores en `docker-compose.yml`.

### HTTPS

Caddy está listo para HTTPS automático vía Let's Encrypt. Para activarlo, apuntá un dominio real a tu servidor (registro A en DNS) y editá el Caddyfile en `config/caddy/` para agregar el `email` y el dominio. Mirá la [doc de Caddy](https://caddyserver.com/docs/automatic-https).

## Configuración inicial

Una vez que el stack está arriba y accesible:

1. **Prowlarr** — `Settings → Indexers → Add Indexer`. Agregá tus trackers favoritos.
2. **Sonarr / Radarr / Lidarr** — `Settings → Indexers → Add → Prowlarr` (usa la API key de Prowlarr, está en `Settings → General` dentro de Prowlarr).
3. **Sonarr / Radarr / Lidarr** — `Settings → Media Management → Root Folders` y agregá:
   - Sonarr: `/data/series`
   - Radarr: `/data/movies`
   - Lidarr: `/data/music`
4. **Sonarr / Radarr / Lidarr** — `Settings → Download Clients → Add → qBittorrent` (puerto default `8080` adentro del container, host `qbittorrent`).
5. **qBittorrent** — iniciá sesión con la contraseña temporal que imprime el container en los logs:
   ```bash
   docker logs qbittorrent | grep -i 'temporary password'
   ```
   Cambiala apenas entres. Después andá a `Tools → Options → Downloads` y poné `Default Save Path = /data/torrents` (sin subcarpeta — los *arr la arman solitos al asignar la descarga).
6. **Jellyfin** — agregá bibliotecas apuntando a `/data/media/movies`, `/data/media/series`, `/data/media/music`.
7. **Bazarr** — `Settings → Sonarr/Radarr → Connect` (pegá la API key de cada app).
8. **Jellyseerr** — conectalo a Jellyfin (API key en `Dashboard → API Keys`) y a Sonarr/Radarr.
9. **Wizarr** — generá links de invitación desde la UI web para sumar amigos o familia.

## Operaciones diarias

```bash
# Ver qué está corriendo
docker compose ps

# Ver logs en vivo de una app
docker compose logs -f jellyfin

# Actualizar una imagen
docker compose pull sonarr
docker compose up -d sonarr

# Actualizar todo
docker compose pull
docker compose up -d

# Frenar el stack (conserva configs y datos)
docker compose down

# Frenar y borrar TODO — configs incluidas (¡destructivo!)
docker compose down -v
```

## Troubleshooting

- **La app muestra página en blanco o 404 después de `docker compose up`.** Probablemente no se aplicó la config de subpath. Corré `bash scripts/configure-base-urls.sh` y después `docker compose restart`.
- **qBittorrent pide contraseña y no la aceptás.** Es la contraseña temporal que imprime el container en el primer arranque. Corré `docker logs qbittorrent | grep -i 'temporary password'`.
- **Caddy devuelve 502 / no llega a las apps.** Verificá que Caddy esté arriba (`docker compose ps caddy`) y que los demás containers estén en la red `proxy` (lo están por default).
- **Errores de "Permission denied" escribiendo a `/data/torrents` o `/data/media`.** Los valores `PUID`/`PGID` en `docker-compose.yml` no coinciden con tu usuario del host. Actualizalos y reiniciá.
- **"Address already in use" en los puertos 80/443.** Hay otro servidor web (nginx, apache, otro Caddy) ocupando esos puertos. Frenalo o cambialos en `docker-compose.yml`.
- **Los *arr no encuentran las descargas / Jellyfin no muestra archivos nuevos.** Mirá [docs/DATA_LAYOUT.md](docs/DATA_LAYOUT.md): cada *arr necesita el Root Folder correcto y qBittorrent tiene que tener como Default Save Path `/data/torrents`.

## Estructura del repo

```
media-stack/
├── config/                 # Settings de cada app (ignorado por git)
│   ├── jellyfin/
│   ├── sonarr/
│   ├── radarr/
│   ├── lidarr/
│   ├── prowlarr/
│   ├── bazarr/
│   ├── qbittorrent/
│   ├── jellyseerr/
│   ├── wizarr/
│   └── caddy/
│       └── Caddyfile
├── data/                   # Medios + descargas (ignorado por git)
│   ├── torrents/           # staging (escribe qBittorrent)
│   │   ├── movies/
│   │   ├── series/
│   │   └── music/
│   └── media/              # biblioteca final (lee Jellyfin/Bazarr)
│       ├── movies/
│       ├── series/
│       └── music/
├── scripts/
│   ├── init-data-dirs.sh         # crea la estructura de data/ (idempotente)
│   └── configure-base-urls.sh    # setea los subpaths en cada app post-boot
├── docs/
│   └── DATA_LAYOUT.md            # explica por qué la estructura sigue TRaSH Guides
├── architecture.excalidraw       # diagrama top-down del stack
├── docker-compose.yml
├── .env.example
├── .gitignore
└── README.md
```

## Contribuciones

Pull requests bienvenidos. Mantené los cambios enfocados y actualizá este README cuando agregues o cambies servicios.

## Agradecimientos

- [TRaSH Guides](https://trash-guides.info/) — por la convención de folder structure que seguimos
- [LinuxServer.io](https://docs.linuxserver.io/) — por mantener la mayoría de las imágenes Docker
- El proyecto [Servarr](https://wiki.servarr.com/) (Sonarr, Radarr, Lidarr, Prowlarr, Bazarr)
- [Jellyfin](https://jellyfin.org) — por el servidor de medios
- [Jellyseerr](https://github.com/Fallenbagel/jellyseerr) — por la UI de pedidos
- [Wizarr](https://github.com/Wizarrrr/wizarr) — por el sistema de invitaciones
