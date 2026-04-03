# Plugins

Most plugins are managed automatically via `MODRINTH_PROJECTS` in `.env` and downloaded at container startup.

This `plugins` folder is only for `.jar` files that cannot be sourced from Modrinth (e.g., premium or custom plugins). Any `.jar` placed here will be copied into the server's plugin directory on startup.