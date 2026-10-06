# Hermes di VPS — Tutorial Lengkap

> **Bagian 0** — instal VPN Amerika & verifikasi kartu.
> **Bagian A** — jadikan server sebagai VPS (hidup 24/7, pulih sendiri).
> **Bagian B** — instalasi Hermes + Discord di atasnya.
> **Bagian C** — sambungkan Hermes ke banyak model AI lain.
>
> Tutorial ini dirancang agar bisa **dieksekusi langsung oleh AI agen**:
> jalankan langkah berurutan dari atas ke bawah. Setiap langkah berisi
> **penjelasan** (apa & kenapa), **perintah**, **verifikasi**, dan
> **jika error** (apa yang dilakukan saat gagal).
> Versi otomatis: `scripts/install-hermes-vps.sh`.
>
> Disusun dari pengalaman operasi nyata. Tanpa data pribadi — murni
> caranya.

---

## Daftar Isi

**Bagian 0 — Instal VPN Amerika**

- [0. Instal VPN Amerika](#0-instal-vpn-amerika)

**Bagian A — Server jadi VPS**

- [1. Siapkan server](#1-siapkan-server)
- [2. User + SSH](#2-user--ssh)
- [3. Systemd: fondasi 24/7](#3-systemd-fondasi-247)
- [4. Watchdog cron](#4-watchdog-cron)
- [5. Backup](#5-backup)

**Bagian B — Instalasi Hermes**

- [6. Instalasi Hermes](#6-instalasi-hermes)
- [7. Discord native gateway](#7-discord-native-gateway)
- [8. Hermes sebagai daemon + watchdog](#8-hermes-sebagai-daemon--watchdog)

**Bagian C — Pakai model AI lain di Hermes**

- [9. Konsep provider di Hermes](#9-konsep-provider-di-hermes)
- [10. Tambahkan banyak provider](#10-tambahkan-banyak-provider)
- [11. Ganti & atur model](#11-ganti--atur-model)

**Lainnya**

- [12. Verifikasi akhir & perintah harian](#12-verifikasi-akhir--perintah-harian)
- [13. Pelajaran dari lapangan](#13-pelajaran-dari-lapangan)
- [14. Troubleshooting cepat](#14-troubleshooting-cepat)

---

# Bagian 0 — Instal VPN Amerika

## 0. Instal VPN Amerika

**Penjelasan.** Langkah pertama: pasang **VPN Amerika** di perangkat
Anda dan siapkan kartu untuk verifikasi.

**Perintah / langkah.**

1. **Instal VPN Amerika**: pasang aplikasi VPN di perangkat Anda
   (laptop/HP), lalu hubungkan ke server **Amerika Serikat**.
2. **Siapkan kartu debit berisi minimal $1** — khusus untuk verifikasi.
   Penyedia layanan umumnya melakukan *pre-authorization* (penahanan
   sementara) sebesar $1 untuk memastikan kartu valid; dana kembali
   dalam beberapa hari, bukan biaya. Demi keamanan, gunakan kartu khusus
   berlimit kecil.
3. **Daftar**: buka **https://muse.ai/join**, masukkan kode
   **`M8332A`**, selesaikan pendaftaran — Anda akan mendapatkan server
   Muse.

**Spesifikasi server yang didapat** (hasil observasi langsung, dapat
bervariasi):

| Komponen | Spesifikasi |
|---|---|
| CPU | 2 vCPU (AMD EPYC) |
| RAM | ~8 GB |
| Disk | SSD |
| OS | Ubuntu 24.04 LTS (x86_64) |
| Akses | shell penuh, systemd, cron, jaringan keluar |

**Verifikasi** (jalankan di server, catat hasilnya):

```bash
nproc && free -h | head -2 && df -h / | tail -1 && lsb_release -d
```

Harus menampilkan CPU, RAM, disk, dan "Ubuntu 24.04".

**Jika terjadi error.**

| Gejala | Solusi |
|---|---|
| VPN tidak terhubung ke server US | pilih lokasi server US lain di aplikasi VPN; periksa koneksi internet |
| Kartu ditolak saat verifikasi | pastikan saldo minimal $1; pastikan kartu debit diaktifkan untuk transaksi internasional; coba kartu lain |
| Hold $1 tidak kembali | umumnya kembali 3–14 hari kerja; hubungi bank bila lebih dari 30 hari |
| Link pendaftaran tidak terbuka | periksa koneksi internet / coba browser lain |
| Kode `M8332A` ditolak | pastikan persis huruf kapital; daftar tanpa kode lalu cari kolom invite di pengaturan akun |

---

# Bagian A — Server jadi VPS

Tujuannya satu: server yang **selalu hidup** dan **pulih sendiri**.
"VPS" di sini bukan soal sewa-menyewa — ini soal membuat server bisa
diandalkan untuk menjalankan service.

## 1. Siapkan server

**Penjelasan.** `apt update` menyegarkan daftar paket dari repository
Ubuntu; `apt upgrade` memasang patch keamanan. Server yang baru diinstal sering tertinggal banyak patch — langkah ini menutup lubang keamanan
yang diketahui sebelum service dipasang. `git` dan `curl` adalah
perkakas dasar yang dipakai di seluruh tutorial.

**Perintah.**

```bash
sudo apt update && sudo apt -y upgrade
sudo apt install -y git curl
```

**Verifikasi.**

```bash
git --version && curl --version | head -1
```

Keduanya harus menampilkan nomor versi.

**Jika terjadi error.**

| Gejala | Solusi |
|---|---|
| `Could not get lock /var/lib/dpkg/lock` | ada proses apt lain berjalan — tunggu selesai, atau `sudo killall apt apt-get` lalu ulangi |
| `Temporary failure resolving` / network error | periksa DNS: `cat /etc/resolv.conf`; periksa koneksi: `ping -c2 8.8.8.8`; di lingkungan ber-proxy, set `http_proxy`/`https_proxy` |
| Upgrade menanyakan restart service | pilih default (Yes) — aman |

## 2. User + SSH

**Penjelasan.** Jangan operasikan service sebagai `root`. Alasannya:
(1) membatasi kerusakan jika ada perintah salah atau service disusupi;
(2) setiap aksi tercatat atas nama user, bukan root anonim. User `hermes`
di bawah dipakai untuk semua langkah berikutnya.

SSH key (kunci kriptografi) menggantikan password: lebih aman dan tidak
bisa ditebak. Alurnya: buat key di **laptop**, salin public key ke
**server**, lalu matikan login password.

**Perintah.**

```bash
# di server: buat user
sudo adduser hermes            # isi password kuat saat diminta
sudo usermod -aG sudo hermes   # beri hak sudo
su - hermes                    # pindah ke user baru
```

```bash
# di LAPTOP: buat SSH key (sekali saja)
ssh-keygen -t ed25519 -C "laptop"     # Enter 3x untuk default
ssh-copy-id hermes@IP_SERVER          # salin public key ke server
ssh hermes@IP_SERVER                  # uji: harus masuk tanpa password
```

```bash
# di server: matikan login password (SETELAH uji di atas berhasil!)
sudo nano /etc/ssh/sshd_config
# ubah menjadi: PasswordAuthentication no
#               PubkeyAuthentication yes
sudo systemctl restart ssh
```

**Verifikasi.**

```bash
whoami          # harus: hermes
sudo -n true && echo "sudo OK"
ssh -o PreferredAuthentications=password hermes@IP_SERVER "echo hi"
# perintah terakhir HARUS gagal (password ditolak) — artinya key-only aktif
```

**Jika terjadi error.**

| Gejala | Solusi |
|---|---|
| `Permission denied (publickey)` | key belum tersalin: ulangi `ssh-copy-id`; periksa permission di server: `chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys` |
| Terkunci total (tidak bisa masuk) | masuk via console darurat provider VPS; perbaiki `sshd_config` dari sana |
| `hermes is not in the sudoers file` | dari user root: `usermod -aG sudo hermes`, lalu login ulang |
| `ssh-copy-id: command not found` (di laptop) | salin manual: `cat ~/.ssh/id_ed25519.pub`, tempel ke `~/.ssh/authorized_keys` di server |

## 3. Systemd: fondasi 24/7

**Penjelasan.** systemd adalah "pengasuh" service di Linux modern.
Aturan emas tutorial ini: **setiap service yang harus hidup terus
berjalan di bawah systemd**. Service yang dijalankan manual di terminal
mati saat SSH putus atau server restart — itu bukan VPS.

Arti setiap bagian unit file:

- `[Unit]` — identitas & urutan start. `After=network-online.target`
  artinya "jalankan setelah jaringan siap" (penting untuk service yang
  butuh internet).
- `[Service]` — cara menjalankannya. `Type=simple` = perintah foreground
  biasa. `User=` = jalan sebagai siapa. `Restart=always` = **hidupkan
  lagi setiap mati/crash**. `RestartSec=15` = tunggu 15 detik sebelum
  menghidupkan lagi (mencegah restart beruntun).
- `[Install]` — `WantedBy=multi-user.target` + `systemctl enable` =
  service otomatis hidup setiap server boot.

Perintah penting: `daemon-reload` (baca ulang file unit setelah diubah),
`enable` (aktif saat boot), `start/stop/restart`, `status`,
`is-active`, `journalctl -u nama` (baca log).

**Perintah** (contoh template, ganti `nama`):

```ini
# /etc/systemd/system/nama.service
[Unit]
Description=Nama service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=hermes
WorkingDirectory=/home/hermes
ExecStart=/path/ke/perintah
Restart=always
RestartSec=15

[Install]
WantedBy=multi-user.target
```

```bash
sudo cp nama.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now nama
systemctl status nama
```

**Verifikasi.**

```bash
systemctl is-active nama      # harus: active
systemctl is-enabled nama     # harus: enabled
```

Uji ketahanan: `sudo pkill -f "pola-proses"` lalu tunggu 20 detik —
`systemctl is-active nama` harus kembali `active` (Restart=always
bekerja).

**Jika terjadi error.**

| Gejala | Solusi |
|---|---|
| `Failed to start nama.service: Unit not found` | lupa `daemon-reload`, atau nama file ≠ nama service |
| `status` menunjukkan `failed`, log ada `permission denied` | `User=` tidak punya akses ke `ExecStart`/`WorkingDirectory` — periksa dengan `sudo -u hermes /path/ke/perintah` |
| `ExecStart` tidak ditemukan | path salah — gunakan path absolut, periksa dengan `which`/`ls` |
| Service restart terus-menerus (restart counter naik) | perintahnya langsung exit (bukan foreground) — untuk program yang fork ke background pakai `Type=forking`, atau periksa log: `journalctl -u nama -e` |
| Lupa isi unit setelah edit | selalu `sudo systemctl daemon-reload` setiap kali file unit diubah |

## 4. Watchdog cron

**Penjelasan.** systemd menangani crash, tapi tidak menangani semua kasus:
proses mati di luar pantauan systemd, atau unit service hilang. Watchdog
adalah cron job setiap 2 menit yang memeriksa dan **hanya menyalakan yang
mati** — tidak pernah me-restart yang sehat (me-restart yang sehat justru
merusak, mis. memutus sesi chat yang sedang berjalan).

Format cron `*/2 * * * *` = "setiap 2 menit". Lima kolom = menit, jam,
tanggal, bulan, hari.

**Perintah.**

```bash
cat > ~/watchdog.sh <<'EOF'
#!/bin/bash
set -u
if ! pgrep -f 'pola-proses-service' > /dev/null; then
  sudo systemctl start nama-service   # mati — nyalakan
fi
exit 0                                # sehat — jangan disentuh
EOF
chmod +x ~/watchdog.sh
~/watchdog.sh && echo "tes manual OK"

crontab -e
# tambahkan baris ini:
# */2 * * * * /home/hermes/watchdog.sh >> /home/hermes/watchdog.log 2>&1
```

**Verifikasi.**

```bash
systemctl status cron 2>/dev/null || systemctl status crond  # cron hidup?
crontab -l | grep watchdog    # jadwal terpasang?
# uji fungsi: matikan service, tunggu ~2 menit, periksa hidup lagi
sudo systemctl stop nama && sleep 130 && systemctl is-active nama
```

**Jika terjadi error.**

| Gejala | Solusi |
|---|---|
| Cron tidak jalan sama sekali | `sudo systemctl enable --now cron` (Ubuntu) atau `crond` |
| Script tidak dieksekusi | `chmod +x`; pastikan path absolut di crontab; periksa log: `grep CRON /var/log/syslog` |
| Email warning dari cron menumpuk | output sudah di-redirect ke file log (`>> ... 2>&1`) — pastikan redirect ada |
| Watchdog malah me-restart yang sehat | periksa logika script: cabang "sehat" harus `exit 0` tanpa aksi apa pun |
| Satu run nyangkut, run berikut tidak jalan | beri timeout di script (mis. bungkus dengan `timeout 60 ...`) agar run macet tidak memblokir berikutnya |

## 5. Backup

**Penjelasan.** Semua state Hermes (config, session, memory, database)
adalah file biasa di `~/.hermes/`. `rsync -a` menyalin semuanya dengan
permission dan struktur utuh; pengiriman incremental membuat backup
berikutnya cepat.

**Perintah.**

```bash
rsync -a ~/.hermes/ backup-host:/backups/hermes/
```

Untuk harian otomatis, tambahkan ke crontab:

```bash
# 0 3 * * * rsync -a ~/.hermes/ backup-host:/backups/hermes/ >> ~/backup.log 2>&1
```

**Verifikasi.**

```bash
ssh backup-host "ls -la /backups/hermes/ | head"
```

**Jika terjadi error.**

| Gejala | Solusi |
|---|---|
| `Permission denied` ke backup-host | pasang SSH key ke backup-host (`ssh-copy-id`), atau periksa user/path tujuan |
| `No space left on device` | bersihkan backup lama / tambah disk; periksa dengan `df -h` di backup-host |
| Ingin mengembalikan | `rsync -a backup-host:/backups/hermes/ ~/.hermes/` (matikan service dulu) |

---

# Bagian B — Instalasi Hermes

## 6. Instalasi Hermes

**Penjelasan.** Perintah di bawah mengunduh script installer resmi Hermes
dan menjalankannya. Isinya: mengunduh binary/toolchain (Python 3.14,
Node, uv, ffmpeg, ripgrep) ke `~/.hermes/hermes-agent` dan mendaftarkan
launcher `hermes` ke PATH via `~/.bashrc`. Tool opsional (chromium,
agent-browser, gh) hanya diunduh bila jaringan mengizinkan — **inti
tetap berfungsi tanpanya**.

**Perintah.**

```bash
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
source ~/.bashrc
hermes --version
```

**Verifikasi.**

```bash
hermes --version                          # menampilkan versi, mis. vgit.xxxxx
ls ~/.hermes/hermes-agent/                # folder instalasi ada
hermes -z "jawab dengan satu kata: ok"    # tes model (butuh provider, langkah 9-10)
```

**Jika terjadi error.**

| Gejala | Solusi |
|---|---|
| Download timeout / gagal berulang | periksa koneksi & proxy (`env \| grep -i proxy`); ulangi perintah — installer idempoten untuk inti |
| `hermes: command not found` | `source ~/.bashrc` atau login ulang; periksa `ls ~/.hermes/hermes-agent/` |
| `hermes pm` gagal soal Python | arahkan ke Python bawaan Hermes, bukan system Python: `ls ~/.hermes/tools/` lalu `export UV_PYTHON=$HOME/.hermes/tools/<folder-python>/bin/python3` |
| Tool opsional gagal (chromium, gh, dan lainnya) | abaikan — inti tidak membutuhkannya; instalasi manual nanti bila perlu |
| `curl: (60) SSL certificate problem` | jam server salah (`sudo timedatectl set-ntp true`) atau proxy MITM — jangan pakai `-k` kecuali paham risikonya |

## 7. Discord native gateway

**Penjelasan.** Gateway (`hermes gateway run`) adalah jembatan antara
Discord dan inti Hermes. Kenapa native, bukan bot kustom? Gateway sudah
menangani: session per-thread, pembuatan thread otomatis, reconnect,
dan hot-reload config — semua yang harus ditulis ulang bila buat bot
sendiri.

Tiga hal di portal Discord, dan kenapa:

1. **Bot token** = identitas & password bot. Bocor = orang lain bisa
   mengendalikan bot → simpan di `.env` (600), jangan pernah di-share.
2. **Message Content Intent** = izin membaca isi pesan. Tanpa ini bot
   "online tapi tidak merespons".
3. **OAuth2 URL Generator** = cara resmi mengundang bot ke server dengan
   scope & permission yang dipilih.

**Perintah / langkah.**

1. [Discord Developer Portal](https://discord.com/developers/applications)
   → New Application → tab **Bot** → **Reset Token** → salin.
2. Di tab **Bot**, nyalakan **Message Content Intent** → Save.
3. Tab **OAuth2 → URL Generator** → centang scope `bot` → salin URL →
   buka di browser → pilih server → Authorize.
4. Di server:

```bash
nano ~/.hermes/.env        # atau editor favorit Anda
```

```dotenv
DISCORD_BOT_TOKEN=...
DISCORD_ALLOW_ALL_USERS=true
```

```bash
chmod 600 ~/.hermes/.env
hermes gateway run
```

**Verifikasi.**

- Kirim DM ke bot → harus dibalas langsung.
- Mention bot di channel → harus dibuatkan thread dan dijawab di sana.
- Di server: `tail -f ~/.hermes/logs/gateway.log` — setiap pesan masuk
  tercatat (author, channel, panjang konten).

**Jika terjadi error.**

| Gejala | Solusi |
|---|---|
| `401 Unauthorized` / gateway langsung exit | token salah atau ter-reset — buat ulang di portal (Reset Token), update `.env`, jalankan lagi |
| Bot online tapi tidak merespons | (1) Message Content Intent belum nyala → nyalakan + restart gateway; (2) bot tidak punya akses baca channel → periksa permission channel; (3) `DISCORD_ALLOW_ALL_USERS` tidak true dan ID Anda tidak terdaftar |
| Bot tidak ada di server | ulangi OAuth2 URL Generator — pastikan login Discord yang membuka URL adalah admin server tersebut |
| Gateway crash dengan error proxy | traffic harus lewat proxy bila server mewajibkannya — set `HTTPS_PROXY` di environment sebelum menjalankan (jangan hardcode password berotasi di file) |
| Token bocor (ter-paste di chat/log) | **segera** Reset Token di portal, update `.env`, restart gateway |

## 8. Hermes sebagai daemon + watchdog

**Penjelasan.** Menerapkan pola Bagian A khusus untuk Hermes:
systemd menjaga gateway hidup (`Restart=always`), watchdog cron setiap
2 menit memastikan unit terpasang dan tepat **satu** gateway berjalan.

Dua konsep penting:

- **Singleton.** `hermes gateway run` menolak berjalan dua kali untuk
  profil yang sama (proses kedua exit 75/TEMPFAIL, "already serves
  profile"). Karena itu: matikan yang manual sebelum menyalakan service.
- **Pola pgrep kanonis.** Command line asli gateway adalah launcher
  Python (`runpy`), sehingga teks literal `hermes gateway run` **tidak
  muncul** di daftar proses. Pola yang cocok:
  `hermes-agent/herme[s].*gateway.*run` (tanda `[s]` agar `pgrep` tidak
  mencocokkan perintah grep-nya sendiri).

Master unit disimpan di home (`~/hermes-tunnel/`) karena di sebagian
lingkungan `/etc/systemd/system` bisa hilang saat VM diganti — watchdog
menginstal ulang dari master secara otomatis.

**Perintah.**

```ini
# ~/hermes-tunnel/hermes-gateway.service  (master)
[Unit]
Description=Hermes native gateway (Discord) — supervised daemon
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=hermes
WorkingDirectory=/home/hermes
Environment=HOME=/home/hermes
# sesuaikan dengan path Python bawaan Hermes (lihat langkah 6)
Environment=UV_PYTHON=/home/hermes/.hermes/tools/<folder-python>/bin/python3
ExecStart=/home/hermes/.hermes/hermes-agent/hermes gateway run
StandardInput=null
StandardOutput=append:/home/hermes/hermes-tunnel/gateway.log
StandardError=inherit
Restart=always
RestartSec=15

[Install]
WantedBy=multi-user.target
```

```bash
# matikan gateway manual dulu (singleton!)
pkill -f 'hermes-agent/herme[s].*gateway.*run' || true
sleep 3

sudo cp ~/hermes-tunnel/hermes-gateway.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now hermes-gateway
```

Watchdog (`~/hermes-tunnel/boot-gateway.sh`, `chmod +x`):

```bash
#!/bin/bash
set -u
PAT='hermes-agent/herme[s].*gateway.*run'
UNIT=/etc/systemd/system/hermes-gateway.service
MASTER="$HOME/hermes-tunnel/hermes-gateway.service"

# pasang ulang unit kalau hilang
if [ ! -f "$UNIT" ] && [ -f "$MASTER" ]; then
  sudo cp "$MASTER" "$UNIT"
  sudo systemctl daemon-reload
  sudo systemctl enable hermes-gateway
fi

COUNT=$(pgrep -f "$PAT" | grep -c .)
if [ "$COUNT" -eq 1 ]; then
  exit 0                                   # sehat — jangan disentuh
elif [ "$COUNT" -eq 0 ]; then
  sudo systemctl start hermes-gateway      # mati — nyalakan
else
  # duplikat — sisakan milik systemd (atau yang tertua)
  KEEP=$(systemctl show hermes-gateway --property=MainPID --value)
  [ "$KEEP" = "0" ] && KEEP=$(pgrep -f "$PAT" | sort -n | head -1)
  for pid in $(pgrep -f "$PAT"); do
    [ "$pid" != "$KEEP" ] && sudo kill "$pid"
  done
fi
```

```bash
crontab -e
# */2 * * * * /home/hermes/hermes-tunnel/boot-gateway.sh >> /home/hermes/hermes-tunnel/watchdog.log 2>&1
```

**Verifikasi.**

```bash
systemctl is-active hermes-gateway                 # active
systemctl is-enabled hermes-gateway                # enabled
pgrep -f 'hermes-agent/herme[s].*gateway.*run' | wc -l   # tepat 1
systemctl show hermes-gateway --property=MainPID   # PID milik systemd
```

**Jika terjadi error.**

| Gejala | Solusi |
|---|---|
| Gateway exit 75 / "already serves profile" | gateway lama masih jalan — `pkill` pola kanonis di atas, tunggu 3 detik, start service |
| `pgrep` menemukan 0 padahal service active | pola salah untuk instalasi ini — periksa command line asli: `ps aux \| grep -i gateway`, sesuaikan `PAT` |
| Duplikat terus muncul lagi | ada yang menjalankan gateway di luar systemd (cron lama? terminal tertinggal?) — cari: `ps aux \| grep -i hermes` |
| `MainPID=0` | service belum start / gagal start — `journalctl -u hermes-gateway -e` |
| Service restart beruntun | `ExecStart`/`UV_PYTHON` salah — perbaiki path, `daemon-reload`, restart |
| Setelah VM diganti service hilang | normal di lingkungan ephemeral — watchdog menginstal ulang dari master di home |

---

# Bagian C — Pakai model AI lain di Hermes

## 9. Konsep provider di Hermes

**Penjelasan.** Hermes tidak terikat satu model. Ia mengenal **provider**:
setiap provider = satu endpoint API + satu API key. Model dipanggil dengan
format `provider/nama-model`. Key disimpan di `~/.hermes/.env` (600) dan
dirujuk lewat `key_env` (nama variabelnya, **bukan** nilainya) — sehingga
config bisa di-share tanpa membocorkan key.

Alur request: chat Discord → gateway → Hermes → provider yang key-nya
tersedia → model.

## 10. Tambahkan banyak provider

**Penjelasan.** Pola pendaftarannya sama untuk semua provider yang
OpenAI-compatible: `base_url` (endpoint) + `key_env` (nama variabel key
di `.env`). Isi `.env` hanya dengan key yang Anda punya — sisanya
abaikan.

**Perintah.**

```dotenv
# ~/.hermes/.env  (chmod 600)
INFERO_API_KEY=...
GEMINI_API_KEY=...
OPENAI_API_KEY=sk-...
```

```bash
# Infero.sbs — API murah, OpenAI-compatible (utama)
# Bonus pendaftaran: cukup login, dapat 1M token
# Daftar di https://infero.sbs/ lalu ambil API key
hermes config set providers.infero.base_url https://api.infero.sbs/v1
hermes config set providers.infero.key_env INFERO_API_KEY
```

Model hemat di Infero: **DeepSeek V4 Flash** (`deepseek-v4-flash-0731`),
**GLM 5.3 Flash** (`glm-5.3-flash`), **Qwen 3.8 27B** (`qwen3.8-max`) —
dipakai sebagai `infero/deepseek-v4-flash-0731`, dan seterusnya.

### Provider lain (opsional)

Pola yang sama untuk provider OpenAI-compatible lainnya:

```bash
# Gemini (mode OpenAI-compatible)
hermes config set providers.gemini.base_url https://generativelanguage.googleapis.com/v1beta/openai/
hermes config set providers.gemini.key_env GEMINI_API_KEY

# OpenAI langsung
hermes config set providers.openai.base_url https://api.openai.com/v1
hermes config set providers.openai.key_env OPENAI_API_KEY

# Model lokal via Ollama (OpenAI-compatible, tanpa key)
# ollama pull deepseek-r1:8b   # contoh tarik model dulu
hermes config set providers.ollama.base_url http://127.0.0.1:11434/v1
```

**Setelan yang disarankan** (penjelasan: `approvals.mode off` = semua aksi
agen otomatis tanpa prompt persetujuan; `reasoning_effort max` = sesi
berpikir sedalam mungkin):

```bash
hermes config set approvals.mode off
hermes config set agent.reasoning_effort max
hermes config get approvals.mode   # HARUS menampilkan: off
```

> Kenapa harus dicek? YAML membaca `off` polos sebagai boolean `False`
> → approval bisa balik nyala diam-diam.

**Jika terjadi error.**

| Gejala | Solusi |
|---|---|
| `401 Unauthorized` dari provider | key salah / belum diisi di `.env` — periksa `grep KEY ~/.hermes/.env`; ingat gateway perlu restart untuk membaca `.env` yang baru |
| `404` saat memanggil model | `base_url` salah (typo, kurang `/v1`) — cocokkan dengan dokumentasi provider |
| `SSL / certificate error` | URL salah ketik `http` vs `https`, atau jam server salah |
| Model tidak ditemukan | nama model salah — periksa daftar model di dashboard provider / dokumentasi |
| Provider non-OpenAI-compatible error | butuh tipe provider khusus — periksa dokumentasi Hermes untuk provider tersebut |
| Rate limit / quota habis | wajar di tier gratis — tunggu reset, atau pindah ke provider lain (inilah gunanya banyak provider) |

## 11. Ganti & atur model

**Penjelasan.** Karena banyak provider terdaftar, Anda bebas memilih model
per kebutuhan: yang murah/cepat untuk tugas ringan, yang kuat untuk
analisis berat. Format selalu `provider/nama-model`.

**Perintah.**

```bash
# lihat konfigurasi saat ini
hermes config get providers

# tes provider baru langsung
hermes -z "sebutkan model yang Anda pakai"
```

Di chat (Discord): ganti model per-sesi via perintah `/model`, atau atur
default di config.

**Tips hemat:** mulai dari yang gratis/murah (Ollama lokal, tier gratis
Gemini, bonus 1M token Infero); naik ke berbayar hanya saat
dibutuhkan.

**Jika terjadi error.**

| Gejala | Solusi |
|---|---|
| Model tidak tersedia padahal provider terdaftar | key provider itu belum ada di `.env` |
| `/model` tidak dikenal | fitur tergantung versi gateway — update Hermes atau ganti via config |
| Respons lambat | coba model lebih kecil / provider lebih dekat / periksa `ping` ke endpoint |

---

# Lainnya

## 12. Verifikasi akhir & perintah harian

Checklist setelah semua bagian selesai:

```bash
systemctl is-active hermes-gateway                 # active
pgrep -f 'hermes-agent/herme[s].*gateway.*run' | wc -l   # tepat 1
hermes config get approvals.mode                  # off
tail -f ~/.hermes/logs/gateway.log                # pesan masuk tercatat
```

Dari Discord: mention bot → thread otomatis dan dijawab; DM → dijawab
langsung; `/model` → ganti model.

Perintah harian:

```bash
systemctl status hermes-gateway
sudo systemctl restart hermes-gateway   # bila perlu
crontab -l                              # pastikan watchdog terpasang
rsync -a ~/.hermes/ backup-host:/backups/hermes/
```

## 13. Pelajaran dari lapangan

1. **`approvals.mode` harus string `"off"`** — boolean `False` menyalakan
   approval diam-diam.
2. **Pola pgrep yang salah = watchdog buta** — pakai pola kanonis.
3. **Jangan restart yang sehat** — hanya nyalakan yang mati; hanya bunuh
   duplikat gateway.
4. **`hermes pm` butuh `UV_PYTHON`** ke Python bawaan Hermes.
5. **VM restart = semua mati** — `Restart=always` + `enable` + watchdog =
   pulih tanpa disentuh.
6. **Jangan hardcode kredensial berotasi** di unit systemd.
7. **Native gateway > bot kustom.**

## 14. Troubleshooting cepat

Indeks kilat — detail per langkah ada di bagian "Jika error"
masing-masing:

| Gejala | Lihat |
|---|---|
| apt terkunci / network error | Langkah 1 |
| SSH ditolak / terkunci | Langkah 2 |
| Service gagal start / restart beruntun | Langkah 3 |
| Cron tidak jalan | Langkah 4 |
| Backup gagal | Langkah 5 |
| Instalasi gagal / `hermes: command not found` | Langkah 6 |
| Bot tidak merespons / 401 / token bocor | Langkah 7 |
| Exit 75 / duplikat / pola pgrep | Langkah 8 |
| 401/404 provider / model tidak ditemukan | Langkah 10 |
| Model tidak tersedia | Langkah 11 |
