import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'mesh_protocol.dart';
import 'identity.dart';

/// A chat message shown in Family Nest / Live.
class MeshMessage {
  final String id;
  final String sourceEid; // 'me' for locally-sent
  final String senderName;
  final String text;
  final int hopCount;
  final bool viaMesh; // received over the mesh (vs. locally echoed)

  const MeshMessage({
    required this.id,
    required this.sourceEid,
    required this.senderName,
    required this.text,
    required this.hopCount,
    required this.viaMesh,
  });
}

/// Live presence/status of a family member seen over the mesh.
class MemberPresence {
  final String eid;
  String name;
  String status;
  int lastSeenMs;
  double? lat;
  double? lng;
  MemberPresence({
    required this.eid,
    required this.name,
    required this.status,
    required this.lastSeenMs,
    this.lat,
    this.lng,
  });
  bool get hasLocation => lat != null && lng != null;
}

/// Single source of truth for the dtn-mesh engine, wrapping the platform
/// channel. Decodes the [MeshEnvelope] and maintains chat + presence state.
class MeshService extends ChangeNotifier {
  MeshService._();
  static final MeshService instance = MeshService._();

  static const _method = MethodChannel('nestlink/mesh');
  static const _events = EventChannel('nestlink/mesh/events');

  bool _running = false;
  String? _eid;
  StreamSubscription? _sub;
  Timer? _locTimer;
  Timer? _pingTimer;
  Timer? _refreshTimer;
  SharedPreferences? _prefs;
  static const _kHistory = 'chat_history';

  final _messages = <MeshMessage>[]; // chat only
  final _presence = <String, MemberPresence>{}; // eid -> presence

  bool get running => _running;
  String? get eid => _eid;
  List<MeshMessage> get messages => List.unmodifiable(_messages);
  List<MemberPresence> get presence => _presence.values.toList();
  bool get hasPresence => _presence.isNotEmpty;

  Future<void> start() async {
    if (_running) return;
    await [
      Permission.locationWhenInUse,
      Permission.nearbyWifiDevices,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.microphone,
      Permission.notification,
    ].request();

    await _method.invokeMethod('start');
    _running = true;
    _sub ??= _events.receiveBroadcastStream().listen(_onEvent);

    // Tell the native service my family code so notifications only fire for my family.
    try {
      await _method.invokeMethod('setFamilyCode', {'code': Identity.instance.familyCode ?? ''});
    } catch (_) {}

    // Broadcast my GPS to the family every 20s so they appear on each other's map.
    _locTimer ??= Timer.periodic(const Duration(seconds: 20), (_) => _broadcastLocation());
    _broadcastLocation();

    // Lightweight heartbeat every 12s so we reliably know who's still reachable.
    _pingTimer ??= Timer.periodic(const Duration(seconds: 12), (_) => _sendPing());
    _sendPing();

    // Tick the UI every 5s so signal/age indicators update even with no packets.
    _refreshTimer ??= Timer.periodic(const Duration(seconds: 5), (_) => notifyListeners());

    for (var i = 0; i < 12; i++) {
      await Future.delayed(const Duration(milliseconds: 250));
      final eid = await _method.invokeMethod<String>('getLocalEid').catchError((_) => null);
      if (eid != null) {
        _eid = eid;
        break;
      }
    }
    notifyListeners();
  }

  /// Re-send my (possibly changed) family code to the native engine.
  Future<void> syncFamilyCode() async {
    try {
      await _method.invokeMethod('setFamilyCode', {'code': Identity.instance.familyCode ?? ''});
    } catch (_) {}
    notifyListeners();
  }

  Future<void> stop() async {
    if (!_running) return;
    _locTimer?.cancel();
    _locTimer = null;
    _pingTimer?.cancel();
    _pingTimer = null;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    await _method.invokeMethod('stop');
    _running = false;
    _eid = null;
    notifyListeners();
  }

  /// Read my GPS and broadcast it over the mesh (best-effort).
  Future<void> _broadcastLocation() async {
    if (!_running) return;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition();
      final name = Identity.instance.name ?? 'You';
      final family = Identity.instance.familyCode ?? '';
      final payload = MeshEnvelope.location(family, name, pos.latitude, pos.longitude);
      await _method.invokeMethod('sendText', {'text': payload, 'destEid': 'broadcast'});
    } catch (_) {
      // location unavailable — skip this round
    }
  }

  void _onEvent(dynamic event) {
    final m = event as Map;
    final sourceEid = m['sourceEid']?.toString() ?? '';
    final hops = (m['hopCount'] as num?)?.toInt() ?? 0;
    final env = MeshEnvelope.decode(m['text']?.toString() ?? '');

    // Privacy: ignore traffic that isn't from my family (the phone still relays
    // it for others, it just won't be shown here).
    final myFamily = Identity.instance.familyCode ?? '';
    if (env.familyCode.isNotEmpty && myFamily.isNotEmpty && env.familyCode != myFamily) {
      return;
    }

    // learn the sender's name from the envelope (registry rename still wins)
    if (env.senderName.isNotEmpty && !Identity.instance.isKnown(sourceEid)) {
      _touchPresence(sourceEid, env.senderName, null);
    }

    switch (env.kind) {
      case MeshKind.chat:
        // Guard: never show an empty/garbled chat bubble (e.g. a stray packet
        // from a mismatched build, or a non-chat payload).
        if (env.text.trim().isEmpty) break;
        _messages.add(MeshMessage(
          id: m['id']?.toString() ?? '',
          sourceEid: sourceEid,
          senderName: _displayName(sourceEid, env.senderName),
          text: env.text,
          hopCount: hops,
          viaMesh: true,
        ));
        _saveHistory();
        break;
      case MeshKind.status:
        _touchPresence(sourceEid, env.senderName, env.status);
        break;
      case MeshKind.location:
        _touchPresence(sourceEid, env.senderName, null);
        if (env.lat != null && env.lng != null) {
          final p = _presence[sourceEid];
          p?.lat = env.lat;
          p?.lng = env.lng;
        }
        break;
      case MeshKind.ping:
      case MeshKind.unknown:
        _touchPresence(sourceEid, env.senderName, null);
        break;
    }
    notifyListeners();
  }

  String _displayName(String eid, String fromPayload) {
    if (Identity.instance.isKnown(eid)) return Identity.instance.nameForEid(eid);
    if (fromPayload.isNotEmpty) return fromPayload;
    return Identity.instance.nameForEid(eid);
  }

  void _touchPresence(String eid, String name, String? status) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = _presence[eid];
    if (existing == null) {
      _presence[eid] = MemberPresence(
        eid: eid,
        name: name.isNotEmpty ? name : Identity.instance.nameForEid(eid),
        status: status ?? '—',
        lastSeenMs: now,
      );
    } else {
      if (name.isNotEmpty) existing.name = name;
      if (status != null) existing.status = status;
      existing.lastSeenMs = now;
    }
  }

  /// Send a chat chirp (Family Nest broadcast). Shows instantly (optimistic),
  /// then hands the payload to the mesh engine.
  Future<void> sendChat(String text) async {
    if (!_running || text.trim().isEmpty) return;
    final name = Identity.instance.name ?? 'You';

    // optimistic: show my bubble immediately
    _messages.add(MeshMessage(
      id: 'local-${DateTime.now().millisecondsSinceEpoch}',
      sourceEid: 'me',
      senderName: name,
      text: text,
      hopCount: 0,
      viaMesh: false,
    ));
    _saveHistory();
    notifyListeners();

    final family = Identity.instance.familyCode ?? '';
    final payload = MeshEnvelope.chat(family, name, text);
    try {
      await _method.invokeMethod('sendText', {'text': payload, 'destEid': 'broadcast'});
    } catch (_) {
      // engine not ready — bubble already shown; it will resend on next contact
    }
  }

  /// Reload saved chat history so a restart doesn't wipe the conversation.
  Future<void> loadHistory() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs?.getStringList(_kHistory) ?? [];
    for (final s in raw) {
      try {
        final m = jsonDecode(s) as Map;
        final text = m['t']?.toString() ?? '';
        if (text.trim().isEmpty) continue; // drop old blank/garbled entries
        _messages.add(MeshMessage(
          id: m['id']?.toString() ?? '',
          sourceEid: m['s']?.toString() ?? '',
          senderName: m['n']?.toString() ?? '',
          text: text,
          hopCount: 0,
          viaMesh: m['v'] == true,
        ));
      } catch (_) {}
    }
    _saveHistory(); // persist the cleaned list
    if (_messages.isNotEmpty) notifyListeners();
  }

  void _saveHistory() {
    final start = _messages.length > 200 ? _messages.length - 200 : 0;
    final raw = _messages.sublist(start).map((m) => jsonEncode({
          'id': m.id,
          's': m.sourceEid,
          'n': m.senderName,
          't': m.text,
          'v': m.viaMesh,
        })).toList();
    _prefs?.setStringList(_kHistory, raw);
  }

  /// Broadcast a tiny heartbeat so the family knows I'm still reachable.
  Future<void> _sendPing() async {
    if (!_running) return;
    final name = Identity.instance.name ?? 'You';
    final family = Identity.instance.familyCode ?? '';
    try {
      await _method.invokeMethod('sendText', {'text': MeshEnvelope.ping(family, name), 'destEid': 'broadcast'});
    } catch (_) {}
  }

  /// Signal quality for a family member, from how recently we last heard them.
  /// 'strong' (<25s) · 'weak' (<55s) · 'lost' (older).
  static String qualityOf(MemberPresence p) {
    final age = DateTime.now().millisecondsSinceEpoch - p.lastSeenMs;
    if (age < 25000) return 'strong';
    if (age < 55000) return 'weak';
    return 'lost';
  }

  /// Members we currently consider reachable (heard within the last ~55s).
  List<MemberPresence> get reachable =>
      _presence.values.where((p) => qualityOf(p) != 'lost').toList();

  /// Broadcast my Safe Flight status to the family.
  Future<void> sendStatus(String status) async {
    if (!_running) return;
    final name = Identity.instance.name ?? 'You';
    final family = Identity.instance.familyCode ?? '';
    final payload = MeshEnvelope.statusUpdate(family, name, status);
    await _method.invokeMethod('sendText', {'text': payload, 'destEid': 'broadcast'});
  }

  @override
  void dispose() {
    _sub?.cancel();
    _locTimer?.cancel();
    _pingTimer?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }
}
