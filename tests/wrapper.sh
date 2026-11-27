#!/bin/bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/bin" "$scratch/game"
export PATH="$scratch/bin:$PATH"
export CAPTURE="$scratch/args" STARTED="$scratch/started"
export STEAMCMD_APP_ID=1203110 STEAMCMD_INSTALL_DIR="$scratch/game"
unset STEAMCMD_BETA STEAMCMD_BETA_PASSWORD STEAMCMD_LOGIN STEAMCMD_SKIP STEAMCMD_NO_VALIDATE

cat > "$scratch/bin/steamcmd" <<'STUB'
#!/bin/bash
printf '%s\n' "$@" > "$CAPTURE"
exit "${STEAMCMD_TEST_EXIT:-0}"
STUB
cat > "$scratch/bin/game" <<'STUB'
#!/bin/bash
touch "$STARTED"
STUB
chmod +x "$scratch/bin/steamcmd" "$scratch/bin/game"

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_line() { grep -Fx -- "$1" "$CAPTURE" >/dev/null || fail "missing argument: $1"; }

bash "$repo/steamcmd-wrapper" game
[[ -f $STARTED ]] || fail 'default launch did not run game'
mapfile -t arguments < "$CAPTURE"
[[ ${arguments[0]} == +force_install_dir && ${arguments[2]} == +login ]] || fail 'install directory must precede login'
assert_line public
if grep -Fx validate "$CAPTURE" >/dev/null; then fail 'default launch should not validate every file'; fi

STEAMCMD_BETA=staging STEAMCMD_BETA_PASSWORD='test password * literal' STEAMCMD_NO_VALIDATE=false \
  bash "$repo/steamcmd-wrapper" game
assert_line staging
assert_line 'test password * literal'
assert_line validate

rm "$STARTED"
if STEAMCMD_TEST_EXIT=42 bash "$repo/steamcmd-wrapper" game; then fail 'SteamCMD failure accepted'; fi
[[ ! -e $STARTED ]] || fail 'game started after failed update'

rm "$CAPTURE"
if STEAMCMD_SKIP=true bash "$repo/steamcmd-wrapper" game; then fail 'skip accepted on missing installation'; fi
[[ ! -e $STARTED && ! -e $CAPTURE ]] || fail 'missing-install skip ran a command'
touch "$STEAMCMD_INSTALL_DIR/BadLadsServer.sh"
STEAMCMD_SKIP=true bash "$repo/steamcmd-wrapper" game
[[ -f $STARTED && ! -e $CAPTURE ]] || fail 'skip invoked SteamCMD or failed to start game'

for invalid in STEAMCMD_SKIP=typo STEAMCMD_NO_VALIDATE=typo STEAMCMD_APP_ID=invalid; do
  if env "$invalid" bash "$repo/steamcmd-wrapper" game; then fail "accepted $invalid"; fi
done

cat > "$STEAMCMD_INSTALL_DIR/BadLadsServer.sh" <<'STUB'
#!/bin/bash
printf '%s\n' "$@" > "$CAPTURE"
STUB
SERVERNAME='Staging With Spaces' BADLADS_ARGS='-log -port=7778' \
  bash "$repo/badlads-run" '-extra=value with spaces'
assert_line '-SteamServerName=Staging With Spaces'
assert_line '-port=7778'
assert_line '-extra=value with spaces'
echo 'PASS: defaults, branch/password quoting, validation, update failure, skip, invalid settings and launch arguments'
