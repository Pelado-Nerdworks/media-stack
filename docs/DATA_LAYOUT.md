# Estructura de datos

Este documento explica cómo está estructurado el directorio `data/`, por qué se estructura así, y cómo cada app lo ve desde adentro de su container.

Seguimos la convención de **[TRaSH Guides: Docker folder structure](https://trash-guides.info/File-and-Folder-Structure/How-to-set-up/Docker/)** para que los *arr (Sonarr, Radarr) puedan usar hardlinks y moves atómicos en lugar de copy + delete.

## Árbol de carpetas

```
data/
├── torrents/              # qBittorrent escribe acá. Los *arr mueven los archivos al terminar.
│   ├── movies/
│   ├── series/
│   └── music/
└── media/                 # Biblioteca final. Jellyfin y Bazarr leen de acá.
    ├── movies/
    ├── series/
    └── music/
```

Los archivos `.gitkeep` mantienen cada subcarpeta vacía en git para que la estructura sea reproducible desde un clone limpio.

## Quién ve qué (mounts de los containers)

Cada app solo ve la parte de `data/` que necesita:

| App | Path en container | Path en host | Propósito |
| --- | --- | --- | --- |
| **Sonarr** | `/data` | `${DATA_DIR:-./data}` | Lee torrents, importa a media. Necesita el árbol entero para los hardlinks. |
| **Radarr** | `/data` | `${DATA_DIR:-./data}` | Igual que Sonarr. |
| **qBittorrent** | `/data/torrents` | `${DATA_DIR:-./data}/torrents` | Solo escribe descargas. Nunca toca media. |
| **Jellyfin** | `/data/media` | `${DATA_DIR:-./data}/media` | Lee la biblioteca final. |
| **Bazarr** | `/data/media` | `${DATA_DIR:-./data}/media` | Lee la biblioteca final para bajar subtítulos. |
| Jackett, FlareSolverr, Jellyseerr, Wizarr, Caddy | — | — | No acceden a `data/`. |

## ¿Por qué no montar `/data/movies` y `/data/downloads` separados?

Es el atajo que sugieren la mayoría de las guías de inicio rápido, y es lo que hacía este stack antes. Funciona, pero tiene un costo real:

- **Sin hardlinks**. Cuando Radarr mueve un archivo terminado de `downloads/` a `movies/`, Docker trata los dos mounts como filesystems separados aunque no lo sean. Radarr cae a **copy + delete**: el archivo existe dos veces en disco temporalmente, pagás doble I/O, y el move no es atómico.
- **Sin moves atómicos**. Si el proceso se cae a mitad de move, queda un archivo a medio copiar en `movies/` y un huérfano en `downloads/`.
- **Pico de uso de disco más alto**. Durante el copy, una peli de 50 GB consume temporalmente 50 GB libres más los 50 GB que está copiando desde el origen.
- **Más wear en SSDs**. Amplificación de writes innecesaria.

El layout de TRaSH arregla todo esto montando `/data` entero en los *arr. Ven el mismo filesystem que el host, así que el kernel puede hardlinkear archivos entre `torrents/` y `media/`, y un rename es una sola operación sobre inodes.

## Dentro de las apps

Después de levantar el stack, configurá los Root Folders de cada app para que matcheen:

- **Sonarr**: Settings → Media Management → Root Folders → add `/data/series`
- **Radarr**: Settings → Media Management → Root Folders → add `/data/movies`
- **qBittorrent**: Tools → Options → Downloads → Default Save Path → `/data/torrents`
- **Jellyfin**: Dashboard → Libraries → Movies `/data/media/movies`, Series `/data/media/series`, Music `/data/media/music`
- **Bazarr**: Settings → Sonarr/Radarr → Folder mappings con los mismos paths

## Agregar un nuevo tipo de medio

Si en algún momento sumás Books (Readarr) o Audiobooks (Audiobookshelf), extendé el layout de la misma forma:

```bash
mkdir -p data/torrents/books data/torrents/audiobooks data/media/books data/media/audiobooks
touch data/torrents/{books,audiobooks}/.gitkeep data/media/{books,audiobooks}/.gitkeep
```

Montá `/data` en Readarr (o el nuevo arr que sea), y `/data/torrents/<tipo>` en el cliente torrent. El truco del hardlink sigue funcionando porque toda carpeta queda bajo el mismo padre en el host.

## Migración desde el layout viejo

Si venís de una versión anterior de este stack que usaba `data/{movies,series,music,downloads}/` plano, seguí estos pasos. **Frená el stack primero** para que nada esté escribiendo:

```bash
cd /opt/media-stack
docker compose down

# Mover descargas existentes al nuevo árbol de staging
mkdir -p data/torrents
mv data/downloads/* data/torrents/
rmdir data/downloads

# Mover bibliotecas existentes al nuevo árbol de media
mkdir -p data/media
mv data/movies data/series data/music data/media/

# Reiniciar
docker compose up -d
bash scripts/configure-base-urls.sh
docker compose restart
```

Después actualizá los Root Folders adentro de Sonarr/Radarr a `/data/series` y `/data/movies` respectivamente. Jellyfin y Bazarr no necesitan cambios (su target de mount `/data/media` no cambió).

## Fuente

- [TRaSH Guides — Docker folder structure](https://trash-guides.info/File-and-Folder-Structure/How-to-set-up/Docker/)
- [Servarr Wiki — Hardlinks and atomic moves](https://wiki.servarr.com/docker-guide#hard-links-and-moves)
