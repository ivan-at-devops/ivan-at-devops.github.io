---
title: "BackupPC in Docker with Ubuntu image"
tags: BackupPC Docker Docker-Compose Ubuntu
---

BackupPC for personal use, without installing it.

BackupPC has an unattractive and misleading name. Despite this, I find BackupPC is a great piece of software that deserves more recognition.  
It has advanced backup methods [to reduce size and transfer](https://en.wikipedia.org/wiki/BackupPC). It's great for browsing the backed up files, and you can restore single files easily.  
For small files sometimes I use `git` as a backup solution, but it's not so good for big files. BackupPC handles efficiently mutable big binary files (for instance: virtual machine disks).  

So I want to use BackupPC for my workstation, but it requires a web server, and I don't want to install it in the system. So let's use Docker to run it.

## Background

Available BackupPC docs:

- [GitHub source](https://github.com/backuppc/backuppc)
- [GitHub pages/site](https://backuppc.github.io/backuppc/)
- [GitHub wiki](https://github.com/backuppc/backuppc/wiki) with custom install instructions
- Always useful [ArchWiki](https://wiki.archlinux.org/index.php/BackupPC)

Already done BackupPC Docker images:

- [adferrand/docker-backuppc](https://github.com/adferrand/docker-backuppc)
- [tiredofit/docker-backuppc](https://github.com/tiredofit/docker-backuppc)

These images use [Alpine Linux](https://alpinelinux.org/) as base.

### Alpine vs Ubuntu

Alpine Linux is a base distro focused on beeing small.

I once too cared about size, and I've used: 
[Puppy Linux](https://puppylinux.com/), 
[SliTaz](https://www.slitaz.org/en/), 
[DSL: Damn Small Linux](http://www.damnsmalllinux.org/), 
[Slackware](http://www.slackware.com/), 
[Linux From Scratch](http://www.linuxfromscratch.org/), 
...  
Not anymore. Now I care more about developer time; knowledge reuse, avoid doing the same things with different tools, avoid spend time trying and debugging them.


Alpine Linux:

- uses `apk` as package manager, not `apt`, not `yum`. Has its own smaller repos.
- does not use `libc`, and this sometimes causes bugs difficult to debug, reportedly when compiling python libraries.
- does not use `bash` but `ash` from `busybox`.
- does not have the tools I'm used to, that I need for debugging.

See more [opinions](https://www.reddit.com/r/docker/comments/b6gk1x/why_use_ubuntu_as_base_image_when_alpine_exists/).
Ubuntu team also has a [post](https://ubuntu.com/blog/docker-alpine-ubuntu-and-you).
Size is not so important in Docker, because base image is stored only once, and other images are layers over it.

I could not find existing BackupPC Docker images based on Ubuntu.
So I decided to read the install instructions for Ubuntu, and adapt them to Docker.


## DEB package inspection

One way that was explored, but abandoned, was to inspect the current BackupPC `deb` package for Ubuntu, to adapt the `postinst` script.

You can [download the package](https://askubuntu.com/questions/30482/is-there-an-apt-command-to-download-a-deb-file-from-the-repositories-to-the-curr) with:

``` bash
apt-cache search backuppc
apt-cache show   backuppc
apt-get download backuppc
``` 

Then [unpack the package](https://unix.stackexchange.com/questions/138188/easily-unpack-deb-edit-postinst-and-repack-deb) with:

``` bash
mkdir deb
sudo dpkg-deb -R backuppc_3.3.2-3_amd64.deb deb

# edit
# nano deb/DEBIAN/postinst

# repack
# dpkg-deb -b deb modified.deb
``` 


## Ubuntu installation instructions

From the manual:  
[Step 2: Installing the distribution](https://backuppc.github.io/backuppc/BackupPC.html#Step-2:-Installing-the-distribution)

From the wiki:  
[Installing BackupPC 4 from tarball or git on Ubuntu](https://github.com/backuppc/backuppc/wiki/Installing-BackupPC-4-from-tarball-or-git-on-Ubuntu)

BackupPC is a Perl program that runs as a service, and Apache conects to it by CGI.
There are `apt` packages available, but only for version 3.x. We want version 4.x, that is much better performant.  
So we'll have to install it from sources, that is not trivial.
We'll basically follow an existing script from [Molnix](https://molnix.com/).


## backuppc-ubuntu-installer

``` bash
wget https://gitlab.molnix.com/molnix-open-source/backuppc-ubuntu-installer/-/raw/master/backuppc-ubuntu-installer
``` 

This script does the job, in a full Ubuntu system, but it has some issues on the Ubuntu Docker image.
Also, it can be improved with some small changes:

- There is no reason to use `bash`. It can use the faster `sh` that is `dash`, default Ubuntu system shell. It's easy and it requires only a few changes. See [differences](https://wiki.ubuntu.com/DashAsBinSh) and [man page](https://linux.die.net/man/1/dash).
- It uses both `wget`and `curl` for no reason. It could use only one of them, say `wget`.
- It uses `sudo`in exacly one place, but the whole script must be ran as `root` anyway. It can avoid `sudo`, that by the way doesn't exist in the image.
- Some packages (`tzdata`) fail to install, because require input from user. We can fix it by using the usual `export DEBIAN_FRONTEND=noninteractive`. 
- Some packages (`rsync`) fail to install, because require restart of the service, but the image has no `systemd` nor alike. We can fix it following this [post](http://jpetazzo.github.io/2013/10/06/policy-rc-d-do-not-start-services-automatically/). 
  This fix is only for Docker, so we'll make it outside the script, in the `Dockerfile`.
- There is no need to upgrade all installed packages. You should not do this without asking or warning the system owner.
- BackupPC once installed will require `ping`. We'll add `iputils-ping` to the packages we must install.
- It's better to handle the admin password as an envvar/argument than having it in a file, that ends up inside the image and the project git repo. 
- This script creates a `backuppc` user, with auto `uid` number. For Docker we need to set the `uid` of that user, to avoid permission issues between instance and host. We'll add the option to set the `uid` user number.


See the original version: [backuppc-ubuntu-installer.orig](/assets/posts/2021-04-22-backuppc-docker-ubuntu.md/backuppc-ubuntu-installer.orig)  
See my version: [backuppc-ubuntu-installer](/assets/posts/2021-04-22-backuppc-docker-ubuntu.md/backuppc-ubuntu-installer)  


## Devel


We'll start with the base Docker image, and run and debug the installation script until ok.  
Let's start with this Dockerfile:

``` 
FROM ubuntu:20.04
COPY backuppc-ubuntu-installer  /root/
EXPOSE 80
``` 


Remove previous instance or image:
``` bash
docker rm  -f bpc
docker rmi -f bpc

``` 

Build:
``` bash
docker build --tag bpc .
``` 

Run:
``` bash
docker run \
--name=bpc \
-v "$PWD"/v/etc/BackupPC:/etc/BackupPC \
-v "$PWD"/v/var/lib/backuppc:/var/lib/backuppc \
-p 8080:80 \
-ti \
bpc
``` 

Exit with `CTRL+D` as usual. Instance will stop by itself.

Once inside the container, run: 

``` bash
sh /root/backuppc-ubuntu-installer
``` 

You'll probably get the error:

``` 
Setting up rsync (3.1.3-8) ...
invoke-rc.d: could not determine current runlevel
invoke-rc.d: policy-rc.d denied execution of start.
``` 

That's because `rsync` install/update requires restart of the service, but the Docker image has no `systemd` nor alike.  
We can fix it following this [post](http://jpetazzo.github.io/2013/10/06/policy-rc-d-do-not-start-services-automatically/). 

So, run this before the installation script:

``` bash
echo "#!/bin/sh\nexit 0" > /usr/sbin/policy-rc.d
``` 

If all it's ok, you can now access http://backuppc:password@127.0.0.1:8080


We'll have to remember to `apt-get clean` after the installation script, in the Dockerfile, to reduce a little the image size.


## Fix user perms

It all seems ok, but when we try to run the instance again, there is an error about file permissions.  
This is very common while working with Docker.  

The container has two *bind mounts*, folders inside the instance that are actually in the host:

- `/etc/BackupPC     = {host}/v/etc/BackupPC`  
  We want to configure BackupPC from outside, and keep the configuration between runs.
  
- `/var/lib/backuppc = {host}/v/var/lib/backuppc`  
  We want to keep the backed up data outside, and obviously to keep it between runs.

Notice the folder `./v` has been auto generated, by just defining it in Dockerfile.

Content in these folders is generated and owned by the `backuppc` user.  
In order to avoid permission issues, that user must have the same `uid` that the user that is running the host.  
So we'll pass the `uid` of the host user to the instance script as an envvar, $BPC_UID.


## Populate Bind mounts

Another common issue in Docker. When you `docker build`, there are no bind mounts, neither the ones you want to use when `docker run`.  
If some files are created in the mount points at build time, they will be overlapped with empty folders at run time. 

BackupPC service needs some configuration files to run. If `/etc/BackupPC` is empty, then you'll get the error:

``` bash
Starting backuppc: No language setting
BackupPC::Lib->new failed
``` 

Service returns exit code 2, Docker kills the instance.


How can we get the needed files from the image?  
One easy way is to run it with different bind mounts, and copy the files outside.  
We actually only need the files in `/etc/BackupPC`.


``` bash
NAME=bpc

docker run \
-v "$PWD"/vv/etc/:/vv \
-p 8080:80 \
-ti \
$NAME /bin/bash -c "cp -a /etc/BackupPC /vv/"


rm -rf  v/etc/BackupPC
cp -a  vv/etc/BackupPC  v/etc/
sudo rm -rf vv

``` 

BackupPC while using rsync acts as a common ssh user, and so it needs its own key, in its home folder `/var/lib/backuppc`.  
We can make it now, using the same commands of the installation script:

``` bash
mkdir -p                                                  v/var/lib/backuppc/.ssh
chmod 700                                                 v/var/lib/backuppc/.ssh
echo -e "BatchMode yes\nStrictHostKeyChecking no" >       v/var/lib/backuppc/.ssh/config
ssh-keygen -q -t rsa -b 4096 -N '' -C "BackupPC key" -f   v/var/lib/backuppc/.ssh/id_rsa
chmod 600                                                 v/var/lib/backuppc/.ssh/id_rsa
chmod 644                                                 v/var/lib/backuppc/.ssh/id_rsa.pub
#chown -R backuppc:backuppc                                v/var/lib/backuppc/.ssh

``` 


## Fix start

Another common issue in Docker, is to have more that one service, and need to keep them running.  
A Docker instance is meant to run only one service, in foreground, by its `CMD` line, and die when the service stops.  
If the service goes to background, Docker unfortunatelly mistakes it, and kills the instance.  
This is not evident when you use `docker run -ti ...`, because the open terminal (the `-ti` part) keeps the instance running.  
But you'll find this issue as soon as you `docker run -d ...` or `docker compose ...`.

The workarounds are many. In some cases, you can use the foreground version of the service.

``` 
# Use this:
CMD /usr/sbin/apache2ctl -D FOREGROUND

# Or this:
CMD service php7.4-fpm start && /usr/sbin/apache2ctl -D FOREGROUND
``` 

Notice this only *monitors* the last service, not both.

In other cases, you can use `supervisord`, that is a Python program that keeps things alive. Kind of `mmonit` or `systemd`. Great if you already installed `pip`.

In simpler cases, like now, we can use a trick, to keep Docker instance alive:

``` 
CMD service backuppc start && service apache2 start && tail -F /dev/null
``` 

See some internet wisdom: 
[one](https://stackoverflow.com/questions/30209776/docker-container-will-automatically-stop-after-docker-run-d), 
[two](https://github.com/docker/compose/issues/1926), 
[three](https://stackoverflow.com/questions/38546755/docker-compose-keep-container-running), 
[four](https://stackoverflow.com/questions/25775266/how-to-keep-docker-container-running-after-starting-services), 
[five](https://stackoverflow.com/questions/44376852/how-to-start-apache2-automatically-in-a-ubuntu-docker-container), 
...


## Docker Compose


The final Dockerfile:

``` 
FROM ubuntu:20.04

ARG BPC_UID
ARG BPC_PASS

RUN echo "#!/bin/sh\nexit 0" > /usr/sbin/policy-rc.d
COPY backuppc-ubuntu-installer  /root/
RUN sh /root/backuppc-ubuntu-installer

EXPOSE 80

CMD service backuppc start && service apache2 start && tail -F /dev/null

``` 

Download [Dockerfile](/assets/posts/2021-04-22-backuppc-docker-ubuntu.md/Dockerfile)


This can be build with a `build.sh` script:

``` bash
#! /bin/sh

NAME=bpc

docker rmi -f $NAME  2>/dev/null

docker build                          \
  --build-arg BPC_UID="$BPC_UID"      \
  --build-arg BPC_PASS="$BPC_PASS"    \
  --tag $NAME .

``` 

Download [build.sh](/assets/posts/2021-04-22-backuppc-docker-ubuntu.md/build.sh)

Build it:

``` bash
export BPC_UID=$(id -u)
export BPC_PASS=somepass
sh build.sh
``` 


This can be run with a `start.sh` script:

``` bash
#! /bin/sh

NAME=bpc

docker rm  -f $NAME  2>/dev/null

docker run                                      \
--name=$NAME                                    \
-v "$PWD"/v/etc/BackupPC:/etc/BackupPC          \
-v "$PWD"/v/var/lib/backuppc:/var/lib/backuppc  \
-p 8080:80                                      \
-ti                                             \
$NAME

``` 

Download [start.sh](/assets/posts/2021-04-22-backuppc-docker-ubuntu.md/start.sh)

Run it:

``` bash
sh start.sh
``` 

You can also use `docker-compose` or `docker compose` depending on your version:

``` yaml
version: "3"

services:
  backuppc:
    build:
      context: .
      args:
        - BPC_UID=${BPC_UID}
        - BPC_PASS=${BPC_PASS}
    ports:
      - "8080:80"
    volumes:
      - "./v/etc/BackupPC:/etc/BackupPC:rw"
      - "./v/var/lib/backuppc:/var/lib/backuppc:rw"

``` 

Download [compose.yml](/assets/posts/2021-04-22-backuppc-docker-ubuntu.md/compose.yml)


Compose it:

``` bash
export BPC_UID=$(id -u)
export BPC_PASS=somepass
docker compose up
``` 

## BackupPC conf

All configuration can be made using the web GUI, or the files in the bind mounts.  
How to configure it will/shall be a matter of another article.
 





