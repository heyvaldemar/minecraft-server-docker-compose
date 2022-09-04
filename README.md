# Minecraft Server in a Docker Compose

Install Docker Engine and Docker Compose by following my [guide](https://www.heyvaldemar.com/install-docker-engine-and-docker-compose-on-ubuntu-server/).

Note that `plugins` folder should be in the same directory with `minecraft-server-docker-compose.yml`

Deploy Minecraft server with a Docker Compose using the command:

`docker compose -f minecraft-server-docker-compose.yml -p minecraft up -d`

Detailed installation guide can be found on my [website](https://www.heyvaldemar.com/install-minecraft-server-with-docker-compose/).

# Minecraft Server Management

Apply new configuration after a change in the `minecraft-server-docker-compose.yml` using the command:

`docker compose -f minecraft-server-docker-compose.yml -p minecraft up -d`

Connect to the Minecraft server command-line interface using the command:

`docker exec -i ContainerName rcon-cli`

Stop Minecraft server using the command:

`docker exec ContainerName rcon-cli stop`

# Infrastructure Model
![Infrastructure model](.infragenie/infrastructure_model.png)

# Author
hey, I’m Vladimir Mikhalev, but my friends call me Valdemar.

🌐 My [website](https://www.heyvaldemar.com/) with detailed IT guides\
🎬 Follow me on [YouTube](https://www.youtube.com/channel/UCf85kQ0u1sYTTTyKVpxrlyQ?sub_confirmation=1)\
🐦 Follow me on [Twitter](https://twitter.com/heyValdemar)\
🎨 Follow me on [Instagram](https://www.instagram.com/heyvaldemar/)\
🎸 Follow me on [Facebook](https://www.facebook.com/heyValdemarFB/)\
🎥 Follow me on [TikTok](https://www.tiktok.com/@heyvaldemar)\
💻 Follow me on [LinkedIn](https://www.linkedin.com/in/heyvaldemar/)\
🐈 Follow me on [GitHub](https://github.com/heyvaldemar)

# Communication
👾 Chat with IT pros on [Discord](https://discord.com/invite/D7fGMYjdR9)\
🚀 Chat with IT pros on [Telegram](https://t.me/heyValdemarCOMchat)\
📧 Reach me at ask@sre.gg

# Give Thanks
💎 Support on [GitHub](https://github.com/sponsors/heyValdemar)\
🏆 Support on [Patreon](https://www.patreon.com/heyValdemar)\
🥤 Support on [BuyMeaCoffee](https://www.buymeacoffee.com/heyValdemar)\
🍪 Support on [Ko-fi](https://ko-fi.com/heyValdemar)\
💖 Support on [PayPal](https://www.paypal.com/paypalme/heyValdemarCOM)
