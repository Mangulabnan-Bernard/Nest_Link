import 'package:flutter/material.dart';
import 'theme.dart';

/// ── Mock domain models (UI-only for now; real data arrives in later sprints) ──

enum MemberRole { parent, child }

class FamilyMember {
  final String id;
  final String name;
  final MemberRole role;
  final String initials;
  final Color color;
  final double distanceM; // metres from the Home Nest
  final double bearing; // radians around the radar
  final bool online; // has internet right now
  final bool viaMesh; // currently reachable only over the mesh
  final String status; // Safe Flight status label
  final String lastSeen;

  const FamilyMember({
    required this.id,
    required this.name,
    required this.role,
    required this.initials,
    required this.color,
    required this.distanceM,
    required this.bearing,
    required this.online,
    required this.viaMesh,
    required this.status,
    required this.lastSeen,
  });
}

class ChirpMessage {
  final String fromId; // 'me' for self
  final String text;
  final String time;
  final bool viaMesh; // delivered purely over the offline mesh
  final bool isVoice;
  final int? voiceSeconds;

  const ChirpMessage({
    required this.fromId,
    required this.text,
    required this.time,
    this.viaMesh = false,
    this.isVoice = false,
    this.voiceSeconds,
  });
}

class Conversation {
  final String id;
  final String title;
  final String? memberId; // null = family broadcast
  final IconData icon;
  final String preview;
  final String time;
  final int unread;
  final bool lastViaMesh;
  final List<ChirpMessage> messages;

  const Conversation({
    required this.id,
    required this.title,
    required this.memberId,
    required this.icon,
    required this.preview,
    required this.time,
    required this.unread,
    required this.lastViaMesh,
    required this.messages,
  });
}

class ChecklistItem {
  final String text;
  final bool checked;
  final String by;
  const ChecklistItem(this.text, this.checked, this.by);
}

class StatusOption {
  final String label;
  final IconData icon;
  final Color color;
  const StatusOption(this.label, this.icon, this.color);
}

/// ── Mock data ────────────────────────────────────────────────────────────

const meId = 'me';

const family = <FamilyMember>[
  FamilyMember(
    id: 'me',
    name: 'You',
    role: MemberRole.parent,
    initials: 'ME',
    color: Brand.emerald,
    distanceM: 0,
    bearing: 0,
    online: true,
    viaMesh: false,
    status: "I'm Safe",
    lastSeen: 'now',
  ),
  FamilyMember(
    id: 'kuya',
    name: 'Kuya',
    role: MemberRole.child,
    initials: 'KU',
    color: Brand.teal,
    distanceM: 150,
    bearing: 0.7,
    online: false,
    viaMesh: true,
    status: 'Heading Home',
    lastSeen: '2 min ago',
  ),
  FamilyMember(
    id: 'ate',
    name: 'Ate',
    role: MemberRole.child,
    initials: 'AT',
    color: Brand.amber,
    distanceM: 60,
    bearing: 2.4,
    online: true,
    viaMesh: false,
    status: 'At School',
    lastSeen: '5 min ago',
  ),
  FamilyMember(
    id: 'nanay',
    name: 'Nanay',
    role: MemberRole.parent,
    initials: 'NA',
    color: Brand.coral,
    distanceM: 320,
    bearing: 4.1,
    online: false,
    viaMesh: true,
    status: 'Stuck in Traffic',
    lastSeen: '12 min ago',
  ),
];

FamilyMember memberById(String id) =>
    family.firstWhere((m) => m.id == id, orElse: () => family.first);

final conversations = <Conversation>[
  Conversation(
    id: 'fam',
    title: 'Family Nest',
    memberId: null,
    icon: Icons.diversity_3,
    preview: 'Nanay: Stuck in traffic, be home soon',
    time: '12m',
    unread: 2,
    lastViaMesh: true,
    messages: const [
      ChirpMessage(fromId: 'ate', text: 'Dismissed na, waiting for sundo', time: '3:01 PM'),
      ChirpMessage(fromId: 'me', text: 'On my way, anak', time: '3:02 PM'),
      ChirpMessage(
          fromId: 'nanay',
          text: 'Stuck in traffic, be home soon',
          time: '3:14 PM',
          viaMesh: true),
    ],
  ),
  Conversation(
    id: 'kuya',
    title: 'Kuya',
    memberId: 'kuya',
    icon: Icons.person,
    preview: 'Voice chirp · 0:07',
    time: '2m',
    unread: 1,
    lastViaMesh: true,
    messages: const [
      ChirpMessage(fromId: 'me', text: 'Where are you?', time: '3:10 PM'),
      ChirpMessage(
          fromId: 'kuya',
          text: 'Walking home, malapit na',
          time: '3:12 PM',
          viaMesh: true),
      ChirpMessage(
          fromId: 'kuya',
          text: '',
          time: '3:13 PM',
          viaMesh: true,
          isVoice: true,
          voiceSeconds: 7),
    ],
  ),
  Conversation(
    id: 'ate',
    title: 'Ate',
    memberId: 'ate',
    icon: Icons.person,
    preview: 'At School ✓',
    time: '5m',
    unread: 0,
    lastViaMesh: false,
    messages: const [
      ChirpMessage(fromId: 'ate', text: 'Nasa school pa ako', time: '2:40 PM'),
      ChirpMessage(fromId: 'me', text: 'Okay, ingat', time: '2:41 PM'),
    ],
  ),
];

const statusOptions = <StatusOption>[
  StatusOption("I'm Safe", Icons.verified_user, Brand.emerald),
  StatusOption('At School', Icons.school, Brand.teal),
  StatusOption('Heading Home', Icons.directions_walk, Brand.amber),
  StatusOption('Stuck in Traffic', Icons.traffic, Brand.coral),
];

const checklist = <ChecklistItem>[
  ChecklistItem('Rice (5kg)', true, 'Nanay'),
  ChecklistItem('Drinking water', true, 'You'),
  ChecklistItem('Flashlight + batteries', false, 'Kuya'),
  ChecklistItem('Power bank charged', false, 'Ate'),
  ChecklistItem('First-aid kit', true, 'Nanay'),
  ChecklistItem('Canned goods', false, 'You'),
];
