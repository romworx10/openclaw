# Stable SSH to the OpenClaw Mac Mini

LAN IPs such as `192.168.1.196` change when the mini moves networks. Use a **hostname that follows the machine**, not the subnet.

## Recommended: Tailscale MagicDNS

With Tailscale installed on the Mini and your laptop, enable **MagicDNS** in the Tailscale admin console. Each device gets a name like **`your-mini.tail1234.ts.net`** that resolves wherever Tailscale runs.

Add to **`~/.ssh/config`** (adjust `HostName`, user, and key path):

```sshconfig
Host openclaw-mac-mini
  HostName your-mini.tail1234.ts.net
  User operator
  IdentityFile ~/.ssh/id_ed25519_openclaw_mac_mini
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
```

Then always:

```bash
ssh openclaw-mac-mini
```

**`IdentitiesOnly yes`** avoids “Too many authentication failures” when your agent has many keys.

## Optional: LAN-only alias (IP can still change)

```sshconfig
Host openclaw-mac-mini-lan
  HostName 192.168.1.196
  User operator
  IdentityFile ~/.ssh/id_ed25519_openclaw_mac_mini
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
```

## Pull repo and run admin SSH setup on the Mini

From your machine (interactive session so passphrases work), after `Host` is configured or using the raw IP:

```bash
ssh operator@192.168.1.196 'set -e; for d in "$HOME/client-agents/manny/openclaw" "$HOME/Projects/openclaw" "$HOME/openclaw"; do [[ -f "$d/.git/config" ]] && cd "$d" && break; done; pwd; git pull --rebase; bash scripts/shell/openclaw-mini-admin-init-authorized-keys.sh'
```

Or with a stable host:

```bash
ssh openclaw-mac-mini 'set -e; for d in "$HOME/client-agents/manny/openclaw" "$HOME/Projects/openclaw" "$HOME/openclaw"; do [[ -f "$d/.git/config" ]] && cd "$d" && break; done; pwd; git pull --rebase; bash scripts/shell/openclaw-mini-admin-init-authorized-keys.sh'
```
