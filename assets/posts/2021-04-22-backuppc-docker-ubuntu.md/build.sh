#! /bin/sh

NAME=bpc

docker rmi -f $NAME  2>/dev/null

docker build                          \
  --build-arg BPC_UID="$BPC_UID"      \
  --build-arg BPC_PASS="$BPC_PASS"    \
  --tag $NAME .
