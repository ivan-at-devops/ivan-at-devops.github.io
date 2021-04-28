FROM ubuntu:20.04

ARG BPC_UID
ARG BPC_PASS

RUN echo "#!/bin/sh\nexit 0" > /usr/sbin/policy-rc.d
COPY backuppc-ubuntu-installer  /root/
RUN sh /root/backuppc-ubuntu-installer

EXPOSE 80

CMD service backuppc start && service apache2 start && tail -F /dev/null
