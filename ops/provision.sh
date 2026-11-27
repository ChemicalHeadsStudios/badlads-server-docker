#!/bin/bash
# Run only on the new Ubuntu 24.04 staging VPS, never on the production host.
set -euo pipefail

usage() {
  echo "Usage: $0 prepare EXPECTED_HOSTNAME PUBLIC_KEY_FILE | lockdown EXPECTED_HOSTNAME" >&2
  exit 2
}
[[ $# -ge 2 ]] || usage
phase=$1
expected_hostname=$2
[[ $phase == prepare || $phase == lockdown ]] || usage
[[ $(id -u) == 0 ]] || { echo 'Run with sudo.' >&2; exit 1; }
[[ $(hostname) == "$expected_hostname" ]] || {
  echo 'Hostname mismatch: refusing to change this host.' >&2; exit 1;
}
# shellcheck source=/dev/null
. /etc/os-release
[[ $ID == ubuntu && $VERSION_ID == 24.04 ]] || {
  echo 'This bootstrap requires Ubuntu 24.04.' >&2; exit 1;
}

if [[ $phase == prepare ]]; then
  [[ $# == 3 && -f $3 ]] || usage
  key_file=$(realpath "$3")
  ssh-keygen -l -f "$key_file" >/dev/null
  # Refuse to silently take over an already configured game account/server.
  if id steam >/dev/null 2>&1 && [[ ! -f /etc/badlads-staging-bootstrap ]]; then
    echo 'Existing steam account found. Review the host manually before provisioning.' >&2
    exit 1
  fi
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get -y upgrade
  apt-get install -y ca-certificates git openssh-server ufw fail2ban \
    python3-systemd unattended-upgrades docker.io docker-compose-v2
  id steam >/dev/null 2>&1 || useradd --create-home --shell /bin/bash steam
  usermod -aG sudo steam
  install -d -m 700 -o steam -g steam /home/steam/.ssh
  install -m 600 -o steam -g steam "$key_file" /home/steam/.ssh/authorized_keys
  printf '%s\n' 'steam ALL=(ALL) NOPASSWD: ALL' >/etc/sudoers.d/badlads-steam
  chmod 440 /etc/sudoers.d/badlads-steam
  visudo -cf /etc/sudoers.d/badlads-steam
  install -d -m 755 /opt/badlads-staging
  install -d -m 750 -o steam -g steam /var/lib/badlads-staging

  cat >/etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
  # Apply security updates automatically; reboots remain an explicit operation.
  cat >/etc/apt/apt.conf.d/52badlads-unattended-upgrades <<'EOF'
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
EOF
  install -d /etc/systemd/journald.conf.d
  printf '[Journal]\nSystemMaxUse=200M\n' >/etc/systemd/journald.conf.d/badlads.conf
  cat >/etc/fail2ban/jail.d/badlads.local <<'EOF'
[sshd]
enabled = true
backend = systemd
banaction = ufw
maxretry = 5
findtime = 10m
bantime = 1h
EOF
  cat >/etc/sysctl.d/60-badlads-staging.conf <<'EOF'
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
EOF
  sysctl --system >/dev/null
  systemctl enable --now docker unattended-upgrades
  systemctl restart systemd-journald
  touch /etc/badlads-staging-bootstrap
  echo 'Preparation complete. Keep the current SSH session open.'
  echo 'Verify a separate key-based SSH login as steam, then run the lockdown phase from that login.'
  exit 0
fi

[[ $# == 2 ]] || usage
[[ -f /etc/badlads-staging-bootstrap && ${SUDO_USER:-} == steam ]] || {
  echo 'Run lockdown via sudo from the verified steam SSH account after prepare.' >&2
  exit 1
}
[[ -s /home/steam/.ssh/authorized_keys ]] || { echo 'SSH key missing.' >&2; exit 1; }
install -d /etc/ssh/sshd_config.d
cat >/etc/ssh/sshd_config.d/00-badlads-staging.conf <<'EOF'
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
AllowUsers steam
X11Forwarding no
AllowAgentForwarding no
AllowTcpForwarding no
PermitTunnel no
MaxAuthTries 3
LoginGraceTime 30
EOF
sshd -t
effective=$(sshd -T -C user=steam,host=localhost,addr=127.0.0.1)
for setting in 'passwordauthentication no' 'kbdinteractiveauthentication no' \
               'permitrootlogin no' 'pubkeyauthentication yes' 'allowusers steam'; do
  grep -qxF "$setting" <<<"$effective" || {
    echo "SSH setting was overridden: $setting. Refusing to reload." >&2; exit 1;
  }
done
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment 'SSH administration'
ufw allow 7777/udp comment 'BadLads game'
ufw allow 27015/udp comment 'Steam server query'
ufw --force enable
systemctl reload ssh
systemctl enable --now fail2ban
systemctl restart fail2ban
ufw status verbose
fail2ban-client status sshd
echo 'Lockdown complete. Verify another SSH login and the running game before closing this session.'
