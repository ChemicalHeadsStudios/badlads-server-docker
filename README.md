# BadLads dedicated server

Linux amd64 Docker image for Steam app **1203110**, using Ubuntu 24.04 and
SteamCMD. Requires Docker Engine and Docker Compose v2 on a Linux host.

## Start a public server

Create `.env` and choose the server name, then run:

```sh
cp .env.example .env
chmod 600 .env
docker compose up -d --build
docker compose logs -f --tail=100
```

The default Steam branch is `public`. Game files, settings and saves persist in
`./data`. SteamCMD checks for game updates at each container start; image builds
do not download the game. An update downloads changed files without validating
the entire installation unless explicitly requested.

## Start staging on a separate host

```sh
cp staging.env.example .env.staging
chmod 600 .env.staging
# Edit .env.staging if the branch needs a password or Steam account.
docker compose --env-file .env.staging up -d --build
docker compose --env-file .env.staging logs -f --tail=100
```

This selects `staging`, names the server `BadLads-Staging-EU`, and keeps its data
in `./data-staging`. Branch access is controlled by Steam: if staging requires a
beta password, set `STEAMCMD_BETA_PASSWORD`. The image cannot grant branch access.
SteamGuard interaction is not supported. Do not commit account credentials or
private branch passwords; `.env` and private `.env.*` files are ignored by Git
and Docker builds.

Use the same `--env-file .env.staging` option for all later Compose commands.
After changing the env file, run `up -d` to recreate the container; `restart`
alone does not apply environment changes. Do not point staging at production's
data directory or run both with the same ports on one host.

## Prepare a new Ubuntu 24.04 VPS

Place this checkout in `/opt/badlads-staging` as root, and copy your SSH **public**
key to `/tmp/operator.pub`. Check the hostname against the new VPS's OVH details;
substitute that exact hostname for `EXPECTED_HOSTNAME` below. The provisioner is
for a fresh staging VPS only.

```sh
sudo bash /opt/badlads-staging/ops/provision.sh prepare EXPECTED_HOSTNAME /tmp/operator.pub
```

Keep that connection open. Open a separate `ssh steam@VPS_IP` connection using
the key, then run lockdown from that verified session:

```sh
sudo bash /opt/badlads-staging/ops/provision.sh lockdown EXPECTED_HOSTNAME
cd /opt/badlads-staging
sudo cp staging.env.example .env.staging
sudo chmod 600 .env.staging
sudo sed -i \
  -e "s/^USER_UID=.*/USER_UID=$(id -u steam)/" \
  -e "s/^USER_GID=.*/USER_GID=$(id -g steam)/" \
  -e 's|^BADLADS_DATA_DIR=.*|BADLADS_DATA_DIR=/var/lib/badlads-staging|' .env.staging
sudo docker compose --env-file .env.staging up -d --build
```

The setup installs Docker, fail2ban and automatic security updates, configures
key-only SSH for `steam`, and allows TCP 22 plus UDP 7777/27015 through UFW.
The `steam` SSH account has sudo administration access; the game runs as an
unprivileged user inside its container. Verify a further SSH connection and
game connectivity before closing the original connection. The provisioner
has syntax/static checks; it still needs validation on a fresh VPS.

## Updates and shutdown

```sh
# Check for the latest staging build and restart (no image rebuild needed).
docker compose --env-file .env.staging restart
# Upgrade the container's OS packages when maintaining the image.
docker compose --env-file .env.staging build --pull --no-cache
docker compose --env-file .env.staging up -d
# Stop gracefully, keeping saves.
docker compose --env-file .env.staging down
```

Containers restart after crashes and host reboots unless explicitly stopped.
Tini forwards shutdown signals to the game and its launcher; Docker allows
60 seconds to exit before killing them. Container logs rotate at 3 x 10 MB;
game log files under the data directory need separate retention/backups.
Updates occur on startup, not continuously while the server is running.

## Configuration

Set these in `.env` (public) or `.env.staging` (staging):

| Variable | Default | Purpose |
| --- | --- | --- |
| `SERVERNAME` | `BadLadsDockerServer` | Name shown by the game server |
| `STEAMCMD_BETA` | `public` | Steam branch; explicitly resets a reused install to public |
| `STEAMCMD_BETA_PASSWORD` | empty | Optional private branch password |
| `STEAMCMD_LOGIN` | `anonymous` | Legacy space-separated `username password`; no SteamGuard |
| `STEAMCMD_SKIP` | `false` | `true` skips SteamCMD; requires an existing install |
| `STEAMCMD_NO_VALIDATE` | `true` | `false` adds Steam file validation for repair |
| `USER_UID` / `USER_GID` | `1000` | Positive non-root IDs that own the host data |
| `BADLADS_DATA_DIR` | `./data` | Persistent host directory |
| `BADLADS_ARGS` | `-log -useperfthreads` | Whitespace-separated arguments; no shell quoting/evaluation |

The container initially adjusts volume ownership if necessary, then drops to
the `steam` user. It does not recursively change ownership on every restart.
Changing a directory's contents to a different owner manually may require
fixing permissions on the host.

Host networking is used for game networking. Configure the VPS firewall to
allow SSH from trusted sources, game UDP `7777`, and Steam query UDP `27015`
(the current game defaults). Adjust these if your game configuration overrides them.
Do not expose unrelated administration ports. See the
[BadLads server documentation](https://badlads.chemicalheads.com/docs/0.9.5/server-setup)
for game configuration.

The legacy `steamclient-old.so` is intentionally retained from the working
2023 image. Replacing it requires testing Steam initialization and client
connections against the actual game build.

## Checks

```sh
bash tests/wrapper.sh
docker compose config --quiet
docker compose --env-file staging.env.example config --quiet
docker compose build
```

The wrapper tests stub SteamCMD; a successful build is not proof that Steam
grants staging access or that the game can initialize. Verify installation,
Steam login, listening ports, graceful shutdown, and a client connection on
the staging host before considering a deployment ready.
