<!-- Template for <project>/devbox/README.md. Fill the <...> markers from what you detected; delete
     rows for tools this project does not use. Keep the sharing warning and the credentials
     paragraph verbatim - they are the two things a reader must not miss. -->

# Devbox — the containerised work environment

One container carrying every tool this project needs, with **three ways in**: a browser editor,
your local VS Code, or VS Code from another machine over SSH. All three attach to the same
container, the same caches, the same running processes.

This is the **editor**, not the application.

## Start

```bash
cp devbox/.env.example devbox/.env      # set DEVBOX_PASSWORD
docker compose -f devbox/docker-compose.yml up -d --build
```

First build: ~<N> minutes, ~<N> GB. Every cache that matters lives on a named volume, so rebuilds
do not re-download them.

## The three ways in

1. **Browser** — <http://localhost:8443>, password from `DEVBOX_PASSWORD`. Nothing to install; this
   is the one to share.
2. **Local VS Code** — *Dev Containers: Reopen in Container*. Attaches to the same compose service;
   the browser editor keeps running alongside.
3. **Remote-SSH** — put your public key in `devbox/ssh/authorized_keys` and restart. `sshd` runs
   key-only on 2222 **as the unprivileged `dev` user**, so the only login it can grant is that user.
   Leave the file empty, or set `DEVBOX_ENABLE_SSH=0`, and no SSH server runs at all.

```
Host <project>-devbox
    HostName <the docker host>
    Port 2222
    User dev
```

## First terminal: logins

The first terminal you open reports which command-line logins this project needs and which are
still missing:

```
  ✓ git
  ✗ gh      → gh auth login
```

Sign in **inside the box**. No credential is forwarded in from your host — there are no token
variables in `devbox/.env` and none in the compose environment, deliberately. A credential created
in the box lives on the container's volume and can be revoked without touching your host.

## What's inside

| Tool | Version | Why |
|------|---------|-----|
| <tool> | <ver> | <the repo file that demands it> |

## Running the project from inside

```bash
<the project's own run command>       # from /workspace
```

The ports the project's dev servers bind are published by the devbox, so `http://localhost:<port>`
works on the host exactly as it does without the container.

<!-- Include only if the docker socket is mounted:
The host docker socket is mounted, so containers you start are siblings rather than nested. On
Docker Desktop the socket arrives root-owned, so prefix with `sudo`; on a Linux host the entrypoint
joins the socket's group and plain `docker` works.
-->

## Running the gates

`<the project's build/test/lint commands>` run unchanged.

<!-- Record here anything measured to behave differently in the box - build times, a step that is
     dramatically slower because it reads the whole tree through the bind mount, an output path
     that had to move. The next person should not have to rediscover it. -->

## Sharing it

**A devbox is a shell on a machine holding your source.** Put it behind TLS and an auth gate
(`Caddyfile.hosted.example`) and keep `DEVBOX_PASSWORD` set — both locks, always. If the docker
socket is mounted, exposing the editor is exposing the host.

## Changing it

- A tool everyone needs → add it to `devbox/Dockerfile`, rebuild, confirm it answers `--version`.
- An extension → add its **Open VSX** id to `devbox/settings/extensions.txt`. The list is
  re-applied whenever that file changes, and an id Open VSX does not carry is skipped, never fatal.
  Removing an id does not uninstall it: use `code-server --uninstall-extension <id>`.
- An editor setting → `devbox/settings/settings.json`. Copied on first start, so in-editor tweaks
  stick.
- Never bake a secret into the image.
