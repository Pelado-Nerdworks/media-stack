# Data Layout

This document explains how the `data/` directory is structured, why it is structured that way, and how each app sees it from inside its container.

We follow the convention from **[TRaSH Guides: Docker folder structure](https://trash-guides.info/File-and-Folder-Structure/How-to-set-up/Docker/)** so that the *arr apps (Sonarr, Radarr) can use hardlinks and atomic moves instead of copy + delete.

## Folder tree

```
data/
├── torrents/              # qBittorrent writes here. *arr move files out when complete.
│   ├── movies/
│   ├── series/
│   └── music/
└── media/                 # Final library. Jellyfin and Bazarr read from here.
    ├── movies/
    ├── series/
    └── music/
```

`.gitkeep` files keep every empty subfolder in git so the structure is reproducible from a fresh clone.

## Who sees what (container mounts)

Each app only sees the slice of `data/` it needs:

| App | Container path | Host path | Purpose |
| --- | --- | --- | --- |
| **Sonarr** | `/data` | `${DATA_DIR:-./data}` | Reads torrents, imports to media. Needs the full tree for hardlinks. |
| **Radarr** | `/data` | `${DATA_DIR:-./data}` | Same as Sonarr. |

| **qBittorrent** | `/data/torrents` | `${DATA_DIR:-./data}/torrents` | Writes downloads only. Never touches media. |
| **Jellyfin** | `/data/media` | `${DATA_DIR:-./data}/media` | Reads the final library. |
| **Bazarr** | `/data/media` | `${DATA_DIR:-./data}/media` | Reads the final library to download subtitles. |
| Prowlarr, Jellyseerr, Wizarr, Caddy | — | — | No access to `data/`. |

## Why not just mount `/data/movies` and `/data/downloads`?

That's the shortcut most quickstart guides suggest, and it's what this stack used to do. It works, but it has a real cost:

- **No hardlinks**. When Radarr moves a finished file from `downloads/` to `movies/`, Docker treats the two mounts as separate filesystems even when they aren't. Radarr falls back to **copy + delete**: the file exists twice on disk temporarily, you pay double I/O, and the move is not atomic.
- **No atomic moves**. A crash mid-move leaves a half-copied file in `movies/` and an orphan in `downloads/`.
- **Higher peak disk usage**. During a copy, a 50 GB movie briefly consumes 50 GB of free space plus the 50 GB it's copying from.
- **More SSD wear**. Unnecessary write amplification.

The TRaSH layout fixes all of this by mounting `/data` whole into the *arr apps. They see the same filesystem the host sees, so the kernel can hardlink files across `torrents/` and `media/`, and rename is a single inode operation.

## Inside the apps

After the stack is up, configure each app's root folders to match:

- **Sonarr**: Settings → Media Management → Root Folders → add `/data/series`
- **Radarr**: Settings → Media Management → Root Folders → add `/data/movies`

- **qBittorrent**: Tools → Options → Downloads → Default Save Path → `/data/torrents`
- **Jellyfin**: Dashboard → Libraries → Movies `/data/media/movies`, Series `/data/media/series`, Music `/data/media/music`
- **Bazarr**: Settings → Sonarr/Radarr → Folder mappings reflect the same paths

## Adding a new media type

If you ever add Books (Readarr) or Audiobooks (Audiobookshelf), extend the layout the same way:

```bash
mkdir -p data/torrents/books data/torrents/audiobooks data/media/books data/media/audiobooks
touch data/torrents/{books,audiobooks}/.gitkeep data/media/{books,audiobooks}/.gitkeep
```

Mount `/data` into Readarr (or whatever the new arr is), and `/data/torrents/<type>` into the download client. The hardlink trick keeps working because every folder is under the same parent on the host.

## Migrating from the old layout

If you're upgrading from a previous version of this stack that used flat `data/{movies,series,music,downloads}/`, follow these steps. **Stop the stack first** so nothing is mid-write:

```bash
cd /opt/media-stack
docker compose down

# Move existing downloads into the new staging tree
mkdir -p data/torrents
mv data/downloads/* data/torrents/
rmdir data/downloads

# Move existing libraries into the new media tree
mkdir -p data/media
mv data/movies data/series data/music data/media/

# Restart
docker compose up -d
bash scripts/configure-base-urls.sh
docker compose restart
```

Then update the root folder paths inside Sonarr/Radarr to `/data/series` and `/data/movies` respectively. Jellyfin and Bazarr do not need any changes (their mount target `/data/media` is unchanged).

## Source

- [TRaSH Guides — Docker folder structure](https://trash-guides.info/File-and-Folder-Structure/How-to-set-up/Docker/)
- [Servarr Wiki — Hardlinks and atomic moves](https://wiki.servarr.com/docker-guide#hard-links-and-moves)
