# devbox-anywhere

An [Agent Skill](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview) that
builds a containerised development environment for **any** project — a VS Code host carrying
exactly the toolchain that repository needs, reachable three ways, with the stack detected by
reading the repo rather than assumed.

You point an agent at a project and say "set up a dev environment". It reads the repository,
works out what the project is built with, writes a `devbox/` folder, builds the image, and proves
the project's own tests run inside it.

---

## Contents

- [What it produces](#what-it-produces)
- [The three ways in](#the-three-ways-in)
- [How it works, step by step](#how-it-works-step-by-step)
- [The login onboarding step](#the-login-onboarding-step)
- [Security posture](#security-posture)
- [Installing](#installing)
- [Skill layout](#skill-layout)
- [Design decisions](#design-decisions)
- [Testing this skill](#testing-this-skill)
- [License](#license)

---

## What it produces

```
<project>/
├── .devcontainer/
│   └── devcontainer.json          local VS Code attaches to the same container
└── devbox/
    ├── Dockerfile                 the toolchain, one labelled block per detected tool
    ├── entrypoint.sh              start-up: settings, extensions, bootstrap, sshd, code-server
    ├── auth-onboarding.sh         first-terminal login report
    ├── docker-compose.yml         mounts, caches, ports, limits
    ├── .env.example               password, ports, UID/GID
    ├── README.md                  how to use this project's box
    ├── Caddyfile.hosted.example   only if the box will be shared
    ├── settings/
    │   ├── settings.json          editor settings inherited from your own editor
    │   └── extensions.txt         Open VSX ids, filtered to this project's stack
    └── ssh/                       your public key goes here (gitignored)
```

Nothing in that tree is boilerplate. The Dockerfile's tools are the ones this repo's manifests and
CI workflow call for; the extension list is your own editor's, filtered; the ports are the ones the
project's dev servers actually bind.

## The three ways in

All three attach to the **same container** — same caches, same running processes, same state.

| Way | How | Good for |
|---|---|---|
| **Browser** | `http://localhost:8443`, password from `.env` | Sharing. Nothing to install on the other person's machine. |
| **Local VS Code** | *Dev Containers: Reopen in Container* | Your own machine, native editor, full keybindings. |
| **Remote-SSH** | key-only `sshd` on 2222, as the unprivileged container user | Another machine on your network, or a box on a server. |

The browser editor keeps running while you work in the desktop one.

## How it works, step by step

### 1. Detect

The agent scans the repository — recursively, because monorepos keep their manifests one or two
levels down — for four things:

- **Language runtimes with their pinned versions.** From `global.json`, `.nvmrc`,
  `rust-toolchain.toml`, the `go` directive, the Gradle toolchain block, the CI workflow's
  `setup-*` inputs. Never "latest".
- **Pinned dev tools.** Tool manifests, lockfiles, `devDependencies`, git hooks, CI steps.
- **Services the app talks to.** Compose files, connection strings, `.env.example`.
- **The commands people actually run.** `scripts/`, `Makefile`, task runners, the CI workflow.

The CI workflow is read first: it is the one file where somebody already wrote down everything
needed to build the project from an empty machine.

If a repo has **no manifests at all** — loose `.mjs` files, a single-file `app.cs`, a pile of
scripts — the skill falls back to an extension census rather than concluding there is no toolchain.

### 2. Confirm

The agent decides the obvious itself and asks only where the repo does not say and the answer
changes the image: two plausible base images, or a heavyweight optional component like browsers
for end-to-end tests, GPU support, or a mobile SDK.

### 3. Generate

Templates from `assets/`, filled in. Every tool in the Dockerfile carries a comment naming the repo
file that justifies it — so the next person can remove one with confidence.

Editor settings and extensions come from **your** editor. Look and feel is inherited wholesale
(theme, icons, font, ligatures, minimap); extensions are inherited and then filtered down to the
detected stack. First-party vendor tooling is always preferred over community forks. A theme is an
extension, so the provider is added alongside the setting — copying `colorTheme` alone leaves the
editor on its default with no error.

### 4. Build and verify

The agent builds the image, checks every tool answers `--version`, and then runs **the project's
own build and test command inside the container**. A green `docker build` is not evidence the
project compiles in the box; only the project's own gate is.

### 5. Portability sweep

Scripts written on one OS often fail in a Linux container. The agent greps the project's own
scripts for host-specific APIs — Windows-only PowerShell cmdlets, GNU-versus-BSD flag differences,
hardcoded paths — and fixes or guards them. This is part of the job, not a follow-up.

## The login onboarding step

This is the part most worth understanding, because its name invites the wrong assumption.

**It never touches a token. It never collects, stores, forwards, or transmits a credential.**

Here is the whole mechanism:

**At generation time**, the detection step works out which command-line tools this project needs
you to be signed in to — `gh` because the CI workflow calls it, `docker` because the compose file
starts services, `npm` because the lockfile points at a private registry. Those **names** are
written into the compose file:

```yaml
DEVBOX_AUTH: "git,gh,docker"
```

That string is the entire payload. A list of tool names — no more sensitive than the list of
packages in the Dockerfile.

**At container start**, a one-line hook in `/etc/profile.d/` runs the report on your first
interactive terminal. For each name it asks the tool itself whether it is signed in — `gh auth
status`, `docker info`, `git config --get user.email` — and prints one line each:

```
  ✓ git
  ✗ gh      → gh auth login
  ✗ docker  → sudo docker (Docker Desktop hands the socket over root-owned), or check the mount
```

Then it exits. **You** run `gh auth login`, inside the box, yourself.

What crosses the boundary: **tool names in, a pass/fail line out.** Nothing else. The script cannot
do more than that by construction — no token is passed in, no credential file's contents are ever
opened (the one file-based check tests only that a file is non-empty), nothing is written, no login
flow is performed on your behalf.

**Why this design rather than forwarding your host credentials in:** a credential created inside
the box lives on the container's own volume. It can be revoked without touching anything on your
host, it has its own audit trail, and it does not exist in an image layer or an environment
variable where it could leak. Forwarding the host's secrets into a container is what malware does;
a development environment must not be indistinguishable from it.

**Why bother at all:** without it, a missing login is discovered by failure — a push that 403s
twenty minutes into a task, a CLI that exits 1 with no explanation. This turns that into a
checklist you see before starting work.

## Security posture

Full detail in [references/security.md](references/security.md). The invariants:

- No host secret is forwarded into the container. No credential-shaped environment variables.
- No credential store is mounted. The only home-directory mount is `~/.gitconfig`, read-only,
  which carries a name and an email.
- No secret is baked into the image.
- No script reads or prints a credential.
- SSH is off unless you place a public key, and its `sshd` runs as the unprivileged container
  user, so the only account it could ever grant is that one.
- The editor does not run as root.

Powers the box *does* hold, stated plainly so you can remove them knowingly: passwordless sudo
**inside the container**, full access to the mounted repository, and — **opt-in, commented out in
the template** — the host's docker socket, which is root-equivalent control of the host machine.

If the box will be reachable by anyone else, it needs TLS plus an auth gate at the proxy **and**
code-server's own password. Both, always.

## Installing

**Claude Code**, per-user:

```bash
git clone <this repo> ~/.claude/skills/devbox-anywhere
```

Or per-project, in `.claude/skills/devbox-anywhere/`. The directory name must match the `name`
field in `SKILL.md`.

**Via the skills CLI**, from a repository laid out as `skills/devbox-anywhere/SKILL.md`:

```bash
npx skills add <owner>/<repo>
```

Then just ask: *"set up a containerised dev environment for this project"*.

## Skill layout

```
devbox-anywhere/
├── SKILL.md                          the workflow the agent follows
├── README.md                         this file
├── LICENSE
├── references/                       loaded only when the step needs them
│   ├── detection.md                  signal→toolchain table, sweep commands, version pins
│   ├── toolchain.md                  base image choice, per-ecosystem blocks, failure modes
│   ├── editor-inheritance.md         mining your editor config, first-party tooling, Open VSX ids
│   ├── security.md                   invariants, the auth step in full, review checklist
│   └── evaluations.md                five evaluations and the regression cases
└── assets/                           templates copied into the project
    ├── Dockerfile
    ├── entrypoint.sh
    ├── auth-onboarding.sh
    ├── docker-compose.yml
    ├── devcontainer.json
    ├── env.example
    ├── settings.json                  editor settings: the container baseline to merge onto
    ├── project-readme.md
    └── Caddyfile.hosted.example
```

`SKILL.md` stays short and links one level deep, so the agent loads a reference only when the step
in front of it needs one.

## Design decisions

Each of these exists because the naive alternative was tried and failed.

| Decision | Because |
|---|---|
| Extensions install at entrypoint, not build time | The extensions directory is a volume; a build-time install is shadowed the moment it mounts. |
| The auth hook is installed in `/etc/bash.bashrc` as well as `/etc/profile.d` | The integrated terminal starts an interactive **non-login** shell, which never reads `profile.d`. A profile.d-only hook fires for Remote-SSH and is invisible to everyone working in the browser. |
| The hook tests `$-` for `i`, not just `[ -t 1 ]` | `docker exec -t` passes the TTY test, so a background exec burned the once-per-container marker and the user's own terminal showed nothing. |
| The install marker is a hash of the list, not a flag | With a flag, the first list is frozen for the life of the volume and later edits are ignored with no error. |
| Settings are copied once, not symlinked | So a tweak made in the editor sticks. Editing the committed file therefore does not reach a box that already ran — say so in the project README. |
| Workspace trust is off in the settings baseline | The container is the sandbox. Left on, VS Code opens in Restricted Mode and every language extension stays dormant, which presents as a failed extension install rather than as an untrusted workspace. |
| Caches live on named volumes | A rebuild must never re-download the dependency tree. On Docker Desktop the bind mount also crosses a VM boundary and is slow. |
| Build output goes off the bind mount | Host and container builds sharing an output directory fail on file ownership and timestamps. |
| Every volume path is created in the image | Docker seeds a named volume from the image path; if the path is missing, the volume mounts root-owned. |
| The auth hook is gated on a TTY | Otherwise a background `docker exec` consumes the once-per-container marker and your real terminal never shows the report. |
| `sshd` runs unprivileged on 2222 | It cannot switch users, so the worst case is the container's own user. |
| The docker socket is opt-in | It is root-equivalent access to the host. |

## Testing this skill

[references/evaluations.md](references/evaluations.md) carries four evaluations — a polyglot
monorepo, a repo with no manifests, the security invariants, and proving the project's gates
actually run — plus the regression cases for every defect found while building it.

## License

MIT. See [LICENSE](LICENSE).
