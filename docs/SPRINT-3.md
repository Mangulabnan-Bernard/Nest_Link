# Sprint 3 — "Safe Flight & presence over the mesh"

**Goal:** Make status check-ins and family presence real over the dtn-mesh engine, and give all message kinds a shared transport.

## Delivered
| # | Task | Status |
|---|---|---|
| 1 | **MeshProtocol** — JSON envelope (`chat` / `status` / `loc` + sender name) inside the engine's TEXT bundle; raw text falls back to chat | ✅ |
| 2 | **MeshService** — typed `sendChat()` / `sendStatus()` + live `presence` map (eid → name, status, lastSeen) decoded from incoming packets | ✅ |
| 3 | **Family Nest** wired to the envelope (`sendChat`) | ✅ |
| 4 | **Safe Flight** — tapping a status broadcasts it; family board flips `SAMPLE → LIVE` from real presence | ✅ |
| 5 | **Nest Mat** — member list shows real mesh members when present (mock fallback) | ✅ |

## Definition of Done
- [ ] Two phones: tap "Heading Home" on A → appears on B's Safe Flight LIVE board, data OFF.
- [ ] Presence list populates on both Nest Mat + Safe Flight.
- [x] Single phone: envelope/build/test green (`flutter test`, `flutter build apk --debug`).

## Deferred
- **Real GPS distance/bearing on the radar** — needs a location plugin (`geolocator`) + relaying coordinates; the `loc` envelope kind is already defined for it.
- Per-person (unicast) threads still on mock until message history is exposed from the engine DB.

## Notes
- Status packets update presence but don't appear as chat bubbles (kept separate).
- Both phones must run this build to interoperate (shared envelope format).
