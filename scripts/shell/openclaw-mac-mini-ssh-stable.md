# Stable SSH to the OpenClaw Mac Mini

Plain **LAN IPs** (`192.168.*`) hop when Wi‑Fi or subnets change. Use **Tailscale** instead so the Mini has one stable address wherever it goes.

## Tailscale IP (same on every upstream network)

When both machines run Tailscale, SSH to the Mini’s **`100.x.x.x`** address (shown in “Tailscale IPs” on each device).

Example **`~/.ssh/config`** block (adjust `IdentityFile`; user is often **`operator`**):

```sshconfig
Host openclaw-mac-mini
  HostName 100.126.53.107
  User operator
  IdentityFile ~/.ssh/id_ed25519_openclaw_mac_mini
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
```

Then:

```bash
ssh openclaw-mac-mini
```

Prefer **MagicDNS names** (`*.ts.net`) if you assign them in Tailscale—they stay stable without memorizing digits.

## Why `IdentitiesOnly yes`

Stops **`ssh`** from throwing every agent key at the server and tripping **“Too many authentication failures.”**

## Repo automation / agents

From this checkout, run remote commands **without putting secrets in git** (`OPERATOR_MANNY_ENV_FILE` stays **`chmod 600`** on disk):

```bash
bash scripts/shell/openclaw-mini-exec-from-env.sh 'cd ~/openclaw && git pull --rebase'
```

Uses **`OPENCLAW_OPERATOR_MANNY_*`** keys from **`~/client-agents/manny/.env`** (parsed safely—do **not** **`source`** that file in **`bash`** when values look like **`ssh user@host`** without quotes).

One-shot **SSH** example (interactive host key / passphrase):

```bash
ssh -i ~/.ssh/id_ed25519_openclaw_mac_mini -o IdentitiesOnly=yes operator@100.126.53.107 'uname -sr'
```
