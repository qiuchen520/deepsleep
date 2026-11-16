/// DeepSeek 官方语音能力客户端。
///
/// 参考官方 Web Demo 的接口：
/// - ASR：`POST {base}/v1/tools/asr`，multipart 字段 `file`（recording.wav），返回 `{text}`；
/// - TTS：`POST {base}/v1/tools/tts`，JSON 请求音频二进制流；Demo 返回 PCM，
///   这里优先请求 mp3，按 content-type / 文件头判断，PCM 则补 WAV 头后用
///   audioplayers 播放。
///
/// 录音使用 `record`（WAV / 16kHz / 单声道 / 16bit），任何环节失败都静默降级：
/// TTS 失败自动退回系统 TTS（[VoiceService]，flutter_tts）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../core/constants.dart';
import 'voice_service.dart';

/// DeepSeek 语音客户端（录音 → ASR，文本 → TTS）。
class DeepSeekVoiceClient {
  DeepSeekVoiceClient({
    required String Function() apiKeyProvider,
    required String Function() baseUrlProvider,
  })  : _apiKeyProvider = apiKeyProvider,
        _baseUrlProvider = baseUrlProvider;

  final String Function() _apiKeyProvider;
  final String Function() _baseUrlProvider;

  final http.Client _http = http.Client();
  final AudioRecorder _recorder = AudioRecorder();
  AudioPlayer? _player;

  bool _recording = false;
  bool _speaking = false;
  bool _usingSystemTts = false;
  bool _disposed = false;

  String? _recordingPath;
  int _speakSession = 0;
  Completer<void>? _playbackAbort;

  /// 最近一次录音 / 识别 / TTS 失败的原因（用于 UI 提示，不含敏感信息）。
  String? lastError;

  static const Duration _requestTimeout = Duration(seconds: 60);

  /// Demo 返回的 PCM 参数：16bit 单声道 24kHz。
  static const int _pcmSampleRate = 24000;

  /// 是否正在录音。
  bool get isRecording => _recording;

  /// 是否正在播放语音。
  bool get isSpeaking => _speaking;

  // ---------------------------------------------------------------------------
  // 录音 / ASR
  // ---------------------------------------------------------------------------

  /// 开始录音（WAV，16kHz 单声道 16bit），失败返回 false。
  Future<bool> startRecording() async {
    if (_disposed || _recording) return false;
    lastError = null;
    try {
      final granted = await _recorder.hasPermission();
      if (!granted) {
        lastError = '没有麦克风权限';
        return false;
      }
      final directory = await getTemporaryDirectory();
      final path =
          '${directory.path}/deepsleep_rec_${DateTime.now().millisecondsSinceEpoch}.wav';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
          bitRate: 256000,
        ),
        path: path,
      );
      _recordingPath = path;
      _recording = true;
      return true;
    } catch (error) {
      lastError = '录音启动失败：$error';
      _recording = false;
      _recordingPath = null;
      return false;
    }
  }

  /// 停止录音并调用 DeepSeek ASR，返回识别文本；失败返回 null。
  Future<String?> stopAndTranscribe() async {
    if (_disposed) return null;
    if (!_recording) {
      lastError = '当前没有在录音';
      return null;
    }
    _recording = false;
    lastError = null;

    String? stoppedPath;
    try {
      stoppedPath = await _recorder.stop();
    } catch (error) {
      lastError = '停止录音失败：$error';
    }
    final filePath =
        (stoppedPath != null && stoppedPath.isNotEmpty) ? stoppedPath : _recordingPath;
    _recordingPath = null;
    if (filePath == null || filePath.isEmpty) {
      lastError ??= '没有拿到录音文件';
      return null;
    }

    Uint8List bytes;
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        lastError = '录音文件不存在';
        return null;
      }
      bytes = await file.readAsBytes();
      try {
        await file.delete();
      } catch (_) {
        // 删除临时文件失败不影响识别。
      }
    } catch (error) {
      lastError = '读取录音失败：$error';
      return null;
    }
    if (bytes.isEmpty) {
      lastError = '录音内容为空';
      return null;
    }
    return _transcribe(bytes);
  }

  /// 取消录音并删除临时文件。
  Future<void> cancelRecording() async {
    _recording = false;
    try {
      await _recorder.cancel();
    } catch (_) {
      // 未在录音时可能报错，忽略。
    }
    await _deleteRecordingFile();
  }

  Future<String?> _transcribe(Uint8List bytes) async {
    final apiKey = _apiKeyProvider().trim();
    if (apiKey.isEmpty) {
      lastError = '未配置 API Key';
      return null;
    }
    try {
      final request = http.MultipartRequest('POST', _toolUri('asr'))
        ..headers['Authorization'] = 'Bearer $apiKey';
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: 'recording.wav',
        ),
      );

      final response = await _http.send(request).timeout(_requestTimeout);
      final body = await response.stream.toBytes().timeout(_requestTimeout);
      if (response.statusCode != 200) {
        lastError = _httpErrorMessage(response.statusCode, body);
        return null;
      }

      final decoded = jsonDecode(utf8.decode(body, allowMalformed: true));
      if (decoded is Map) {
        final text = decoded['text'];
        if (text is String) {
          final trimmed = text.trim();
          if (trimmed.isEmpty) {
            lastError = '没有识别到语音内容';
            return null;
          }
          return trimmed;
        }
      }
      lastError = '语音识别响应格式不正确';
      return null;
    } catch (error) {
      lastError = '语音识别失败：$error';
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // TTS
  // ---------------------------------------------------------------------------

  /// 朗读 [text]：优先 DeepSeek TTS，失败时降级系统 TTS。
  Future<void> speak(String text) async {
    if (_disposed) return;
    final content = text.trim();
    if (content.isEmpty) return;

    final session = ++_speakSession;
    await _stopPlayback();
    if (session != _speakSession) return;

    _speaking = true;
    try {
      _TtsAudio? audio;

      final apiKey = _apiKeyProvider().trim();
      if (apiKey.isNotEmpty) {
        // 官方 Demo 返回 PCM；先按 mp3 请求，失败再退 PCM 请求。
        audio = await _requestTts(apiKey, content, 'mp3');
        if (audio == null && session == _speakSession) {
          audio = await _requestTts(apiKey, content, 'pcm');
        }
      }

      if (session != _speakSession) return;

      if (audio != null) {
        try {
          await _playBytes(audio.bytes, audio.contentType);
          return;
        } on TimeoutException {
          // 播放超时：停止即可，不再降级，避免同一段话被读两遍。
          await _stopPlayback();
          return;
        } catch (error) {
          lastError = 'TTS 播放失败：$error';
        }
      }

      if (session != _speakSession) return;
      await _fallbackSpeak(content);
    } finally {
      if (session == _speakSession) _speaking = false;
    }
  }

  Future<_TtsAudio?> _requestTts(
    String apiKey,
    String text,
    String format,
  ) async {
    try {
      final response = await _http
          .post(
            _toolUri('tts'),
            headers: <String, String>{
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json; charset=utf-8',
              'Accept': 'audio/*',
            },
            body: jsonEncode(<String, dynamic>{
              'text': text,
              'voice_id': 'stella',
              'format': format,
              'filter_markdown': true,
            }),
          )
          .timeout(_requestTimeout);
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        return _TtsAudio(response.bodyBytes, _contentTypeOf(response));
      }
      if (response.statusCode != 200) {
        lastError = _httpErrorMessage(response.statusCode, response.bodyBytes);
      } else {
        lastError = 'TTS 返回了空音频';
      }
      return null;
    } catch (error) {
      lastError = 'TTS 请求失败：$error';
      return null;
    }
  }

  /// 停止朗读（含系统 TTS 降级播放）。
  Future<void> stopSpeaking() async {
    _speakSession++;
    await _stopPlayback();
    if (_usingSystemTts) {
      try {
        await VoiceService.instance.stopSpeaking();
      } catch (_) {
        // 静默。
      }
      _usingSystemTts = false;
    }
    _speaking = false;
  }

  Future<void> _playBytes(
    Uint8List bytes,
    String contentType,
  ) async {
    final payload = _resolveAudioPayload(bytes, contentType);
    final player = _player ??= AudioPlayer();
    final completion = Completer<void>();
    final subscription = player.onPlayerComplete.listen((_) {
      if (!completion.isCompleted) completion.complete();
    });
    final abort = Completer<void>();
    _playbackAbort = abort;
    try {
      await player.play(
        BytesSource(payload.data, mimeType: payload.mimeType),
      );
      await Future.any<void>(<Future<void>>[completion.future, abort.future])
          .timeout(_playbackTimeout(payload.seconds));
    } finally {
      await subscription.cancel();
      if (identical(_playbackAbort, abort)) _playbackAbort = null;
    }
  }

  Future<void> _fallbackSpeak(String text) async {
    _usingSystemTts = true;
    try {
      await VoiceService.instance.speak(text);
    } catch (_) {
      // 系统 TTS 也没有可用引擎时保持静默。
    } finally {
      _usingSystemTts = false;
    }
  }

  Future<void> _stopPlayback() async {
    final abort = _playbackAbort;
    if (abort != null && !abort.isCompleted) abort.complete();
    try {
      await _player?.stop();
    } catch (_) {
      // 静默。
    }
  }

  // ---------------------------------------------------------------------------
  // 生命周期 / 工具
  // ---------------------------------------------------------------------------

  /// 释放录音、播放与 HTTP 资源。
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _speakSession++;
    await _stopPlayback();
    try {
      if (_recording) {
        _recording = false;
        await _recorder.cancel();
      }
      await _recorder.dispose();
    } catch (_) {
      // 静默。
    }
    await _deleteRecordingFile();
    try {
      await _player?.dispose();
    } catch (_) {
      // 静默。
    }
    _player = null;
    try {
      _http.close();
    } catch (_) {
      // 静默。
    }
  }

  Future<void> _deleteRecordingFile() async {
    final path = _recordingPath;
    _recordingPath = null;
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // 静默。
    }
  }

  /// 拼接语音接口地址：兼容 base 带/不带 `/v1` 或末尾斜杠。
  Uri _toolUri(String tool) {
    var base = _baseUrlProvider().trim();
    if (base.isEmpty) base = AppInfo.defaultBaseUrl;
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    if (!base.startsWith('http://') && !base.startsWith('https://')) {
      base = 'https://$base';
    }
    final lower = base.toLowerCase();
    if (lower.endsWith('/v1/tools/asr') || lower.endsWith('/v1/tools/tts')) {
      base = base.substring(0, base.lastIndexOf('/v1/tools/'));
    }
    final normalized = base.toLowerCase();
    if (normalized.endsWith('/v1')) return Uri.parse('$base/tools/$tool');
    if (normalized.endsWith('/tools')) return Uri.parse('$base/$tool');
    return Uri.parse('$base/v1/tools/$tool');
  }

  String _contentTypeOf(http.BaseResponse response) {
    for (final entry in response.headers.entries) {
      if (entry.key.toLowerCase() == 'content-type') return entry.value;
    }
    return '';
  }

  String _httpErrorMessage(int statusCode, List<int> body) {
    var message = '';
    try {
      final decoded = jsonDecode(utf8.decode(body, allowMalformed: true));
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map && error['message'] is String) {
          message = error['message'] as String;
        } else if (decoded['message'] is String) {
          message = decoded['message'] as String;
        }
      }
    } catch (_) {
      // 忽略：错误体可能不是 JSON。
    }
    final trimmed = message.trim();
    if (trimmed.isEmpty) return '语音服务请求失败（HTTP $statusCode）';
    final text = trimmed.length > 160 ? trimmed.substring(0, 160) : trimmed;
    return '语音服务请求失败（HTTP $statusCode）：$text';
  }

  /// 根据 content-type / 文件头判断音频格式；非 mp3 一律按 24k PCM 补 WAV 头。
  _AudioPayload _resolveAudioPayload(Uint8List bytes, String contentType) {
    final lower = contentType.toLowerCase();
    if (lower.contains('mpeg') || lower.contains('mp3')) {
      return _AudioPayload(bytes, 'audio/mpeg', _mp3Seconds(bytes));
    }
    if (lower.contains('wav') || _startsWithRiff(bytes)) {
      return _AudioPayload(bytes, 'audio/wav', _wavSeconds(bytes));
    }
    if (_looksLikeMp3(bytes)) {
      return _AudioPayload(bytes, 'audio/mpeg', _mp3Seconds(bytes));
    }
    final wav = _pcmToWav(bytes);
    final seconds = (bytes.length / (_pcmSampleRate * 2)).ceil();
    return _AudioPayload(wav, 'audio/wav', seconds < 1 ? 1 : seconds);
  }

  Duration _playbackTimeout(int seconds) {
    var total = seconds + 15;
    if (total < 10) total = 10;
    if (total > 300) total = 300;
    return Duration(seconds: total);
  }

  int _mp3Seconds(Uint8List bytes) {
    // 按 64kbps 保守估算，避免长音频被提前判定超时。
    final seconds = (bytes.length / 8000).ceil();
    return seconds < 1 ? 1 : seconds;
  }

  int _wavSeconds(Uint8List bytes) {
    if (bytes.length >= 44) {
      final data = ByteData.sublistView(bytes);
      final channels = data.getUint16(22, Endian.little);
      final sampleRate = data.getUint32(24, Endian.little);
      final bits = data.getUint16(34, Endian.little);
      if (channels > 0 && sampleRate > 0 && bits > 0) {
        final bytesPerSecond = sampleRate * channels * (bits ~/ 8);
        final seconds = ((bytes.length - 44) / bytesPerSecond).ceil();
        return seconds < 1 ? 1 : seconds;
      }
    }
    return 30;
  }

  bool _startsWithRiff(Uint8List bytes) =>
      bytes.length >= 4 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46;

  bool _looksLikeMp3(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0x49 &&
        bytes[1] == 0x44 &&
        bytes[2] == 0x33) {
      return true; // ID3
    }
    return bytes.length >= 2 &&
        bytes[0] == 0xFF &&
        (bytes[1] & 0xE0) == 0xE0;
  }

  /// 给裸 PCM 数据补 44 字节 WAV 头（16bit / 单声道 / 24kHz）。
  Uint8List _pcmToWav(Uint8List pcm) {
    const channels = 1;
    const bitsPerSample = 16;
    const sampleRate = _pcmSampleRate;
    const blockAlign = channels * bitsPerSample ~/ 8;
    const byteRate = sampleRate * blockAlign;
    final dataSize = pcm.length;
    final output = Uint8List(44 + dataSize);
    final data = ByteData.view(output.buffer);

    void writeAscii(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        output[offset + i] = value.codeUnitAt(i);
      }
    }

    writeAscii(0, 'RIFF');
    data.setUint32(4, 36 + dataSize, Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    data.setUint32(16, 16, Endian.little); // fmt chunk size
    data.setUint16(20, 1, Endian.little); // PCM
    data.setUint16(22, channels, Endian.little);
    data.setUint32(24, sampleRate, Endian.little);
    data.setUint32(28, byteRate, Endian.little);
    data.setUint16(32, blockAlign, Endian.little);
    data.setUint16(34, bitsPerSample, Endian.little);
    writeAscii(36, 'data');
    data.setUint32(40, dataSize, Endian.little);
    output.setRange(44, 44 + dataSize, pcm);
    return output;
  }
}

/// TTS 返回的音频字节与 content-type。
class _TtsAudio {
  const _TtsAudio(this.bytes, this.contentType);

  final Uint8List bytes;
  final String contentType;
}

/// 播放前的音频数据与预估时长。
class _AudioPayload {
  const _AudioPayload(this.data, this.mimeType, this.seconds);

  final Uint8List data;
  final String mimeType;
  final int seconds;
}
