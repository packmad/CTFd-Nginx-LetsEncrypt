A quick-tweak configuration for Docker-based CTFd, Nginx, and Let's Encrypt TLS.

# Huge Updates
We have created a new version of this repository, which supports scalable and load-balanced CTFd stack: [ScaledCTFd](https://github.com/chrisandoryan/ScaledCTFd). Give it a try!

# Quick Start
1. Open and edit `init-letsencrypt.sh`, fill in the customizable configuration variables, then save.
2. `sudo ./init-letsencrypt.sh`
3. `docker compose up --detach`


# Query Database
1. `docker compose exec db sh`
2. `mariadb -u ctfd -p`
3. `use ctfd;`
4. `show tables;`
