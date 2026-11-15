/// 流式相关的小组件：正在生成提示条、打字动画、末尾光标。
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// 流式中显示在输入区上方的提示条：`正在生成…` + 停止按钮。
class StreamingIndicatorBar extends StatelessWidget {
  const StreamingIndicatorBar({super.key, required this.onStop});

  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 12, 2),
      child: Row(
        children: <Widget>[
          const TypingDots(size: 5),
          const SizedBox(width: 8),
          Text(
            '正在生成…',
            style: TextStyle(fontSize: 12, color: colors.textSecondary),
          ),
          const Spacer(),
          TextButton(
            onPressed: onStop,
            style: TextButton.styleFrom(
              foregroundColor: colors.textSecondary,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              minimumSize: const Size(0, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.stop_circle_outlined, size: 15, color: colors.danger),
                const SizedBox(width: 4),
                Text(
                  '停止',
                  style: TextStyle(fontSize: 12, color: colors.danger),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 三个上下浮动的点，表示助手正在输入。
class TypingDots extends StatefulWidget {
  const TypingDots({super.key, this.size = 6});

  final double size;

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (var i = 0; i < 3; i++)
              Padding(
                padding: const EdgeInsets.only(right: 3),
                child: Opacity(
                  opacity: _opacityFor(t, i),
                  child: Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(
                      color: colors.brand,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  double _opacityFor(double t, int index) {
    final phase = (t + index * 0.18) % 1.0;
    final wave = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
    return 0.3 + 0.7 * wave;
  }
}

/// 流式正文末尾的闪烁光标。
class StreamingCursor extends StatefulWidget {
  const StreamingCursor({super.key});

  @override
  State<StreamingCursor> createState() => _StreamingCursorState();
}

class _StreamingCursorState extends State<StreamingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
      lowerBound: 0.15,
      upperBound: 1,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(left: 2, top: 2, bottom: 2),
      child: FadeTransition(
        opacity: _controller,
        child: Container(
          width: 7,
          height: 16,
          decoration: BoxDecoration(
            color: colors.brand,
            borderRadius: BorderRadius.circular(1.5),
          ),
        ),
      ),
    );
  }
}
