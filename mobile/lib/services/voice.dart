import 'dart:convert';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Records short voice clips and plays received ones. Audio rides the mesh as
/// base64 inside the message envelope (see MeshEnvelope.voice).
class Voice {
  Voice._();
  static final Voice instance = Voice._();

  final _rec = AudioRecorder();
  final _player = AudioPlayer();
  String? _path;

  Future<bool> start() async {
    if (!await _rec.hasPermission()) return false;
    final dir = await getTemporaryDirectory();
    _path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _rec.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 24000, sampleRate: 16000, numChannels: 1),
      path: _path!,
    );
    return true;
  }

  /// Stop and return the clip as base64, or null if it failed / was too big.
  Future<String?> stopAsBase64() async {
    final path = await _rec.stop() ?? _path;
    if (path == null) return null;
    final f = File(path);
    if (!await f.exists()) return null;
    final bytes = await f.readAsBytes();
    try {
      await f.delete();
    } catch (_) {}
    if (bytes.isEmpty || bytes.length > 250000) return null; // ~250KB cap
    return base64Encode(bytes);
  }

  Future<void> cancel() async {
    try {
      await _rec.stop();
    } catch (_) {}
  }

  Future<void> play(String base64Audio) async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/play_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await File(path).writeAsBytes(base64Decode(base64Audio));
    await _player.play(DeviceFileSource(path));
  }
}
