# Garmin Feeds

Log breastfeeding on a Garmin watch and import it into the **My Baby** iOS app.

```
Garmin watch (Connect IQ)
  ├─ start / switch / pause → live state → backend   ("Feeding now" on the phone page)
  └─ Stop & save → queued on watch → upload via Garmin Connect (phone), retried every 5 min
Cloudflare Worker + D1  (backend/)
  └─ phone page "Garmin Feeds" → Download (Nara export format) → My Baby: Settings → Import data → "I imported it"
```

**Why Nara format:** My Baby's *Import data* only accepts files exported by the Nara Baby app
(confirmed by the developer). It rejects My Baby's own export and Huckleberry's. The backend writes
a Nara export; `backend/test/nara-known-good.csv` is a file My Baby imported, and the test checks
our output against it byte for byte.

## Layout
| Path | What |
|---|---|
| `backend/src/index.js` | Worker API |
| `backend/src/format.js` | Nara-format CSV writer |
| `backend/src/page.js` | Phone page (dark, pull-to-refresh, live feed card, delete with confirmation) |
| `backend/schema.sql` | D1 tables: `events`, `batches`, `active` |
| `watch/` | Connect IQ app (Monkey C). Watch-app + glance for FR165 / Venu 3 / Sq 2 / Instinct; widget with one-tap L/R card for Venu Sq |

## Watch features
- One tap to start Left/Right (Venu Sq card), suggested next side
- Pause / resume, switch side, Stop & save, **Stop – ended earlier** (forgot to stop), Started earlier, Discard
- Offline queue on the watch; background retry every 5 min; live state while feeding
- One "Still feeding?" wake-up after 45 min

## Backend
```sh
cd backend
cp wrangler.example.toml wrangler.toml   # gitignored: your D1 id, time zone, baby's name
wrangler d1 create garmin-feeds          # put the id in wrangler.toml
wrangler d1 execute garmin-feeds --remote --file=schema.sql
wrangler secret put API_TOKEN            # once; never commit the token
npm test          # Nara CSV must match the structure of a file My Baby accepted
wrangler deploy
```
API (Bearer token or setup cookie): `POST /events`, `POST /events/delete`, `POST /active`, `GET /pending`
(finished feeds + live feeds), `POST /batch`, `GET /batch/<id>.csv`, `POST /ack`, `POST /unack`.
Phone page: `/app` (one-time setup link `/app?key=…` sets a cookie).
Vars in `wrangler.toml`: `TZ`, `NARA_PROFILE_NAME`, `NARA_CAREGIVER`, `NARA_SEX`.

## Watch
Needs the Connect IQ SDK + device files (SDK Manager) and local secrets in `~/.connectiq-keys/`:
- `developer_key.der` – signing key (back it up; updates must use the same key)
- `feeds_api_token` – backend token
- `feeds_api_url` – your Worker URL (one line)

```sh
cd watch
./build.sh                # all devices → out/Feeds-<device>.prg (with your backend)
./build.sh venusq         # one device
RELEASE=1 ./build.sh      # no backend compiled in → out/release/ (what GitHub Releases ship)
```
`build.sh` generates `source-private/Config.mc` (gitignored) with the URL + token. With no URL, the app works on the watch and never syncs.
Install: copy `out/Feeds-<device>.prg` to `GARMIN/APPS/` (Venu Sq mounts as a USB drive; MTP watches need OpenMTP).
Unit tests (simulator): `monkeyc -d fr165 -f test.jungle -t …` then `monkeydo … -t`.

## Secrets
Nothing secret or personal is in this repo. Token, signing key, Worker URL and phone setup link live only in
`~/.connectiq-keys/`, your D1 id and personal values in the gitignored `backend/wrangler.toml`, and the token
as a Cloudflare Worker secret.
