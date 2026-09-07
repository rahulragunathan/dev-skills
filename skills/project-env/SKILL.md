---
name: project-env
description: Create or repair a project's Python or Node environment when it must not live inside a cloud-synced folder — the `~/Python-Envs` / `~/Node-Envs` layout, the `standardize-*-envs.sh` scripts, dependency files, and the commands that run without a permission prompt. Use when setting up a new repo, migrating a real `.venv` or `node_modules` out of Drive, or repairing a symlink a bare `npm install` replaced.
license: MIT
---

# project-env

**No virtualenv and no `node_modules` ever lives inside Drive.** Thousands of small files in a
synced folder produce constant sync churn and conflicted copies. The real tree lives outside
Drive and the project holds a symlink to it.

| | Real tree | In the project |
| --- | --- | --- |
| Python | `~/Python-Envs/<name>` | `.venv` → symlink |
| Node | `~/Node-Envs/<name>` | `node_modules` → symlink |

**One name for both.** The env name is the project path relative to the machine's code root,
flattened with `_`: `Code/Skills/drawio` → `Skills_drawio`, `Clients/ClientX/Code/api` →
`ClientX_Code_api`. Same-named repos never collide, and a repo with both languages gets
`~/Python-Envs/<name>` and `~/Node-Envs/<name>`.

The code root is `…/My Drive/Code` on one machine and `…/My Drive/Clients` on the other, which
is also where the two scripts live.

## Python

**New repo — run the script, don't hand-roll the env.**

```bash
standardize-python-envs.sh new [PROJECT_DIR] [ENV_ROOT]
```

It builds the env, links `.venv`, and gitignores it. `PROJECT_DIR` defaults to the current
directory, `ENV_ROOT` to `~/Python-Envs`, and the Python version to `PYVER` (3.13 by default).

**Use uv. Never conda, and never a plain `python3 -m venv .venv`** — that puts a real
directory in Drive, which is the thing this skill exists to prevent.

**Existing repo with a real `.venv` directory** gets migrated by the same script:

```bash
standardize-python-envs.sh check    # inventory first
standardize-python-envs.sh envs     # move and rebuild
```

`new` refuses that case on purpose, so an accidental re-run cannot clobber an env in place.

**Dependencies:** runtime in `requirements.txt`, dev (pytest, ruff/black, …) in
`requirements-dev.txt`.

```bash
uv pip install --python .venv/bin/python -r requirements.txt
```

**uv is the standalone build at `~/.local/bin/uv`, not the Homebrew one**, so `brew upgrade`
cannot break an env.

**Run tools through the relative venv path**, from the project root:

```bash
.venv/bin/python -m pytest
.venv/bin/ruff
.venv/bin/black
```

The permission allowlist matches those exact prefixes. **An absolute venv path does not match
and will prompt.**

## Node

**New repo:**

```bash
standardize-node-envs.sh new [PROJECT_DIR] [ENV_ROOT]
```

It builds the env, installs from the manifests, links `node_modules`, and gitignores it.
`ENV_ROOT` defaults to `~/Node-Envs`, overridable with `NODEENVROOT`.

**Existing repo with a real `node_modules`:** `check` to inventory, then `envs` to relocate and
rebuild. `new` refuses that case, same as Python.

**Install deps with the script, never a bare `npm install`:**

```bash
standardize-node-envs.sh install . -- --save-dev vitest   # everything after -- goes to npm
```

**npm cannot be pointed at the symlink the way uv can.** It always materializes a real
`node_modules` in its working directory and deletes whatever is in the way first — even on a
no-op install, even when the symlink is already fully populated. So the install runs in the env
dir, which holds a copy of the manifests plus the real tree, and the project only ever holds
the link.

A bare `npm install` still succeeds, but it replaces the symlink with a real directory on
Drive. Repair it with:

```bash
standardize-node-envs.sh relink
```

`package.json` and `package-lock.json` stay authoritative in the repo. The script copies them
into the env dir before installing and back afterwards, writing back only when they actually
changed.

**The `.gitignore` entry must be `node_modules`, with no trailing slash.** `node_modules/` is a
directory-only pattern and does not match a symlink, so git reports the link as untracked
forever.

**Run tests and tools from the project root as normal:**

```bash
npm test
npx vitest
```

Resolution goes through the symlink, so nothing else changes. Those two prefixes are
allow-listed. **`npm run <script>` deliberately is not** — it executes whatever the
`package.json` defines, so it stays a conscious approval.
