# Base image and toolchain blocks

## Contents

- Choosing the base
- Blocks (baseline, JDK, Node, Python, Go/Rust, GitHub CLI, Docker CLI, PowerShell, code-server, non-root user)
- Known failure modes

## Choosing the base

Pick the **heaviest single runtime** the project needs as the base, then layer the rest. Layering
a JDK onto a .NET SDK image is easy; the reverse is not.

| Project | Base |
|---|---|
| .NET (± anything) | `mcr.microsoft.com/dotnet/sdk:<major>` — Debian, apt available |
| JVM only | `eclipse-temurin:<ver>-jdk` |
| Node only | `node:<ver>-bookworm` (not `-alpine`: musl breaks many native modules and some tools) |
| Python only | `python:<ver>-bookworm` |
| Go / Rust only | `golang:<ver>` / `rust:<ver>` |
| Genuinely polyglot, no dominant runtime | `mcr.microsoft.com/devcontainers/base:bookworm` + a block per runtime |

Prefer a Debian-based image. `apt` availability is what makes every block below a two-line job,
and glibc avoids the native-module failures musl produces.

Verify the tag exists before you pin it; do not assume a major version has shipped an image.

## Blocks

Each is a `RUN` layer. Keep one concern per layer, label it, and name the repo file that
justifies it. Always `rm -rf /var/lib/apt/lists/*` at the end of an apt layer.

### Baseline — always

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl wget gnupg lsb-release \
        git git-lfs openssh-client openssh-server \
        build-essential unzip zip jq less nano procps \
        iproute2 lsof sudo locales tzdata \
    && rm -rf /var/lib/apt/lists/*
```

`iproute2`/`lsof` matter more than they look: scripts that find "who owns port N" need them on
Linux. `openssh-server` is what makes Remote-SSH possible.

### JDK

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends openjdk-<ver>-jdk-headless \
    && rm -rf /var/lib/apt/lists/*
ENV JAVA_HOME=/usr/lib/jvm/java-<ver>-openjdk-${TARGETARCH}
```

If the Debian release does not carry that JDK version, use the Adoptium apt repo instead of
downgrading the project.

### Node

```dockerfile
RUN curl -fsSL https://deb.nodesource.com/setup_<major>.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/* \
    && corepack enable        # only if the lockfile is pnpm/yarn
```

### Python

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends python3 python3-pip python3-venv \
    && rm -rf /var/lib/apt/lists/*
```

For a pinned minor version use `uv python install <ver>` or the deadsnakes repo — the distro's
python3 is whatever Debian shipped, which is rarely what the project pins.

### Go / Rust

Install from the official tarball / `rustup`, pinned. Distro packages lag badly.

### GitHub CLI

```dockerfile
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=${TARGETARCH} signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*
```

### Docker CLI (no daemon)

```dockerfile
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && echo "deb [arch=${TARGETARCH} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
        > /etc/apt/sources.list.d/docker.list \
    && apt-get update && apt-get install -y --no-install-recommends docker-ce-cli docker-compose-plugin docker-buildx-plugin \
    && rm -rf /var/lib/apt/lists/*
```

The repo path segment must match the base image's distro **and** codename — a Ubuntu-based image
needs `linux/ubuntu` and `$UBUNTU_CODENAME`. Getting this wrong is the single most common build
failure in this skill.

### PowerShell

```dockerfile
ARG PWSH_VERSION=<a release that exists — check the releases page>
RUN set -eux; \
    case "${TARGETARCH}" in amd64) a=x64 ;; arm64) a=arm64 ;; *) exit 1 ;; esac; \
    curl -fsSL "https://github.com/PowerShell/PowerShell/releases/download/v${PWSH_VERSION}/powershell-${PWSH_VERSION}-linux-${a}.tar.gz" -o /tmp/p.tgz; \
    mkdir -p /opt/microsoft/powershell/7 && tar zxf /tmp/p.tgz -C /opt/microsoft/powershell/7; \
    chmod +x /opt/microsoft/powershell/7/pwsh; ln -s /opt/microsoft/powershell/7/pwsh /usr/bin/pwsh; rm /tmp/p.tgz
```

### code-server

```dockerfile
RUN curl -fsSL https://code-server.dev/install.sh | sh
```

### Non-root user with the host's ids

```dockerfile
ARG USERNAME=dev
ARG USER_UID=1000
ARG USER_GID=1000
RUN if getent group ${USER_GID} >/dev/null; then groupmod -n ${USERNAME} "$(getent group ${USER_GID} | cut -d: -f1)"; else groupadd -g ${USER_GID} ${USERNAME}; fi \
    && if getent passwd ${USER_UID} >/dev/null; then usermod -l ${USERNAME} -d /home/${USERNAME} -m "$(getent passwd ${USER_UID} | cut -d: -f1)"; else useradd -m -u ${USER_UID} -g ${USER_GID} -s /bin/bash ${USERNAME}; fi \
    && echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} && chmod 0440 /etc/sudoers.d/${USERNAME}
```

Many base images already have a UID-1000 user under a different name — hence the rename branches
rather than a bare `useradd`, which fails on exactly those images.

## Known failure modes

| Symptom | Cause |
|---|---|
| apt repo 404 on build | distro/codename mismatch in a third-party repo line |
| `useradd: UID already in use` | base image ships a UID-1000 user — use the rename branch |
| Extensions missing despite a successful build | installed at build time into a path a volume later masks — install at entrypoint |
| Native npm module fails to build | alpine/musl base — use Debian |
| Bind-mounted files owned by root | UID/GID build args not matched to the host user |
| `pwsh` script dies on a Windows-only cmdlet | do the portability sweep in the parent skill, step 5 |
| Image works, project does not compile | you verified the build, not the project — run the project's own test command inside the box |
| Build fails on `obj/` permissions (MSBuild MSB3374, or the equivalent for other toolchains) | host and container are sharing build output through the bind mount. Send the container's output elsewhere (.NET: `ArtifactsPath`; and create that directory in the image, or the named volume mounts root-owned) |
| A whole-solution analyzer takes 20× longer than on the host | it reads every source file through the Docker Desktop VM share. Run those on the host, or put the repo in a named volume instead of a bind mount |
