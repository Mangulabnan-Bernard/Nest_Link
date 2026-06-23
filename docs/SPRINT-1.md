# Sprint 1 — "First real mesh message from Flutter"

**Duration:** 2 weeks
**Sprint goal:** A button in a Flutter screen sends a message that travels over **real Wi-Fi Direct / Bluetooth** and appears on a **second phone's** Flutter screen — with Wi-Fi/data **off**.

Why first: the platform-channel + foreground-service plumbing is the riskiest part of the whole project. De-risk it before building any features.

## Tasks
| # | Task | Status |
|---|---|---|
| 1 | **Restructure repo** → `mobile/` `web/` `firebase/` `docs/`, keep `reference/dtn-mesh` | ✅ done |
| 2 | **Pull the engine** into `mobile/android` (`service/ dtn/ crypto/ db/ model/ transport/ audio/`); drop `ui/` + `MainActivity` + `DTNApplication`; repoint `DTNService` notif intent to Flutter `MainActivity` | ✅ done |
| 3 | **Merge AndroidManifest** — permissions, `DTNService` (FGS type `connectedDevice`), cleartext, `tools` ns; LoRa USB auto-launch filter omitted | ✅ done |
| 4 | **Wire Gradle deps** — Room 2.7.x + KSP2 2.3.9, Gson, coroutines, lifecycle-service, core-ktx, `usb-serial` AAR; minSdk bumped to 26 | ✅ done |
| — | **Verify Gradle sync / debug build** (validate Room+KSP versions on this toolchain) | ⬜ in progress |
| 5 | **Platform channel** — `MethodChannel` (start/stop/getLocalEid/sendText) + `EventChannel` (receivedBundles → Flutter) | ✅ done |
| 6 | **Minimal Flutter test screen** — EID, text box, send, incoming list (charcoal+emerald) | ✅ done |
| 7 | **Runtime permissions** in Flutter — `permission_handler`: location, nearby-wifi, bluetooth, mic, notifications | ✅ done |

**Build status:** `flutter build apk --debug` ✅ passes end-to-end (Flutter UI + platform channel + dtn-mesh engine + plugin). Room/KSP2 version pins validated on Kotlin 2.3.20 / AGP 9.

### Version-pinning watch (most likely first-sync fixes)
- `roomVersion` (`app/build.gradle.kts`) — set to `2.7.2`; the floor for KSP2 support. Bump within 2.7.x/2.8.x if unresolved.
- KSP plugin `2.3.9` (`settings.gradle.kts`) — latest KSP2 (May 2026); aligned to Kotlin 2.3.x. Adjust if Gradle reports a Kotlin/KSP mismatch.
- `lifecycle-service:2.8.7`, `core-ktx:1.13.1`, `gson:2.11.0`, `coroutines:1.8.1` — bump if newer required by AGP 9.

## Definition of Done
- [ ] App launches `DTNService`; Flutter displays the local EID.
- [ ] Two physical Android phones discover each other.
- [ ] Send on phone A → message appears on phone B's Flutter list, with **Wi-Fi & mobile data OFF**.
- [ ] No crashes on engine start/stop.

## Notes / risks
- Needs **2 physical Android phones** (mesh can't run on emulators — Wi-Fi Direct `required="true"`).
- `minSdk 26`, Java 17, KSP for Room.
- Engine package namespace stays `com.dtnmesh.app`; Flutter app id is `com.example.nest_link` — the engine compiles as a package inside the Flutter Android module, the bridge lives in `MainActivity`.
- This sprint builds **no UI features** — just the proof that Flutter drives the real mesh.

## Tracking
Sprint board lives in the session todo list; this file is the durable record.
