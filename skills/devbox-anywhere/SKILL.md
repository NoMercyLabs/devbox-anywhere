---
name: devbox-anywhere
description: Builds a containerised development environment for any project - a VS Code host reachable three ways (browser code-server, local Dev Containers, Remote-SSH) carrying exactly the toolchain that project needs. Detects the stack by reading the repository rather than assuming it. Use when the user asks to dockerise a dev environment, set up a devbox or dev container, give a teammate a ready-made work environment, run an editor in Docker, or make "it works on my machine" reproducible.
---

# Devbox anywhere

Produce a `devbox/` for the project you are standing in: one container, three ways in, carrying the
toolchain **this** repository actually needs.

**Every tool in the image must be justified by a file in the repo.** If you cannot point at the
manifest, lockfile, config, or script that needs it, it does not go in. An image full of
speculative tooling is slow to build, expensive to maintain, and hides what the project really
depends on.

**Never forward a host secret into the container.** Read [references/security.md](references/security.md)
before writing any compose file. This is not negotiable and the convenient shortcut is the wrong
answer.

## Workflow

Copy this checklist and check off each step:

```
Devbox progress:
- [ ] Step 1: Detect the stack
- [ ] Step 2: Confirm only the genuine forks
- [ ] Step 3: Generate the files
- [ ] Step 4: Build and verify
- [ ] Step 5: Portability sweep
```

### Step 1: Detect the stack

Read [references/detection.md](references/detection.md) and run the sweep. You are looking for four
things: language runtimes with their **pinned** versions, pinned dev tools, services the app talks
to, and the commands people actually run.

Read the CI workflow first. It is the one file where someone already wrote down every tool needed
to build the project from an empty machine.

Two traps, both caught by dry-running this on real repositories:

- **Scan recursively.** Manifests live one or two levels down in a monorepo. A root-only look
  reported "no JVM" for a repo whose entire frontend was `app/build.gradle.kts`.
- **No manifest is not no toolchain.** Loose `.mjs` files, a single-file `app.cs`, a pile of
  scripts — fall back to the extension census in the same reference.

### Step 2: Confirm only the genuine forks

Decide the obvious yourself. Ask only where the repo does not say and the answer changes the image:
two plausible base images, or a heavyweight optional component (browsers for end-to-end tests,
GPU/CUDA, a mobile SDK, a database inside the box rather than alongside it).

### Step 3: Generate the files

Copy from `assets/` and fill in the markers. Each template carries comments explaining what every
block does and why.

| File | From | Notes |
|---|---|---|
| `devbox/Dockerfile` | `assets/Dockerfile` | Base image per [references/toolchain.md](references/toolchain.md), then one labelled block per detected tool, each naming the repo file that demands it |
| `devbox/entrypoint.sh` | `assets/entrypoint.sh` | Verbatim — it is project-agnostic |
| `devbox/auth-onboarding.sh` | `assets/auth-onboarding.sh` | Add a `check()`/`fix()` case for any tool the asset does not cover |
| `devbox/docker-compose.yml` | `assets/docker-compose.yml` | Cache volumes for the detected ecosystems; publish the ports this project's dev servers bind |
| `devbox/settings/settings.json` | `assets/settings.json` | The container baseline first — workspace trust off, Linux terminal, LF — then the user's look and feel merged on top, per [references/editor-inheritance.md](references/editor-inheritance.md) |
| `devbox/settings/extensions.txt` | — | Inherited then filtered to the detected stack, same reference. Open VSX ids |
| `devbox/.env.example` | `assets/env.example` | |
| `devbox/README.md` | `assets/project-readme.md` | |
| `devbox/Caddyfile.hosted.example` | `assets/Caddyfile.hosted.example` | Only if the box will be shared |
| `.devcontainer/devcontainer.json` | `assets/devcontainer.json` | Points at the same compose service, so local VS Code attaches to the identical container |

Three parts of this step have their own rules:

**Editor inheritance.** Read [references/editor-inheritance.md](references/editor-inheritance.md).
Look and feel is inherited wholesale from the user's own VS Code / Cursor / VSCodium; extensions
are inherited then filtered to what the detected stack uses. Always take the vendor's own
first-party language tooling. Remember that a theme is an extension — copying `colorTheme` without
its provider leaves the editor on its default with no error.

**Login onboarding.** Declare the CLIs this project needs a login for as a comma-separated list of
**names** in `DEVBOX_AUTH`. The first terminal reports which are missing and the exact command to
fix each. It reports only: no credential is passed in, read, stored, or transmitted, and the user
signs in themselves inside the box. Full mechanism in
[references/security.md](references/security.md).

**The five things a fresh container silently lacks.** None announce themselves; each surfaces as a
different, misleading failure:

1. **Workspace trust** — VS Code opens a container workspace in **Restricted Mode**, which keeps
   every language extension dormant. The symptom is no IntelliSense and no formatter, so you go
   hunting for a failed extension install that never happened. Set
   `security.workspace.trust.enabled: false` in the settings baseline; the container is the sandbox.
2. **Git identity** — mount the host `~/.gitconfig` read-only, or commits land under a name nobody
   recognises. On Windows and macOS hosts `~` does not expand as expected; expose a full-path
   override variable.
3. **Forge credentials** — absent by design. The user logs in inside the box.
4. **Memory** — a container sees the *host's* total RAM, so build daemons size their heaps for a
   machine they do not have and get OOM-killed, which surfaces as a *compiler crash*. Cap the
   daemons with environment variables **and** set `mem_limit`.
5. **The agent's own CLI** — if the user works with one, install it and let it authenticate itself
   in the box.

### Step 4: Build and verify

```bash
docker compose -f devbox/docker-compose.yml build
docker compose -f devbox/docker-compose.yml up -d
docker exec <name> bash -lc '<tool> --version'   # every tool, one by one
curl -fsS -o /dev/null -w '%{http_code}' http://localhost:<port>/healthz   # expect 200
```

Then run **the project's own build and test command inside the box**. That is the only proof the
environment works; a successful `docker build` proves nothing about whether the project compiles in
it. Fix what breaks, rebuild, re-verify.

Report the version each tool actually printed. A tool that does not answer `--version` is not
installed, whatever the build log said.

**Then open the editor and look at it.** `docker exec` proves the toolchain; it says nothing about
the editor the person will actually sit in, and every editor-side defect is silent by design. Load
`http://localhost:<DEVBOX_PORT>`, sign in, and confirm on the rendered page:

- **No Restricted Mode banner.** If it is there, the language extensions are dormant — fix the
  trust setting, do not dismiss the banner.
- The inherited **theme and icon theme actually rendered**, not the default — proof their provider
  extensions resolved on Open VSX.
- The status bar shows **no extension-activation errors**, and the integrated terminal opens a shell.
- Open one file per detected language and confirm IntelliSense responds.

When you correct a setting on a running box, edit it **as the box's own user**
(`docker exec -u <user> …`). A `docker cp` writes the file owned by root, and the editor then fails
every later save with `EACCES` — a break that outlives the fix it delivered.

Two failures to expect the first time, both covered in
[references/toolchain.md](references/toolchain.md): build output colliding with the host's, and a
named volume mounting root-owned because its path is missing from the image.

### Step 5: Portability sweep

Scripts written on one operating system often will not run in the container. Grep the project's own
scripts for host-specific APIs and fix or guard them — this is part of the job, not a follow-up:

- PowerShell: `Get-NetTCPConnection`, `Get-CimInstance`, `Get-WmiObject`, `Start-Process
  -WindowStyle`, `$env:USERPROFILE`, drive letters. Branch on `$IsWindows`.
- Bash: GNU versus BSD flags for `sed`, `date`, `readlink`.
- Any: hardcoded absolute paths, host-only process names, backslash path separators.

## Design decisions in the templates

Keep these unless the project forces otherwise. Each exists because the naive alternative fails.

- **Three ways in, one container.** Browser code-server; local VS Code through Dev Containers on
  the same compose service; Remote-SSH through an **unprivileged** `sshd` on 2222, started only
  when a public key is present.
- **Caches on named volumes**, never in the image — a rebuild must not re-download the dependency
  tree.
- **Extensions install at entrypoint, not build time.** The extensions directory is a volume, so a
  build-time install is shadowed by it. Tolerate a missing extension: Open VSX carries a smaller
  catalogue than the Microsoft marketplace.
- **Settings are copied once, not symlinked**, so an in-editor tweak sticks.
- **Non-root user with the host's UID and GID** as build args, or bind-mounted files come out
  root-owned on Linux.
- **Docker CLI only, host socket opt-in** — sibling containers, not Docker-in-Docker. The socket is
  root-equivalent access to the host; the template leaves it commented out.
- **Bind-mount reality** — on Docker Desktop the mounted repo crosses a VM boundary. That is why
  every dependency cache belongs on a named volume rather than under the repo, and why a
  whole-project analyzer can be an order of magnitude slower in the box than on the host.

## Reference files

- [references/detection.md](references/detection.md) — signal-to-toolchain table, the sweep
  commands, version-pin sources
- [references/toolchain.md](references/toolchain.md) — base image choice, a ready block per
  ecosystem, known failure modes
- [references/editor-inheritance.md](references/editor-inheritance.md) — mining the user's editor
  config, first-party tooling, Open VSX id traps
- [references/security.md](references/security.md) — what the box never does, the login-onboarding
  mechanism in full, the powers it does hold, review checklist
- [references/evaluations.md](references/evaluations.md) — four evaluations and the regression cases
