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
  final String destEid; // 'broadcast' (Family Nest) or a peer EID (private)
  final String? audioB64; // set when this is a voice message (this session)
  final int hopCount;
  final bool viaMesh; // received over the mesh (vs. locally echoed)

  bool get isVoice => audioB64 != null || text == '🎙️ Voice message';

  const MeshMessage({
    required this.id,
    required this.sourceEid,
    required this.senderName,
    required this.text,
    this.destEid = 'broadcast',
    this.audioB64,
    required this.hopCount,
    required this.viaMesh,
  });
}

/// Live presence/status of a person seen over the mesh.
class MemberPresence {
  final String eid;
  String name;
  String status;
  String familyCode; // which family they belong to (for the discover list)
  int lastSeenMs;
  double? lat;
  double? lng;
  MemberPresence({
    required this.eid,
    required this.name,
    required this.status,
    required this.lastSeenMs,
    this.familyCode = '',
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

  // Live radio-level diagnostic (from the engine).
  bool _wifiConnected = false;
  int _discoveredPeers = 0;
  bool get wifiConnected => _wifiConnected;
  int get discoveredPeers => _discoveredPeers;

  final _messages = <MeshMessage>[]; // chat only
  final _presence = <String, MemberPresence>{}; // eid -> presence

  bool get running => _running;
  String? get eid => _eid;
  List<MeshMessage> get messages => List.unmodifiable(_messages);
  List<MemberPresence> get presence => _presence.values.toList();
  bool get hasPresence => _presence.isNotEmpty;

  /// Family Nest (group) messages.
  List<MeshMessage> get broadcastMessages =>
      _messages.where((m) => m.destEid == 'broadcast').toList();

  /// Private 1-on-1 thread with a specific peer.
  List<MeshMessage> directMessagesWith(String peerEid) => _messages
      .where((m) =>
          (m.sourceEid == peerEid && m.destEid == _eid) ||
          (m.sourceEid == 'me' && m.destEid == peerEid))
      .toList();

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

    // Tick every 5s: refresh signal/age indicators + poll the radio diagnostic.
    _refreshTimer ??= Timer.periodic(const Duration(seconds: 5), (_) => _poll());

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

  /// Poll the engine for the radio-level connection state + refresh the UI.
  Future<void> _poll() async {
    try {
      final s = await _method.invokeMethod('getMeshStatus');
      if (s is Map) {
        _wifiConnected = s['wifiConnected'] == true;
        _discoveredPeers = (s['discoveredPeers'] as num?)?.toInt() ?? 0;
      }
    } catch (_) {}
    notifyListeners();
  }

  /// Force a fresh nearby scan (Wi-Fi Direct + Bluetooth discovery).
  Future<void> rescan() async {
    if (!_running) {
      await start();
      return;
    }
    try {
      await _method.invokeMethod('rescan');
    } catch (_) {}
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

    final myFamily = Identity.instance.familyCode ?? '';
    final sameFamily = env.familyCode.isEmpty || myFamily.isEmpty || env.familyCode == myFamily;
    final destEid = m['destEid']?.toString() ?? 'broadcast';
    final toBroadcast = destEid == 'broadcast';
    final toMe = destEid == _eid;

    // Always track presence so EVERYONE nearby (any family) is discoverable.
    _touchPresence(sourceEid, env.senderName, null, env.familyCode);

    switch (env.kind) {
      case MeshKind.chat:
        if (env.text.trim().isEmpty) break;
        if (toBroadcast && !sameFamily) break; // group chat is family-private
        if (!toBroadcast && !toMe) break; // a private message not addressed to me
        _messages.add(MeshMessage(
          id: m['id']?.toString() ?? '',
          sourceEid: sourceEid,
          senderName: _displayName(sourceEid, env.senderName),
          text: env.text,
          destEid: destEid,
          hopCount: hops,
          viaMesh: true,
        ));
        _saveHistory();
        break;
      case MeshKind.voice:
        if (env.audioB64.isEmpty) break;
        if (toBroadcast && !sameFamily) break;
        if (!toBroadcast && !toMe) break;
        _messages.add(MeshMessage(
          id: m['id']?.toString() ?? '',
          sourceEid: sourceEid,
          senderName: _displayName(sourceEid, env.senderName),
          text: '🎙️ Voice message',
          destEid: destEid,
          audioB64: env.audioB64,
          hopCount: hops,
          viaMesh: true,
        ));
        _saveHistory();
        break;
      case MeshKind.status:
        // status/location are only shared within your own family (privacy)
        if (sameFamily) _touchPresence(sourceEid, env.senderName, env.status, env.familyCode);
        break;
      case MeshKind.location:
        if (sameFamily && env.lat != null && env.lng != null) {
          final p = _presence[sourceEid];
          p?.lat = env.lat;
          p?.lng = env.lng;
        }
        break;
      case MeshKind.ping:
      case MeshKind.unknown:
        break; // presence already tracked above
    }
    notifyListeners();
  }

  String _displayName(String eid, String fromPayload) {
    if (Identity.instance.isKnown(eid)) return Identity.instance.nameForEid(eid);
    if (fromPayload.isNotEmpty) return fromPayload;
    return Identity.instance.nameForEid(eid);
  }

  void _touchPresence(String eid, String name, String? status, String familyCode) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = _presence[eid];
    if (existing == null) {
      _presence[eid] = MemberPresence(
        eid: eid,
        name: name.isNotEmpty ? name : Identity.instance.nameForEid(eid),
        status: status ?? '—',
        familyCode: familyCode,
        lastSeenMs: now,
      );
    } else {
      if (name.isNotEmpty) existing.name = name;
      if (status != null) existing.status = status;
      if (familyCode.isNotEmpty) existing.familyCode = familyCode;
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
      destEid: 'broadcast',
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

  /// Send a voice clip (base64) — to the family (broadcast) or one peer.
  Future<void> sendVoice(String base64Audio, {String destEid = 'broadcast'}) async {
    if (!_running || base64Audio.isEmpty) return;
    final name = Identity.instance.name ?? 'You';
    final family = Identity.instance.familyCode ?? '';
    _messages.add(MeshMessage(
      id: 'local-${DateTime.now().millisecondsSinceEpoch}',
      sourceEid: 'me',
      senderName: name,
      text: '🎙️ Voice message',
      destEid: destEid,
      audioB64: base64Audio,
      hopCount: 0,
      viaMesh: false,
    ));
    _saveHistory();
    notifyListeners();
    final payload = MeshEnvelope.voice(family, name, base64Audio);
    try {
      await _method.invokeMethod('sendText', {'text': payload, 'destEid': destEid});
    } catch (_) {}
  }

  /// Send a private chat directly to one peer (1-on-1, not the whole family).
  Future<void> sendChatTo(String peerEid, String text) async {
    if (!_running || text.trim().isEmpty) return;
    final name = Identity.instance.name ?? 'You';

    _messages.add(MeshMessage(
      id: 'local-${DateTime.now().millisecondsSinceEpoch}',
      sourceEid: 'me',
      senderName: name,
      text: text,
      destEid: peerEid,
      hopCount: 0,
      viaMesh: false,
    ));
    _saveHistory();
    notifyListeners();

    final family = Identity.instance.familyCode ?? '';
    final payload = MeshEnvelope.chat(family, name, text);
    try {
      await _method.invokeMethod('sendText', {'text': payload, 'destEid': peerEid});
    } catch (_) {}
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
          destEid: m['d']?.toString() ?? 'broadcast',
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
          'd': m.destEid,
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

  /// Everyone reachable on the mesh right now (any family), for discovery.
  List<MemberPresence> get reachable =>
      _presence.values.where((p) => qualityOf(p) != 'lost').toList();

  /// Reachable people in MY family (same code, or code-less).
  List<MemberPresence> get familyReachable {
    final my = Identity.instance.familyCode ?? '';
    return reachable
        .where((p) => p.familyCode.isEmpty || my.isEmpty || p.familyCode == my)
        .toList();
  }

  /// Reachable people in OTHER families — shown in the "discover nearby" list.
  List<MemberPresence> get othersReachable {
    final my = Identity.instance.familyCode ?? '';
    if (my.isEmpty) return const [];
    return reachable.where((p) => p.familyCode.isNotEmpty && p.familyCode != my).toList();
  }

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
