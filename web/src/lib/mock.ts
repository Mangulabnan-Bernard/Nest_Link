// UI-only mock data for the web showcase + dashboard (wires to Firebase in Sprint 4).

export type Member = {
  id: string;
  name: string;
  role: "parent" | "child";
  initials: string;
  color: string;
  distanceM: number;
  bearing: number; // radians around the radar
  online: boolean;
  viaMesh: boolean;
  status: string;
  lastSeen: string;
};

export const family: Member[] = [
  { id: "kuya", name: "Kuya", role: "child", initials: "KU", color: "#1abc9c", distanceM: 150, bearing: 0.7, online: false, viaMesh: true, status: "Heading Home", lastSeen: "2 min ago" },
  { id: "ate", name: "Ate", role: "child", initials: "AT", color: "#f1c40f", distanceM: 60, bearing: 2.4, online: true, viaMesh: false, status: "At School", lastSeen: "5 min ago" },
  { id: "nanay", name: "Nanay", role: "parent", initials: "NA", color: "#ff6b6b", distanceM: 320, bearing: 4.1, online: false, viaMesh: true, status: "Stuck in Traffic", lastSeen: "12 min ago" },
];

export type Chirp = { from: string; text: string; time: string; viaMesh: boolean };

export const recentChirps: Chirp[] = [
  { from: "Nanay", text: "Stuck in traffic, be home soon", time: "3:14 PM", viaMesh: true },
  { from: "Kuya", text: "Walking home, malapit na", time: "3:12 PM", viaMesh: true },
  { from: "Ate", text: "Dismissed na, waiting for sundo", time: "3:01 PM", viaMesh: false },
  { from: "You", text: "On my way, anak", time: "3:02 PM", viaMesh: false },
];

export type Check = { text: string; done: boolean; by: string };

export const checklist: Check[] = [
  { text: "Rice (5kg)", done: true, by: "Nanay" },
  { text: "Drinking water", done: true, by: "You" },
  { text: "Flashlight + batteries", done: false, by: "Kuya" },
  { text: "Power bank charged", done: false, by: "Ate" },
  { text: "First-aid kit", done: true, by: "Nanay" },
];

export const features = [
  {
    key: "nest-mat",
    name: "Nest Mat",
    tag: "Offline radar",
    desc: "A live GPS map online — and a beautiful proximity radar offline. See how far each family member is, even with no signal.",
    icon: "📡",
  },
  {
    key: "chirp-chat",
    name: "Chirp Chat",
    tag: "Mesh messaging",
    desc: "Text and voice 'Chirps' that hop phone-to-phone. If towers are down, your message rides home on a passing family member's phone.",
    icon: "💬",
  },
  {
    key: "safe-flight",
    name: "Safe Flight",
    tag: "Status & checklists",
    desc: "One-tap check-ins — 'At School', 'Heading Home' — plus a shared survival checklist that syncs across the family.",
    icon: "🛡️",
  },
];

export const techBadges = [
  "Delay-Tolerant Networking",
  "AES-256-GCM",
  "ECDH P-256",
  "Wi-Fi Direct + Bluetooth",
  "PRoPHET routing",
  "Store-carry-forward",
];
