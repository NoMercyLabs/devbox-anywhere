# Detection

## Contents

- The sweep
- When no manifest matches
- Signal to toolchain
- Services
- Versions
- Ports

Read the repo. Do not infer the stack from the project's name, its README prose, or your memory
of what such projects usually use.

## The sweep

**Scan recursively, not just the root.** A monorepo keeps its manifests one or two levels down
(`server/`, `app/`, `packages/*`), and a root-only `ls` silently reports "no JVM here" for a repo
whose `app/build.gradle.kts` is the whole frontend — producing an image with no JDK that fails on
the project's first build. Verified failure mode, not a hypothetical.

```bash
# 1. manifests anywhere shallow, vendor dirs pruned
find . -maxdepth 3 \
     \( -name node_modules -o -name .git -o -name bin -o -name obj -o -name build -o -name target -o -name vendor -o -name .venv \) -prune -o \
     -type f \( -name 'package.json' -o -name '*.csproj' -o -name '*.sln*' -o -name 'go.mod' \
             -o -name 'Cargo.toml' -o -name 'pom.xml' -o -name 'build.gradle*' -o -name 'pyproject.toml' \
             -o -name 'requirements.txt' -o -name 'Gemfile' -o -name 'composer.json' -o -name 'mix.exs' \) -print

# 2. THE most informative file in the repo — read it first
cat .github/workflows/*.yml .gitlab-ci.yml 2>/dev/null

# 3. version pins, task runners, services, team editor config
cat .tool-versions .nvmrc .python-version global.json rust-toolchain* 2>/dev/null
ls scripts/ Makefile justfile Taskfile.yml 2>/dev/null
cat docker-compose*.yml .env.example 2>/dev/null
cat .vscode/extensions.json 2>/dev/null
```

The CI workflow is written by someone who had to make the project build from an empty machine.
Every `setup-*` action, `apt-get install`, and tool-restore step in it is a requirement you would
otherwise have to guess.

## When no manifest matches

A real project can have **zero manifests**: loose `.mjs` files run straight by node, a single-file
`app.cs` run by `dotnet run`, a pile of shell or Python scripts. Do not conclude "no toolchain".
Fall back to an extension census and treat the top extensions as the stack:

```bash
find . -maxdepth 4 \( -name node_modules -o -name .git -o -name bin -o -name obj -o -name target \) -prune -o \
     -type f -name '*.*' -print | sed 's/.*\.//' | sort | uniq -c | sort -rn | head -15
```

Then read the CI workflow and the entry scripts to learn how those files are actually executed —
that is what tells you the runtime and its version, not the extension alone.

## Signal → toolchain

| File found | Means | Put in the image |
|---|---|---|
| `*.csproj` / `*.sln` / `*.slnx` | .NET | SDK at the `global.json` version (not "latest") |
| `.config/dotnet-tools.json` | pinned .NET tools | run `dotnet tool restore` at entrypoint — pins matter |
| `package.json` | Node | Node at the `engines` / `.nvmrc` / CI version; the package manager its lockfile names |
| `pnpm-lock.yaml` / `yarn.lock` / `bun.lockb` | pnpm / yarn / bun | that manager, at the lockfile's version — not npm |
| `requirements.txt` / `pyproject.toml` | Python | CPython at the pinned version; `uv` or `poetry` if the lockfile says so |
| `go.mod` | Go | the `go` directive's version |
| `Cargo.toml` | Rust | rustup toolchain per `rust-toolchain.toml`; `build-essential` + `pkg-config` |
| `pom.xml` / `build.gradle*` | JVM | JDK per the toolchain block or CI; the wrapper handles Maven/Gradle itself |
| `*.gradle.kts` with `kotlin("multiplatform")` | KMP | JDK; Wasm/JS targets pull their own toolchain at build time |
| `Gemfile` | Ruby | Ruby at `.ruby-version`; `build-essential` for native gems |
| `composer.json` | PHP | PHP + the extensions `composer.json` requires |
| `*.xcodeproj` / `Package.swift` | Swift/Apple | **flag it**: Apple platform builds cannot run in a Linux container |
| `mix.exs` / `deps.ts` / `*.cabal` | Elixir / Deno / Haskell | the matching runtime |
| `playwright.config.*` / `cypress.config.*` | browser E2E | the vendor's own deps install (`playwright install --with-deps`) — heavy, so confirm |
| `*.ps1` in `scripts/` | PowerShell | `pwsh` — cross-platform; also do the portability sweep |
| `Dockerfile` at the root | the shipping image | read it for OS packages the app needs; do **not** reuse it as the devbox |
| `.pre-commit-config.yaml` / `.husky/` | git hooks | whatever the hooks invoke, or every commit fails inside the box |
| `terraform/` / `*.tf` / `k8s/` / `helm/` | infra | `terraform` / `kubectl` / `helm`, and note the credentials are the user's, never baked |

## Services

`docker-compose*.yml` and `.env.example` name the databases, caches and brokers. **Do not put
them in the devbox image.** Mount the host docker socket and let the project's own compose file
start them as siblings — one definition, not two that drift.

Check which profile actually runs in development. A project may define Postgres and still run on
SQLite locally; putting a Postgres client in the image is then justified, running a Postgres
server is not.

## Versions

Take the exact version from the repo. `global.json`, `.nvmrc`, `.tool-versions`,
`rust-toolchain.toml`, the `go` directive, the Gradle toolchain block, the CI `setup-*` inputs.
Where the repo does not pin one, pin it yourself in the Dockerfile and say so in a comment — an
unpinned base image is a build that breaks on a day nobody changed anything.

For anything whose current version you cannot read out of the repo (a CLI's latest release, a
base image tag), **look it up** rather than recalling it. Training data goes stale; a wrong pin
fails the build at the worst moment.

## Ports

Collect every port the project's own dev servers bind — from launch settings, `vite.config`,
`build.gradle.kts`, `appsettings.json`, the README's "open http://localhost:…". Publish those
from the devbox so behaviour inside the container matches behaviour outside it.
