# Inherit the user's editor, then filter to the project

## Contents

- Settings the container needs, whatever the host says
- Where the config lives
- Inherit: look and feel
- Filter: extensions
- Always take the vendor's own tooling
- The Open VSX catch
- Comment the choices

Two independent jobs. **Look and feel is inherited wholesale** — it is personal, and a devbox
that looks foreign is one people avoid. **Extensions are inherited then filtered** — the user's
machine carries every stack they have ever touched, and the devbox carries only this project's.

## Settings the container needs, whatever the host says

Inheritance is the second job, not the first. Start from `assets/settings.json` — the container
baseline — and merge the user's look and feel **on top of** it. Those baseline settings are true
because the editor runs in a container, so no inherited value may overwrite one.

| Setting | Why the host's answer is wrong inside the box |
|---|---|
| `security.workspace.trust.enabled: false` | The container is already the sandbox. Left on, the workspace opens in **Restricted Mode** and every language extension stays dormant |
| `terminal.integrated.defaultProfile.linux` + a `bash` profile | The host may be Windows or macOS; the box is Linux, and an inherited profile leaves the terminal unable to open a shell |
| `files.eol: "\n"` | A Windows host writes CRLF into a Linux container's build tree |
| `telemetry.telemetryLevel: "off"` | Nothing in a disposable box should phone home |

**Workspace trust is the one that costs a day.** It surfaces as a thin banner across the top —
easy to dismiss unread — and the symptom is not "untrusted workspace", it is *no IntelliSense, no
formatter, no debugger*, which reads exactly like the extension install having failed. You then go
looking in the entrypoint log, where everything installed fine. Set it in the baseline, and confirm
the banner is absent when you open the editor (Step 4).

## Where the config lives

| Editor | Settings | Extensions |
|---|---|---|
| VS Code | `%APPDATA%/Code/User/settings.json` · `~/.config/Code/User/settings.json` · `~/Library/Application Support/Code/User/settings.json` | `~/.vscode/extensions/` |
| Cursor | same path with `Cursor` | `~/.cursor/extensions/` |
| Windsurf | same path with `Windsurf` | `~/.windsurf/extensions/` |
| VSCodium | same path with `VSCodium` | `~/.vscode-oss/extensions/` |

Read **every** variant that exists; people configure one and drift on the others. Where they
disagree, prefer the one whose settings file was modified most recently.

```bash
# ids, version suffix stripped
ls ~/.vscode/extensions ~/.cursor/extensions 2>/dev/null \
  | sed -E 's/-[0-9]+\.[0-9]+\.[0-9]+.*$//' | sort -u
```

Also read the project's own `.vscode/extensions.json` — that is the team's stated list, and it
outranks a personal one where they conflict.

## Inherit: look and feel

Carry these across verbatim: `workbench.colorTheme`, `workbench.iconTheme`,
`workbench.productIconTheme`, `editor.fontFamily`, `editor.fontSize`, `editor.fontLigatures`,
`editor.minimap.enabled`, `editor.renderWhitespace`, `editor.cursorStyle`, `terminal.integrated.fontSize`,
`workbench.startupEditor`, `git.autofetch`, `git.enableSmartCommit`.

**A theme is an extension.** Inheriting `workbench.colorTheme` without adding the extension that
provides it leaves the editor on its default theme with no error shown — the single most common
way this step half-works. Map the theme name to its extension and put it in `extensions.txt`:

| Theme name | Extension |
|---|---|
| One Dark Pro / Darker / Flat | `zhuangtongfa.material-theme` |
| Dracula | `dracula-theme.theme-dracula` |
| GitHub Dark / Light | `github.github-vscode-theme` |
| Material Theme | `equinusocio.vsc-material-theme` |
| Night Owl | `sdras.night-owl` |
| Catppuccin | `catppuccin.catppuccin-vsc` |
| Tokyo Night | `enkia.tokyo-night` |
| vscode-icons | `vscode-icons-team.vscode-icons` |
| Material Icon Theme | `pkief.material-icon-theme` |

If the theme is not in that table, find its publisher id rather than substituting a lookalike.

## Filter: extensions

Keep an extension only if it serves a language, tool, or file type the detection step actually
found in this repo. Everything else goes — in a browser editor every extension costs start-up
time, and a devbox stuffed with a stack the project does not use misrepresents the project.

**Keep** — theme + icons; the language extension for each detected runtime; the project's own
pinned formatter or linter (that one matters most: it makes format-on-save agree with the
commit gate); the file types the repo genuinely contains (XML if resources are XML, YAML for
compose/CI, TOML, dotenv); a client for the detected database; git/CI helpers; markdown tooling
if the repo is documentation-heavy; the user's small everyday habits (todo-tree, better-comments,
spell-check, indent-rainbow) — those are cheap and personal.

**Drop** — every stack the repo does not contain, however many the user has installed; remote
development extensions (`ms-vscode-remote.*`, `anysphere.remote-*`) — you are already inside the
container; anything doing local machine integration (Live Share, browser devtools bridges, pets).

**Judge AI assistants case by case.** Include the one the user actually works with if it is
published on Open VSX; do not add one they do not use.

## Always take the vendor's own tooling

For every detected language, install the **first-party** extension — the one published by the
people who make the language or framework. A community fork lags the language, misses the newest
syntax, and diverges from the compiler the project actually builds with. Reach for a third-party
one only when the vendor publishes nothing for that host, and say so in a comment when you do.

| Language / framework | First party | Publisher |
|---|---|---|
| C# / .NET | `ms-dotnettools.csharp` + `ms-dotnettools.csdevkit` | Microsoft |
| Kotlin | `jetbrains.kotlin-server` | JetBrains |
| Java | `redhat.java` (`vscjava.vscode-java-pack`) | Red Hat / Microsoft |
| Vue | `vue.volar` | the Vue team |
| Go | `golang.go` | the Go team |
| Rust | `rust-lang.rust-analyzer` | the Rust project |
| Python | `ms-python.python` + `ms-python.vscode-pylance` | Microsoft |
| TypeScript | built in; add `dbaeumer.vscode-eslint` (ESLint team) | Microsoft |
| Dart / Flutter | `dart-code.dart-code`, `dart-code.flutter` | the Dart team |
| PHP | `bmewburn.vscode-intelephense-client` | Intelephense (the de-facto vendor server) |
| Ruby | `shopify.ruby-lsp` | Shopify (upstream `ruby-lsp`) |
| Docker | `docker.docker` | Docker Inc — supersedes `ms-azuretools.vscode-docker` |
| PowerShell | `ms-vscode.powershell` | Microsoft |
| YAML / XML | `redhat.vscode-yaml`, `redhat.vscode-xml` | Red Hat |
| Terraform | `hashicorp.terraform` | HashiCorp |
| Prisma | `prisma.prisma` | Prisma |
| Astro | `astro-build.astro-vscode` | the Astro team |
| Tailwind | `bradlc.vscode-tailwindcss` | Tailwind Labs |

The project's **own pinned formatter or linter** counts as first-party tooling too and outranks a
language extension's built-in formatter — point `editor.defaultFormatter` at it, so format-on-save
agrees with the commit gate instead of fighting it.

## The Open VSX catch

code-server installs from **Open VSX**, not the Microsoft marketplace, and the ids differ or the
extension is simply absent. The ones that bite:

| Marketplace | Open VSX |
|---|---|
| `ms-dotnettools.csharp` / `csdevkit` | `muhammad-sammy.csharp` — a repackage of the first-party extension, the closest thing Open VSX has; the Dev Kit is licensed to Microsoft products and is not available at all |
| `jetbrains.kotlin-server` | published — take it over `fwcd.kotlin` |
| `docker.docker` | published — take it over `ms-azuretools.vscode-docker` |
| `ms-vscode.cpptools` | not published — use `llvm-vs-code-extensions.vscode-clangd` |
| `ms-python.python` | published, but the pylance language server is not — use `ms-pyright.pyright` |
| `ms-vscode-remote.*` | not published, and not needed inside the container |

So `devbox/settings/extensions.txt` (Open VSX, for code-server) and
`.devcontainer/devcontainer.json`'s extension list (marketplace, for local VS Code) are **two
different lists**. Write both, and let each use its own correct ids.

Removing an id from the list does **not** uninstall it — the entrypoint only adds, so extensions a
person installed by hand in their own box survive a list change. Uninstall a dropped one with
`code-server --uninstall-extension <id>`.

The entrypoint tolerates a missing extension by design. After the first start, read the container
log and confirm the ones that matter installed — a silently skipped theme is why the editor came
up looking wrong.

## Comment the choices

Say in `extensions.txt` which repo file justifies each block, and say explicitly which of the
user's stacks you dropped and why. The next person to open that file should not have to re-derive
the filter, or wonder whether their favourite was forgotten or excluded.
