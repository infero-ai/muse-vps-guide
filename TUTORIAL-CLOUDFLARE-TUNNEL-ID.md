# Jaringan VPS Keluar via Cloudflare — Tunnel Worker + Agent

> Tutorial ini menjelaskan pola yang membuat service di VPS bisa diakses
> publik **tanpa membuka port inbound** di VPS: VPS justru yang
> **membuka koneksi keluar** ke Cloudflare, dan Cloudflare meneruskan
> trafik publik lewat koneksi tersebut.
>
> Setiap langkah berisi **penjelasan** (apa & kenapa), **perintah**,
> **verifikasi**, dan **jika error**.

---

## Daftar Isi

- [0. Konsep & arsitektur](#0-konsep--arsitektur)
- [1. Prasyarat](#1-prasyarat)
- [2. Tulis Worker + Durable Object](#2-tulis-worker--durable-object)
- [3. Konfigurasi & secret](#3-konfigurasi--secret)
- [4. Deploy Worker](#4-deploy-worker)
- [5. Route domain ke Worker](#5-route-domain-ke-worker)
- [6. Agent di VPS](#6-agent-di-vps)
- [7. Agent sebagai daemon](#7-agent-sebagai-daemon)
- [8. Verifikasi akhir](#8-verifikasi-akhir)
- [9. Troubleshooting](#9-troubleshooting)

---

## 0. Konsep & arsitektur

**Penjelasan.** VPS pada umumnya sulit diakses dari publik: IP berubah,
firewall provider, atau tidak ada IP publik sama sekali. Pola tunnel ini
membalik arahnya:

```
publik ──HTTPS──▶ Cloudflare Worker ──WebSocket──▶ agent di VPS ──HTTP──▶ service lokal (127.0.0.1:PORT)
```

1. **Agent** berjalan di VPS dan membuka **satu koneksi WebSocket keluar**
   ke Worker (`wss://domain-anda/__tunnel`). Karena koneksi dibuka dari
   dalam, firewall/NAT bukan masalah — tidak perlu port inbound.
2. **Worker** menerima request publik di domain Anda, lalu meneruskannya
   lewat WebSocket itu ke agent; agent meneruskan ke service lokal dan
   mengembalikan responsnya.
3. **Durable Object (DO)** wajib dipakai sebagai titik temu: isolate
   Worker tidak berbagi memori, sehingga socket agent dan request publik
   bisa mendarat di isolate berbeda. DO adalah satu instansi global —
   keduanya selalu bertemu di sana.

Hasilnya: service lokal (dashboard, API, webhook receiver) dapat diakses
publik via `https://tunnel.domainanda.com` dengan TLS dan proteksi
Cloudflare, tanpa membuka port apa pun di VPS.

---

## 1. Prasyarat

**Penjelasan.** Yang dibutuhkan sebelum mulai:

- Domain yang nameserver-nya sudah di Cloudflare (zona aktif).
- [Wrangler](https://developers.cloudflare.com/workers/wrangler/)
  terinstal di laptop: `npm i -g wrangler`, lalu `wrangler login`.
- Node.js di VPS (untuk agent). Service lokal yang ingin dipublikasikan
  sudah berjalan, mis. di `127.0.0.1:3000`.

**Verifikasi.**

```bash
wrangler --version        # di laptop
node --version            # di VPS
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:3000/   # di VPS, harus 200/3xx
```

---

## 2. Tulis Worker + Durable Object

**Penjelasan.** Worker ini punya dua jalur: `/__tunnel` untuk koneksi
WebSocket agent (diamankan dengan secret), dan selain itu meneruskan
request publik ke agent. Pesan bolak-balik memakai JSON dengan `id`
acak agar banyak request bisa berjalan bersamaan dalam satu socket.

**Perintah.** Di laptop, buat folder proyek dan file `worker.js`:

```js
// worker.js — Cloudflare Worker: reverse-proxy tunnel via Durable Object.

function bufToB64(buf) {
  const bytes = new Uint8Array(buf);
  let s = "";
  for (let i = 0; i < bytes.length; i += 0x8000) {
    s += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
  }
  return btoa(s);
}

function b64ToBytes(b64) {
  const bin = atob(b64);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes;
}

export class Tunnel {
  constructor(state, env) {
    this.state = state;
    this.env = env;
    this.agentSocket = null;
    this.pending = new Map();
  }

  async fetch(request) {
    const url = new URL(request.url);

    // --- Jalur agent: WebSocket keluar dari VPS ---
    if (url.pathname === "/__tunnel") {
      if (request.headers.get("Upgrade") !== "websocket") {
        return new Response("expected websocket", { status: 426 });
      }
      if (!this.env.TUNNEL_SECRET || url.searchParams.get("token") !== this.env.TUNNEL_SECRET) {
        return new Response("forbidden", { status: 403 });
      }
      const pair = new WebSocketPair();
      const [client, server] = Object.values(pair);
      server.accept();

      // Hanya satu agent: yang baru menendang yang lama (kode 1012).
      if (this.agentSocket) {
        try { this.agentSocket.close(1012, "replaced"); } catch (_) {}
      }
      this.agentSocket = server;

      server.addEventListener("message", (evt) => {
        try {
          const msg = JSON.parse(evt.data);
          const p = this.pending.get(msg.id);
          if (p) { this.pending.delete(msg.id); p.resolve(msg); }
        } catch (_) {}
      });
      const onClose = () => {
        if (this.agentSocket === server) this.agentSocket = null;
        for (const [, p] of this.pending) p.reject(new Error("tunnel closed"));
        this.pending.clear();
      };
      server.addEventListener("close", onClose);
      server.addEventListener("error", onClose);
      return new Response(null, { status: 101, webSocket: client });
    }

    // --- Jalur publik: teruskan ke agent ---
    if (!this.agentSocket) {
      return new Response("tunnel offline — agent not connected", { status: 502 });
    }
    const sock = this.agentSocket;
    const id = crypto.randomUUID();
    const bodyBuf = request.body ? await request.arrayBuffer() : null;
    const headers = {};
    request.headers.forEach((v, k) => { headers[k] = v; });

    const resp = await new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error("timeout"));
      }, 25000);
      this.pending.set(id, {
        resolve: (m) => { clearTimeout(timer); resolve(m); },
        reject: (e) => { clearTimeout(timer); reject(e); },
      });
      try {
        sock.send(JSON.stringify({
          id,
          method: request.method,
          path: url.pathname + url.search,
          headers,
          body: bodyBuf && bodyBuf.byteLength ? bufToB64(bodyBuf) : null,
        }));
      } catch (e) {
        this.pending.delete(id);
        clearTimeout(timer);
        reject(e);
      }
    }).catch(() => null);

    if (!resp) return new Response("tunnel timeout", { status: 504 });

    const outHeaders = new Headers();
    for (const [k, v] of Object.entries(resp.headers || {})) {
      const kl = k.toLowerCase();
      if (kl === "content-length" || kl === "transfer-encoding" || kl === "connection") continue;
      try { outHeaders.append(k, Array.isArray(v) ? v.join(", ") : String(v)); } catch (_) {}
    }
    const body = resp.body ? b64ToBytes(resp.body) : null;
    return new Response(body, { status: resp.status || 200, headers: outHeaders });
  }
}

export default {
  async fetch(request, env) {
    const stub = env.TUNNEL.get(env.TUNNEL.idFromName("main"));
    return stub.fetch(request);
  },
};
```

---

## 3. Konfigurasi & secret

**Penjelasan.** `wrangler.toml` mendaftarkan Durable Object `Tunnel`
(kelas SQLite `new_sqlite_classes` — tersedia di paket gratis). Secret
tunnel jangan ditulis di file: simpan via `wrangler secret`.

**Perintah** (di folder proyek, laptop):

```toml
# wrangler.toml
name = "tunnel-vps"
main = "worker.js"
compatibility_date = "2026-01-01"

[[durable_objects.bindings]]
name = "TUNNEL"
class_name = "Tunnel"

[[migrations]]
tag = "v1"
new_sqlite_classes = ["Tunnel"]
```

```bash
openssl rand -hex 32 > .tunnel-secret   # hanya di laptop, jangan di-commit
wrangler secret put TUNNEL_SECRET < .tunnel-secret
shred -u .tunnel-secret   # hapus file sementara setelah tersimpan
```

**Verifikasi.**

```bash
wrangler secret list   # TUNNEL_SECRET harus terdaftar
```

---

## 4. Deploy Worker

**Perintah** (laptop):

```bash
wrangler deploy
```

Catat hostname Worker yang diberikan (mis.
`tunnel-vps.<akun>.workers.dev`) — dipakai agent sebagai fallback bila
domain kustom belum di-route.

**Verifikasi.**

```bash
curl -s https://tunnel-vps.<akun>.workers.dev/__tunnel
# harus: "expected websocket" (426) — artinya Worker hidup
```

---

## 5. Route domain ke Worker

**Penjelasan.** Agar bisa diakses via domain sendiri
(`tunnel.domainanda.com`), tambahkan route di Worker tersebut.

**Perintah.** Daftarkan route di `wrangler.toml` (`wrangler route add`
sudah deprecated dan tidak tersedia di Wrangler modern):

```toml
[[routes]]
pattern = "tunnel.domainanda.com/*"
zone_name = "domainanda.com"
```

lalu deploy ulang:

```bash
wrangler deploy
```

atau via dashboard: **Workers & Pages → tunnel-vps → Settings →
Domains & Routes → Add → Route** → isi
`tunnel.domainanda.com/*`.

Pastikan ada DNS record (A/AAAA/CNAME, proxied/orange-cloud) untuk
`tunnel.domainanda.com` di zona tersebut — route tidak berfungsi tanpa
DNS record.

**Verifikasi.**

```bash
curl -s -o /dev/null -w "%{http_code}" https://tunnel.domainanda.com/
# harus: 502 (tunnel offline — wajar, agent belum jalan di langkah 6)
```

---

## 6. Agent di VPS

**Penjelasan.** Agent adalah program Node kecil di VPS. Ia membuka
WebSocket **keluar** ke `wss://tunnel.domainanda.com/__tunnel` memakai
secret, lalu meneruskan setiap request yang datang ke service lokal.
Reconnect memakai backoff eksponensial (5 dtk → 60 dtk) agar tidak
membanjiri saat jaringan putus.

Dua detail penting:

- Header `accept-encoding` **dihapus** sebelum diteruskan ke backend —
  Cloudflare kadang menambahkan `Accept-Encoding: gzip` ke request, dan
  header `Content-Encoding` balasan bisa hilang di jalan sehingga browser
  menampilkan teks rusak.
- **Agent harus tepat satu proses.** Dua agent berebut socket di DO (yang
  baru menendang yang lama, kode 1012) → koneksi flap.

**Perintah** (di VPS):

```bash
mkdir -p ~/tunnel-agent && cd ~/tunnel-agent
npm init -y >/dev/null 2>&1
npm i ws
```

Simpan secret (600, jangan di-share):

```bash
nano ~/.config/tunnel-secret   # tempel secret 64 hex, tanpa newline di akhir lebih baik
chmod 600 ~/.config/tunnel-secret
```

`agent.js`:

```js
// agent.js — berjalan di VPS, koneksi WebSocket KELUAR ke Worker.
const WebSocket = require("ws");
const http = require("http");
const fs = require("fs");

const WORKER_HOST = process.env.WORKER_HOST;   // mis. tunnel.domainanda.com
const SECRET = fs.readFileSync(process.env.SECRET_FILE, "utf8").trim();
const BACKEND = process.env.BACKEND || "http://127.0.0.1:3000";

if (!WORKER_HOST) { console.error("WORKER_HOST env missing"); process.exit(1); }

const URL = `wss://${WORKER_HOST}/__tunnel?token=${encodeURIComponent(SECRET)}`;

let retryDelay = 5000;
const RETRY_MAX = 60000;

function forward(req) {
  return new Promise((resolve) => {
    const body = req.body ? Buffer.from(req.body, "base64") : null;
    const headers = { ...(req.headers || {}) };
    delete headers["host"];
    delete headers["content-length"];
    delete headers["accept-encoding"];   // cegah respons gzip rusak
    if (body) headers["content-length"] = body.length;

    const r = http.request(BACKEND + req.path, { method: req.method, headers }, (res) => {
      const chunks = [];
      res.on("data", (c) => chunks.push(c));
      res.on("end", () => {
        const buf = Buffer.concat(chunks);
        resolve({ id: req.id, status: res.statusCode, headers: res.headers,
                  body: buf.length ? buf.toString("base64") : null });
      });
    });
    r.on("error", () => resolve({ id: req.id, status: 502, headers: {}, body: null }));
    r.setTimeout(20000, () => r.destroy(new Error("backend timeout")));
    if (body) r.write(body);
    r.end();
  });
}

function connect() {
  console.log("[agent] connecting to", WORKER_HOST);
  const ws = new WebSocket(URL, { handshakeTimeout: 10000 });
  ws.on("open", () => {
    console.log("[agent] tunnel connected");
    retryDelay = 5000;
    clearInterval(ws._hb);
    ws._hb = setInterval(() => { if (ws.readyState === WebSocket.OPEN) ws.ping(); }, 20000);
  });
  ws.on("message", async (data) => {
    let req;
    try { req = JSON.parse(data.toString()); } catch { return; }
    try { ws.send(JSON.stringify(await forward(req))); }
    catch { try { ws.send(JSON.stringify({ id: req.id, status: 502, headers: {}, body: null })); } catch {} }
  });
  const retry = () => {
    clearInterval(ws._hb);
    console.log(`[agent] disconnected, retrying in ${Math.round(retryDelay / 1000)}s`);
    setTimeout(connect, retryDelay);
    retryDelay = Math.min(retryDelay * 2, RETRY_MAX);
  };
  ws.on("close", retry);
  ws.on("error", (e) => console.log("[agent] ws error:", e.message));
}

connect();
```

Jalankan manual dulu untuk tes:

```bash
WORKER_HOST=tunnel.domainanda.com SECRET_FILE=$HOME/.config/tunnel-secret \
  BACKEND=http://127.0.0.1:3000 node agent.js
# harus: "[agent] tunnel connected"
```

**Verifikasi** (dari laptop/browser):

```bash
curl -s -o /dev/null -w "%{http_code}" https://tunnel.domainanda.com/
# harus: kode status dari service lokal Anda (200/3xx), bukan 502 lagi
```

---

## 7. Agent sebagai daemon

**Penjelasan.** Agent harus hidup terus dan pulih sendiri — terapkan pola
yang sama seperti service lain: systemd `Restart=always` + watchdog yang
**hanya menyalakan yang mati** dan menjaga tepat satu proses.

`~/tunnel-agent/tunnel-agent.service` (master):

```ini
[Unit]
Description=Tunnel agent (Cloudflare Worker) — supervised daemon
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=hermes
WorkingDirectory=/home/hermes/tunnel-agent
Environment=WORKER_HOST=tunnel.domainanda.com
Environment=SECRET_FILE=/home/hermes/.config/tunnel-secret
Environment=BACKEND=http://127.0.0.1:3000
ExecStart=/usr/bin/node /home/hermes/tunnel-agent/agent.js
Restart=always
RestartSec=15

[Install]
WantedBy=multi-user.target
```

```bash
sudo cp ~/tunnel-agent/tunnel-agent.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now tunnel-agent
```

**Verifikasi.**

```bash
systemctl is-active tunnel-agent                          # active
pgrep -f 'tunnel-agent/agent[.]js' | wc -l                # tepat 1
```

---

## 8. Verifikasi akhir

Checklist setelah semua langkah selesai:

```bash
# di VPS
systemctl is-active tunnel-agent                 # active
pgrep -f 'tunnel-agent/agent[.]js' | wc -l       # tepat 1

# dari mana saja
curl -s -o /dev/null -w "%{http_code}\n" https://tunnel.domainanda.com/
```

Buka `https://tunnel.domainanda.com/` di browser — harus menampilkan
service lokal Anda dengan gembok TLS Cloudflare.

---

## 9. Troubleshooting

| Gejala | Solusi |
|---|---|
| `502 tunnel offline` | agent tidak terhubung — cek `systemctl status tunnel-agent` dan log agent; pastikan `WORKER_HOST` dan secret benar |
| `403` di `/__tunnel` | secret salah — samakan `TUNNEL_SECRET` di Worker dengan isi `~/.config/tunnel-secret` di VPS |
| `504 tunnel timeout` | backend lambat (>25 dtk) atau mati — cek service lokal di VPS |
| Browser menampilkan teks rusak | pastikan agent menghapus header `accept-encoding` (sudah ada di kode di atas) |
| Koneksi flap / putus-nyambung | kemungkinan **dua agent berjalan** — matikan yang satu, sisakan tepat 1 (`pkill` lalu biarkan systemd menyalakan satu) |
| Setelah deploy ulang Worker 404 | route/domain belum terpasang — ulangi langkah 5 |
| Agent tidak bisa konek dari jaringan ber-proxy | set `HTTPS_PROXY`/`https_proxy` di environment service dan teruskan ke WebSocket via proxy agent |

---

## Catatan batasan

- Satu Worker + satu DO melayani satu "jalur" tunnel. Untuk service
  kedua, duplikasikan pola ini (Worker/DO/secret terpisah) atau tambahkan
  routing berdasar hostname di Worker.
- Timeout per request 25 detik (batas di Worker) — untuk proses lama,
  buat endpoint yang mengembalikan cepat lalu polling hasilnya.
- Jangan menaruh secret di kode atau repo — selalu via `wrangler secret`
  dan file `600` di VPS.
