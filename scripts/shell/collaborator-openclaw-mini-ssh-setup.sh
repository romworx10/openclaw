#!/usr/bin/env bash
#
# Collaborator SSH helper for the OpenClaw Mac Mini. Menu: generate keypair, or SSH in.
#
# New keys: export OPENCLAW_COLLAB_TEAM_SSH_PASSPHRASE (admin only; never committed or printed here).
#
# Mac Mini admin: run scripts/shell/openclaw-mini-admin-init-authorized-keys.sh on the mini,
# then append each collaborator's single-line pubkey to ~/.ssh/authorized_keys.
#
# Optional: OPENCLAW_COLLAB_SSH_ALIAS=myhost fills user@host from ~/.ssh/config (ssh -G).

set -u

bold() { printf '\033[1m%s\033[0m' "$1"; }
dim() { printf '\033[2m%s\033[0m' "$1"; }

die() {
  printf '%s\n' "$1" >&2
  exit 1
}

is_yes() {
  local v
  v=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  [[ "$v" == "y" || "$v" == "yes" ]]
}

team_ssh_passphrase() {
  [[ -n "${OPENCLAW_COLLAB_TEAM_SSH_PASSPHRASE:-}" ]] || die "For new keys: export OPENCLAW_COLLAB_TEAM_SSH_PASSPHRASE (admin supplies value; not stored in git)."
  printf '%s' "${OPENCLAW_COLLAB_TEAM_SSH_PASSPHRASE}"
}

prompt() {
  local label="$1"
  local _def="$2"
  local _s
  read -r -p "${label} — default: ${_def} (press Enter): " _s || true
  if [[ -z "$_s" ]]; then
    printf '%s' "$_def"
  else
    printf '%s' "$_s"
  fi
}

# Read until non-empty (no fake hostname default possible).
prompt_required() {
  local label="$1"
  local s
  while true; do
    read -r -p "${label}: " s || true
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    if [[ -n "$s" ]]; then
      printf '%s' "$s"
      return 0
    fi
    printf '%s\n' "$(dim "Required—ask your admin for the Mac Mini user, IP, or Tailscale hostname.")" >&2
  done
}

normalize_dest() {
  local _raw="$1"
  _raw="${_raw#"${_raw%%[![:space:]]*}"}"
  _raw="${_raw%"${_raw##*[![:space:]]}"}"
  if [[ "$_raw" =~ ^[[:space:]]*[sS][sS][hH][[:space:]]+(.+)$ ]]; then
    _raw="${BASH_REMATCH[1]}"
    _raw="${_raw#"${_raw%%[![:space:]]*}"}"
    _raw="${_raw%"${_raw##*[![:space:]]}"}"
  fi
  printf '%s' "$_raw"
}

# Reject template hostnames that look like docs, not real addresses.
host_is_placeholder() {
  local h lc
  h="${1:-}"
  [[ -z "$h" ]] && return 0
  lc=$(printf '%s' "$h" | tr '[:upper:]' '[:lower:]')
  case "$lc" in
  *replace*host* | *replace_with* | *placeholder* | *your_host* | *changeme* | *example.invalid*) return 0 ;;
  esac
  return 1
}

copy_pubkey_hint() {
  local pub="$1"
  if command -v pbcopy >/dev/null 2>&1; then
    pbcopy <"$pub" && printf '%s\n' "$(bold "OK") — public key copied to clipboard."
    return 0
  fi
  if command -v xclip >/dev/null 2>&1; then
    xclip -selection clipboard <"$pub" && printf '%s\n' "$(bold "OK") — public key copied to clipboard."
    return 0
  fi
  if command -v wl-copy >/dev/null 2>&1; then
    wl-copy <"$pub" && printf '%s\n' "$(bold "OK") — public key copied to clipboard."
    return 0
  fi
  printf '%s\n' "$(dim "Copy the public key line above manually.")"
}

local_username_hint() {
  printf '%s' "${USER:-${LOGNAME:-user}}"
}

short_hostname_label() {
  local hn
  hn="$(hostname -s 2>/dev/null || hostname 2>/dev/null || printf '%s' localhost)"
  hn="${hn%%.*}"
  printf '%s' "$hn"
}

detect_default_ssh_private_key_path() {
  local base="${HOME}/.ssh"
  if [[ -f "${base}/id_ed25519_openclaw_mac_mini" ]]; then
    printf '%s/id_ed25519_openclaw_mac_mini' "$base"
    return 0
  fi
  if [[ -f "${base}/id_ed25519" ]]; then
    printf '%s/id_ed25519' "$base"
    return 0
  fi
  if [[ ! -e "${base}/id_ed25519" && ! -e "${base}/id_ed25519.pub" ]]; then
    printf '%s/id_ed25519' "$base"
  else
    printf '%s/id_ed25519_openclaw_mac_mini' "$base"
  fi
}

default_key_comment() {
  printf 'openclaw-mac-mini-%s@%s' "$(local_username_hint)" "$(short_hostname_label)"
}

# Sets DEFAULT_SSH_DEST when ssh -G succeeds.
try_apply_ssh_config_alias_defaults() {
  local al g u h
  DEFAULT_SSH_DEST=""
  al="${OPENCLAW_COLLAB_SSH_ALIAS:-${COLLAB_SSH_ALIAS:-}}"
  [[ -z "$al" ]] && return 0
  [[ -r "${HOME}/.ssh/config" ]] || return 0
  g="$(ssh -G "${al}" 2>/dev/null)" || return 0
  u="$(printf '%s\n' "$g" | awk '/^user /{print $2; exit}')"
  h="$(printf '%s\n' "$g" | awk '/^hostname /{print $2; exit}')"
  [[ -n "$u" && -n "$h" ]] || return 0
  DEFAULT_SSH_DEST="${u}@${h}"
  printf '%s\n' "$(dim "Using ~/.ssh/config Host ${al} → ${DEFAULT_SSH_DEST}")"
}

prompt_for_key_path_expand() {
  local DEFAULT_KEY="$1"
  KEY_PATH="$(prompt "Private key path" "${DEFAULT_KEY}")"
  KEY_PATH="${KEY_PATH/#\~/${HOME}}"
  if [[ "$KEY_PATH" != /* ]]; then
    die "Path must be absolute or start with ~ — got: ${KEY_PATH}"
  fi
  PUB_PATH="${KEY_PATH}.pub"
}

# Sets globals R_USER, R_HOST after validation.
prompt_for_ssh_destination() {
  try_apply_ssh_config_alias_defaults

  local RAW_DEST DEST
  if [[ -n "${DEFAULT_SSH_DEST:-}" ]]; then
    RAW_DEST="$(prompt "Mac Mini SSH target (user@host or hostname only—from admin)" "${DEFAULT_SSH_DEST}")"
  else
    RAW_DEST="$(prompt_required "Mac Mini SSH target (user@host or hostname only—from admin)")"
  fi

  DEST="$(normalize_dest "$RAW_DEST")"
  if [[ "$DEST" != *@* ]]; then
    R_USER="$(prompt "Username on Mac Mini (for hostname above)" "$(local_username_hint)")"
    R_USER="${R_USER#"${R_USER%%[![:space:]]*}"}"
    R_USER="${R_USER%"${R_USER##*[![:space:]]}"}"
    R_HOST="$DEST"
  else
    R_USER="${DEST%%@*}"
    R_HOST="${DEST#*@}"
  fi
  R_USER="${R_USER#"${R_USER%%[![:space:]]*}"}"
  R_USER="${R_USER%"${R_USER##*[![:space:]]}"}"
  R_HOST="${R_HOST#"${R_HOST%%[![:space:]]*}"}"
  R_HOST="${R_HOST%"${R_HOST##*[![:space:]]}"}"

  if [[ -z "$R_USER" || -z "$R_HOST" ]]; then
    die "Need both user and host (example: alice@100.x.x.x or hostname + username prompt)."
  fi
  if host_is_placeholder "$R_HOST"; then
    die "That hostname looks like a template, not the real Mini (use the IP or Tailscale name from your admin)."
  fi
}

ssh_command_human() {
  printf 'ssh -tt -i %q -o StrictHostKeyChecking=accept-new -o IdentitiesOnly=yes -o IdentityAgent=none -o AddKeysToAgent=no %q@%q' \
    "${KEY_PATH}" "${R_USER}" "${R_HOST}"
}

run_ssh_to_mini() {
  printf '%s\n' "$(ssh_command_human)"
  exec ssh -tt \
    -i "${KEY_PATH}" \
    -o StrictHostKeyChecking=accept-new \
    -o IdentitiesOnly=yes \
    -o IdentityAgent=none \
    -o AddKeysToAgent=no \
    "${R_USER}@${R_HOST}"
}

do_connect_or_exit() {
  local yn
  yn="$(prompt "Run SSH now?" "y")"
  if is_yes "$yn"; then
    run_ssh_to_mini
    exit $?
  fi
}

path_do_generate_keypair() {
  local yn COMMENT PW

  SSH_DIR="${HOME}/.ssh"
  mkdir -p "$SSH_DIR"
  chmod 700 "$SSH_DIR" || true

  printf '\n%s\n' "$(bold "1 · Keypair")"

  prompt_for_key_path_expand "$(detect_default_ssh_private_key_path)"

  if [[ -f "$KEY_PATH" ]]; then
    yn="$(prompt "Use existing key at ${KEY_PATH}?" "y")"
    if ! is_yes "$yn"; then
      die "Choose another path or delete the key and re-run."
    fi
    [[ -f "$PUB_PATH" ]] || die "Missing ${PUB_PATH}"
  else
    COMMENT="$(prompt "Key comment (public line)" "$(default_key_comment)")"
    PW="$(team_ssh_passphrase)"
    [[ -n "$PW" ]] || die "Internal passphrase empty."
    ssh-keygen -t ed25519 -f "$KEY_PATH" -C "${COMMENT}" -N "${PW}" || die "ssh-keygen failed."
    chmod 600 "$KEY_PATH" || true
    [[ -f "$PUB_PATH" ]] || die "Missing ${PUB_PATH}"
  fi

  printf '\n%s\n' "$(bold "2 · Send this one line to the admin")"
  printf '%s\n' "$(dim "They append it to the Mac Mini account ~/.ssh/authorized_keys (see openclaw-mini-admin-init-authorized-keys.sh).")"
  printf '\n'
  cat "${PUB_PATH}"
  printf '\n'
  copy_pubkey_hint "${PUB_PATH}"

  printf '\n%s\n' "$(bold "3 · After admin adds your key")"
  read -r -p "$(dim 'Press Enter when that is done…') " _

  printf '\n%s\n' "$(bold "4 · Connect")"
  prompt_for_ssh_destination
  do_connect_or_exit
}

path_do_ssh_login() {
  SSH_DIR="${HOME}/.ssh"
  mkdir -p "$SSH_DIR"
  chmod 700 "$SSH_DIR" || true

  printf '\n%s\n' "$(bold "SSH to Mac Mini")"

  prompt_for_key_path_expand "$(detect_default_ssh_private_key_path)"

  if [[ ! -f "$KEY_PATH" ]]; then
    die "No private key at ${KEY_PATH}. Run menu 1 first, or pick another path that exists."
  fi
  if [[ ! -f "$PUB_PATH" ]]; then
    die "No ${PUB_PATH}. Run menu 1 first."
  fi

  prompt_for_ssh_destination
  do_connect_or_exit
}

umask 077
clear 2>/dev/null || true

printf '\n'
bold "OpenClaw Mac Mini — collaborator SSH"
printf '\n'

if ! command -v ssh-keygen >/dev/null 2>&1; then
  die "Need ssh-keygen."
fi
if ! command -v ssh >/dev/null 2>&1; then
  die "Need ssh."
fi

printf '%s\n' "$(dim "Account on this machine: $(local_username_hint); home: ${HOME}")"
printf '%s\n' "$(bold "Choose")"; printf '%s\n' \
  "  1) Create or reuse keypair, then connect" \
  "  2) SSH only (key must already exist on this machine and on the Mini)" \
  "  3) Exit"

menu="$(prompt "1 / 2 / 3" "1")"
menu="$(printf '%s' "${menu}" | tr -cd '123')"
[[ -z "$menu" ]] && menu=1

case "${menu}" in
1) path_do_generate_keypair ;;
2) path_do_ssh_login ;;
3)
  printf '%s\n' "Bye."
  exit 0
  ;;
*)
  printf '%s\n' "Bye."
  exit 0
  ;;
esac

printf '%s\n' "Done."
