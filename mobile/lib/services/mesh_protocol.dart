import 'dart:convert';

/// Nest Link rides several message kinds over the engine's single TEXT bundle
/// type by JSON-encoding a small envelope. Every envelope carries the sender's
/// family code ("f") so phones only show their own family's traffic.
/// Unparseable payloads are treated as plain chat text (backward-compatible).
enum MeshKind { chat, voice, status, location, ping, unknown }

class MeshEnvelope {
  final MeshKind kind;
  final String familyCode; // which family this belongs to
  final String senderName; // sender's chosen display name
  final String text; // chat body
  final String audioB64; // voice clip (base64)
  final String status; // Safe Flight status label
  final double? lat;
  final double? lng;

  const MeshEnvelope({
    required this.kind,
    this.familyCode = '',
    this.senderName = '',
    this.text = '',
    this.audioB64 = '',
    this.status = '',
    this.lat,
    this.lng,
  });

  static String chat(String family, String senderName, String text) =>
      jsonEncode({'f': family, 'k': 'chat', 'n': senderName, 't': text});

  static String voice(String family, String senderName, String base64Audio) =>
      jsonEncode({'f': family, 'k': 'voice', 'n': senderName, 'a': base64Audio});

  static String statusUpdate(String family, String senderName, String status) =>
      jsonEncode({'f': family, 'k': 'status', 'n': senderName, 's': status});

  static String location(String family, String senderName, double lat, double lng) =>
      jsonEncode({'f': family, 'k': 'loc', 'n': senderName, 'lat': lat, 'lng': lng});

  /// Lightweight "I'm here" heartbeat — keeps presence fresh without needing GPS.
  static String ping(String family, String senderName) =>
      jsonEncode({'f': family, 'k': 'ping', 'n': senderName});

  /// Decode a payload. Falls back to a chat envelope for raw / legacy text.
  static MeshEnvelope decode(String raw) {
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return MeshEnvelope(kind: MeshKind.chat, text: raw);
      final family = m['f']?.toString() ?? '';
      final name = m['n']?.toString() ?? '';
      switch (m['k']) {
        case 'chat':
          return MeshEnvelope(
              kind: MeshKind.chat, familyCode: family, senderName: name, text: m['t']?.toString() ?? '');
        case 'voice':
          return MeshEnvelope(
              kind: MeshKind.voice, familyCode: family, senderName: name, audioB64: m['a']?.toString() ?? '');
        case 'status':
          return MeshEnvelope(
              kind: MeshKind.status, familyCode: family, senderName: name, status: m['s']?.toString() ?? '');
        case 'loc':
          return MeshEnvelope(
            kind: MeshKind.location,
            familyCode: family,
            senderName: name,
            lat: (m['lat'] as num?)?.toDouble(),
            lng: (m['lng'] as num?)?.toDouble(),
          );
        case 'ping':
          return MeshEnvelope(kind: MeshKind.ping, familyCode: family, senderName: name);
        default:
          return MeshEnvelope(kind: MeshKind.unknown, familyCode: family, senderName: name);
      }
    } catch (_) {
      // Not JSON — a raw text chirp (e.g. from the legacy Live sender).
      return MeshEnvelope(kind: MeshKind.chat, text: raw);
    }
  }
}
