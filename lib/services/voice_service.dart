/// 语音能力封装：文字转语音（flutter_tts）与语音识别（speech_to_text）。
///
/// 设计要点：
/// - 单例 [VoiceService.instance]：两个插件都只应在 App 内创建一个实例
///   （speech_to_text 的 initialize 只生效一次，重复创建会互相覆盖回调）；
/// - 所有插件异常都在内部吞掉：设备没有 TTS 引擎、没有麦克风权限、
///   没有语音识别服务时只表现为「没反应」，绝不向 UI 抛异常导致 App 崩溃；
/// - 状态（[isSpeaking] / [isListening]）由内部维护，UI 直接读取即可。
library;

import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// 语音服务（TTS + 语音识别）单例封装。
class VoiceService {
  VoiceService._();

  /// 全局唯一实例。
  static final VoiceService instance = VoiceService._();

  final FlutterTts _tts = FlutterTts();
  final SpeechToText _speech = SpeechToText();

  bool _speaking = false;
  bool _ttsConfigured = false;
  bool _speechInitialized = false;
  bool _listening = false;
  bool _starting = false;

  /// 朗读会话序号：连续调用 speak 时，避免上一次的收尾把新一次的状态清掉。
  int _speakSession = 0;

  /// 当前一轮语音识别的结果回调与结束回调。
  void Function(String text, bool isFinal)? _onResult;
  void Function()? _onDone;

  /// 是否正在朗读。
  bool get isSpeaking => _speaking;

  /// 是否正在录音识别。
  bool get isListening => _listening;

  // ---------------------------------------------------------------------------
  // TTS
  // ---------------------------------------------------------------------------

  /// 朗读 [text]。
  ///
  /// 再次调用会先停掉上一次未读完的内容；空文本直接忽略。
  Future<void> speak(String text) async {
    final content = text.trim();
    if (content.isEmpty) return;

    final session = ++_speakSession;
    // 再次调用先 stop，避免两段语音叠在一起。
    try {
      await _tts.stop();
    } catch (_) {
      // 忽略：TTS 未初始化/不可用时 stop 也可能失败。
    }
    if (session != _speakSession) return; // 期间又有新的 speak 调用
    _speaking = false;

    try {
      await _configureTts();
      _speaking = true;
      // 已开启 awaitSpeakCompletion，speak 会等到朗读结束才返回。
      await _tts.speak(content);
    } catch (_) {
      // 无 TTS 引擎 / 语言包缺失 / 平台异常：静默失败。
    } finally {
      if (session == _speakSession) _speaking = false;
    }
  }

  /// 停止当前朗读。
  Future<void> stopSpeaking() async {
    _speakSession++;
    try {
      await _tts.stop();
    } catch (_) {
      // 静默。
    }
    _speaking = false;
  }

  Future<void> _configureTts() async {
    if (_ttsConfigured) return;

    _tts.setStartHandler(() {
      _speaking = true;
    });
    _tts.setCompletionHandler(() {
      _speaking = false;
    });
    _tts.setCancelHandler(() {
      _speaking = false;
    });
    _tts.setErrorHandler((dynamic message) {
      _speaking = false;
    });

    await _tts.awaitSpeakCompletion(true);
    await _tts.setLanguage('zh-CN');
    await _tts.setSpeechRate(0.5);
    _ttsConfigured = true;
  }

  // ---------------------------------------------------------------------------
  // 语音识别
  // ---------------------------------------------------------------------------

  /// 初始化语音识别（会触发系统的麦克风授权）。
  ///
  /// 返回 false 表示设备不支持 / 权限被拒 / 初始化失败，调用方无需处理异常。
  Future<bool> initSpeech() async {
    if (_speechInitialized) return true;
    try {
      final available = await _speech.initialize(
        onError: (error) {
          // 永久错误（如权限被撤、无识别服务）也视为一轮结束。
          _finishListening();
        },
        onStatus: (status) {
          if (status == SpeechToText.doneStatus ||
              status == SpeechToText.notListeningStatus) {
            _finishListening();
          }
        },
        debugLogging: false,
      );
      _speechInitialized = available;
      return available;
    } catch (_) {
      _speechInitialized = false;
      return false;
    }
  }

  /// 开始录音识别。
  ///
  /// 识别过程中（含中间结果）通过 [onResult] 回调文本与是否为最终结果；
  /// 识别结束、出错或被 [stopListening] 停止时调用 [onDone]。
  Future<void> startListening({
    required void Function(String text, bool isFinal) onResult,
    void Function()? onDone,
  }) async {
    if (_listening || _starting) return;
    _starting = true;
    try {
      final available = await initSpeech();
      if (!available) {
        // 没有麦克风权限或设备不支持：静默结束，不让 UI 卡在聆听状态。
        _safeCall(onDone);
        return;
      }

      _onResult = onResult;
      _onDone = onDone;
      _listening = true;
      await _speech.listen(
        onResult: (result) {
          final text = result.recognizedWords;
          final isFinal = result.finalResult;
          final callback = _onResult;
          if (callback != null) {
            try {
              callback(text, isFinal);
            } catch (_) {
              // UI 回调异常不应影响录音流程。
            }
          }
          // 拿到最终结果就视为本轮结束。
          if (isFinal) _finishListening();
        },
        listenOptions: SpeechListenOptions(
          localeId: 'zh_CN',
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 3),
          partialResults: true,
          cancelOnError: true,
        ),
      );
    } catch (_) {
      // 权限被拒 / 识别服务不可用 / 平台异常：静默收尾。
      _listening = false;
      _onResult = null;
      final done = _onDone;
      _onDone = null;
      _safeCall(done);
    } finally {
      _starting = false;
    }
  }

  /// 停止录音识别；插件不会自己回调时由这里兜底触发 onDone。
  Future<void> stopListening() async {
    try {
      await _speech.stop();
    } catch (_) {
      // 未初始化 / 已停止时可能抛异常，忽略。
    }
    _finishListening();
  }

  // ---------------------------------------------------------------------------
  // 内部工具
  // ---------------------------------------------------------------------------

  /// 结束一轮识别：保证 onDone 只触发一次且回调异常不外抛。
  void _finishListening() {
    if (!_listening) return;
    _listening = false;
    _onResult = null;
    final done = _onDone;
    _onDone = null;
    _safeCall(done);
  }

  void _safeCall(void Function()? callback) {
    if (callback == null) return;
    try {
      callback();
    } catch (_) {
      // 静默。
    }
  }
}
