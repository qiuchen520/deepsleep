/// 输入区：底部 sticky 输入卡片 + 功能行 + 免责声明。
///
/// 对齐 docs/UI_SPEC.md：外层宽 776、max-width calc(100%-32)；卡片圆角 24、
/// 1px 边框、欢迎页阴影（深色无阴影）；输入 16/24、最小高 60、内边距
/// 12 12 0 16；发送按钮 34×34；功能行 padding 12、gap 8；开关高 34、圆角 18、
/// 字号 13/20；免责声明 11/16 居中。
library;

import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/profile_models.dart';
import '../../../state/app_services.dart';
import '../../../state/conversation_controller.dart';
import '../../../state/settings_controller.dart';
import 'attachment_preview.dart';
import 'model_picker_sheet.dart';

class Composer extends StatefulWidget {
  const Composer({
    super.key,
    required this.controller,
    required this.settings,
    required this.textController,
    required this.focusNode,
    required this.onOpenSettings,
    required this.services,
  });

  final ConversationController controller;
  final SettingsController settings;
  final TextEditingController textController;
  final FocusNode focusNode;
  final VoidCallback onOpenSettings;
  final AppServices services;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  final GlobalKey _cardKey = GlobalKey();

  // 长按录音状态。
  bool _recording = false;
  bool _cancelArmed = false;
  bool _voiceStarted = false;
  DateTime? _recordStartedAt;
  Timer? _recordTicker;
  Timer? _longPressTimer;
  OverlayEntry? _recordingOverlay;
  Future<bool>? _startFuture;
  int? _activePointer;
  Offset? _pointerDownPosition;

  ConversationController get controller => widget.controller;
  SettingsController get settings => widget.settings;
  TextEditingController get textController => widget.textController;
  FocusNode get focusNode => widget.focusNode;
  VoidCallback get onOpenSettings => widget.onOpenSettings;
  AppServices get services => widget.services;

  bool get _searchConfigured {
    final appSettings = settings.settings;
    switch (appSettings.searchBackend) {
      case SearchBackend.off:
        return false;
      case SearchBackend.deepseek:
        // DeepSeek 内置搜索不需要单独的搜索服务 Key。
        return true;
      case SearchBackend.tavily:
      case SearchBackend.serper:
        return settings.searchApiKey.trim().isNotEmpty;
    }
  }

  void _send() {
    if (_recording || controller.streaming) return;
    final text = textController.text;
    if (text.trim().isEmpty && controller.pendingAttachments.isEmpty) return;
    focusNode.requestFocus();
    textController.clear();
    controller.sendMessage(text);
  }

  void _stop() {
    controller.stop();
  }

  void _toggleSearch(BuildContext context) {
    if (!_searchConfigured) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(
        SnackBar(
          content: const Text('请在设置中选择搜索方式或填写搜索 API Key'),
          action: SnackBarAction(
            label: '前往设置',
            onPressed: onOpenSettings,
          ),
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }
    controller.setSearchEnabled(!controller.searchOn);
  }

  List<BoxShadow> _cardShadow(BuildContext context) {
    if (context.isDark) return const <BoxShadow>[];
    final colors = context.colors;
    if (controller.messages.isEmpty) {
      // 欢迎页阴影（Spec §5）。
      return <BoxShadow>[
        BoxShadow(
          color: colors.shadow.withValues(alpha: 0.02),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
        BoxShadow(
          color: colors.brand.withValues(alpha: 0.01),
          blurRadius: 2,
          offset: const Offset(0, 2),
        ),
        BoxShadow(
          color: colors.brand.withValues(alpha: 0.03),
          blurRadius: 60,
          offset: const Offset(0, 30),
        ),
      ];
    }
    // 会话中阴影。
    return <BoxShadow>[
      BoxShadow(
        color: colors.shadow.withValues(alpha: 0.02),
        blurRadius: 10,
        offset: const Offset(0, 4),
      ),
      BoxShadow(
        color: colors.shadow.withValues(alpha: 0.04),
        blurRadius: 4,
        offset: const Offset(0, 2),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: focusNode,
      builder: (context, _) => _buildCard(context),
    );
  }

  Widget _buildCard(BuildContext context) {
    final colors = context.colors;
    final appSettings = settings.settings;
    final pending = controller.pendingAttachments;
    final borderColor = context.isDark ? colors.border : colors.borderStrong;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 776),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              AnimatedContainer(
                key: _cardKey,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                decoration: BoxDecoration(
                  color: colors.bgInput,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: focusNode.hasFocus
                        ? colors.brand.withValues(alpha: 0.32)
                        : borderColor,
                  ),
                  boxShadow: _cardShadow(context),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (pending.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: <Widget>[
                            for (final attachment in pending)
                              AttachmentChip(
                                attachment: attachment,
                                onRemove: () => controller.removeAttachment(
                                  attachment.id,
                                ),
                              ),
                          ],
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 12, 0),
                      child: Listener(
                        onPointerDown: _handlePointerDown,
                        onPointerMove: _handlePointerMove,
                        onPointerUp: _handlePointerUp,
                        onPointerCancel: _handlePointerCancel,
                        child: TextField(
                          controller: textController,
                          focusNode: focusNode,
                          readOnly: _recording,
                          // 长按用于语音输入，因此关闭输入框自带的文本选择手势。
                          enableInteractiveSelection: false,
                          minLines: 1,
                          maxLines: 8,
                          keyboardType: TextInputType.multiline,
                          textInputAction: appSettings.sendWithEnter
                              ? TextInputAction.send
                              : TextInputAction.newline,
                          onSubmitted: appSettings.sendWithEnter
                              ? (value) => _send()
                              : null,
                          style: TextStyle(
                            fontSize: 16,
                            height: 24 / 16,
                            color: colors.textPrimary,
                          ),
                          cursorColor: colors.brand,
                          decoration: InputDecoration(
                            isDense: true,
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                            hintText: '发消息或按住说话',
                            hintStyle: TextStyle(
                              fontSize: 16,
                              height: 24 / 16,
                              // 近似 Spec 的 caption 色（浅 #ADB2B8 / 深 #81858C）。
                              color: colors.textTertiary.withValues(
                                alpha: 0.65,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: <Widget>[
                                _CircleButton(
                                  icon: Icons.add_rounded,
                                  tooltip: '添加附件',
                                  onTap: controller.streaming
                                      ? null
                                      : controller.pickAttachments,
                                ),
                                _ModelChip(
                                  label: shortModelName(
                                    appSettings.effectiveModel,
                                    appSettings,
                                  ),
                                  onTap: () =>
                                      showModelPicker(context, services),
                                ),
                                _Toggle(
                                  icon: Icons.lightbulb_outline_rounded,
                                  label: '深度思考',
                                  active: controller.deepThinking,
                                  onTap: () => controller.setDeepThinking(
                                    !controller.deepThinking,
                                  ),
                                ),
                                _Toggle(
                                  icon: Icons.language_rounded,
                                  label: '智能搜索',
                                  active: controller.searchOn,
                                  onTap: () => _toggleSearch(context),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: _streamOrSendButton(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  AppInfo.disclaimer,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    height: 16 / 11,
                    color: colors.textTertiary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _streamOrSendButton() {
    if (controller.streaming) {
      return _SendButton(
        icon: Icons.stop_rounded,
        tooltip: '停止生成',
        onPressed: _stop,
      );
    }
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: textController,
      builder: (context, value, child) {
        final hasInput =
            value.text.trim().isNotEmpty ||
            controller.pendingAttachments.isNotEmpty;
        final enabled = !_recording && controller.canSend && hasInput;
        return _SendButton(
          icon: Icons.arrow_upward_rounded,
          tooltip: '发送',
          enabled: enabled,
          onPressed: _send,
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 长按语音输入（松开发送 · 上滑取消）
  // ---------------------------------------------------------------------------

  void _handlePointerDown(PointerDownEvent event) {
    if (_recording || _longPressTimer != null) return;
    _activePointer = event.pointer;
    _pointerDownPosition = event.position;
    _longPressTimer = Timer(const Duration(milliseconds: 380), () {
      _longPressTimer = null;
      _beginVoice();
    });
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer) return;
    final down = _pointerDownPosition;
    if (down == null) return;
    if (!_recording) {
      // 明显移动视为滚动 / 选择意图，取消长按录音。
      if ((event.position - down).distance > 12) _cancelLongPressTimer();
      return;
    }
    final cancel = event.position.dy - down.dy < -60;
    if (cancel != _cancelArmed) {
      setState(() => _cancelArmed = cancel);
      _recordingOverlay?.markNeedsBuild();
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    _cancelLongPressTimer();
    if (event.pointer != _activePointer) return;
    _activePointer = null;
    _pointerDownPosition = null;
    if (_recording) _finishVoice(cancel: _cancelArmed);
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _cancelLongPressTimer();
    final wasActive = event.pointer == _activePointer;
    _activePointer = null;
    _pointerDownPosition = null;
    if (wasActive && _recording) _finishVoice(cancel: true);
  }

  void _cancelLongPressTimer() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
  }

  Future<bool> _startRecordingSafely() async {
    try {
      return await services.voice.startRecording();
    } catch (_) {
      return false;
    }
  }

  Future<void> _beginVoice() async {
    if (_recording) return;
    focusNode.unfocus();
    setState(() {
      _recording = true;
      _cancelArmed = false;
      _voiceStarted = false;
      _recordStartedAt = DateTime.now();
    });
    _recordTicker?.cancel();
    _recordTicker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      _recordingOverlay?.markNeedsBuild();
    });
    _insertRecordingOverlay();
    final future = _startRecordingSafely();
    _startFuture = future;
    final ok = await future;
    if (!mounted || !_recording) return;
    if (ok) {
      setState(() => _voiceStarted = true);
      _recordingOverlay?.markNeedsBuild();
    } else {
      _teardownRecording();
      _showSnack('麦克风不可用或权限被拒绝');
    }
  }

  Future<void> _finishVoice({required bool cancel}) async {
    if (!_recording) return;
    final future = _startFuture;
    if (!_voiceStarted && future != null) {
      final ok = await future;
      if (!mounted || !_recording) return;
      if (!ok) {
        _teardownRecording();
        _showSnack('麦克风不可用或权限被拒绝');
        return;
      }
    }
    _teardownRecording();
    if (cancel) {
      try {
        await services.voice.cancelRecording();
      } catch (_) {
        // 静默：取消失败不影响 UI。
      }
      return;
    }
    String? text;
    try {
      text = await services.voice.stopAndTranscribe();
    } catch (_) {
      text = null;
    }
    if (!mounted) return;
    final content = text?.trim() ?? '';
    if (content.isEmpty) {
      _showSnack('没有识别到内容，请重试');
      return;
    }
    textController.value = TextEditingValue(
      text: content,
      selection: TextSelection.collapsed(offset: content.length),
    );
    controller.sendMessage(content);
    textController.clear();
  }

  void _teardownRecording() {
    _recordTicker?.cancel();
    _recordTicker = null;
    _recordingOverlay?.remove();
    _recordingOverlay = null;
    _startFuture = null;
    if (!mounted) return;
    setState(() {
      _recording = false;
      _cancelArmed = false;
      _voiceStarted = false;
      _recordStartedAt = null;
    });
  }

  void _insertRecordingOverlay() {
    final overlay = Overlay.of(context, rootOverlay: true);
    final entry = OverlayEntry(builder: (overlayContext) {
      final screenHeight = MediaQuery.sizeOf(overlayContext).height;
      final keyboard = MediaQuery.viewInsetsOf(overlayContext).bottom;
      var bottom = screenHeight - 220;
      final cardContext = _cardKey.currentContext;
      if (cardContext != null) {
        final renderObject = cardContext.findRenderObject();
        if (renderObject is RenderBox && renderObject.hasSize) {
          bottom =
              screenHeight - renderObject.localToGlobal(Offset.zero).dy + 10;
        }
      }
      bottom = bottom.clamp(24.0, screenHeight - 80).toDouble();
      final start = _recordStartedAt;
      final seconds =
          start == null ? 0 : DateTime.now().difference(start).inSeconds;
      return Positioned(
        left: 0,
        right: 0,
        bottom: bottom + keyboard,
        child: IgnorePointer(
          child: Center(
            child: _RecordingCapsule(
              cancelArmed: _cancelArmed,
              seconds: seconds,
            ),
          ),
        ),
      );
    });
    _recordingOverlay = entry;
    overlay.insert(entry);
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _cancelLongPressTimer();
    _recordTicker?.cancel();
    _recordingOverlay?.remove();
    _recordingOverlay = null;
    if (_recording) {
      unawaited(
        services.voice.cancelRecording().catchError((Object _) {}),
      );
    }
    super.dispose();
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.icon,
    required this.tooltip,
    this.enabled = true,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: 34,
      height: 34,
      child: IconButton(
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon, size: 18),
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          backgroundColor: colors.brand,
          foregroundColor: Colors.white,
          disabledBackgroundColor: colors.brand.withValues(alpha: 0.4),
          disabledForegroundColor: Colors.white,
          fixedSize: const Size(34, 34),
          padding: EdgeInsets.zero,
          shape: const CircleBorder(),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = onTap != null;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(100),
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.bgHover,
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 20,
            color: enabled
                ? colors.textSecondary
                : colors.textTertiary.withValues(alpha: 0.4),
          ),
        ),
      ),
    );
  }
}

class _ModelChip extends StatelessWidget {
  const _ModelChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.borderStrong),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.tune_rounded,
              size: 14,
              color: colors.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                height: 20 / 13,
                fontWeight: FontWeight.w500,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = active ? colors.brand : colors.textTertiary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: active ? colors.brandSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: active
                ? colors.brand.withValues(alpha: 0.32)
                : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                height: 20 / 13,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 录音浮层：底部居中的毛玻璃胶囊（红点脉冲 + 计时 + 上滑取消提示）。
class _RecordingCapsule extends StatefulWidget {
  const _RecordingCapsule({required this.cancelArmed, required this.seconds});

  final bool cancelArmed;
  final int seconds;

  @override
  State<_RecordingCapsule> createState() => _RecordingCapsuleState();
}

class _RecordingCapsuleState extends State<_RecordingCapsule>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 820),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hintColor =
        widget.cancelArmed ? colors.danger : colors.textSecondary;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: colors.bgElevated.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: colors.border.withValues(alpha: 0.7),
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              FadeTransition(
                opacity: Tween<double>(begin: 0.3, end: 1).animate(_pulse),
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: colors.danger,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${widget.seconds} 秒',
                style: TextStyle(
                  fontSize: 14,
                  height: 24 / 14,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(width: 14),
              Text(
                widget.cancelArmed ? '松开取消' : '松开发送 · 上滑取消',
                style: TextStyle(
                  fontSize: 14,
                  height: 24 / 14,
                  fontWeight: FontWeight.w500,
                  color: hintColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
