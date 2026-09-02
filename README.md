# Minecraft Server (Paper) — Docker Compose

[![Deployment Verification](https://github.com/heyvaldemar/minecraft-server-docker-compose/actions/workflows/deployment-verification.yml/badge.svg?branch=main)](https://github.com/heyvaldemar/minecraft-server-docker-compose/actions/workflows/deployment-verification.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## Contents

- [Why this stack?](#why-this-stack)
- [Prerequisites](#prerequisites)
- [Getting started](#getting-started)
- [Features](#features)
- [Plugins](#plugins)
- [Supply chain trust](#supply-chain-trust)
- [Production checklist](#production-checklist)
- [Backups](#backups)
- [Testing](#testing)
- [About the maintainer](#about-the-maintainer)

This repository deploys a **Paper Minecraft server** with automatic plugin installation (Modrinth + direct URLs, Geyser/Floodgate for Bedrock crossplay out of the box) and a scheduled **world backup container**. One `docker compose up` away from a survival server your friends can join.

📙 Full narrative installation guide on the blog: [heyvaldemar.com/install-minecraft-server-using-docker-compose/](https://www.heyvaldemar.com/install-minecraft-server-using-docker-compose/).

## Why this stack?

| Need | This stack | Manual install | Other compose examples |
|------|-----------|----------------|------------------------|
| Ready to deploy in <10 min | ✅ | ❌ java, jars, systemd | Often |
| Plugins auto-installed on start | ✅ Modrinth + URL lists | Manual downloads | Rare |
| Bedrock crossplay (Geyser/Floodgate) preconfigured | ✅ | Manual setup | Rare |
| Scheduled world backups + pruning | ✅ RCON-coordinated `mc-backup` | Manual cron + save-off dance | Rare |
| Upstream images pinned by `sha256` digest | ✅ | N/A | Almost never (usually `latest`) |
| Weekly pin-freshness check in CI | ✅ | N/A | Rare |
| CI-verified deployment on every push | ✅ boots a real server | N/A | Rare |
| Every setting tunable via env | ✅ 40+ knobs with sane defaults | server.properties by hand | Varies |

Two moving parts (server + backups sidecar). The heavy lifting comes from the excellent [`itzg/minecraft-server`](https://github.com/itzg/docker-minecraft-server) and [`itzg/mc-backup`](https://github.com/itzg/docker-mc-backup) images, pinned and wired together.

## Prerequisites

- **A server** (Linux recommended) with Docker Engine 24+ and Docker Compose 2.20+.
- **~3 GB free RAM** (2 GB heap default + overhead) and a CPU core or two; more for many players or heavy plugins.
- **Port 25565 open** (TCP) on the firewall for Java Edition; Geyser's Bedrock port needs extra config if you use it beyond LAN.
- **Disk for the world and backups** — worlds grow; the default retention keeps 7 days of archives.

## Getting started

```bash
# 1. Clone
git clone https://github.com/heyvaldemar/minecraft-server-docker-compose
cd minecraft-server-docker-compose

# 2. Create the Docker network the stack expects
docker network create minecraft-server-network

# 3. Copy the environment template and set the RCON password
cp .env.example .env
$EDITOR .env
# ^ Required: MINECRAFT_SERVER_RCON_PASSWORD. Everything else has defaults.
#   Keeping MINECRAFT_SERVER_EULA=true means you accept the Minecraft EULA.

# 4. Deploy
docker compose -f minecraft-server-docker-compose.yml -p minecraft up -d
```

First boot downloads the Paper jar and the configured plugins, then generates the world — give it a few minutes. Players connect to `your-server-ip:25565`.

### What success looks like

```bash
# The server container turns healthy once it accepts connections:
docker compose -f minecraft-server-docker-compose.yml -p minecraft ps

# RCON works (lists online players):
docker compose -p minecraft exec minecraft-server rcon-cli list

# Watch the boot log:
docker compose -p minecraft logs -f minecraft-server

# Backups land in ./minecraft-server-data-backups on the schedule:
ls minecraft-server-data-backups/
```

### Common first-deploy issues

- **Container exits immediately with an EULA message.** `MINECRAFT_SERVER_EULA` must be `true` (you are accepting the [Minecraft EULA](https://www.minecraft.net/eula)).
- **`docker compose up` fails with `set in .env`.** `MINECRAFT_SERVER_RCON_PASSWORD` is empty — generate one per `.env.example`.
- **`network minecraft-server-network not found`.** Step 2 was skipped.
- **Slow first start.** Paper jar + plugins download once; later starts are much faster.

### Apply `.env` or compose-file changes

```bash
docker compose -f minecraft-server-docker-compose.yml -p minecraft up -d --force-recreate
```

## Features

- **Paper server** (`TYPE=PAPER`, `VERSION=LATEST` by default — pin a game version via `MINECRAFT_SERVER_VERSION` for stability).
- **Automatic plugin install** from Modrinth project slugs and direct download URLs, with dependency resolution.
- **Bedrock crossplay ready** — Floodgate ships in the default plugin list; pair with Geyser to let Bedrock players join.
- **RCON enabled** for admin commands (`rcon-cli` inside the container) and coordinated backups.
- **RCON-coordinated backups** — `mc-backup` runs `save-off`/`save-all` around each archive so world saves are consistent, then prunes archives older than the retention window.
- **40+ game settings** (mode, difficulty, view distance, whitelist, ops, world type…) exposed as env vars with compose-level defaults.
- **Local bind mounts** — world data in `./minecraft-server-data`, archives in `./minecraft-server-data-backups`, custom plugin jars in `./plugins`.

## Plugins

Two mechanisms, combinable:

- `MINECRAFT_SERVER_MODRINTH_PROJECTS` — comma-separated [Modrinth](https://modrinth.com/plugins) slugs (default: `viaversion,viabackwards,skinsrestorer`), with `MODRINTH_DOWNLOAD_DEPENDENCIES=required`.
- `MINECRAFT_SERVER_PLUGINS` — newline/comma-separated direct jar URLs (default: latest Floodgate build).
- Drop `.jar` files into `./plugins/` for anything not available by URL.

Plugins are re-resolved on every container start, so version bumps arrive with a `--force-recreate`.

## Supply chain trust

This repository is a **deployment template** orchestrating two upstream images:

- [`itzg/minecraft-server`](https://github.com/itzg/docker-minecraft-server) — the de-facto standard Minecraft server image
- [`itzg/mc-backup`](https://github.com/itzg/docker-mc-backup) — its companion backup sidecar

Both are pinned to `tag@sha256:<digest>` as interpolation defaults in the compose file's `x-images` block — `git pull` alone delivers the version combination this repository has tested. Setting an `*_IMAGE_TAG` variable in `.env` overrides the default. The daily `check-pin-freshness` CI job re-resolves both pinned tags against Docker Hub and compares the pinned versions against the latest itzg releases — any drift fails the run and notifies the maintainer. GitHub Actions are pinned by commit SHA; Dependabot keeps those fresh.

Note the deliberate trade-off: the **image** is pinned for reproducibility, while `VERSION=LATEST` floats the **game version** by default. Pin `MINECRAFT_SERVER_VERSION` too if plugin compatibility matters to you.

## Production checklist

- [ ] **Strong RCON password** — it is remote admin access to the server console.
- [ ] **Do not expose 25575 (RCON)** beyond the Docker network; the compose file does not publish it — keep it that way.
- [ ] **Set `MINECRAFT_SERVER_OPS`** to your username(s) so you can moderate in-game.
- [ ] **Consider a whitelist** (`MINECRAFT_SERVER_WHITELIST`) for private servers; `ONLINE_MODE=true` (default) keeps authentication against Mojang.
- [ ] **Off-host backups** — `./minecraft-server-data-backups` lives on the same disk as the world. Sync it elsewhere (restic, rclone, S3) for real disaster recovery.
- [ ] **Pin the game version** before inviting players if you rely on specific plugins.

## Backups

The `mc-backup` sidecar coordinates with the server over RCON: `save-off` → `save-all` → tar the world → `save-on`, on an interval (`MINECRAFT_SERVER_BACKUP_INTERVAL`, default 23h), pruning archives older than `MINECRAFT_SERVER_PRUNE_BACKUPS_DAYS` (default 7). Archives are plain `.tar.gz` files in `./minecraft-server-data-backups` — restore by stopping the stack, extracting an archive over `./minecraft-server-data`, and starting again.

## Unattended updates

Releases are the update channel: a tag is cut only after CI has built the pinned images, booted the full stack, and passed the smoke tests. `update.sh` moves a deployment to the newest tag and nothing else:

```bash
./update.sh --dry-run   # show what would be applied
./update.sh             # update within the current major and redeploy
```

Put it on a timer for hands-off minor/patch updates:

```bash
# crontab -e
17 5 * * *  /opt/minecraft-server-docker-compose/update.sh >> /var/log/minecraft-server-update.log 2>&1
```

The script refuses to cross a MAJOR template version on its own — majors are breaking by definition and their release notes exist to be read. After reading them, `./update.sh --allow-major` performs the jump. It also refuses to touch a checkout with local modifications: your customization belongs in `.env`, which updates never overwrite.

This is deliberately a host-side script and not a container in the stack: an in-stack updater needs the Docker socket (root on the host) and turns "someone pushed to a repo" into "someone deployed to your machine" with no operator in the loop. A cron job under your own user updates only to tagged, CI-verified states and leaves the trust boundary where it was.

## Resource limits

Every service carries memory and CPU limits plus reservations as compose-level defaults — the same values CI boots the stack under. Override any of them in `.env` (the knobs and their defaults are listed in `.env.example`, e.g. `TRAEFIK_MEMORY_LIMIT=512m`) and the override survives every `git pull`. If a service is OOM-killed under real load, `docker inspect <container> --format '{{.State.OOMKilled}}'` says so; raise its `_MEMORY_LIMIT` and recreate.

## Testing

The [Deployment Verification](https://github.com/heyvaldemar/minecraft-server-docker-compose/actions/workflows/deployment-verification.yml?query=branch%3Amain) workflow runs on every push, pull request, and every day at 06:00 UTC:

1. **Lint** — actionlint on the workflow.
2. **Trivy scans** of both pinned images (CRITICAL/HIGH, SARIF to the Security tab).
3. **Pin freshness** (daily/manual) — digest drift against Docker Hub plus release-lag checks against both itzg upstreams.
4. **Deploy-and-test** — boots a real Paper server with ephemeral credentials, waits for the built-in healthcheck to pass (jar + plugin download + world generation), proves RCON answers `list`, and requires a backup archive to appear before the run may pass.

A green run is the authoritative proof that the shipped configuration produces a joinable server — not just a started container.

---

## About the maintainer

<div align="center">

**Maintained by [Vladimir Mikhalev](https://github.com/heyvaldemar)** — Docker Captain · IBM Champion · AWS Community Builder

[YouTube](https://www.youtube.com/channel/UCf85kQ0u1sYTTTyKVpxrlyQ?sub_confirmation=1) · [Blog](https://heyvaldemar.com) · [LinkedIn](https://www.linkedin.com/in/heyvaldemar/)

</div>
