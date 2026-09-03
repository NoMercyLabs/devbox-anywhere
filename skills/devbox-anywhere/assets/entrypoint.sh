#!/usr/bin/env bash
#
# Devbox container entrypoint. PID 1 for the dev environment: it prepares the mounted state,
# then hands the process over to code-server.
#
# Copy this file verbatim into <project>/devbox/. It is project-agnostic on purpose - anything
# project-specific belongs in DEVBOX_BOOTSTRAP (set in docker-compose.yml), not in here, so the
# next project can take the same file without a diff.
#
# Design rule for everything below: it must be safe to run on EVERY container start, not just the
# first. Named volumes outlive the image, so this script re-runs against state a previous version
# of itself created. Each step therefore checks the current state and does the smallest thing that
# makes it correct.
#
# This script NEVER reads, writes, forwards, or stores a credential. See references/security.md.

set -euo pipefail

HOME_DIR="${HOME:-/home/dev}"
WORKSPACE="${DEVBOX_WORKSPACE:-/workspace}"
# The port INSIDE the container. The host-side port is chosen in docker-compose.yml; keeping the
# inside fixed means the healthcheck and the docs never have to track the user's port choice.
PORT="${DEVBOX_INTERNAL_PORT:-8080}"

log() { printf '\033[36m[devbox]\033[0m %s\n' "$*"; }

# --- git ---------------------------------------------------------------------
# The workspace is bind-mounted from the host, so its files are owned by a uid that does not match
# this container's user. Git treats that as a possible attack ("dubious ownership") and refuses
# every command in the repo. Marking this ONE directory as safe restores normal git operation.
#
# Scoped to the workspace deliberately: the wildcard form (safe.directory '*') would disable the
# check for every repository the user ever touches inside the box, including anything cloned later.
git config --global --add safe.directory "${WORKSPACE}" 2>/dev/null || true

# --- docker socket -----------------------------------------------------------
# Only relevant when docker-compose.yml mounts the host's docker socket. The socket arrives owned
# by a group id from the HOST, which almost never matches a group inside this image, so the
# container user cannot read it and every docker command fails on permissions.
#
# The fix is to put the user in the group that owns the socket, creating that group locally when
# the host's gid has no local name.
#
# gid 0 is excluded: that is what Docker Desktop hands over, and "join group root" is a privilege
# escalation, not a permission fix. There, sudo is the correct route and the message says so.
if [ -S /var/run/docker.sock ] && ! docker info >/dev/null 2>&1; then
    SOCK_GID="$(stat -c '%g' /var/run/docker.sock)"
    if [ "${SOCK_GID}" = "0" ]; then
        log "docker socket is root-owned (Docker Desktop) - use 'sudo docker' in this box"
    else
        SOCK_GROUP="$(getent group "${SOCK_GID}" | cut -d: -f1)"
        if [ -z "${SOCK_GROUP}" ]; then
            SOCK_GROUP=dockerhost
            sudo groupadd -g "${SOCK_GID}" "${SOCK_GROUP}" 2>/dev/null || true
        fi
        sudo usermod -aG "${SOCK_GROUP}" "$(id -un)" 2>/dev/null || true
        log "joined group ${SOCK_GROUP} (gid ${SOCK_GID}) for docker socket access"
    fi
fi

# --- editor settings ---------------------------------------------------------
# Copied rather than symlinked, and only when absent. A symlink would make the file effectively
# read-only from the editor's point of view; copying once means the user can tweak a setting in the
# UI and keep that tweak across restarts.
USER_SETTINGS_DIR="${HOME_DIR}/.local/share/code-server/User"
mkdir -p "${USER_SETTINGS_DIR}"
if [ ! -f "${USER_SETTINGS_DIR}/settings.json" ] && [ -f /opt/devbox/settings/settings.json ]; then
    cp /opt/devbox/settings/settings.json "${USER_SETTINGS_DIR}/settings.json"
    log "seeded editor settings"
fi

# --- extensions --------------------------------------------------------------
# Installed here rather than in the Dockerfile because the extensions directory is a named volume:
# anything the image installed there is shadowed the moment the volume mounts.
#
# The marker stores a hash of the list, not a boolean. With a boolean, the first list ever
# installed would be frozen for the life of the volume and every later edit to extensions.txt
# would be ignored with no error - a silent failure that is hard to attribute.
EXT_MARKER="${HOME_DIR}/.local/share/code-server/.devbox-extensions-installed"
EXT_LIST=/opt/devbox/settings/extensions.txt
if [ -f "${EXT_LIST}" ]; then
    EXT_HASH="$(sha256sum "${EXT_LIST}" | cut -d' ' -f1)"
    if [ "${EXT_HASH}" != "$(cat "${EXT_MARKER}" 2>/dev/null)" ]; then
        log "installing extensions (list changed)"
        while read -r ext; do
            # Drop the trailing "# why this one" annotation and all whitespace. code-server takes
            # the entire argument as the extension id, so an annotated line would be looked up
            # verbatim and reported as unavailable.
            ext="${ext%%#*}"
            ext="$(echo "${ext}" | tr -d '[:space:]')"
            [ -z "${ext}" ] && continue
            # A single missing extension must not stop the box from starting: Open VSX carries a
            # smaller catalogue than the Microsoft marketplace, so a miss is expected and is
            # reported rather than raised.
            code-server --install-extension "${ext}" --force || log "skipped ${ext} (not available)"
        done < "${EXT_LIST}"
        printf '%s' "${EXT_HASH}" > "${EXT_MARKER}"
    fi
fi

# --- project bootstrap -------------------------------------------------------
# Whatever this project needs before work can start: a tool restore, a dependency install, codegen.
# Failure is logged, never fatal - a box that refuses to start because a restore failed leaves the
# user with no terminal in which to fix the restore.
if [ -n "${DEVBOX_BOOTSTRAP:-}" ]; then
    log "bootstrap: ${DEVBOX_BOOTSTRAP}"
    bash -lc "${DEVBOX_BOOTSTRAP}" || log "bootstrap failed - run it by hand"
fi

# --- sshd (VS Code Remote-SSH) -----------------------------------------------
# Runs as the container's unprivileged user on 2222, not as root on 22. An sshd started by a
# non-root user cannot switch users, so the only account it can ever grant is this one - the blast
# radius of a mistake here is the container's own user, not the container's root.
#
# No key mounted means no ssh server at all: the feature is opt-in by the presence of a key, so the
# default posture is "no listening ssh service".
if [ "${DEVBOX_ENABLE_SSH:-1}" = "1" ]; then
    # The mounted key directory is read-only and owned by the host user. sshd rejects an
    # authorized_keys file with loose permissions, so the key is copied to a path this user owns
    # and given the mode sshd requires.
    if [ -s "${HOME_DIR}/.ssh-host/authorized_keys" ]; then
        install -d -m 700 "${HOME_DIR}/.ssh"
        install -m 600 "${HOME_DIR}/.ssh-host/authorized_keys" "${HOME_DIR}/.ssh/authorized_keys"
    fi
    if [ -s "${HOME_DIR}/.ssh/authorized_keys" ]; then
        SSHD_DIR="${HOME_DIR}/.ssh/sshd"
        install -d -m 700 "${SSHD_DIR}"
        # Generated on first start and kept on the home volume, so the host key is stable across
        # restarts. A key regenerated every boot would trip the client's known_hosts warning every
        # time, training the user to click through exactly the warning that matters.
        [ -f "${SSHD_DIR}/ssh_host_ed25519_key" ] || \
            ssh-keygen -q -t ed25519 -N '' -f "${SSHD_DIR}/ssh_host_ed25519_key"
        # Written fresh each start so an edit to this script actually takes effect. Every line is a
        # deliberate narrowing of sshd's defaults.
        cat > "${SSHD_DIR}/sshd_config" <<EOF
Port 2222
ListenAddress 0.0.0.0
HostKey ${SSHD_DIR}/ssh_host_ed25519_key
PidFile ${SSHD_DIR}/sshd.pid
AuthorizedKeysFile ${HOME_DIR}/.ssh/authorized_keys
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
UsePAM no
PrintMotd no
X11Forwarding no
AllowTcpForwarding yes
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server
EOF
        if /usr/sbin/sshd -f "${SSHD_DIR}/sshd_config"; then
            log "sshd on 2222 (key-only, user $(id -un))"
        else
            # Reported, not fatal: the browser editor is the primary way in and must still come up.
            log "sshd failed to start - Remote-SSH unavailable, browser editor unaffected"
        fi
    else
        log "no key in devbox/ssh/authorized_keys - sshd not started"
    fi
fi

# --- code-server -------------------------------------------------------------
# exec, so code-server becomes PID 1 and receives docker's stop signal directly. Without exec it
# would be a child of this shell, miss SIGTERM, and be killed after the grace period instead of
# shutting down cleanly.
log "code-server on ${PORT}, workspace ${WORKSPACE}"
exec code-server \
    --bind-addr "0.0.0.0:${PORT}" \
    --disable-telemetry \
    --disable-update-check \
    "${WORKSPACE}"
