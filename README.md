# Minecraft Server in a Docker Compose

Install the Docker Engine by following the official guide: https://docs.docker.com/engine/install/

Install the Docker Compose by following the official guide: https://docs.docker.com/compose/install/

Note that `plugins` folder should be in the same directory with `minecraft-server-docker-compose.yml`

Deploy Minecraft server with a Docker Compose using the command:

`docker compose -f minecraft-server-docker-compose.yml -p minecraft up -d`

# Minecraft Server Management

Apply new configuration after a change in the `minecraft-server-docker-compose.yml` using the command:

`docker compose -f minecraft-server-docker-compose.yml -p minecraft up -d`

Connect to the Minecraft server command-line interface using the command:

`docker exec -i ContainerName rcon-cli`

Stop Minecraft server using the command:

`docker exec ContainerName rcon-cli stop`
