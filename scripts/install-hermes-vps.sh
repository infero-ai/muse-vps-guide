#!/bin/bash
# install-hermes-vps.sh — Instalasi Hermes di server Muse, ujung ke ujung.
#
# Dirancang agar bisa dieksekusi LANGSUNG oleh AI agent (atau manusia):
# jalankan dari atas ke bawah, tiap tahap ada verifikasi otomatis.
# Berhenti (set -e) saat ada yang gagal, dengan pesan yang jelas.
#
# Cara pakai:
#   DISCORD_BOT_TOKEN=... INFERO_API_KEY=... bash scripts/install-hermes-vps.sh
#
# Variabel lingkungan:
#   HERMES_USER        user operasional (default: hermes). Script dijalankan
#                      SEBAGAI user ini, dengan akses sudo.
#   DISCORD_BOT_TOKEN  (wajib) token bot Discord
#   INFERO_API_KEY     (opsional) API murah https://infero.sbs (bonus 1M token)
#   GEMINI_API_KEY     (opsional)
#   OPENAI_API_KEY     (opsional)
#
set -euo pipefail

HERMES_USER="${HERMES_USER:-hermes}"
HOME_DIR="$(eval echo "~$HERMES_USER")"

log()  { echo "==> $*"; }
fail() { echo "GAGAL: $*" >&2; exit 1; }
need() { [ -n "${!1:-}" ] || fail "env $1 belum diisi"; }

# ---------- 0. prasyarat ----------
log "[0/8] cek prasyarat"
[ "$(whoami)" = "$HERMES_USER" ] || fail "jalankan sebagai user '$HERMES_USER' (bukan $(whoami))"
sudo -n true 2>/dev/null || fail "user '$HERMES_USER' butuh akses sudo"
need DISCORD_BOT_TOKEN
command -v systemctl >/dev/null || fail "systemd tidak tersedia"

# ---------- 1. paket dasar ----------
log "[1/8] paket dasar"
sudo apt update -qq
sudo apt install -y -qq git curl >/dev/null
log "OK"

# ---------- 2. install Hermes ----------
log "[2/8] install Hermes"
if command -v hermes >/dev/null 2>&1; then
  log "hermes sudah terinstall — lewati"
else
  curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
fi
export PATH="$HOME_DIR/.hermes/hermes-agent:$PATH"
command -v hermes >/dev/null || fail "binary hermes tidak ditemukan setelah install"
hermes --version
log "OK"

# ---------- 3. .env ----------
log "[3/8] tulis ~/.hermes/.env"
ENV_FILE="$HOME_DIR/.hermes/.env"
touch "$ENV_FILE"; chmod 600 "$ENV_FILE"
set_kv() { # $1=KEY $2=value (tambah atau ganti)
  if grep -q "^$1=" "$ENV_FILE"; then
    sed -i "s|^$1=.*|$1=$2|" "$ENV_FILE"
  else
    printf '%s=%s\n' "$1" "$2" >> "$ENV_FILE"
  fi
}
set_kv DISCORD_BOT_TOKEN "$DISCORD_BOT_TOKEN"
set_kv DISCORD_ALLOW_ALL_USERS "true"
[ -n "${INFERO_API_KEY:-}" ] && set_kv INFERO_API_KEY "$INFERO_API_KEY"
[ -n "${GEMINI_API_KEY:-}" ]     && set_kv GEMINI_API_KEY "$GEMINI_API_KEY"
[ -n "${OPENAI_API_KEY:-}" ]     && set_kv OPENAI_API_KEY "$OPENAI_API_KEY"
log "OK (.env 600)"

# ---------- 4. provider model ----------
log "[4/8] daftarkan provider model"
if [ -n "${INFERO_API_KEY:-}" ]; then
  hermes config set providers.infero.base_url https://api.infero.sbs/v1
  hermes config set providers.infero.key_env INFERO_API_KEY
fi
if [ -n "${GEMINI_API_KEY:-}" ]; then
  hermes config set providers.gemini.base_url https://generativelanguage.googleapis.com/v1beta/openai/
  hermes config set providers.gemini.key_env GEMINI_API_KEY
fi
if [ -n "${OPENAI_API_KEY:-}" ]; then
  hermes config set providers.openai.base_url https://api.openai.com/v1
  hermes config set providers.openai.key_env OPENAI_API_KEY
fi
log "OK"

# ---------- 5. setelan wajib ----------
log "[5/8] setelan wajib"
hermes config set approvals.mode off
MODE="$(hermes config get approvals.mode)"
[ "$MODE" = "off" ] || fail "approvals.mode terbaca '$MODE' (harus string 'off')"
hermes config set agent.reasoning_effort max
log "OK (approvals.mode=off, reasoning_effort=max)"

# ---------- 6. matikan gateway lama (singleton) ----------
log "[6/8] pastikan tidak ada gateway ganda"
if pgrep -f 'hermes-agent/herme[s].*gateway.*run' >/dev/null 2>&1; then
  log "gateway lama ditemukan — hentikan dulu"
  pkill -f 'hermes-agent/herme[s].*gateway.*run' || true
  sleep 3
fi
log "OK"

# ---------- 7. systemd daemon ----------
log "[7/8] pasang systemd service"
PYBIN="$(ls -d "$HOME_DIR"/.hermes/tools/python-3.14*/bin/python3 2>/dev/null | head -1 || true)"
[ -n "$PYBIN" ] || fail "Python bawaan Hermes tidak ditemukan di ~/.hermes/tools/"
UNIT_SRC="$HOME_DIR/hermes-tunnel/hermes-gateway.service"
mkdir -p "$HOME_DIR/hermes-tunnel"
cat > "$UNIT_SRC" <<EOF
[Unit]
Description=Hermes native gateway (Discord) — supervised daemon
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$HERMES_USER
WorkingDirectory=$HOME_DIR
Environment=HOME=$HOME_DIR
Environment=UV_PYTHON=$PYBIN
ExecStart=$HOME_DIR/.hermes/hermes-agent/hermes gateway run
StandardInput=null
StandardOutput=append:$HOME_DIR/hermes-tunnel/gateway.log
StandardError=inherit
Restart=always
RestartSec=15

[Install]
WantedBy=multi-user.target
EOF
sudo cp "$UNIT_SRC" /etc/systemd/system/hermes-gateway.service
sudo systemctl daemon-reload
sudo systemctl enable --now hermes-gateway
sleep 5
systemctl is-active -q hermes-gateway || fail "service tidak active — cek: journalctl -u hermes-gateway"
COUNT="$(pgrep -f 'hermes-agent/herme[s].*gateway.*run' | wc -l)"
[ "$COUNT" -eq 1 ] || fail "gateway berjalan $COUNT proses (harus tepat 1)"
log "OK (service active, tepat 1 gateway)"

# ---------- 8. verifikasi akhir ----------
log "[8/8] verifikasi akhir"
hermes -z "jawab dengan satu kata: ok" 2>&1 | head -3 || log "(tes model dilewati — cek manual)"
echo ""
echo "SELESAI. Ringkasan:"
echo "  - hermes: $(hermes --version 2>/dev/null | head -1)"
echo "  - gateway: $(systemctl is-active hermes-gateway)"
echo "  - log: tail -f ~/.hermes/logs/gateway.log"
echo "  - uji dari Discord: mention bot / kirim DM"
