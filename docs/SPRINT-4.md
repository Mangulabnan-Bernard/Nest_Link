# Sprint 4 — "Redesign + Offline SOS"

The pivot from a family app toward a **community safety platform**: a new
Home command center that leads with **SOS**, plus the first life-safety feature.

## Goal
Reframe the UI around safety (SOS front-and-center) and let anyone send an
**offline emergency SOS** that reaches their family/barangay over the mesh.

## Delivered
| # | Item | Status |
|---|---|---|
| 1 | **New 5-tab shell** — Home · Chat · Map · Safety · Me | ✅ |
| 2 | **Home command center** — big hold-to-send **SOS**, live **Alerts** feed, family-nearby snapshot | ✅ |
| 3 | **Offline SOS** — `sos` envelope kind (type + GPS + medical flag + name), re-broadcast x3 for reliability, dedupe by id | ✅ |
| 4 | **Receiving an SOS** — loud in-app banner + native heads-up notification ("🆘 … needs help") | ✅ |
| 5 | **Me tab** — profile, family/group code (create/join/copy), mesh diagnostics | ✅ |

## How SOS works
- Hold the SOS button ~1.6s (prevents accidental taps) → attaches GPS +
  emergency type + medical flag → broadcasts over the mesh (offline).
- Same-family/barangay phones show it in the Alerts feed + a red banner +
  a system notification. Sender sees "waiting for help…".

## Definition of Done
- [ ] 2 phones, same code: hold SOS on A → B gets a loud alert with type +
      location, **data OFF**.

## Notes / next
- SOS currently reaches **same-family/barangay** (family code). Officials
  share the barangay code.
- Next sprints: **roles + Emergency Broadcast** (S5), **Firebase sync +
  Barangay dashboard** (S6), **SMS fallback** (S7).
- Delivery receipt ("received by X") is a stub ("waiting for help") — real
  ACK comes with the dashboard/roles.
