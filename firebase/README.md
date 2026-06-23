# Nest Link — Firebase

Shared backend that aligns the mobile app and the web app. Holds **Auth**, **Firestore**, **Storage**, **Hosting**.

> Not started yet — set up in **Sprint 4**. See [`../docs/PLAN.md`](../docs/PLAN.md).

## Planned contents
- `firestore.rules` — security rules (family-scoped access)
- `firestore.indexes.json` — composite indexes
- `firebase.json` — hosting + emulator config
- (optional) Cloud Functions for mesh ↔ cloud reconciliation

## Firestore shape (see PLAN.md §5)
```
families/{familyId}/{members, packets, statuses, locations, checklist}
```
