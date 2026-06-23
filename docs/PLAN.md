# Nest Link — System Plan

> Source of truth for the build. This is a **real product** we are shipping (not a thesis).

## 1. Vision
Keep families connected and safe **even when there is no internet or cell signal.** Messages, locations, and status updates hop phone-to-phone over an offline mesh, and sync to the cloud the moment any family member gets online — so a web dashboard stays up to date too.

## 2. Locked decisions
| Decision | Choice | Notes |
|---|---|---|
| Mobile framework | **Flutter** | UI runs cross-platform; mesh features are Android-only |
| Mesh engine | **Reuse `jeremiaspala/dtn-mesh`** (MIT) | Kotlin engine, bridged to Flutter |
| Mobile integration | **Option A** — Flutter UI + dtn-mesh engine via platform channel | Keeps Flutter + web alignment |
| Transport | **Wi-Fi Direct + Bluetooth** | No extra hardware needed |
| LoRa (2–15 km) | **Skipped for now** | Needs ESP32 USB hardware (~$15/node). Add later if wanted |
| Web app | **Separate Next.js** (TypeScript + Tailwind) | Showcase landing + parent dashboard |
| Web purpose | **Showcase + Dashboard** | |
| Backend | **Firebase** (Auth, Firestore, Storage, Hosting) | The shared "brain" aligning mobile + web |
| Test devices | **2 physical Android phones** | Mesh can't be verified on emulators |
| Sprint cadence | **2-week sprints** | |

## 3. Architecture
```
┌────────────────────────────┐      ┌────────────────────────────┐
│      MOBILE (Android)       │      │       WEB (Next.js)         │
│  ┌──────────────────────┐  │      │   Showcase + Dashboard      │
│  │  Flutter UI           │  │      └──────────────┬──────────────┘
│  │  charcoal + emerald   │  │                     │
│  └──────────┬───────────┘  │                     │
│   platform channel ↓        │                     ▼
│  ┌──────────────────────┐  │           ┌──────────────────┐
│  │  dtn-mesh ENGINE      │  │  online   │   FIREBASE       │
│  │  • PRoPHET routing    │──┼──sync────▶│  Auth·Firestore  │
│  │  • ECDH+AES crypto    │  │           │  Storage·Hosting │
│  │  • WiFi Direct + BT   │  │           └──────────────────┘
│  └──────────────────────┘  │
└────────────────────────────┘
```
Rule: the DTN engine treats **Firebase as just another peer.** Offline → sync to nearby phones. Online → sync to the cloud. Same store-carry-forward logic, one more destination.

## 4. Engine review (`reference/dtn-mesh`, read from source)

### Keep as the engine
`service/DTNService.kt` (orchestrator + bridge target), `dtn/` (BundleManager, ProphetRouter, FragmentManager), `crypto/CryptoManager.kt`, `db/` + `model/`, `transport/` (WifiDirect, Bluetooth, LoRa), `audio/` (Opus PTT).

### Discard (rebuilt in Flutter)
`ui/*` (Fragments/XML), `MainActivity.kt`.

### Bridge surface (Kotlin ↔ Flutter)
```
MethodChannel:  start() / stop()
                getLocalEid() -> "DTN-A1B2C3D4"
                sendText(text, destEid) -> bundleId
                sendAudio(bytes, destEid)
                getPeers()
EventChannel:   receivedBundles  (stream of incoming messages)
                peerEvents       (nearby peers / RSSI)
```
Engine already exposes a `LocalBinder`, a `receivedBundles` SharedFlow, and `BundleManager.createTextBundle(text, destEid)` / `createAudioBundle(...)`.

### Findings that shape our work
1. **Identity is device-based**, not accounts. EID = `"DTN-" + ANDROID_ID` prefix. → We build an **EID ↔ Firebase user/family mapping** layer.
2. **Crypto is pairwise (per-peer ECDH), not a family group key.** `decrypt()` tries all known peer secrets. Broadcast/group messages aren't E2E the same way. → Decide in S6: accept pairwise, or add a family-group-key layer (affects whether the web dashboard can read chat).
3. **Only payload types: `TEXT, AUDIO, ACK, FRAGMENT`** — no location/status type. → Encode location & status as **JSON inside TEXT payloads** with a type tag. No engine fork needed.
4. **Offline-only today** — Firebase sync is 100% ours. `minSdk 26`. Wi-Fi Direct is `required="true"` in the manifest (real phones only).

## 5. Shared data model (engine ↔ Firestore mirror)
Engine bundle (`DTNBundle`): `id, sourceEid, destEid, payloadType, payload, ttlMillis, createdAt, hopCount, delivered, deliveredAt, refBundleId, isEncrypted`.

Firestore mirror:
```
families/{familyId}
  members/{userId}    -> name, role(parent/child), avatar, eid, lastSeen
  packets/{packetId}  -> sourceEid, destEid, type, payload/ciphertext, createdAt, ttl, hopCount, delivered
  statuses/{userId}   -> label("Heading Home"), updatedAt, versionVector
  locations/{userId}  -> lat, lng, accuracy, updatedAt
  checklist/{itemId}  -> text, checked, updatedBy
```
Location & status ride inside TEXT payloads on the mesh, then land in their own Firestore collections on sync.

## 6. Build stages (product-first: ship a working app, then layer the mesh polish)
| Sprint | Goal |
|---|---|
| **S1** | Restructure + bridge proof — Flutter sends a real mesh message between 2 phones |
| **S2** | Identity + Chirp Chat UI on the engine (EID ↔ family mapping) |
| **S3** | Location & status payloads — Nest Mat radar + Safe Flight |
| **S4** | Firebase online-sync (mesh ↔ cloud) |
| **S5** | Next.js showcase + parent dashboard (live) |
| **S6** | Harden + ship — crypto decision, battery, polish, release |

## 7. Open decisions (deferred, tracked)
1. **Crypto vs web dashboard** — pairwise (engine default) vs family group key for readable web chat. *(S6)*
2. **iOS** — online-only mode (no mesh) for mixed households. *(S5+)*
3. **Routing** — keep PRoPHET (engine default). Epidemic/Spray-and-Wait only if needed.

## 8. Theme
Deep charcoal-gray background (battery-friendly, night-safe), glowing **emerald green** for safety/connection, **teal** for normal messaging. Mesh-delivered messages glimmer emerald with a nest icon.
