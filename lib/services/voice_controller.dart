/// 语音门面：统一「长按说话」录音 → DeepSeek ASR，以及 DeepSeek TTS 朗读。
///
/// 底层实现（record / audioplayers / DeepSeek 接口）在
/// [DeepSeekVoiceClient]；保留系统语音能力作为降级方案。
library;

import 'deepseek_voice_client.dart';

class VoiceController {
  VoiceController({
    String Function()? apiKeyProvider,
    String Function()? baseUrlProvider,
  }) : _client = DeepSeekVoiceClient(
          apiKeyProvider: apiKeyProvider ?? (() => ''),
          baseUrlProvider: baseUrlProvider ?? (() => 'https://api.deepseek.com'),
        );

  final DeepSeekVoiceClient _client;

  bool get isRecording => _client.isRecording;
  bool get isSpeaking => _client.isSpeaking;

  /// 开始录音（按住说话）。
  Future<bool> startRecording() => _client.startRecording();

  /// 停止录音并返回识别文本；失败时返回 null。
  Future<String?> stopAndTranscribe() => _client.stopAndTranscribe();

  /// 取消录音并丢弃。
  Future<void> cancelRecording() => _client.cancelRecording();

  /// 朗读（优先 DeepSeek TTS，失败时降级系统 TTS）。
  Future<void> speak(String text) => _client.speak(text);

  Future<void> stopSpeaking() => _client.stopSpeaking();

  Future<void> dispose() => _client.dispose();
}
