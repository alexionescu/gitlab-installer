gitlab-installer
================

This bash script installs GitLab 5.1 for you.

This script is intended to work on a **clean** install of Ubuntu 12.04 LTS x64.

* Unattended install once started
* Updates your packages
* Downloads & compiles ruby, redis, etc
* Creates user for git
* Installs gitlab-shell
* Sets up MySQL server & inits database
* Postfix for emails
* Sets up init script for gitlab
* Nginx for web interface


### USAGE

#### Run script as root account

    sudo su
    wget https://raw.github.com/alexionescu/gitlab-installer/master/gitlab-install.sh
    chmod +x ./gitlab-install.sh
    ./gitlab-install.sh
