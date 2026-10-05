FROM fedora:latest

LABEL org.opencontainers.image.title="sd-vpn-client" \
      org.opencontainers.image.description="Fedora-based OpenVPN and SSH client container"

ARG USERNAME=dev
ARG UID=1000
ARG GID=1000

RUN dnf -y upgrade && \
    dnf -y install \
      bash \
      bind-utils \
      ca-certificates \
      curl \
      file \
      gzip \
      iproute \
      iputils \
      jq \
      less \
      openssh-clients \
      openvpn \
      procps-ng \
      tar \
      traceroute \
      unzip \
      vim-minimal \
      wget \
      which \
      && dnf clean all && \
      rm -rf /var/cache/dnf

RUN if getent group "$GID" >/dev/null; then \
      GROUP_NAME="$(getent group "$GID" | cut -d: -f1)"; \
    else \
      GROUP_NAME="$USERNAME"; \
      groupadd -g "$GID" "$GROUP_NAME"; \
    fi \
 && useradd \
      -m \
      -u "$UID" \
      -g "$GID" \
      "$USERNAME"

ENV HOME=/home/${USERNAME}

COPY scripts/entrypoint.sh /usr/local/bin/vpn-ssh-entrypoint

RUN chmod 0755 /usr/local/bin/vpn-ssh-entrypoint && \
    mkdir -p /config /work && \
    chown -R "$UID:$GID" /config /work

RUN touch /etc/client.ovpn && \
    chown "$UID:$GID" /etc/client.ovpn

WORKDIR /work

ENTRYPOINT ["/usr/local/bin/vpn-ssh-entrypoint"]
CMD []
