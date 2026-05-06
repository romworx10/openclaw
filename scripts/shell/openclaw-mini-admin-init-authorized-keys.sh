#!/usr/bin/env bash
#
# Run on the OpenClaw Mac Mini (Remote Login account the collaborators use, e.g. operator).
# Creates ~/.ssh with correct permissions and an empty authorized_keys file ready for lines.
#
# Usage on the mini:
#   bash openclaw-mini-admin-init-authorized-keys.sh
#   bash openclaw-mini-admin-init-authorized-keys.sh /Users/operator
#
# Add a collaborator (paste one line: ssh-ed25519 AAA... comment):
#   cat >> ~/.ssh/authorized_keys
#   # or:  printf '%s\n' 'ssh-ed25519 AAA... comment' >> ~/.ssh/authorized_keys
#
# See scripts/shell/openclaw-mac-mini-ssh-stable.md for a stable ssh Host (Tailscale MagicDNS).
#   bash openclaw-mini-admin-init-authorized-keys.sh --append /path/to/collaborator.pub

set -euo pipefail

die() {
  printf '%s\n' "$1" >&2
  exit 1
}

mode_init=1
append_file=""

if [[ "${1:-}" == "--append" ]]; then
  mode_init=0
  [[ -n "${2:-}" ]] || die "Usage: $0 --append /path/to/key.pub"
  append_file="$2"
  [[ -f "$append_file" ]] || die "Not a file: $append_file"
fi

if [[ "$mode_init" == 1 ]]; then
  target_home="${1:-$HOME}"
  [[ -d "$target_home" ]] || die "Not a directory: $target_home"
  ssh_dir="${target_home}/.ssh"
  mkdir -p "$ssh_dir"
  chmod 700 "$ssh_dir"
  auth="${ssh_dir}/authorized_keys"
  if [[ ! -f "$auth" ]]; then
    (umask 077 && : >"$auth")
  fi
  chmod 600 "$auth" || true
  printf '%s\n' "OK — ${ssh_dir} is mode 700, ${auth} is mode 600."
  printf '%s\n' "Paste one public-key line per collaborator into ${auth}, or:"
  printf '%s\n' "  bash $0 --append /path/to/someone.pub"
  exit 0
fi

ssh_dir="${HOME}/.ssh"
auth="${ssh_dir}/authorized_keys"
mkdir -p "$ssh_dir"
chmod 700 "$ssh_dir"
if [[ ! -f "$auth" ]]; then
  (umask 077 && : >"$auth")
fi
chmod 600 "$auth"
line="$(tr -d '\r' <"$append_file" | head -n 1)"
[[ -n "$line" ]] || die "Empty or unreadable public key line in $append_file"
if grep -Fxq "$line" "$auth" 2>/dev/null; then
  printf '%s\n' "That exact line is already in ${auth}; no change."
  exit 0
fi
printf '%s\n' "$line" >>"$auth"
chmod 600 "$auth"
printf '%s\n' "Appended one line from $append_file to $auth"
