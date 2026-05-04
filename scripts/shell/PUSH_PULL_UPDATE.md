# Push / pull update — 2026-05-04 (UTC anchor: operator-manny tooling)

What shipped in this repo change:

1. **`.gitignore`** — ignore **`.cursor/`** so Cursor rules, workspace memory, and similar stay local-only and are not bundled in this clone.

2. **`scripts/shell/operator-manny.zsh`** and **`scripts/shell/operator-manny-remote-login.bash`** — Mac Mini SSH helpers: quiet bootstrap (`ssh -q`, base64 `bash -lc`), PATH for Node/`openclaw`, repo root detection via **`package.json`** (fixes `OPENCLAW_OPERATOR_MANNY_REMOTE_REPO` pointing at `$HOME`), optional **`pnpm install && pnpm build`** when **`dist/entry.*` is missing**, purple prompt / bash 3.2 flag order fix, **`openclaw … operator-manny`** wrapper by default (**opt-out** `ZSH_OPERATOR_MANNY_NO_OPENCLAW_WRAP=1`), **`pull-operator-manny`** optional post-pull build.

3. **`operator-manny` device (`pull-operator-manny`)** — after **push**, run **`source /path/to/…/scripts/shell/operator-manny.zsh`** from this Mac then **`pull-operator-manny`**, **or** on the Mini **`cd`** to `OPENCLAW_OPERATOR_MANNY_REMOTE_REPO`/`~/openclaw` and **`git pull`**.

**Commit author:** this commit used a **noreply GitHub-form** identity for tooling (see **`git log -1`**). Use your normal identity for subsequent commits if preferred.
