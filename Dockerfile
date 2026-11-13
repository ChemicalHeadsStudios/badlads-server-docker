FROM ubuntu:24.04

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates curl gosu lib32gcc-s1 lib32stdc++6 libatomic1 tini && \
    rm -rf /var/lib/apt/lists/* && \
    if id ubuntu >/dev/null 2>&1; then userdel ubuntu; fi && \
    if getent group ubuntu >/dev/null; then groupdel ubuntu; fi && \
    groupadd --gid 1000 steam && \
    useradd --uid 1000 --gid steam --create-home --shell /bin/bash steam && \
    install -d -o steam -g steam /data /opt/steamcmd /home/steam/linux64 && \
    curl --fail --location --retry 3 \
      https://media.steampowered.com/installer/steamcmd_linux.tar.gz \
      --output /tmp/steamcmd.tar.gz && \
    tar -xzf /tmp/steamcmd.tar.gz -C /opt/steamcmd && \
    rm /tmp/steamcmd.tar.gz && \
    chown -R steam:steam /opt/steamcmd && \
    printf '#!/bin/sh\nexec /opt/steamcmd/steamcmd.sh "$@"\n' > /usr/local/bin/steamcmd && \
    chmod +x /usr/local/bin/steamcmd

# Preserve the known-working BadLads Steam client until a replacement is tested.
COPY --chown=steam:steam steamclient-old.so /home/steam/linux64/steamclient.so
COPY entrypoint.sh /entrypoint.sh
COPY steamcmd-wrapper badlads-run /usr/local/bin/
RUN chmod +x /entrypoint.sh /usr/local/bin/steamcmd-wrapper /usr/local/bin/badlads-run

ENV HOME=/home/steam \
    STEAMCMD_APP_ID=1203110 \
    STEAMCMD_LOGIN=anonymous \
    STEAMCMD_BETA=public \
    STEAMCMD_SKIP=false \
    STEAMCMD_NO_VALIDATE=true \
    SERVERNAME=BadLadsDockerServer \
    BADLADS_ARGS="-log -useperfthreads"

WORKDIR /data
# Forward stop signals to the whole process group, including the game's launcher.
ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/entrypoint.sh"]
CMD ["steamcmd-wrapper", "badlads-run"]
