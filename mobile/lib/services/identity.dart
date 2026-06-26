import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores who you are, your family code, and maps mesh EIDs to friendly names.
/// (Local only for now; Firebase-backed family accounts arrive in Sprint 4.)
class Identity extends ChangeNotifier {
  Identity._();
  static final Identity instance = Identity._();

  static const _kName = 'profile_name';
  static const _kRole = 'profile_role';
  static const _kFamily = 'family_code';
  static const _kRegistryPrefix = 'eid_name_';

  SharedPreferences? _prefs;
  String? _name;
  String _role = 'parent';
  String? _familyCode;
  final Map<String, String> _registry = {}; // eid -> name

  String? get name => _name;
  String get role => _role;
  String? get familyCode => _familyCode;

  /// Setup is complete only when we know who you are AND which family you're in.
  bool get isSetUp => (_name ?? '').isNotEmpty && (_familyCode ?? '').isNotEmpty;

  Future<void> load() async {
    final p = _prefs = await SharedPreferences.getInstance();
    _name = p.getString(_kName);
    _role = p.getString(_kRole) ?? 'parent';
    _familyCode = p.getString(_kFamily);
    for (final key in p.getKeys()) {
      if (key.startsWith(_kRegistryPrefix)) {
        _registry[key.substring(_kRegistryPrefix.length)] = p.getString(key) ?? '';
      }
    }
    notifyListeners();
  }

  Future<void> setProfile(String name, String role) async {
    _name = name.trim();
    _role = role;
    await _prefs?.setString(_kName, _name!);
    await _prefs?.setString(_kRole, role);
    notifyListeners();
  }

  /// Create a brand-new family and return its shareable code (e.g. NEST-7XK2).
  Future<String> createFamily() async {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random();
    final code = 'NEST-${List.generate(4, (_) => chars[r.nextInt(chars.length)]).join()}';
    await _setFamily(code);
    return code;
  }

  /// Join an existing family by its code. Normalizes to NEST-XXXX form.
  Future<void> joinFamily(String raw) async {
    var c = raw.trim().toUpperCase().replaceAll(' ', '');
    if (c.isEmpty) return;
    if (!c.startsWith('NEST-')) c = 'NEST-$c';
    await _setFamily(c);
  }

  Future<void> _setFamily(String code) async {
    _familyCode = code;
    await _prefs?.setString(_kFamily, code);
    notifyListeners();
  }

  /// Friendly name for an EID — falls back to a short "Nestling-XXXX" label.
  String nameForEid(String eid) {
    if (eid == 'me') return _name ?? 'You';
    final mapped = _registry[eid];
    if (mapped != null && mapped.isNotEmpty) return mapped;
    final short = eid.length > 4 ? eid.substring(eid.length - 4) : eid;
    return 'Nestling-$short';
  }

  bool isKnown(String eid) => _registry.containsKey(eid);

  Future<void> rename(String eid, String name) async {
    _registry[eid] = name.trim();
    await _prefs?.setString('$_kRegistryPrefix$eid', name.trim());
    notifyListeners();
  }
}
