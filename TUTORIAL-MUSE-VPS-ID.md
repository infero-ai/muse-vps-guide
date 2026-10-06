# M.U.S.E di Server Muse — Varian Fork

> M.U.S.E adalah fork Hermes Agen. Tutorial ini menerapkan **pola yang sama**
> seperti [tutorial Hermes](TUTORIAL-HERMES-VPS-ID.md) — bedanya CLI
> (`muse` vs `hermes`) dan fitur khas fork. Bagian bertanda `[fork-docs]`
> mengikuti dokumentasi resmi repo fork; bagian operasi (systemd, watchdog,
> gateway, gotcha) berasal dari pengalaman operasi nyata.
>
> **Belum punya server?** Ikuti dulu
> [Bagian 0 — Instal VPN Amerika](TUTORIAL-HERMES-VPS-ID.md#0-instal-vpn-amerika)
> pada tutorial Hermes (VPN Amerika → daftar dengan kode `M8332A`).

---

## Daftar Isi

- [Kenapa varian ini ada](#kenapa-varian-ini-ada)
- [1. Instalasi — pilih jalur](#1-instalasi--pilih-jalur)
- [2. Sambungkan provider & model](#2-sambungkan-provider--model)
- [3. Discord native gateway](#3-discord-native-gateway)
- [4. Daemon systemd + watchdog](#4-daemon-systemd--watchdog)
- [5. Fitur khas M.U.S.E](#5-fitur-khas-muse)
- [6. Verifikasi & perintah harian](#6-verifikasi--perintah-harian)
- [7. Gotcha & troubleshooting](#7-gotcha--troubleshooting)

---

## Kenapa varian ini ada

M.U.S.E mewarisi struktur Hermes 1:1 (config, CLI, gateway), jadi seluruh
pola operasi — systemd daemon, watchdog jinak, aturan singleton, gotcha
`approvals.mode` — berlaku sama. Yang berbeda hanya instalasi dan
fitur tambahannya:

| | Hermes asli | M.U.S.E |
|---|---|---|
| CLI | `hermes` | `muse` |
| Install | `curl .../install.sh \| bash` | `git clone` + `scripts/install.sh` / Docker |
| Plus | — | `/jarvis`, Memory Tree, GraphRAG, AXIOM |

---

## 1. Instalasi — pilih jalur

```bash
git clone https://github.com/A-C-I-SOFTWARE-AND-DEVELOPMENT/M.U.S.E ~/M.U.S.E
cd ~/M.U.S.E
```

**One-command** `[fork-docs]`:

```bash
bash scripts/quickstart.sh            # auto: Docker jika ada, kalau tidak native
bash scripts/quickstart.sh --docker
bash scripts/quickstart.sh --native
```

### Jalur A — Docker `[fork-docs]`

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker "$USER"   # logout/login agar docker tanpa sudo
cd ~/M.U.S.E
HERMES_UID=$(id -u) HERMES_GID=$(id -g) docker compose up -d --build
```

Naik: `gateway` (orchestrator; boot pertama auto-wire model via
`HERMES_BOOTSTRAP_MODELS=1`) + `dashboard` (`127.0.0.1:9119`, loopback).
Data di `~/.hermes` (bind-mount `/opt/data`).

```bash
docker compose logs -f gateway
docker compose ps
cd ~/M.U.S.E && git pull && docker compose up -d --build   # update
```

### Jalur B — Native `[fork-docs]`

```bash
bash scripts/quickstart.sh --native
# di balik layar: scripts/install.sh --jarvis-launch --bootstrap-models
# → memasang uv/Python/Node, gateway sebagai service systemd,
#   lalu muse models bootstrap --free-first --jarvis
```

```bash
muse gateway status
muse gateway restart
muse gateway ensure     # idempoten: pasang+enable+start bila belum berjalan
```

Opsional, di `~/.hermes/config.yaml`:

```yaml
gateway:
  auto_start: true
```

> Kalau service bawaan fork bermasalah, pakai pola systemd manual
> [bagian 4](#4-daemon-systemd--watchdog) .

---

## 2. Sambungkan provider & model

Key di `~/.hermes/.env` (**chmod 600**), hanya isi yang Anda punya:

```dotenv
INFERO_API_KEY=...
GEMINI_API_KEY=...
ANTHROPIC_API_KEY=sk-ant-...
OPENAI_API_KEY=sk-...
```

```bash
muse models bootstrap --free-first --jarvis        # native
docker compose exec gateway hermes models bootstrap --free-first --jarvis  # docker
muse models bootstrap --free-first --jarvis --dry-run   # diagnosa tanpa mengubah
```

`--free-first` = local OSS → free/hosted OSS → paid API (eksplisit saja).

**Setelan yang disarankan:**

```bash
muse config set approvals.mode off
muse config set agent.reasoning_effort max
muse config get approvals.mode   # harus terbaca: off (string, bukan boolean!)
```

---

## 3. Discord native gateway

Jangan buat bot kustom — native gateway sudah termasuk session per-thread,
auto-thread, dan reconnect (native gateway menghapus ratusan baris kode perawatan bot kustom).

1. [Discord Developer Portal](https://discord.com/developers/applications)
   → New Application → Bot → Reset Token → salin.
2. Nyalakan **Message Content Intent** (tanpa ini bot tidak merespons).
3. Invite: OAuth2 → URL Generator → scope `bot`.
4. `~/.hermes/.env`:

```dotenv
DISCORD_BOT_TOKEN=...
DISCORD_ALLOW_ALL_USERS=true
```

5. Restart:

```bash
muse gateway restart              # native
docker compose restart gateway    # docker
```

Uji: mention → dibuatkan thread dan dijawab. Kalau diam:
`tail -f ~/.hermes/logs/gateway.log`.

Platform lain (Telegram, Slack, WhatsApp, Signal, Matrix, Email) polanya
sama: `*_TOKEN` / `*_API_KEY` / `*_ALLOWED_USERS` di `.env` → restart.

---

## 4. Daemon systemd + watchdog

Pola yang disarankan untuk jalur native (Docker sudah
ditangani `restart: unless-stopped`).

**Unit** — simpan master di home (bisa hilang dari `/etc` saat VM diganti):

```ini
[Unit]
Description=M.U.S.E native gateway — supervised daemon
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=muse
WorkingDirectory=/home/muse
Environment=HOME=/home/muse
ExecStart=/home/muse/.muse/bin/muse gateway run
StandardInput=null
StandardOutput=append:/home/muse/muse-tunnel/gateway.log
StandardError=inherit
Restart=always
RestartSec=15

[Install]
WantedBy=multi-user.target
```

*(Sesuaikan `ExecStart` dengan path binary `muse` hasil instalasi fork.)*

```bash
sudo cp ~/muse-tunnel/muse-gateway.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now muse-gateway
```

> ⚠️ Gateway itu **singleton** — proses kedua exit 75/TEMPFAIL ("already
> serves profile"). Matikan yang lama dulu.

**Watchdog** (cron setiap 2 menit, kontrak yang disarankan):

- BOLEH: menyalakan yang mati; memasang ulang unit dari master bila hilang.
- DILARANG: restart proses sehat.
- Satu-satunya yang boleh dibunuh: **duplikat gateway** (tepat 1 jalan).

```bash
PAT='mus[e].*gateway.*run'
# periksa dulu path aslinya: ps aux | grep -i "gateway run"
# 1 proses → jangan sentuh | 0 → systemctl start | >1 → sisakan milik systemd
```

Detail lengkap pola ini:
[TUTORIAL-HERMES-VPS-ID.md#8-hermes-sebagai-daemon--watchdog](TUTORIAL-HERMES-VPS-ID.md#8-hermes-sebagai-daemon--watchdog).

---

## 5. Fitur khas M.U.S.E `[fork-docs]`

- **`/jarvis`** — mode operasi: Companion / Strategy / Critic / Operator /
  Builder / Voice.
- **Memory Tree** — memori ber-provenance, tanpa overwrite diam-diam.
- **GraphRAG** — knowledge graph kode + docs + memori.
- **AXIOM kernel** — ledger verifikasi + governance + rating model.
- **Dashboard** di `127.0.0.1:9119` — **jangan ekspos langsung** (menyimpan
  API key). Akses via `ssh -L 9119:localhost:9119 user@vps` atau reverse
  proxy ber-autentikasi + TLS.
- **Long-horizon**: `scripts/vps-harden-longhorizon.sh` (`--dry-run` dulu,
  `--uninstall` untuk mengembalikan).

---

## 6. Verifikasi & perintah harian

```bash
muse doctor
muse gateway status
systemctl is-active muse-gateway
tail -f ~/.hermes/logs/gateway.log
rsync -a ~/.hermes/ backup-host:/backups/hermes/   # backup
```

---

## 7. Gotcha & troubleshooting

Semua gotcha Hermes berlaku 1:1 (lengkap di
[TUTORIAL-HERMES-VPS-ID.md#13-pelajaran-dari-lapangan](TUTORIAL-HERMES-VPS-ID.md#13-pelajaran-dari-lapangan)).
Yang paling sering menggigit:

| Gejala | Solusi |
|---|---|
| Bot tidak membalas | `muse gateway status` → `tail -f ~/.hermes/logs/gateway.log` → `muse doctor` |
| Model "tidak tersedia" | key di `.env`? → re-run bootstrap (`--dry-run` untuk diagnosa) |
| Approval muncul lagi | `approvals.mode` ke-parse boolean → set ulang string `off` |
| Gateway tidak auto-start | `muse gateway ensure` / `gateway.auto_start: true` / systemd manual |
| Dashboard tidak dapat diakses | bind loopback — pakai SSH tunnel |
