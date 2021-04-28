FROM ubuntu:20.04

ARG BPC_UID
ARG BPC_PASS

RUN adduser --system --uid=$BPC_UID --home /var/lib/backuppc --group --disabled-password --shell /bin/false backuppc

RUN echo "#!/bin/sh\nexit 0" > /usr/sbin/policy-rc.d
COPY backuppc-ubuntu-installer  /root/
RUN sh /root/backuppc-ubuntu-installer

EXPOSE 80

CMD service backuppc start && service apache2 start && tail -F /dev/null
