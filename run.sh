#!/bin/sh
set -eu

# Resolve paths relative to this script so it can be launched from anywhere.
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

# Prefer Podman when it is available, then fall back to Docker.
if command -v podman >/dev/null 2>&1; then
  container_command=podman
elif command -v docker >/dev/null 2>&1; then
  container_command=docker
else
  echo "Neither podman nor docker is installed. Please install one of them to run this script." >&2
  exit 1
fi

# Allow callers to keep provider and SSH configuration outside the repository.
vpn_config=${SD_VPN_CONFIG:-"$script_dir/config/client.ovpn"}
vpn_credentials=${SD_VPN_CREDENTIALS:-"$script_dir/config/credentials"}
ssh_config=${SD_SSH_CONFIG:-"$HOME/.ssh"}

if [ ! -f "$vpn_config" ]; then
  echo "VPN configuration file not found: $vpn_config" >&2
  exit 2
fi

# Credentials are optional; the entrypoint only enables them when mounted.
if [ -e "$vpn_credentials" ] && [ ! -f "$vpn_credentials" ]; then
  echo "VPN credentials path is not a regular file: $vpn_credentials" >&2
  exit 2
fi

if [ ! -d "$ssh_config" ]; then
  echo "SSH configuration directory not found: $ssh_config" >&2
  exit 3
fi

host=${1:-}
tmux_session=${2:-}
username=$(id -un)
uid=$(id -u)
gid=$(id -g)

# Build the command as positional parameters so paths and optional arguments
# remain safely quoted, including when no SSH host is supplied.
set -- run --rm -it \
  --cap-add=NET_ADMIN \
  --device /dev/net/tun \
  -u "$uid:$gid" \
  -v "$vpn_config:/config/client.ovpn:ro" \
  -v "$ssh_config:/home/$username/.ssh:ro"

if [ -f "$vpn_credentials" ]; then
  set -- "$@" -v "$vpn_credentials:/config/credentials:ro"
fi

set -- "$@" sd-vpn-client:latest

# The first optional argument connects to an SSH host. A second one requests
# a tmux session on that host; the entrypoint validates the session name.
if [ -n "$host" ]; then
  set -- "$@" "$host"
fi
if [ -n "$tmux_session" ]; then
  set -- "$@" "$tmux_session"
fi

"$container_command" "$@"
