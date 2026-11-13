#!/bin/bash
set -euo pipefail

umask 0002
export LD_LIBRARY_PATH="/home/steam/linux64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

if [[ $(id -u) == 0 ]]; then
  uid=${USER_UID:-1000}
  gid=${USER_GID:-1000}
  if [[ ! $uid =~ ^[1-9][0-9]*$ || ! $gid =~ ^[1-9][0-9]*$ ]]; then
    echo "ERROR: USER_UID and USER_GID must be positive, non-root numeric IDs" >&2
    exit 1
  fi
  [[ $(id -g steam) == "$gid" ]] || groupmod -o -g "$gid" steam
  [[ $(id -u steam) == "$uid" ]] || usermod -u "$uid" steam

  # Avoid recursively walking an unchanged game installation on every restart.
  for directory in /data /home/steam /opt/steamcmd; do
    if [[ $(stat -c '%u:%g' "$directory") != "$uid:$gid" ]]; then
      chown -R steam:steam "$directory"
    fi
  done
  exec gosu steam:steam "$@"
fi

exec "$@"
