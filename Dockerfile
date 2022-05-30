FROM ubuntu:focal
ENV TZ=Europe/Bratislava
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone
RUN apt update -y && apt upgrade -y
RUN apt install iproute2 inetutils-ping curl cron socat sshpass -y
RUN echo "exit" > ${HOME}/file.sh && ssh-keygen -f ${HOME}/.ssh/file -t rsa -b 4096 -q -N "" && mkdir "/tmp/acme.sh"
COPY deploy /tmp/acme.sh/deploy
COPY dnsapi /tmp/acme.sh/dnsapi
COPY acme.sh /tmp/acme.sh/acme.sh
COPY notify /tmp/acme.sh/notify
RUN touch /tmp/run_config.sh && chmod +x /tmp/run_config.sh && echo '#!/bin/bash' > /tmp/run_config.sh &&  \
    echo 'tail -f /dev/null' >> /tmp/run_config.sh && cd /tmp/acme.sh && ./acme.sh --install -m shad.hasan@tinyorb.xyz
ENTRYPOINT /tmp/run_config.sh