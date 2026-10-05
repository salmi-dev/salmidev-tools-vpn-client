# sd-vpn-client

A small Fedora-based container that starts OpenVPN from one mounted `.ovpn`
file and then optionally opens an SSH session through the VPN.

## Build

Build the image directly with Docker or Podman:

```bash
docker build -f Containerfile -t sd-vpn-client .
# or: podman build -f Containerfile -t sd-vpn-client .
```

The included `build.sh` helper detects Podman first and Docker second. It also
passes the current user's UID, GID, and username into the image so mounted SSH
files have matching ownership:

```bash
./build.sh
```

## Run

The provider configuration must be mounted at exactly
`/config/client.ovpn`. OpenVPN needs the TUN device and `NET_ADMIN`:

```bash
docker run --rm -it \
  --cap-add=NET_ADMIN \
  --device=/dev/net/tun \
  --mount type=bind,src="$PWD/config/client.ovpn",dst=/config/client.ovpn,readonly \
  --mount type=bind,src="$HOME/.ssh",dst=/home/dev/.ssh,readonly \
  sd-vpn-client
```

The container starts OpenVPN in the background, waits for the tunnel, and then
opens a shell. The entrypoint has no subcommands or OpenVPN options; put all
VPN-specific settings in `client.ovpn`.

The included `run.sh` helper mounts the standard configuration files, detects
Podman or Docker, and accepts the same optional host and tmux-session arguments:

```bash
./run.sh [ssh-host] [tmux-session]
```

By default it reads `config/client.ovpn`, `config/credentials` when present,
and `$HOME/.ssh`. Override those locations with `SD_VPN_CONFIG`,
`SD_VPN_CREDENTIALS`, and `SD_SSH_CONFIG` when needed.

### Create a configured launcher

You can create a small wrapper around `run.sh` with all paths set in one
place. Save this as, for example, `run-my-vpn.sh` in the project directory:

```sh
#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

export SD_VPN_CONFIG="$project_dir/config/my-provider.ovpn"
export SD_VPN_CREDENTIALS="$project_dir/config/my-provider.credentials"
export SD_SSH_CONFIG="$HOME/.ssh"

exec "$project_dir/run.sh" "$@"
```

Make the launcher executable and use it like `run.sh`:

```bash
chmod 700 run-my-vpn.sh
./run-my-vpn.sh [ssh-host] [tmux-session]
```

Keep the launcher and credentials private if they contain machine-specific
paths or other sensitive configuration. The provider `.ovpn` and credentials
files remain ignored by Git when stored under `config/`.

Pass the SSH host as the first argument to connect immediately:

```bash
docker run --rm -it \
  --cap-add=NET_ADMIN --device=/dev/net/tun \
  -v "$PWD/config/client.ovpn:/config/client.ovpn:ro" \
  -v "$HOME/.ssh:/home/dev/.ssh:ro" \
  sd-vpn-client vpn-host
```

Pass a second argument to create or attach to a tmux session on that host:

```bash
sd-vpn-client vpn-host work-session
```

This runs the equivalent of:

```bash
ssh vpn-host -t "tmux new -s work-session || tmux attach -t work-session"
```

The first argument can be an SSH config alias or a normal target such as
`user@internal-host`.

## Avoid entering credentials every time

### VPN credentials

Create `config/credentials` on the host with exactly two lines:

```text
my-vpn-username
my-vpn-password
```

Protect it and reference it from `client.ovpn`:

```bash
chmod 600 config/credentials
```

```ovpn
auth-user-pass /config/credentials
```

Mount it read-only in addition to the `.ovpn` file:

```bash
docker run --rm -it \
  --cap-add=NET_ADMIN --device=/dev/net/tun \
  --mount type=bind,src="$PWD/config/client.ovpn",dst=/config/client.ovpn,readonly \
  --mount type=bind,src="$PWD/config/credentials",dst=/config/credentials,readonly \
  --mount type=bind,src="$HOME/.ssh",dst=/home/dev/.ssh,readonly \
  sd-vpn-client
```

OpenVPN reads the first line as the username and the second as the password.
This avoids prompting on every run without putting the password into the
`.ovpn` file.

### SSH credentials

Use SSH public-key authentication and mount the host's `.ssh` directory, as
shown above. Put the username, hostname, identity file, and other connection
settings in `~/.ssh/config`; an SSH config alias then avoids both username and
password prompts. An `ssh-agent` can also be forwarded when the private key
should not be mounted into the container.

## Security notes

- Treat the `.ovpn` file as a secret when it contains private keys or inline
  credentials.
- Grant `NET_ADMIN` and `/dev/net/tun` only to this VPN container.
- Prefer SSH keys over password authentication.
- The image normally runs as root because OpenVPN needs to configure the tunnel. The `run.sh` helper maps the container user to the invoking host user for mounted SSH files.

## Structure

```text
Containerfile                 Image definition
scripts/entrypoint.sh         Starts OpenVPN and handles optional SSH/tmux
config/client.ovpn.example    Provider configuration template
```
