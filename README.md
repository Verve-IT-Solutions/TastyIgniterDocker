# TastyIgniter Docker

Run with docker compose for automatic database configuration

```sh
git clone https://github.com/Verve-IT-Solutions/TastyIgniterDocker.git
cd TastyIgniterDocker
```
change the needed settings in the docker-compose using `nano docker-compose.yml`
```sh
docker compose up db -d
sleep 10
docker compose up --build -d
```

Browse to port 8001 of your docker host. Use the `/admin` page to set up the admin and insert the general info

## Credits
TastyIgniter: https://github.com/tastyigniter/TastyIgniter
