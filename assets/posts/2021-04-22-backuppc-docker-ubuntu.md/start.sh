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

