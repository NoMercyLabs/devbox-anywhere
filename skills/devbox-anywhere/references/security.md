# Security model

## Contents

- What the generated devbox never does
- The auth-onboarding step, in detail
- Powers the box does hold, and why
- Exposing the box to other people
- Supply chain
- Review checklist

## What the generated devbox never does

These are invariants of this skill. A generated devbox that breaks one has a bug.

| Never | Why |
|---|---|
| Forward a host secret into the container | No `GH_TOKEN: ${GH_TOKEN}`, no API keys, no cloud credentials in `environment:`. Harvesting the host's credentials into a container is what malware does; a dev environment must not be indistinguishable from it. |
| Mount a credential store | Not `~/.aws`, not `~/.ssh` private keys, not an agent's auth directory. The only home-directory mount is `~/.gitconfig`, read-only, which carries a name and an email. |
| Bake a secret into the image | Image layers are cached, shared, and pushed. Anything in one is public to anyone who can pull it. |
| Read, print, or store a credential in a script | `auth-onboarding.sh` tests whether a tool is signed in and prints yes or no. It never opens a credential file's contents. |
| Enable a listening SSH service by default | `sshd` starts only when the operator has placed a public key in `devbox/ssh/`. |
| Run the editor as root | The container's user is unprivileged and owns only its own home and the workspace. |

If a project genuinely cannot work without a host secret, **ask the user first** and state the
exposure plainly. Never wire it up because it is convenient.

## The auth-onboarding step, in detail

The most common misreading of this skill is that it "collects auth". It does not. Here is the
entire mechanism.

**At generation time.** The detection step establishes which CLIs the project needs a login for —
`gh` because the repo's CI workflow calls it, `docker` because the compose file starts services,
`npm` because the lockfile points at a private registry. Those **names** are written into
`docker-compose.yml` as a comma-separated list:

```yaml
DEVBOX_AUTH: "git,gh,docker"
```

That string is the entire payload. It is a list of tool names, no different in sensitivity from
the list of packages in the Dockerfile.

**At container start.** A one-line hook in `/etc/profile.d/` runs `devbox-auth` on the first
interactive terminal. For each name, the script asks the tool itself whether it is signed in —
`gh auth status`, `docker info`, `git config --get user.email` — and prints one line per tool:

```
  ✓ git
  ✗ gh      → gh auth login
  ✗ docker  → sudo docker (Docker Desktop hands the socket over root-owned), or check the mount
```

**What crosses the boundary:** tool names in, a pass/fail line out. Nothing else.

**What the script cannot do**, by construction:

- It never receives a token, because none is passed in.
- It never reads a credential's contents. The `claude` check tests that a credentials file is
  non-empty; it does not open it.
- It never writes a credential anywhere.
- It never performs a login. It prints the command for the user to type.
- It never contacts a network service on the user's behalf beyond the tool's own local status
  check.

**Where credentials actually come from:** the user runs `gh auth login` (or equivalent) inside the
box. That credential is created in the container, lives on the container's home volume, and can be
revoked without touching anything on the host. This is strictly better than forwarding the host's
credential in — the box gets its own identity, with its own audit trail and its own revocation.

**Why bother at all:** without it, a fresh container's missing login is discovered by failure —
a push that 403s twenty minutes into a task, a CLI that exits 1 with no explanation. The step
converts that into a checklist shown before any work starts.

## Powers the box does hold, and why

Development environments need real capability. These are the deliberate grants; each is listed so
an operator can remove it knowingly.

**Passwordless sudo inside the container.** Needed for two things: the entrypoint joining the
docker socket's group, and a developer installing a missing package mid-task. Its scope is the
container, not the host. Remove the `sudoers.d` line if your policy forbids it — the socket
group-join is then the only feature that stops working.

**The workspace bind mount.** The box has full read/write access to the repository. That is the
point of a dev environment. It has no access to anything else on the host filesystem.

**The docker socket — opt-in, and the one to think hard about.** Mounting `/var/run/docker.sock`
gives everything in the container root-equivalent control of the host: it can start a privileged
container that mounts `/`. It is genuinely useful (the project's own compose stack runs as sibling
containers rather than nested), and it is genuinely dangerous. It is commented out in the template
for that reason. Enable it when the project needs it, and never enable it on a box other people
can reach without both locks below.

**`git config --global --add safe.directory <workspace>`.** Scoped to the one mounted repository.
The wildcard form disables git's ownership check for every repository the user touches inside the
box, including anything cloned later — do not widen this.

## Exposing the box to other people

A devbox is a shell on a machine with your source code on it. If it is reachable beyond localhost,
it needs **both** of:

1. **A transport and gate you control** — TLS plus an auth gate at the reverse proxy
   (`assets/Caddyfile.hosted.example`).
2. **code-server's own password** — `DEVBOX_PASSWORD`.

And, before exposing: confirm with the user, and check whether the docker socket is mounted. With
the socket enabled, exposing the editor is exposing the host, full stop.

## Supply chain

The image installs from three kinds of source. Know which is which:

| Source | Examples | Note |
|---|---|---|
| Distribution packages, signed | `apt` from Debian, plus vendor apt repos added with their signing key (Docker, GitHub CLI, NodeSource) | The keyring is fetched over HTTPS and referenced with `signed-by=`, so package signatures are verified |
| Vendor installer over HTTPS | `curl -fsSL https://code-server.dev/install.sh \| sh` | This is the vendor's published install path. If your policy forbids piping an installer to a shell, replace it with the vendor's `.deb` at a pinned version |
| Language package managers | `npm install -g <cli>` | Pin versions where the tool's behaviour matters to the gates |

**Pin everything.** An unpinned base image or tool version turns an untouched project into a build
that breaks on a day nobody changed anything. Where the repo pins a version, use exactly that one.

## Review checklist

Before handing a generated devbox to anyone:

- [ ] No credential-shaped environment variables in `docker-compose.yml`
- [ ] No mount of a credential store; `~/.gitconfig` is read-only if present
- [ ] `DEVBOX_AUTH` contains tool names only
- [ ] The docker socket is mounted only if this project needs it, and the README says what that means
- [ ] `devbox/.env` is gitignored, and `.env.example` holds no real values
- [ ] `devbox/ssh/` is gitignored for key files
- [ ] Base image and every added tool are pinned
- [ ] `safe.directory` is scoped to the workspace, not `*`
- [ ] The container runs as a non-root user
