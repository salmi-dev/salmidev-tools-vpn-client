#!/usr/bin/env bash
set -euo pipefail

config=/config/client.ovpn
credentials=/config/credentials
vpn_config=/etc/client.ovpn

pidfile=/tmp/openvpn.pid
logfile=/tmp/openvpn.log

if [[ ! -r "$config" ]]; then
  echo "VPN configuration not found: $config" >&2
  echo "Mount a provider .ovpn file at /config/client.ovpn." >&2
  exit 1
fi

cat $config > "$vpn_config"
if [[ -r "$credentials" ]]; then
  echo "auth-user-pass $credentials" >> "$vpn_config"
fi

# OpenVPN stays in the background so the remaining arguments can describe the
# SSH connection.  The configuration is deliberately the only input to VPN
# setup: provider-specific options belong in the .ovpn file.
openvpn \
  --config "$vpn_config" \
  --daemon vpn-ssh-openvpn \
  --writepid "$pidfile" \
  --log "$logfile"

cleanup() {
  if [[ -s "$pidfile" ]]; then
    kill "$(<"$pidfile")" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

# Do not race the SSH client against OpenVPN's daemon startup.  tun0 is not
# guaranteed to be named tun0, so accept any tun device in /sys/class/net.
for _ in {1..60}; do
  if compgen -G '/sys/class/net/tun*' >/dev/null; then
    break
  fi
  if [[ -s "$pidfile" ]] && ! kill -0 "$(<"$pidfile")" 2>/dev/null; then
    echo "OpenVPN failed to start:" >&2
    cat "$logfile" >&2 || true
    exit 1
  fi
  sleep 1
done

if ! compgen -G '/sys/class/net/tun*' >/dev/null; then
  echo "Timed out waiting for the VPN tunnel." >&2
  cat "$logfile" >&2 || true
  exit 1
fi

host=${1:-}
session=${2:-}

# The container currently runs as root because OpenVPN needs to configure the
# tunnel. Explicitly point SSH at the non-root user's config when it exists;
# otherwise OpenSSH would look in /root/.ssh.
ssh_args=()
if [[ -f $HOME/.ssh/config ]]; then
  ssh_args=(-F $HOME/.ssh/config)
fi

if [[ -n "$session" ]]; then
  if [[ ! "$session" =~ ^[[:alnum:]_.-]+$ ]]; then
    echo "tmux session names may contain only letters, numbers, ., _, and -." >&2
    exit 2
  fi
  if [[ -z "$host" ]]; then
    echo "A host is required when a tmux session is specified." >&2
    exit 2
  fi
  ssh "${ssh_args[@]}" "$host" -t "tmux new -s '$session' || tmux attach -t '$session'"
elif [[ -n "$host" ]]; then
  ssh "${ssh_args[@]}" "$host"
else
  echo "VPN is connected. OpenVPN log: $logfile"
  /bin/bash -i
fi
