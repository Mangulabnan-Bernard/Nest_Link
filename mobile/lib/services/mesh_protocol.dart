import 'dart:convert';

/// Nest Link rides several message kinds over the engine's single TEXT bundle
/// type by JSON-encoding a small envelope. Unparseable payloads are treated as
/// plain chat text (backward-compatible with raw sends).
enum MeshKind { chat, status, location, unknown }

class MeshEnvelope {
  final MeshKind kind;
  final String senderName; // sender's chosen display name
  final String text; // chat body
  final String status; // Safe Flight status label
  final double? lat;
  final double? lng;

  const MeshEnvelope({
    required this.kind,
    this.senderName = '',
    this.text = '',
    this.status = '',
    this.lat,
    this.lng,
  });

  static String chat(String senderName, String text) =>
      jsonEncode({'k': 'chat', 'n': senderName, 't': text});

  static String statusUpdate(String senderName, String status) =>
      jsonEncode({'k': 'status', 'n': senderName, 's': status});

  static String location(String senderName, double lat, double lng) =>
      jsonEncode({'k': 'loc', 'n': senderName, 'lat': lat, 'lng': lng});

  /// Decode a payload. Falls back to a chat envelope for raw / legacy text.
  static MeshEnvelope decode(String raw) {
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return MeshEnvelope(kind: MeshKind.chat, text: raw);
      final name = m['n']?.toString() ?? '';
      switch (m['k']) {
        case 'chat':
          return MeshEnvelope(kind: MeshKind.chat, senderName: name, text: m['t']?.toString() ?? '');
        case 'status':
          return MeshEnvelope(kind: MeshKind.status, senderName: name, status: m['s']?.toString() ?? '');
        case 'loc':
          return MeshEnvelope(
            kind: MeshKind.location,
            senderName: name,
            lat: (m['lat'] as num?)?.toDouble(),
            lng: (m['lng'] as num?)?.toDouble(),
          );
        default:
          return MeshEnvelope(kind: MeshKind.unknown, senderName: name);
      }
    } catch (_) {
      // Not JSON — a raw text chirp (e.g. from the legacy Live sender).
      return MeshEnvelope(kind: MeshKind.chat, text: raw);
    }
  }
}
