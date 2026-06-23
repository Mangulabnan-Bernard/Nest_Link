# Nest Link

A family-first communication & safety system that keeps families connected **even with no internet** — using an offline phone-to-phone mesh (Delay-Tolerant Networking) that syncs to the cloud whenever a signal is available.

## Monorepo layout

| Folder | What it is | Stack |
|---|---|---|
| `mobile/` | The Nest Link mobile app | Flutter UI + native Android DTN mesh engine |
| `web/` | Showcase landing page + parent dashboard | Next.js + TypeScript + Tailwind |
| `firebase/` | Shared backend (online sync + web data) | Firebase: Auth, Firestore, Storage, Hosting |
| `reference/dtn-mesh` | Upstream mesh engine we build on (MIT) | Kotlin / Android — read-only reference |
| `docs/` | Plan, sprint docs, diagrams | Markdown |

## The three features
- **Chirp Chat** — encrypted family messaging (text + voice "Chirps") that hops device-to-device offline.
- **Nest Mat** — online GPS map / offline proximity radar of family members.
- **Safe Flight** — one-tap status check-ins ("At School", "Heading Home") + shared family checklist.

## How it works in one picture
```
MOBILE (Android)                                WEB (Next.js)
 Flutter UI                                       Showcase + Dashboard
   │ platform channel                                   │
 dtn-mesh ENGINE  ──── online sync ────▶  FIREBASE  ◀───┘
 (PRoPHET routing, ECDH+AES crypto,        (Auth, Firestore,
  Wi-Fi Direct + Bluetooth)                 Storage, Hosting)
```

Offline → phones relay messages to each other (store-carry-forward).
Online → a phone "meets" the cloud, syncs up, and the web dashboard catches up.

See [`docs/PLAN.md`](docs/PLAN.md) for the full blueprint and [`docs/SPRINT-1.md`](docs/SPRINT-1.md) for the current sprint.
