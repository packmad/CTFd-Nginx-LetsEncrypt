A quick-tweak configuration for Docker-based CTFd, Nginx, and Let's Encrypt TLS.

# Huge Updates
We have created a new version of this repository, which supports scalable and load-balanced CTFd stack: [ScaledCTFd](https://github.com/chrisandoryan/ScaledCTFd). Give it a try!

# Quick Start
1. Open and edit `init-letsencrypt.sh`, fill in the customizable configuration variables, then save.
2. `./init-letsencrypt.sh`
3. Later restarts: `docker compose up --detach`

TLS defaults are vendored under `tls/` (copied into `data/certbot/conf/` by the init script). Compose waits for healthy MariaDB/Redis/CTFd before starting nginx.

If MariaDB fails to start after a broken first boot, remove `.data/mysql` and run `docker compose up --detach` again (this wipes CTFd DB data).

# Query Database
1. `docker compose exec db sh`
2. `mariadb -u ctfd -p`
3. `use ctfd;`
4. `show tables;`
