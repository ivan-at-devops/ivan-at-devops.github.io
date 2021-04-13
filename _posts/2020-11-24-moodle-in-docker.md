---
title: "Moodle in Docker"
tags: Docker Moodle php.ini docker-compose
---

This is an example of how can a DevOps spend a day playing with his/her toys.

## Goal: In a Moodle course, have items rearranged

We are asked to manually rearrange lots of items in a big [Moodle](https://docs.moodle.org/) course.  
Doing it in production is very slow. It'll be a lot faster if we can use the [Mass actions](https://moodle.org/plugins/block_massaction) Moodle plugin. 
But that plugin is not installed in production, and we are not admin there, we can not install it there.  

**Way: Backup the course, install a Moodle in local, change the course here, and then restore it to production.**

In order to have Moodle in local, we need a [LAMP](https://en.wikipedia.org/wiki/LAMP_%28software_bundle%29)  
We search for the fastest way to have it, and we find a way using Docker. [Moodle in Docker](https://github.com/moodlehq/moodle-docker).  

### Goal: Have Docker

**Way: Use the [Docker official install doc](https://docs.docker.com/engine/install/ubuntu/), use the repository for Ubuntu.**

#### Common

``` bash

# requirements
sudo apt-get update
sudo apt-get install \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg-agent \
    software-properties-common

# repo
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"

# install
# also docker-compose
sudo apt-get update
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-compose

# test
# not yet!
#sudo docker run hello-world

``` 

#### [Postinstall](https://docs.docker.com/engine/install/linux-postinstall/) custom

- Allow regular users to run docker.
- Do not autorun on boot, manually run if needed.
- Docker uses lots of disk storage for images. Customize [Docker folder path](https://www.freecodecamp.org/news/where-are-docker-images-stored-docker-container-paths-explained/).
- Docker default network usually collides with other local networks. We'll better [customize it](https://serverfault.com/questions/916941/configuring-docker-to-not-use-the-172-17-0-0-range).
- These customizations are made in the [Docker daemon configuration file](https://docs.docker.com/engine/reference/commandline/dockerd/#daemon-configuration-file) 


``` bash

# enable regular user
sudo groupadd docker
sudo usermod -aG docker $USER
# refresh group membership, no need to logout
newgrp -

# test
# not yet!
#docker run hello-world

# disable autostart on boot
sudo systemctl disable  docker

# stop to customize
sudo systemctl stop     docker

sudo mkdir /docker

sudo tee /etc/docker/daemon.json << 'EOF'

{
  "bip": "10.200.0.1/24",
  "default-address-pools":[
    {"base":"10.201.0.0/16","size":24},
    {"base":"10.202.0.0/16","size":24}
  ],
  "data-root": "/docker"
}

EOF

``` 

#### Test

``` bash

# test
sudo dockerd
# look at the log...
# ctrl+c
sudo systemctl start    docker
docker run hello-world
docker info
docker version

``` 


### Goal: Have Moodle


#### Moodle source

Which [Moodle version](https://docs.moodle.org/dev/Releases)? ideally it should be the same version that in production, but we don't have privileges there...

**Obstacle: We don't know the version of Moodle.**

We search and find this way to [get Moodle version](https://docs.moodle.org/en/Moodle_version) from outside.

**Way: Use the help links in pages, and get the version from help URL.**
 
In our case, it was Moodle 3.5.


``` bash
git clone https://github.com/moodle/moodle.git
cd moodle
git checkout MOODLE_35_STABLE
cd ..
``` 


#### Moodle-Docker

``` bash

git clone https://github.com/moodlehq/moodle-docker.git
cd moodle-docker

# Set up path to Moodle code
export MOODLE_DOCKER_WWWROOT="$PWD/../moodle"
# Choose a db server (Currently supported: pgsql, mariadb, mysql, mssql, oracle)
export MOODLE_DOCKER_DB=mysql

# Ensure customized config.php for the Docker containers is in place
cp config.docker-template.php $MOODLE_DOCKER_WWWROOT/config.php
# Start up containers
bin/moodle-docker-compose up -d
# Initialize Moodle database for manual testing
bin/moodle-docker-compose exec webserver php admin/cli/install_database.php --agree-license --fullname="Docker moodle" --shortname="docker_moodle" --adminpass="test" --adminemail="admin@example.com"

# Test
curl -sS -i -w "%{http_code}\n" "http://localhost:8000" -o /dev/null

``` 

Everytime to start Moodle, we do:

``` bash
export MOODLE_DOCKER_WWWROOT="$PWD/../moodle"
export MOODLE_DOCKER_DB=mysql
bin/moodle-docker-compose start
``` 

And to stop it, we do:

``` bash
bin/moodle-docker-compose stop
``` 

At the end of the project, destroy docker images by:

``` bash
bin/moodle-docker-compose down
``` 

Tips:

- `docker-compose` starts `dockerd` itself if needed.
- On `dockerd` start, network goes down for a moment.


#### *Mass actions* plugin


From the [Mass actions plugin page](https://moodle.org/plugins/block_massaction) we read that it's no longer maintained, and in order to use it in Moodle >3.4 we'll better get [a fork from Syxton](https://github.com/Syxton/moodle-block_massaction).

``` bash
cd moodle
cd blocks
git clone https://github.com/Syxton/moodle-block_massaction.git massaction
``` 
After that, to finish plugin installation, as usual you must login as `admin/test` and visit the [admin page](http://localhost:8000/admin/).


### Goal: Have Moodle course rearranged

- In production Moodle, go to `Course administration > Backup > Jump to final step`
- Download the `*.mbz` backup file
- In local Moodle, go to `Front page settings > Restore`
- Upload the backup file

**Obstacle: Backup file is very big, so it can not be uploaded to Moodle.**

This is related to the setting [maxbytes](http://localhost:8000/admin/settings.php?section=sitepolicies):

``` 
maxbytes
Maximum uploaded file size
Default: Site upload limit (2MB)

This specifies a maximum size for files uploaded to the site.
  This setting is limited by the PHP settings `post_max_size` and `upload_max_filesize`, as well as the Apache setting `LimitRequestBody`.
  In turn, maxbytes limits the range of sizes that can be chosen at course or activity level. 
  If 'Site upload limit' is chosen, the maximum size allowed by the server will be used.

``` 

See these settings in the [phpinfo page](http://localhost:8000/admin/phpinfo.php).

- [Apache LimitRequestBody](https://httpd.apache.org/docs/2.4/mod/core.html#limitrequestbody) is by default unlimited. No need to change it.

- [PHP upload_max_filesize](https://www.php.net/manual/en/ini.core.php#ini.upload-max-filesize) is by default 8M, we need to increase it.

- [PHP post_max_size](https://www.php.net/manual/en/ini.core.php#ini.post-max-size) is by default 2M, we need to increase it.

Take note that the `php.ini` file is in:

```
Configuration File (php.ini) Path: /usr/local/etc/php
``` 


**Way: SSH log into the main Docker instance, and change that in php.ini**

 
``` bash
# list running instances
docker ps

# run an interactive shell inside the main instance
docker exec -ti moodle-docker_webserver_1 /bin/bash
``` 

And now, inside the instance:


``` bash
# create new file in conf.d instead of changing the upstream file
tee /usr/local/etc/php/conf.d/max.ini << 'EOF'
post_max_size           = 256M
upload_max_filesize     = 256M
EOF

# reload apache
apachectl graceful
``` 

Logout with `CTRL+D` as usual.

You can check now the values are ok:  
http://localhost:8000/admin/phpinfo.php


**Way to the end: Perform the operations as Moodle user, without issues, to the end**

- In local Moodle, go to `Front page settings > Restore`
- Upload the backup file
- Turn editing on
- Use Mass Actions block to rearrange content
- Backup
- Download the backup file


And that's it. I hope you've enjoyed it.

