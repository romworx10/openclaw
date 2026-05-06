#!/usr/bin/env zsh
# Mac Mini access: load OPENCLAW_* from OPERATOR_MANNY_ENV_FILE, then ssh USER@HOST.
# Bash note: never `source` OPERATOR_MANNY_ENV_FILE — use scripts/shell/openclaw-mini-exec-from-env.sh instead.
#
# Bare `operator-manny`: transport remote-bootstrap script as base64 in `ssh -tt … bash -lc` (avoid PTY echo),
# then remote `exec bash --noprofile --norc -i`; cd + venv + purple PS1 inside operator-manny-remote-login.bash.
#
# Add to ~/.zshrc (path must match your clone):
#   source /Users/agent-os/client-agents/manny/openclaw/scripts/shell/operator-manny.zsh
#
# Local `openclaw … operator-manny` is handled by an `openclaw` wrapper defined below (runs on the Mini over SSH).
# Opt out: export ZSH_OPERATOR_MANNY_NO_OPENCLAW_WRAP=1, or legacy ZSH_OPERATOR_MANNY_OPENCLAW_WRAP=0, before sourcing.
# Source this file AFTER any other openclaw shell integration so `… operator-manny` is routed here.
#
# OPENCLAW_OPERATOR_MANNY_SSH_IP should look like: ssh USER@HOST_OR_IP

emulate -L zsh
[[ -z "${_OPENCLAW_OPERATOR_MANNY_SHELL_LOADED:-}" ]] || return 0
_OPENCLAW_OPERATOR_MANNY_SHELL_LOADED=1

: "${OPERATOR_MANNY_ENV_FILE:=${HOME}/client-agents/manny/.env}"

# Path to this file when sourced (${(%):-%x}); bundled remote login driver is alongside it.
_operator_manny_zsh="${${(%):-%x}:A}"
_operator_manny_remote_login="${_operator_manny_zsh:h}/operator-manny-remote-login.bash"

readonly _OPERATOR_MANNY_SSH_OPTS=( -o StrictHostKeyChecking=accept-new )

_operator_manny_remote_lc_resolve_rep_cd() {
  emulate -L zsh
  print -rn -- "$(<<'REMOTE'
REP="${OPENCLAW_OPERATOR_MANNY_REMOTE_REPO:-}"
if [[ -n "$REP" ]] && [[ ! -d "$REP" ]]; then echo >&2 "operator-manny: OPENCLAW_OPERATOR_MANNY_REMOTE_REPO is not a directory: $REP"; exit 127; fi
if [[ -z "$REP" ]]; then
  REP=""
  for _try in "$HOME/client-agents/manny/openclaw" "$HOME/Projects/openclaw" "$HOME/openclaw"; do
    [[ -f "$_try/package.json" ]] || continue
    REP="$_try"
    break
  done
fi
if [[ -z "$REP" ]]; then echo >&2 "operator-manny: set OPENCLAW_OPERATOR_MANNY_REMOTE_REPO on the Mini, or clone with package.json under ~/openclaw"; exit 127; fi
cd "$REP" || exit 127
if [[ ! -f "$REP/package.json" ]]; then
  if [[ -f "$REP/openclaw/package.json" ]]; then REP="$REP/openclaw"; else
    for _try in "$HOME/openclaw" "$HOME/client-agents/manny/openclaw" "$HOME/Projects/openclaw"; do
      [[ -f "$_try/package.json" ]] || continue
      REP="$_try"
      break
    done
  fi
fi
if [[ ! -f "$REP/package.json" ]]; then echo >&2 "operator-manny: no package.json — set OPENCLAW_OPERATOR_MANNY_REMOTE_REPO to the checkout root (where package.json lives)."; exit 127; fi
cd "$REP" || exit 127
REMOTE
)"
}

_operator_manny_load_dotenv() {
  if [[ ! -r "$OPERATOR_MANNY_ENV_FILE" ]]; then
    print -u2 "operator-manny.zsh: missing OPERATOR_MANNY_ENV_FILE=${OPERATOR_MANNY_ENV_FILE}"
    return 1
  fi
  emulate -L zsh
  setopt LOCAL_OPTIONS EXTENDED_GLOB
  local line key val
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line//$'\r'/}"
    [[ "$line" =~ '^[[:space:]]*$' ]] && continue
    [[ "$line" == \#* ]] && continue
    [[ "$line" != *"="* ]] && continue
    key="${line%%=*}"
    val="${line#*=}"
    key="${key##[[:space:]]##}"
    key="${key%%[[:space:]]##}"
    val="${val##[[:space:]]##}"
    val="${val%%[[:space:]]##}"
    [[ -z "$key" ]] && continue
    if [[ "$val" == \"*\" ]]; then
      val="${val[2,-2]}"
    elif [[ "$val" == \'*\' ]]; then
      val="${val[2,-2]}"
    fi
    export -- "$key=$val"
  done <"$OPERATOR_MANNY_ENV_FILE" || return 1
  return 0
}

# Print ssh destination: USER@HOST, or SSH config hostname `operator-manny` if unset.
_operator_manny_resolve_target() {
  emulate -L zsh
  local s="${OPENCLAW_OPERATOR_MANNY_SSH_IP:-}"
  [[ -z "$s" ]] && { print -r operator-manny; return 0 }
  if [[ "$s" =~ '^[[:space:]]*[sS][sS][hH][[:space:]]+(.+)' ]]; then
    s="$match[1]"
    s="${s## #}"
    s="${s%% #}"
    print -r -- "$s"
    return 0
  fi
  s="${s## #}"
  s="${s%% #}"
  print -r -- "$s"
}

_operator_manny_ssh_run() {
  emulate -L zsh
  local dst="$1"
  shift
  if [[ -n "${OPENCLAW_OPERATOR_MANNY_SSH_PW:-}" ]] && command -v sshpass >/dev/null 2>&1 && [[ "${OPENCLAW_OPERATOR_MANNY_USE_SSHPASS:-0}" == 1 ]]; then
    SSHPASS="$OPENCLAW_OPERATOR_MANNY_SSH_PW" sshpass -e ssh "${_OPERATOR_MANNY_SSH_OPTS[@]}" -o PreferredAuthentications=password -o PubkeyAuthentication=no "$dst" "$@"
  else
    ssh "${_OPERATOR_MANNY_SSH_OPTS[@]}" "$dst" "$@"
  fi
}

# Remote bootstrap: `ssh -tt` allocates a PTY; piping/here-string script bytes into `-s`
# feeds the PTY driver and the kernel echoes every line (looks like "the whole script printed").
# Instead: pass the script as a single-line base64 inside `bash -lc '…'` (no special chars in b64),
# decode on the Mini, then run `bash --noprofile --norc` from a pipe (no echo).

_operator_manny_ssh_bootstrap() {
  emulate -L zsh
  local dst="$1"
  local body="$2"
  local b64 remote_inner
  if command -v openssl >/dev/null 2>&1; then
    b64="$(builtin print -rn -- "$body" | openssl base64 -A)"
  else
    b64="$(builtin print -rn -- "$body" | command base64 | command tr -d '\n\r')"
  fi
  # b64 alphabet has no single quotes — safe inside '…' on the remote.
  # Prefer `base64` over `openssl`: LibreSSL/Mac `openssl base64 -d -A` is unreliable across versions.
  remote_inner="printf %s '${b64}' | (command base64 -d 2>/dev/null || command base64 --decode 2>/dev/null || command base64 -D 2>/dev/null || openssl base64 -d -A 2>/dev/null || openssl base64 -d 2>/dev/null) | bash --noprofile --norc"
  if [[ -n "${OPENCLAW_OPERATOR_MANNY_SSH_PW:-}" ]] && command -v sshpass >/dev/null 2>&1 && [[ "${OPENCLAW_OPERATOR_MANNY_USE_SSHPASS:-0}" == 1 ]]; then
    SSHPASS="$OPENCLAW_OPERATOR_MANNY_SSH_PW" sshpass -e ssh -q "${_OPERATOR_MANNY_SSH_OPTS[@]}" -o PreferredAuthentications=password -o PubkeyAuthentication=no -tt "$dst" bash --noprofile --norc -lc "$(builtin printf '%q' "$remote_inner")"
  else
    ssh -q "${_OPERATOR_MANNY_SSH_OPTS[@]}" -tt "$dst" bash --noprofile --norc -lc "$(builtin printf '%q' "$remote_inner")"
  fi
}

operator-manny() {
  emulate -L zsh
  _operator_manny_load_dotenv || return 1
  local dst
  dst=$(_operator_manny_resolve_target)
  # Extra remote command (e.g. `operator-manny uptime`) — passthrough SSH, no bootstrap.
  if (($#)); then
    _operator_manny_ssh_run "$dst" "$@"
    return
  fi
  if [[ ! -r "$_operator_manny_remote_login" ]]; then
    print -u2 "operator-manny: missing ${_operator_manny_remote_login}"
    return 1
  fi
  local prelude auto_build pull_build
  auto_build="${OPENCLAW_OPERATOR_MANNY_AUTO_BUILD:-1}"
  pull_build="${OPENCLAW_OPERATOR_MANNY_PULL_BUILD:-1}"
  prelude="export OPENCLAW_OPERATOR_MANNY_AUTO_BUILD=$(builtin printf '%q' "$auto_build")"$'\n'
  prelude+="export OPENCLAW_OPERATOR_MANNY_PULL_BUILD=$(builtin printf '%q' "$pull_build")"$'\n'
  [[ -n "${OPENCLAW_OPERATOR_MANNY_REMOTE_REPO:-}" ]] && prelude+="export OPENCLAW_OPERATOR_MANNY_REMOTE_REPO=$(builtin printf '%q' "$OPENCLAW_OPERATOR_MANNY_REMOTE_REPO")"$'\n'
  [[ -n "${OPENCLAW_OPERATOR_MANNY_VENV_REL:-}" ]] && prelude+="export OPENCLAW_OPERATOR_MANNY_VENV_REL=$(builtin printf '%q' "$OPENCLAW_OPERATOR_MANNY_VENV_REL")"$'\n'

  local body
  body="${prelude}$(<"$_operator_manny_remote_login")"

  _operator_manny_ssh_bootstrap "$dst" "$body"

}

pull-operator-manny() {
  emulate -L zsh
  _operator_manny_load_dotenv || return 1
  local dst branch qb inner
  dst=$(_operator_manny_resolve_target)
  branch="${OPENCLAW_OPERATOR_MANNY_GIT_BRANCH:-main}"
  qb=$(builtin printf '%q' "$branch")
  inner="$(_operator_manny_remote_lc_resolve_rep_cd)"
  inner+="; git fetch origin && git pull --ff-only origin ${qb} && git submodule update --init --recursive"
  inner+="; if [[ \"\${OPENCLAW_OPERATOR_MANNY_PULL_BUILD:-1}\" != \"0\" ]] && [[ ! -f \"\$REP/dist/entry.mjs\" ]] && [[ ! -f \"\$REP/dist/entry.js\" ]]; then if command -v pnpm >/dev/null 2>&1; then (cd \"\$REP\" && pnpm install && pnpm build); elif command -v npm >/dev/null 2>&1; then (cd \"\$REP\" && npm install && npm run build); fi; fi"
  _operator_manny_ssh_run "$dst" -t bash -lc "$inner"
}

if [[ "${ZSH_OPERATOR_MANNY_NO_OPENCLAW_WRAP:-}" == 1 || "${ZSH_OPERATOR_MANNY_OPENCLAW_WRAP:-}" == "0" ]]; then
  :
else
  openclaw() {
    emulate -L zsh
    if (($# >= 2)) && [[ "${argv[-1]}" == operator-manny ]]; then
      _operator_manny_load_dotenv || return 1
      local dst fwd_q inner abq
      dst=$(_operator_manny_resolve_target)
      local -a fwd=( "${(@)argv[1,-2]}" )
      fwd_q=$(builtin printf '%q ' "${fwd[@]}")
      abq=$(builtin printf '%q' "${OPENCLAW_OPERATOR_MANNY_AUTO_BUILD:-1}")
      inner="$(_operator_manny_remote_lc_resolve_rep_cd)"
      inner+="; export OPENCLAW_OPERATOR_MANNY_AUTO_BUILD=${abq}; export PATH=\"\$REP/node_modules/.bin:/opt/homebrew/bin:/usr/local/bin:\$HOME/.local/bin:\$HOME/Library/pnpm:\$HOME/.npm-global/bin:\$HOME/bin:\$PATH\""
      inner+="; if [[ \"\${OPENCLAW_OPERATOR_MANNY_AUTO_BUILD:-1}\" != \"0\" ]] && [[ ! -f \"\$REP/dist/entry.mjs\" ]] && [[ ! -f \"\$REP/dist/entry.js\" ]]; then if command -v pnpm >/dev/null 2>&1; then (cd \"\$REP\" && pnpm install && pnpm build); elif command -v npm >/dev/null 2>&1; then (cd \"\$REP\" && npm install && npm run build); fi; fi"
      inner+="; exec command openclaw ${fwd_q}"
      _operator_manny_ssh_run "$dst" -t bash -lc "$inner"
      return $?
    fi
    command openclaw "$@"
  }
fi
