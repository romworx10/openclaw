#!/usr/bin/env bash
# Run ON the Mini: local ssh decodes bootstrap (operator-manny.zsh); this script cd's, activates venv,
# then `exec bash --noprofile --norc -i` on `/dev/tty` (no macOS login-rc noise, keeps purple PS1).
#
# Repo / venv: OPENCLAW_OPERATOR_MANNY_* (optional).

set -euo pipefail

# Quiet macOS system bash deprecation banner ("default interactive shell is now zsh…").
export BASH_SILENCE_DEPRECATION_WARNING=1

# Resolve clone root (must be the directory containing openclaw's package.json).
if [[ -n "${OPENCLAW_OPERATOR_MANNY_REMOTE_REPO:-}" ]]; then
  REP="$OPENCLAW_OPERATOR_MANNY_REMOTE_REPO"
  if [[ ! -d "$REP" ]]; then
    echo >&2 "operator-manny: OPENCLAW_OPERATOR_MANNY_REMOTE_REPO is not a directory: $REP"
    echo >&2 "Fix the path in your LOCAL OPERATOR_MANNY_ENV_FILE." >&2
    exit 127
  fi
else
  REP=""
  for _try in "$HOME/client-agents/manny/openclaw" "$HOME/Projects/openclaw" "$HOME/openclaw"; do
    [[ -f "$_try/package.json" ]] || continue
    REP="$_try"
    break
  done
  if [[ -z "$REP" ]]; then
    echo >&2 "operator-manny: no clone found (needs package.json). Tried:"
    echo >&2 "  $HOME/client-agents/manny/openclaw"
    echo >&2 "  $HOME/Projects/openclaw"
    echo >&2 "  $HOME/openclaw"
    echo >&2 "Set OPENCLAW_OPERATOR_MANNY_REMOTE_REPO=/exact/openclaw on the Mini (repo root)." >&2
    exit 127
  fi
fi

cd "$REP" || {
  echo >&2 "operator-manny: cannot cd to $REP"
  exit 127
}

# Common mis-set: HOME or operator home instead of the openclaw checkout root — fix without ignoring an explicit unrelated path.
_operator_manny_require_openclaw_package_json() {
  if [[ -f "$REP/package.json" ]]; then
    return 0
  fi
  if [[ -f "$REP/openclaw/package.json" ]]; then
    REP="$REP/openclaw"
    return 0
  fi
  # Last resort: typical Mini layout when REMOTE_REPO points at HOME/parent dir by mistake.
  for _try in "$HOME/openclaw" "$HOME/client-agents/manny/openclaw" "$HOME/Projects/openclaw"; do
    [[ -f "$_try/package.json" ]] || continue
    REP="$_try"
    return 0
  done
  echo >&2 "operator-manny: no package.json under $REP (nor openclaw/ subdir or ~/openclaw). Set OPENCLAW_OPERATOR_MANNY_REMOTE_REPO to the checkout root (directory that contains package.json)." >&2
  exit 127
}
_operator_manny_require_openclaw_package_json
cd "$REP" || {
  echo >&2 "operator-manny: cannot cd to $REP"
  exit 127
}

# `--noprofile --norc` skips macOS login path setup (homebrew/nvm-ish paths). `openclaw` is a Node
# CLI (package.bin → openclaw.mjs); expose common locations + repo-local npm bin first.
PATH="${REP}/node_modules/.bin:/opt/homebrew/bin:/usr/local/bin:${HOME}/.local/bin:${HOME}/Library/pnpm:${HOME}/.npm-global/bin:${HOME}/bin${PATH:+:$PATH}"
export PATH

# Bare git clone lacks dist/entry.* until `pnpm install && pnpm build`. Opt out: OPENCLAW_OPERATOR_MANNY_AUTO_BUILD=0 in OPERATOR_MANNY_ENV_FILE / prelude.
_operator_manny_has_entry_files() {
  [[ -f "$REP/dist/entry.mjs" || -f "$REP/dist/entry.js" ]]
}
if ! _operator_manny_has_entry_files && [[ "${OPENCLAW_OPERATOR_MANNY_AUTO_BUILD:-1}" != "0" ]]; then
  if command -v pnpm >/dev/null 2>&1; then
    echo >&2 "operator-manny: missing dist/entry.* — running pnpm install && pnpm build in $REP …"
    (cd "$REP" && pnpm install && pnpm build) || echo >&2 "operator-manny: pnpm build failed (non-fatal)."
  elif command -v npm >/dev/null 2>&1; then
    echo >&2 "operator-manny: missing dist/entry.* — running npm install && npm run build in $REP …"
    (cd "$REP" && npm install && npm run build) || echo >&2 "operator-manny: npm build failed (non-fatal)."
  else
    echo >&2 "operator-manny: missing dist/entry.*; install p/npm on this host or build once: cd $REP && pnpm install && pnpm build"
  fi
fi

VREL="${OPENCLAW_OPERATOR_MANNY_VENV_REL:-venv}"
if [[ -f "$REP/$VREL/bin/activate" ]]; then
  export VIRTUAL_ENV_DISABLE_PROMPT=1
  # shellcheck disable=SC1091
  source "$REP/$VREL/bin/activate"
elif [[ -f "$REP/$VREL/Scripts/activate" ]]; then
  export VIRTUAL_ENV_DISABLE_PROMPT=1
  source "$REP/$VREL/Scripts/activate"
fi

_om_repo_base="$(basename "$REP")"
export _om_repo_base

_omanny_set_ps1() {
  local vn
  if [[ -n "${VIRTUAL_ENV:-}" ]]; then
    vn="${VIRTUAL_ENV##*/}"
  else
    vn="${_om_repo_base}"
  fi
  PS1="(\[\033[35m\]${vn}\[\033[0m\]) \u@\h:\w\$ "
}
export -f _omanny_set_ps1
export PROMPT_COMMAND="_omanny_set_ps1${PROMPT_COMMAND:+;$PROMPT_COMMAND}"

# Interactive shell only: skip login + rc so macOS `/etc/profile` + `.bash_profile` can't
# clobber PROMPT_COMMAND or re-print the zsh migration notice. PATH/VIRTUAL_ENV already exported.
# Bash 3.2 (system macOS) rejects `-i` before `--noprofile`/`--norc` ("bash: --: invalid option").
exec bash --noprofile --norc -i </dev/tty >/dev/tty 2>/dev/tty
