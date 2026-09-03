# devbox-anywhere

An [Agent Skill](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview) that
builds a containerised development environment for **any** project.

Point an agent at a repository and say *"set up a dev environment"*. It reads the repo, works out
what the project is actually built with, writes a `devbox/` folder, builds the image, and proves
the project's own tests run inside it.

```bash
npx skills add NoMercyLabs/devbox-anywhere
```

Or clone it straight into your skills directory:

```bash
git clone https://github.com/NoMercyLabs/devbox-anywhere /tmp/devbox-anywhere \
  && cp -r /tmp/devbox-anywhere/skills/devbox-anywhere ~/.claude/skills/
```

## What you get

One container, **three ways in**, all attached to the same running instance:

- **Browser** — code-server on `localhost:8443`. Nothing to install; the one to share.
- **Local VS Code** — *Dev Containers: Reopen in Container*, same compose service.
- **Remote-SSH** — key-only `sshd` on 2222, running as the unprivileged container user.

The toolchain is derived from the repository, never assumed: pinned runtime versions from
`global.json` / `.nvmrc` / `rust-toolchain.toml` / the CI workflow, the dev tools the repo pins,
the ports its dev servers actually bind. **Every tool in the image is justified by a file in the
repo** — if nothing points at it, it does not go in.

Your editor comes with you: theme, icons, font and settings are inherited from your own VS Code or
Cursor, and your extension list is filtered down to the stack this project uses, preferring
first-party vendor tooling.

## Security

The generated environment **never forwards a host secret into the container**. No credential
environment variables, no mounted credential stores, no secrets baked into the image, no script
that reads or prints a credential.

The login onboarding step is names-only: the detection step records *which* CLIs this project
needs you signed in to (`git,gh,docker`), and the first terminal reports which are missing and the
command to fix each. You sign in inside the box, so that credential lives on the container's own
volume and is revocable without touching your host.

Full model, including the powers the box does hold and how to remove them:
[`skills/devbox-anywhere/references/security.md`](skills/devbox-anywhere/references/security.md).

## Documentation

- [Skill documentation](skills/devbox-anywhere/README.md) — how it works, step by step
- [SKILL.md](skills/devbox-anywhere/SKILL.md) — the workflow the agent follows
- [Security model](skills/devbox-anywhere/references/security.md)
- [Evaluations](skills/devbox-anywhere/references/evaluations.md)

## License

MIT — see [LICENSE](LICENSE).
