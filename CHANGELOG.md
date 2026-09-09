# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- **`itzg/mc-backup:2026.9.0` moved to `itzg/mc-backup:2026.9.1`.** The freshness check reported the lag; the deploy job booted the stack on the new image before this landed.

## [1.5.2] - 2026-09-07

### Changed

- **`update.sh` names any new required variable before it moves.** An update can add a required variable; `docker compose up` used to stop on it after the checkout, with the tree already on the new tag. The script now lists the variables that appeared in `.env.example` since your version and refuses, before anything has moved, when a required one is not in your `.env`. Names only, never values.


  compose file boots and the backup cycle is exercised against the new image
  before this lands.

### Fixed

- **`.env.example` named image versions the compose file no longer pins.** It
  still showed `2026.8.2` for the backup image while the compose default was
  `2026.9.0`, so anyone copying the commented line as a starting point pinned
  something older than the tested combination.

## [1.5.0] - 2026-09-05

### Added

- **Backup and restore tested end to end.** Nine scenarios against the live
  stack: an archive is produced, it is readable, it contains a `level.dat`
  rather than an empty directory tree, a file written after the last archive
  reaches the next one, the archive unpacks into a world, and pruning is
  configured rather than merely intended.
- **The world is proved to have been flushed before it was read.** Before each
  archive the sidecar tells the server over RCON to stop writing and flush.
  What happens when that fails was measured, not assumed, against a sidecar
  given a deliberately wrong password: `itzg/mc-backup` retries five times,
  never archives without a successful flush, and exits 2 — which under
  `restart: unless-stopped` becomes a restart loop producing no backups at all,
  while everything in `docker compose ps` looks ordinary. Nobody watches a
  restart count, so the test reads the sidecar's own log for the flush having
  run and for the absence of RCON errors. Both assertions were confirmed to
  fire against the broken sidecar before being trusted.
- **Every content assertion names an archive whose cycle BEGAN after the state
  it is asserting about**, and no assertion pipes into an early-exiting `grep`.
  Which of the two settled the flake is not established: the run carrying only
  the first still failed and the run carrying both passed, but a synthetic
  reproduction of the SIGPIPE case never triggered it. The test prints the
  archive's contents on failure now, so the next occurrence is diagnosed from
  data rather than from a third guess. "The newest completed archive" is not the same
  thing: the cycle that finishes next may have started before the change, and
  it is entirely correct for it not to contain it. That ordering trap produced
  three separate CI failures before it was written down as one helper used
  everywhere.
- **A cold start can archive before there is a world, and the test says so
  rather than working around it.** The sidecar waits for the server's
  healthcheck, and that passes when the server answers — which on a slow
  machine is before the world directory has been written. The first archive
  then legitimately contains the server's files and no world. Never an issue at
  the shipped 23 hour interval; real for anyone who shortens it or restarts
  often.
- **The archive under test is chosen from the sidecar's log, not by
  modification time.** The newest file on disk is very often the one being
  written, and a half-written gzip is readable by `tar` for as far as it goes.
  Picking by mtime reported a world with no `level.dat` and an archive that
  would not unpack — both true of the file it was handed, and neither anything
  to do with the backups. An archive named by a log line that has a `save-on`
  after it is complete by definition.

## [1.4.0] - 2026-09-03

### Added

- **Per-image version overrides.** Every pin in the `x-images` block is
  now `${<PREFIX>_IMAGE_TAG:-repo:${<PREFIX>_IMAGE_VERSION:-tag@sha256:digest}}`.
  Set `<PREFIX>_IMAGE_VERSION` in `.env` to run a different version of one
  image while every other pin stays as tested (Compose pulls that tag
  without a digest), or `<PREFIX>_IMAGE_TAG` to replace the whole
  reference as before. A deployment that sets neither is unchanged. The
  freshness job, the Trivy matrix and the fleet digest automation resolve
  the nested default before reading a pin. Needs Docker Compose v2.5 or
  newer (2022): v2.0 to v2.4 leave the inner `${...}` unexpanded and
  `docker compose up` fails with an invalid reference instead of
  deploying something unexpected.

### Changed

- `itzg/mc-backup` 2026.8.2 to 2026.9.0.

## [1.3.0] - 2026-09-02

### Security

- **Container hardening.** Every service runs with
  `security_opt: no-new-privileges:true` (no privilege escalation via
  setuid binaries even if a process escapes its initial capability
  set). Infrastructure containers (the reverse proxy, databases,
  caches, backups) drop every Linux capability and add back only what
  their entrypoints need (bind :80/:443, chown a data directory, drop to
  the service user). Application containers keep the default capability
  set: upstream images assume it, and a wrong guess there is a boot loop
  in production, not a hardening win. CI boots the stack under these
  settings on every push.

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

- **`update.sh`**: unattended updates to the newest tagged release,
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
  `itzg/mc-backup` move from floating `latest` to the 2026.8.2 releases:
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

[Unreleased]: https://github.com/heyvaldemar/minecraft-server-docker-compose/compare/v1.5.2...HEAD
[1.5.2]: https://github.com/heyvaldemar/minecraft-server-docker-compose/compare/v1.5.1...v1.5.2
[1.5.1]: https://github.com/heyvaldemar/minecraft-server-docker-compose/compare/v1.5.0...v1.5.1
[1.5.0]: https://github.com/heyvaldemar/minecraft-server-docker-compose/compare/v1.4.0...v1.5.0
[1.4.0]: https://github.com/heyvaldemar/minecraft-server-docker-compose/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/heyvaldemar/minecraft-server-docker-compose/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/heyvaldemar/minecraft-server-docker-compose/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/heyvaldemar/minecraft-server-docker-compose/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/heyvaldemar/minecraft-server-docker-compose/releases/tag/v1.0.0
