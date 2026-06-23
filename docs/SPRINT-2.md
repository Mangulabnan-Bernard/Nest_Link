# Sprint 2 — "Chirp Chat on the mesh"

**Duration:** 2 weeks
**Goal:** Turn the mock Chirp Chat into **real messaging over the dtn-mesh engine**, with friendly family names instead of raw EIDs.

Builds directly on Sprint 1's working bridge (`sendText` / `receivedBundles`).

## Tasks
| # | Task | Status |
|---|---|---|
| 1 | **MeshService** (Dart) — single wrapper around the platform channel: start/stop, send, a broadcast stream of messages, current EID | ⬜ |
| 2 | **Identity store** — my display name + family registry (EID → name) via `shared_preferences` | ⬜ |
| 3 | **Name onboarding** — first-run screen to set your name + role; pick a family code | ⬜ |
| 4 | **Wire "Family Nest" broadcast** in Chirp Chat to the real mesh (send + live receive), names mapped from the registry | ⬜ |
| 5 | **Auto-add senders** — unknown EIDs appear as "New nestling" and can be renamed | ⬜ |
| 6 | **Extend the bridge** — expose message history from the engine DB (not just live) | ⬜ (stretch) |

## Definition of Done
- [ ] On first launch you set your name; it persists.
- [ ] Open Family Nest → toggle is gone; the mesh is always running in the background.
- [ ] Two phones: send from phone A → appears on phone B's Family Nest **with the sender's name**, data OFF.
- [ ] Mesh-delivered bubbles keep the emerald glimmer.

## Notes
- Keep the other (per-person) threads on mock data until identity/history (Task 6) lands.
- The **Live** tab stays as a raw debug view.
- Real pairwise crypto + per-person routing is deferred (engine sends broadcast unencrypted today; revisit in the crypto sprint).
