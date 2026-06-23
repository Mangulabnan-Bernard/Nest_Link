import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores who you are + maps mesh EIDs to friendly family names.
/// (Local only for now; Firebase-backed family accounts arrive in Sprint 4.)
class Identity extends ChangeNotifier {
  Identity._();
  static final Identity instance = Identity._();

  static const _kName = 'profile_name';
  static const _kRole = 'profile_role';
  static const _kRegistryPrefix = 'eid_name_';

  SharedPreferences? _prefs;
  String? _name;
  String _role = 'parent';
  final Map<String, String> _registry = {}; // eid -> name

  String? get name => _name;
  String get role => _role;
  bool get isSetUp => (_name ?? '').isNotEmpty;

  Future<void> load() async {
    final p = _prefs = await SharedPreferences.getInstance();
    _name = p.getString(_kName);
    _role = p.getString(_kRole) ?? 'parent';
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
