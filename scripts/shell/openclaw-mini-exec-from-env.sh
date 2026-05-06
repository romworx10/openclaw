#!/usr/bin/env bash
#
# Run a shell command on the OpenClaw Mac Mini using OPERATOR_MANNY_ENV_FILE.
# Parses KEY=value safely (never `source`): values may contain spaces (e.g.
# OPENCLAW_OPERATOR_MANNY_SSH_IP=ssh user@100.x.x.x).
#
# Auth: pubkey ssh when possible; if OPENCLAW_OPERATOR_MANNY_USE_SSHPASS=1,
# sshpass is installed, and OPENCLAW_OPERATOR_MANNY_SSH_PW is set in the env
# file, uses password SSH (automations only — prefer SSH keys).
#
# Usage:
#   bash scripts/shell/openclaw-mini-exec-from-env.sh 'cd ~/openclaw && git status -sb'
#
# No credentials in git; keep OPERATOR_MANNY_ENV_FILE chmod 600. Do not `source` that file in
# bash: unquoted OPENCLAW_OPERATOR_MANNY_SSH_IP=ssh user@host breaks; this script parses lines.

set -euo pipefail

die() {
  printf '%s\n' "$1" >&2
  exit 1
}

OPERATOR_MANNY_ENV_FILE="${OPERATOR_MANNY_ENV_FILE:-${HOME}/client-agents/manny/.env}"
[[ -r "$OPERATOR_MANNY_ENV_FILE" ]] || die "Cannot read OPERATOR_MANNY_ENV_FILE=${OPERATOR_MANNY_ENV_FILE}"

operator_manny_load_kv_file() {
  local line key val
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line//$'\r'/}"
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" != *"="* ]] && continue
    key="${line%%=*}"
    val="${line#*=}"
    key="${key#"${key%%[![:space:]]*}"}"
    key="${key%"${key##*[![:space:]]}"}"
    val="${val#"${val%%[![:space:]]*}"}"
    val="${val%"${val##*[![:space:]]}"}"
    [[ -z "$key" ]] && continue
    if [[ "$val" == \"*\" ]]; then
      val="${val:1:${#val}-2}"
    elif [[ "$val" == \'*\' ]]; then
      val="${val:1:${#val}-2}"
    fi
    export -- "$key=$val"
  done <"$OPERATOR_MANNY_ENV_FILE"
}

resolve_ssh_target_from_ip_var() {
  local s="${OPENCLAW_OPERATOR_MANNY_SSH_IP:-}"
  [[ -z "$s" ]] && die "OPENCLAW_OPERATOR_MANNY_SSH_IP missing in ${OPERATOR_MANNY_ENV_FILE}"
  if [[ "$s" =~ ^[[:space:]]*[sS][sS][hH][[:space:]]+(.+)$ ]]; then
    s="${BASH_REMATCH[1]}"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
  fi
  [[ -n "$s" ]] || die "Could not parse OPENCLAW_OPERATOR_MANNY_SSH_IP"
  printf '%s' "$s"
}

SSH_BASE_OPTS=( -o StrictHostKeyChecking=accept-new )

operator_manny_load_kv_file
TGT="$(resolve_ssh_target_from_ip_var)"
REMOTE_SHELL="${*:-"uname -sr; pwd"}"
REMOTE_Q="$(printf '%q' "$REMOTE_SHELL")"

if [[ "${OPENCLAW_OPERATOR_MANNY_USE_SSHPASS:-0}" == "1" ]] &&
  command -v sshpass >/dev/null 2>&1 &&
  [[ -n "${OPENCLAW_OPERATOR_MANNY_SSH_PW:-}" ]]; then
  SSHPASS="${OPENCLAW_OPERATOR_MANNY_SSH_PW}" sshpass -e \
    ssh "${SSH_BASE_OPTS[@]}" \
    -o PreferredAuthentications=password \
    -o PubkeyAuthentication=no \
    "$TGT" \
    bash -lc "$REMOTE_Q"
else
  ssh "${SSH_BASE_OPTS[@]}" "$TGT" bash -lc "$REMOTE_Q"
fi
