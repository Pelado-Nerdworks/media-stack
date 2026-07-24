# Media Stack — Self-hosted Jellyfin + *arr

A complete Docker stack for running your own media server at home: movies, TV, music, subtitles, downloads and a Netflix-style request UI, all behind a single reverse proxy with path-based routing.

## What's inside

- **Caddy** — reverse proxy with automatic path-based routing (one domain, many apps)
- **Jellyfin** — media server (movies, TV, music)
- **Sonarr** / **Radarr** / **Lidarr** — library automation (TV, movies, music)
- **Prowlarr** — indexer manager (one place to add trackers)
- **Bazarr** — automatic subtitles
- **qBittorrent** — torrent client
- **Jellyseerr** — request management UI (think Netflix for your users)
- **Wizarr** — user invitations

See [`architecture.excalidraw`](architecture.excalidraw) for the full topology diagram (open it at <https://excalidraw.com>).

## Requirements

- Linux server (or VM) with **Docker 24+** and **Docker Compose v2**
- ~20 GB free disk for configs and downloads (more if you keep a large library)
- Ports **80** and **443** open
- A public domain (recommended for HTTPS) or local DNS entries — the stack works with `http://localhost` too, but HTTPS automation requires a real domain

## Quickstart

1. Clone this repo:

   ```bash
   git clone https://github.com/Pelado-Nerdworks/media-stack.git
   cd media-stack
   ```

2. Copy the example env file:

   ```bash
   cp .env.example .env
   ```

   By default, configs are stored in `./config/` and media/downloads in `./data/`. Edit `.env` if you want to point them somewhere else (see [Configuration](#configuration) below).

3. Start the stack:

   ```bash
   docker compose up -d
   ```

4. Wait about a minute for every app to bootstrap its config, then run the subpath setup:

   ```bash
   bash scripts/configure-base-urls.sh
   ```

   This sets each app's internal base URL so it answers under `/jellyfin`, `/sonarr`, etc. It's idempotent — safe to re-run.

5. Restart the apps so they pick up the new URLs:

   ```bash
   docker compose restart
   ```

6. Open the URLs from your browser:

   | App | URL |
   | --- | --- |
   | Jellyfin | `http://your-server/jellyfin` |
   | Sonarr | `http://your-server/sonarr` |
   | Radarr | `http://your-server/radarr` |
   | Bazarr | `http://your-server/bazarr` |
   | Prowlarr | `http://your-server/prowlarr` |
   | Lidarr | `http://your-server/lidarr` |
   | qBittorrent | `http://your-server/qbittorrent` |
   | Jellyseerr | `http://your-server/jellyseerr` |
   | Wizarr | `http://your-server/wizarr` |

   On first load, each app asks you to create an account. See [First-time setup](#first-time-setup) below.

## Configuration

### Storage paths

By default, the stack stores configs in `./config/` and media/downloads in `./data/`, relative to `docker-compose.yml`. To move them elsewhere (e.g. `/srv/media-stack/`), edit `.env`:

```env
CONFIG_DIR=/srv/media-stack/config
DATA_DIR=/srv/media-stack/data
```

Then move the existing contents:

```bash
rsync -av ./config/ /srv/media-stack/config/
rsync -av ./data/ /srv/media-stack/data/
docker compose down
docker compose up -d
```

`./config/` and `./data/` are in `.gitignore` so personal data never leaks to the repo.

### Time zone

All apps are configured with `America/Argentina/Mendoza`. To change, edit the `TZ=` entries for each service in `docker-compose.yml`.

### User / permissions

Apps run with `PUID=1000` / `PGID=1000` (typical first user on Ubuntu/Debian). To match your own user, run `id -u` and `id -g`, then update those values in `docker-compose.yml`.

### HTTPS

Caddy is ready for automatic HTTPS via Let's Encrypt. To enable it, point a real domain at your server (DNS A record) and edit the Caddyfile in `config/caddy/` to add `email` and the domain. See the [Caddy docs](https://caddyserver.com/docs/automatic-https).

## First-time setup

After the stack is up and reachable:

1. **Prowlarr** — `Settings → Indexers → Add Indexer`. Add your favourite trackers.
2. **Sonarr / Radarr / Lidarr** — `Settings → Indexers → Add → Prowlarr` (uses Prowlarr's API key, found under `Settings → General` in Prowlarr).
3. **Sonarr / Radarr / Lidarr** — `Settings → Download Clients → Add → qBittorrent` (default port `8080` inside the container).
4. **qBittorrent** — log in with the temporary credentials printed in the container logs:
   ```bash
   docker logs qbittorrent | grep -i 'temporary password'
   ```
   Change the password immediately after logging in.
5. **Jellyfin** — add libraries pointing to `/data/movies`, `/data/series`, `/data/music`.
6. **Bazarr** — `Settings → Sonarr/Radarr → Connect` (paste each app's API key).
7. **Jellyseerr** — connect to Jellyfin (API key from `Dashboard → API Keys`) and to Sonarr/Radarr.
8. **Wizarr** — generate invitation links from the web UI to onboard family/friends.

## Daily operations

```bash
# Show what's running
docker compose ps

# Tail logs from one app
docker compose logs -f jellyfin

# Update a single image
docker compose pull sonarr
docker compose up -d sonarr

# Update everything
docker compose pull
docker compose up -d

# Stop the stack (keeps configs and data)
docker compose down

# Stop and delete EVERYTHING — configs included (destructive!)
docker compose down -v
```

## Troubleshooting

- **App shows a blank page or 404 after `docker compose up`.** Subpath config probably didn't apply. Run `bash scripts/configure-base-urls.sh` and then `docker compose restart`.
- **qBittorrent keeps asking for a password.** It's the temporary one printed by the container on first boot. Run `docker logs qbittorrent | grep -i 'temporary password'`.
- **Caddy returns 502 / can't reach the apps.** Make sure Caddy is up (`docker compose ps caddy`) and that all the other containers are on the `proxy` network (they are by default).
- **"Permission denied" errors writing to `/downloads` or `/movies`.** `PUID`/`PGID` in `docker-compose.yml` don't match your host user. Update them and restart.
- **"Address already in use" on ports 80/443.** Another web server (nginx, apache, another Caddy) is already bound. Stop it or change the ports in `docker-compose.yml`.

## Folder structure

```
media-stack/
├── config/                # Each app's settings (git-ignored)
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
├── data/                  # Media + downloads (git-ignored)
│   ├── movies/
│   ├── series/
│   ├── music/
│   └── downloads/
├── scripts/
│   └── configure-base-urls.sh
├── architecture.excalidraw
├── docker-compose.yml
├── .env.example
├── .gitignore
└── README.md
```

## Contributing

Pull requests welcome. Please keep changes scoped and update this README when you add or change services.

## Acknowledgements

- [LinuxServer.io](https://docs.linuxserver.io/) for maintaining most of the Docker images
- The [Servarr](https://wiki.servarr.com/) project (Sonarr, Radarr, Lidarr, Prowlarr, Bazarr)
- [Jellyfin](https://jellyfin.org) for the media server
- [Jellyseerr](https://github.com/Fallenbagel/jellyseerr) for the request UI
- [Wizarr](https://github.com/Wizarrrr/wizarr) for the invitation system
