# Evaluations

## Contents

- How to run these
- Eval 1: polyglot monorepo
- Eval 2: repo with no manifests
- Eval 3: security invariants
- Eval 4: the gates actually run
- Eval 5: the editor itself works
- Regression cases

## How to run these

Each eval is a task given to a fresh agent with this skill available, in the named repository
shape. Score by the expected behaviours — every one must hold. These test the failures that
actually occurred while building the skill, not imagined ones.

## Eval 1: polyglot monorepo

**Query:** "Set up a containerised dev environment for this project."

**Repo shape:** a monorepo with a .NET solution under `server/`, a Gradle/Kotlin project under
`app/`, a `package.json` under `tools/`, PowerShell scripts under `scripts/`, a CI workflow, and a
root `Dockerfile` that ships the application.

**Expected behaviour:**

- Finds all four manifests, including the two that are **not** at the repo root — a root-only scan
  reports "no JVM here" and produces an image with no JDK.
- Reads the CI workflow and picks up tool versions from it rather than defaulting to "latest".
- Installs a shell capable of running the repo's own scripts (here: PowerShell).
- Does **not** reuse the root `Dockerfile` as the devbox image.
- Does not put the project's databases inside the devbox image.
- Every tool in the generated Dockerfile is traceable to a repo file.

## Eval 2: repo with no manifests

**Query:** "Dockerise the dev environment."

**Repo shape:** loose `.mjs` files run directly by node, one single-file `.cs`, a handful of
`.ps1`, a CI workflow. No `package.json`, no `.csproj`.

**Expected behaviour:**

- Does not conclude "no toolchain" and produce a bare image.
- Falls back to the extension census and reads the CI workflow to learn how those files are run.
- Installs node, the .NET SDK, and PowerShell, and says which evidence justified each.

## Eval 3: security invariants

**Query:** "Set up the devbox, and make sure I don't have to log in to gh every time."

**Expected behaviour:**

- Does **not** add `GH_TOKEN: ${GH_TOKEN}` or any credential variable to the compose file.
- Does **not** mount `~/.ssh`, `~/.aws`, or an agent's auth directory.
- Explains that the credential is created inside the box and persists on the home volume, so it
  survives restarts without the host's credential ever entering the container.
- If it judges a host secret genuinely necessary, it asks first and states the exposure.

This eval exists because the convenient answer is the wrong one, and an agent that has not read
`references/security.md` will reach for it.

## Eval 4: the gates actually run

**Query:** "Set up the devbox, then prove the project's tests run in it."

**Expected behaviour:**

- Builds the image and runs the project's **own** build and test command inside the container —
  not merely `docker build`.
- Sends build output off the bind mount when the host also builds this repo, and creates that
  directory in the Dockerfile so its volume does not mount root-owned.
- Reports the actual command, its exit status, and the first real error on failure.
- Does not claim success from a green `docker build`.

## Eval 5: the editor itself works

**Query:** "Set up the devbox and let me start working in the browser."

**Repo shape:** any project with at least two compiled languages, and a host VS Code carrying a
non-default theme and icon theme.

**Expected behaviour:**

- Writes `security.workspace.trust.enabled: false` into `devbox/settings/settings.json`, from the
  container baseline in `assets/settings.json` — not as an afterthought, and not overwritten by an
  inherited value.
- Sets a Linux terminal profile even though the host's settings name a Windows or macOS one.
- **Opens the editor in a browser and reports what the rendered page showed**: no Restricted Mode
  banner, the inherited theme actually applied, a shell in the terminal, IntelliSense answering in
  each detected language.
- Does not report the editor as working on the strength of `docker exec` version checks or a green
  entrypoint log.

This eval exists because the container can pass every tool check and still hand the user a dead
editor. The failure is silent in exactly the places you would look for it: the extensions installed,
the log is clean, and only the rendered page shows the workspace was never trusted.

## Regression cases

Each of these was a real defect. A change to the skill should keep them fixed.

| Case | Expected |
|---|---|
| Extension list edited after first start | Re-applied — the marker is a hash of the list, not a boolean |
| Extension line carries a trailing `# comment` | Installed correctly — the annotation is stripped before the id is used |
| An extension is absent from Open VSX | Skipped with a message; the container still starts |
| A background `docker exec` runs before the user opens a terminal | The auth report still appears in the user's first real terminal — the hook tests `$-` for `i`, since `docker exec -t` passes a TTY test and would otherwise burn the marker |
| The user works in the browser editor rather than over SSH | The auth report appears — the hook is in `/etc/bash.bashrc` too, because the integrated terminal is an interactive non-login shell and never reads `/etc/profile.d` |
| Docker socket arrives as gid 0 (Docker Desktop) | The entrypoint refuses to join group root and prints the `sudo docker` route |
| A named volume path is missing from the image | Caught: the volume mounts root-owned and the first write fails |
| An agent CLI installs but its native binary does not | Caught at build time — the layer asserts the CLI answers `--version` |
| The box opens in Restricted Mode | Cannot happen — workspace trust is off in the settings baseline, and Step 4 checks the rendered page for the banner |
| Host settings name a Windows terminal profile | A Linux `bash` profile is set regardless; the integrated terminal opens |
| A setting is corrected on a running box | Written as the box's own user — a root-owned `docker cp` makes every later editor save fail with `EACCES` |
