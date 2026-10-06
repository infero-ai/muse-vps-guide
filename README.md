# Muse VPS Guide

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![Hermes](https://img.shields.io/badge/Hermes-MIT-yellow.svg)](https://github.com/NousResearch/hermes-agent)
[![M.U.S.E](https://img.shields.io/badge/M.U.S.E-docs-lightgrey.svg)](https://github.com/A-C-I-SOFTWARE-AND-DEVELOPMENT/M.U.S.E)

> Panduan mengubah server Muse menjadi VPS gratis — kemudian menginstal
> Hermes di atasnya dan menggunakan banyak model AI lain. Dari nol hingga
> bot Discord 24/7 dengan pemulihan otomatis.

![Animasi perintah instalasi utama](assets/tutorial.gif?v=2)
*Animasi ilustrasi perintah-perintah utama dalam tutorial.*

---

## Langkah 0 — Instal VPN Amerika

1. **Instal VPN Amerika**: pasang aplikasi VPN di perangkat Anda
   (laptop/HP), lalu hubungkan ke server **Amerika Serikat**.
2. **Siapkan kartu debit berisi minimal $1** — khusus untuk verifikasi.
   Penyedia layanan umumnya melakukan *pre-authorization* (penahanan
   sementara) sebesar $1 untuk memastikan kartu valid; dana tersebut
   kembali dalam beberapa hari — bukan biaya. Demi keamanan, gunakan
   kartu khusus dengan limit kecil.
3. **Daftar**: buka **https://muse.ai/join**, masukkan kode
   **`M8332A`**, selesaikan pendaftaran — Anda akan mendapatkan server
   Muse.

## Spesifikasi server yang didapat

Hasil observasi langsung di server (dapat bervariasi):

| Komponen | Spesifikasi |
|---|---|
| CPU | 2 vCPU (AMD EPYC) |
| RAM | ~8 GB |
| Disk | SSD |
| OS | Ubuntu 24.04 LTS (x86_64) |
| Akses | shell penuh, systemd, cron, jaringan keluar |

Spesifikasi ini memadai untuk menjalankan Hermes beserta gateway Discord
24/7 dengan API-routing (inference ke provider, tanpa GPU).

---

## Alur tutorial

```
INSTAL VPN AMERIKA (kartu debit $1 khusus verifikasi)
    │
    ▼
DAFTAR → https://muse.ai/join (kode M8332A)
    │
    ▼
SERVER UBUNTU 24.04
    │  Bagian A: menjadikan VPS yang andal (systemd + watchdog + backup)
    ▼
VPS 24/7
    │  Bagian B: instalasi Hermes + gateway Discord
    ▼
HERMES BERJALAN
    │  Bagian C: menghubungkan banyak model AI lain
    ▼
HERMES + BANYAK MODEL, 24/7
```

**Jalur cepat (untuk agen):** langkah 1, 6–8, dan 10 tersedia sebagai satu
skrip yang dapat dieksekusi langsung secara berurutan
(user + SSH, watchdog cron, dan backup tetap mengikuti tutorial manual):

```bash
DISCORD_BOT_TOKEN=... INFERO_API_KEY=... bash scripts/install-hermes-vps.sh
```

Skrip berhenti otomatis ketika ada tahap yang gagal, disertai pesan yang
jelas. Penjelasan manual setiap langkah tersedia di tutorial.

| Berkas | Isi |
|---|---|
| [`TUTORIAL-HERMES-VPS-ID.md`](TUTORIAL-HERMES-VPS-ID.md) | **Tutorial utama** — A (server menjadi VPS), B (instalasi Hermes), C (banyak model AI). Setiap langkah bersifat atomik disertai perintah verifikasi, dapat dieksekusi langsung oleh agen. |
| [`TUTORIAL-MUSE-VPS-ID.md`](TUTORIAL-MUSE-VPS-ID.md) | Varian fork M.U.S.E dengan pola yang sama. |
| [`TUTORIAL-CLOUDFLARE-TUNNEL-ID.md`](TUTORIAL-CLOUDFLARE-TUNNEL-ID.md) | **Jaringan VPS keluar via Cloudflare** — Worker + Durable Object + agent: service lokal di VPS dapat diakses publik tanpa membuka port inbound. |
| [`scripts/install-hermes-vps.sh`](scripts/install-hermes-vps.sh) | Skrip instalasi otomatis (untuk agen maupun manusia). |
| [`assets/tutorial.gif`](assets/tutorial.gif) | Animasi ilustrasi perintah utama. |

---

## Ringkasan tiap bagian

**Bagian A — Server menjadi VPS.** Pengguna non-root, SSH, systemd
`Restart=always` untuk semua service, watchdog cron dengan pola "hanya
menyalakan yang mati", serta backup. Fondasi yang membuat server dapat
diandalkan.

**Bagian B — Instalasi Hermes.** `curl -fsSL
https://hermes-agent.nousresearch.com/install.sh | bash`, Discord melalui
native gateway (`hermes gateway run`), dijadikan daemon systemd.

**Bagian C — Banyak model AI di Hermes.** Mendaftarkan provider yang
OpenAI-compatible (Infero, Gemini, OpenAI, Ollama lokal, …) — kunci
di `.env`, endpoint di konfigurasi — dan beralih model dari satu pintu.

---

## Manfaat

1. **VPS gratis** yang berjalan 24/7 (pendaftaran dengan kode `M8332A`).
2. **Hermes di Discord 24/7** — mention → thread otomatis, sesi per thread.
3. **Banyak model AI dalam satu Hermes** — tidak terkunci pada satu provider.
4. **Pemulihan otomatis** — crash/restart → kembali berjalan tanpa intervensi.
5. **Otomasi penuh** — `approvals.mode: "off"` tanpa persetujuan manual.

---

## API murah untuk Hermes

Membutuhkan API yang murah dan terjamin keasliannya? Pertimbangkan
**[Infero](https://infero.sbs/)** — AI router yang OpenAI-compatible:
satu endpoint, satu key, 18 model.

- 🎁 **Bonus pendaftaran: cukup login, dapat 1M token**
- Model hemat yang tersedia: **DeepSeek V4 Flash**, **GLM 5.3 Flash**, **Qwen 3.8 27B**
- Harga transparan per 1 juta token, tanpa biaya tambahan

Daftar di **https://infero.sbs/**, ambil API key, lalu daftarkan sebagai
provider (lihat Bagian C pada tutorial):

```bash
hermes config set providers.infero.base_url https://api.infero.sbs/v1
hermes config set providers.infero.key_env INFERO_API_KEY
```

---

## Lisensi

- **Panduan ini** (teks, skrip, gambar): [Apache License 2.0](LICENSE) —
  Copyright 2026 infero-ai.
- **Hermes Agent** (oleh Nous Research): [MIT](https://github.com/NousResearch/hermes-agent).
- **M.U.S.E** (fork): mengikuti lisensi repositori fork-nya.

Silakan gunakan, fork, dan sebarkan sesuai ketentuan lisensi masing-masing.
