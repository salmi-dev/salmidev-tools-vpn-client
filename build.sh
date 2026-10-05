#!/bin/sh
set -eu

# Build from the repository root, regardless of the caller's current directory.
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

# Match the container user to the invoking host user for mounted SSH files.
uid=$(id -u)
gid=$(id -g)
username=$(id -un)

"$container_command" build \
  -f "$script_dir/Containerfile" \
  -t sd-vpn-client:latest \
  --build-arg USERNAME="$username" \
  --build-arg UID="$uid" \
  --build-arg GID="$gid" \
  "$script_dir"
