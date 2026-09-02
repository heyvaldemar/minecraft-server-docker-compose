# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

_(no unreleased changes yet)_

## [1.2.0] - 2026-09-02

### Added

- **Resource limits on every service, as `.env`-overridable defaults.**
  Each service now carries memory and CPU limits plus reservations
  (`<SERVICE>_MEMORY_LIMIT`, `_CPU_LIMIT`, `_MEMORY_RESERVATION`,
  `_CPU_RESERVATION`, defaults listed in `.env.example`). Set any of
  them in `.env` and the override survives every `git pull`. The
  defaults are what CI boots the stack under, so they are known to be
  enough for a fresh install; raise a limit if a service is OOM-killed
  under your real load (`docker inspect` shows `OOMKilled=true`).

## [1.1.0] - 2026-09-02

### Added

- **`update.sh`** — unattended updates to the newest tagged release,
  and nothing else: a tag is cut only after CI has booted the pinned
  images and passed the smoke tests, so "update to the latest tag" means
  "update to a combination a machine has already run". It refuses to
  cross a major version on its own (`--allow-major` after reading the
  notes), refuses a checkout with local modifications, and supports
  `--dry-run`. Put it on a cron timer for hands-off minor/patch updates.

## [1.0.0] - 2026-08-31

First semver release. Brings this template to the fleet standard established
in [keycloak-traefik-letsencrypt-docker-compose](https://github.com/heyvaldemar/keycloak-traefik-letsencrypt-docker-compose)
v1.2.0.

### Security

- **Images pinned by `tag@sha256:digest`**: `itzg/minecraft-server` and
  `itzg/mc-backup` move from floating `latest` to the 2026.8.2 releases —
  a `latest` pin made deployments unreproducible and updates invisible.
- **RCON password untracked from git.** The tracked `.env` carried a
  generated-looking RCON password published on GitHub; rotate it if your
  deployment reused it. `.env` is now gitignored and compose fails fast
  when the password is unset.

### Changed

- **Image pins live in the compose file as interpolation defaults**
  (`x-images` block): `git pull` alone delivers the tested version
  combination; `.env` carries only the RCON password and deliberate
  overrides. Every game setting now has a compose-level default.
- README rebuilt to the fleet evaluator-first structure.

### Added

- **Deployment Verification workflow**: actionlint; Trivy scans of both
  pinned images; weekly `check-pin-freshness` (digest drift + release lag
  against both itzg upstreams); deploy-and-test that boots the server with
  ephemeral credentials, waits for the built-in healthcheck, proves RCON
  answers `list`, and requires a backup archive to appear.

[Unreleased]: https://github.com/heyvaldemar/minecraft-server-docker-compose/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/heyvaldemar/minecraft-server-docker-compose/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/heyvaldemar/minecraft-server-docker-compose/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/heyvaldemar/minecraft-server-docker-compose/releases/tag/v1.0.0
