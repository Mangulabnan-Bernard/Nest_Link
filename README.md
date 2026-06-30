# Nest Link

A communication & safety platform that keeps people connected **even with no internet** — using offline device-to-device networking that syncs to the cloud whenever a signal is available.

## Monorepo layout

| Folder | What it is | Stack |
|---|---|---|
| `mobile/` | The Nest Link mobile app | Flutter + native Android |
| `web/` | Showcase landing page + dashboard | Next.js + TypeScript + Tailwind |
| `firebase/` | Shared backend (online sync + web data) | Firebase: Auth, Firestore, Storage, Hosting |
| `docs/` | Plan, sprint docs, diagrams | Markdown |

## Core features
- **Chirp Chat** — end-to-end encrypted messaging (text + voice) that works device-to-device offline.
- **Nest Mat** — online GPS map / offline proximity radar.
- **Safe Flight** — one-tap status check-ins + a shared checklist.

## How it works
- **Offline** → nearby devices relay messages for one another until they reach the recipient.
- **Online** → a device syncs to the cloud, and the web dashboard catches up.

```
MOBILE (Android)              WEB (Next.js)
 Flutter UI                    Showcase + Dashboard
   │                                │
 offline engine ── sync ──▶  FIREBASE  ◀──┘
```

See [`docs/PLAN.md`](docs/PLAN.md) for the blueprint.
