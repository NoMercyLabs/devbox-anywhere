# Devbox image skeleton. Fill the <...> markers from what the detection step found, and paste the
# per-ecosystem blocks from references/toolchain.md between the marked sections.
#
# This is the DEVELOPMENT environment. If the project also ships a container, that is a different
# Dockerfile with different goals (small, no toolchain, no editor) - never merge the two.
#
# Rule for every block below: each tool is justified by a file in the repo, and the comment says
# which file. A tool nobody can point at is a tool nobody can remove later with confidence.

# Base = the heaviest runtime this project needs (see references/toolchain.md). Pin the tag; an
# unpinned base turns an untouched project into a build that breaks on a day nobody changed
# anything.
FROM <base image>:<pinned tag>

# TARGETARCH is set by BuildKit (amd64 / arm64). Used below for arch-specific downloads so the
# same file builds on an Intel and an Apple-silicon host.
ARG TARGETARCH=amd64
ARG USERNAME=dev
ARG USER_UID=1000
ARG USER_GID=1000

ENV DEBIAN_FRONTEND=noninteractive

# --- baseline packages -------------------------------------------------------
# iproute2/lsof: scripts that answer "who owns port N" need them on Linux.
# openssh-server: required for the Remote-SSH entry point; the entrypoint only starts it when a
# key is present.
# build-essential: native modules (node-gyp, native gems, cgo) fail to compile without it.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl wget gnupg lsb-release \
        git git-lfs openssh-client openssh-server \
        build-essential unzip zip jq less nano procps \
        iproute2 lsof sudo locales tzdata \
    && rm -rf /var/lib/apt/lists/*

RUN sed -i 's/^# *\(en_US.UTF-8\)/\1/' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

# --- project toolchain -------------------------------------------------------
# One labelled block per detected ecosystem, copied from references/toolchain.md. Name the repo
# file that demands each one.
#
# <block>   # justified by: <repo file>

# --- code-server -------------------------------------------------------------
# The browser editor. Installed from the vendor's own installer over HTTPS; see
# references/security.md for why that is accepted here and what to do if your policy forbids it.
RUN curl -fsSL https://code-server.dev/install.sh | sh

# --- unprivileged user -------------------------------------------------------
# Two reasons for the UID/GID build args: files the box writes into the bind-mounted repo stay
# owned by the host user, and the editor does not run as root.
#
# The rename branches exist because many base images already ship a user at uid 1000 under a
# different name - a bare useradd fails on exactly those images.
#
# Passwordless sudo is granted deliberately: the entrypoint needs it to join the docker socket's
# group, and a developer needs it to apt-install a missing tool mid-task. Scope of that power is
# this container, not the host. Drop the sudoers line if your policy requires it - the docker
# socket group-join is then the only thing that stops working.
RUN if getent group ${USER_GID} >/dev/null; then groupmod -n ${USERNAME} "$(getent group ${USER_GID} | cut -d: -f1)"; else groupadd -g ${USER_GID} ${USERNAME}; fi \
    && if getent passwd ${USER_UID} >/dev/null; then usermod -l ${USERNAME} -d /home/${USERNAME} -m "$(getent passwd ${USER_UID} | cut -d: -f1)"; else useradd -m -u ${USER_UID} -g ${USER_GID} -s /bin/bash ${USERNAME}; fi \
    && echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} \
    && chmod 0440 /etc/sudoers.d/${USERNAME} \
    # Every directory a named volume will mount over must exist here and be owned by the user.
    # Docker seeds an empty named volume from the image path; if the path is missing, the volume
    # is created root-owned and the first write fails with a permission error.
    && mkdir -p /home/${USERNAME}/.local/share/code-server \
                /home/${USERNAME}/.ssh/sshd /home/${USERNAME}/.vscode-server \
                <one line per cache volume, e.g. /home/${USERNAME}/.npm> \
                /workspace \
    && chmod 700 /home/${USERNAME}/.ssh \
    && chown -R ${USER_UID}:${USER_GID} /home/${USERNAME} /workspace

COPY --chown=${USER_UID}:${USER_GID} settings/ /opt/devbox/settings/
COPY entrypoint.sh /usr/local/bin/devbox-entrypoint
COPY auth-onboarding.sh /usr/local/bin/devbox-auth

# The hook that runs the auth report. Installed in TWO places because a shell reads only one of
# them: /etc/profile.d covers login shells (Remote-SSH), /etc/bash.bashrc covers interactive
# non-login shells - which is what the VS Code / code-server integrated terminal starts, so a
# profile.d-only hook never fires for the person working in the browser.
# The `$-` test is what makes the marker safe: `[ -t 1 ]` alone is true for a background
# `docker exec -t`, which then burns it and the user's own terminal shows nothing. Only an
# interactive shell has `i` in `$-`.
# The marker is written only when NOTHING is pending. devbox-auth always exits 0 on purpose - it is
# a report, not a gate - so the hook reads the count it leaves in /tmp/.devbox-auth-pending instead.
# Gating on its exit status silently suppressed the report forever on the first terminal. While a
# credential is still missing the report reappears in each new terminal, because a report shown once
# to whichever shell happened to open first is a report the person never sees.
RUN chmod +x /usr/local/bin/devbox-entrypoint /usr/local/bin/devbox-auth \
    && printf '%s\n' \
        'case $- in' \
        '  *i*)' \
        '    if [ -t 1 ] && [ ! -f /tmp/.devbox-auth-shown ]; then' \
        '      devbox-auth' \
        '      if [ "$(cat /tmp/.devbox-auth-pending 2>/dev/null || echo 1)" = 0 ]; then' \
        '        touch /tmp/.devbox-auth-shown 2>/dev/null' \
        '      fi' \
        '    fi' \
        '    ;;' \
        'esac' \
        'true' \
        > /usr/local/etc/devbox-auth-hook.sh \
    && ln -sf /usr/local/etc/devbox-auth-hook.sh /etc/profile.d/10-devbox-auth.sh \
    && printf '\n. /usr/local/etc/devbox-auth-hook.sh\n' >> /etc/bash.bashrc
. /usr/local/etc/devbox-auth-hook.sh
' >> /etc/bash.bashrc

USER ${USERNAME}
WORKDIR /workspace

# 8080 code-server · 2222 sshd. Add one line per port this project's own dev servers bind.
EXPOSE 8080 2222

ENTRYPOINT ["/usr/local/bin/devbox-entrypoint"]
