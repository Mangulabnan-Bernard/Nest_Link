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
      // Low bitrate mono so short clips fit in a single mesh bundle (~32KB) and
      // arrive reliably without fragmentation.
      const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 16000, sampleRate: 16000, numChannels: 1),
      path: _path!,
    );
    return true;
  }

  /// Stop and return the clip as base64. Returns null if recording failed,
  /// was effectively empty, or is too big to ride the mesh.
  Future<String?> stopAsBase64() async {
    final path = await _rec.stop() ?? _path;
    if (path == null) return null;
    final f = File(path);
    if (!await f.exists()) return null;
    final bytes = await f.readAsBytes();
    try {
      await f.delete();
    } catch (_) {}
    if (bytes.length < 1000) return null; // empty / too-short recording
    if (bytes.length > 22000) return null; // too long — must fit one mesh bundle
    return base64Encode(bytes);
  }

  Future<void> cancel() async {
    try {
      await _rec.stop();
    } catch (_) {}
  }

  /// Play a received clip. Returns an error message on failure, or null on success.
  Future<String?> play(String base64Audio) async {
    try {
      final bytes = base64Decode(base64Audio);
      if (bytes.isEmpty) return 'empty audio';
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/play_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await File(path).writeAsBytes(bytes);
      await _player.stop();
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.play(DeviceFileSource(path));
      return null;
    } catch (e) {
      return e.toString();
    }
  }
}
