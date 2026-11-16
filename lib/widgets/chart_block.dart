/// 简易图表组件：识别 `language == chart` 的围栏代码块。
///
/// JSON 约定：`{"type":"bar|line|pie","title":"","labels":[],"values":[]}`。
/// 用 [CustomPainter] 直接绘制，不引入任何图表依赖；JSON 解析失败时回退成
/// 普通代码块展示原始文本。
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import 'code_block.dart';

enum _ChartKind { bar, line, pie }

class _ChartData {
  const _ChartData({
    required this.kind,
    required this.title,
    required this.labels,
    required this.values,
  });

  final _ChartKind kind;
  final String title;
  final List<String> labels;
  final List<double> values;
}

_ChartData? _parseChart(String source) {
  try {
    final dynamic decoded = jsonDecode(source);
    if (decoded is! Map) return null;
    final dynamic rawType = decoded['type'];
    if (rawType is! String) return null;
    _ChartKind kind;
    switch (rawType.trim().toLowerCase()) {
      case 'bar':
        kind = _ChartKind.bar;
        break;
      case 'line':
        kind = _ChartKind.line;
        break;
      case 'pie':
        kind = _ChartKind.pie;
        break;
      default:
        return null;
    }

    final labels = <String>[];
    final dynamic rawLabels = decoded['labels'];
    if (rawLabels is List) {
      for (final dynamic item in rawLabels) {
        labels.add(item is String ? item : '$item');
      }
    }

    final values = <double>[];
    final dynamic rawValues = decoded['values'];
    if (rawValues is List) {
      for (final dynamic item in rawValues) {
        if (item is num) {
          values.add(item.toDouble());
        } else if (item is String) {
          final parsed = double.tryParse(item);
          if (parsed != null) values.add(parsed);
        }
      }
    }

    if (values.isEmpty || labels.length != values.length) return null;
    if (kind == _ChartKind.pie) {
      var total = 0.0;
      for (final value in values) {
        total += value;
      }
      if (total <= 0) return null;
    }

    final dynamic rawTitle = decoded['title'];
    return _ChartData(
      kind: kind,
      title: rawTitle is String ? rawTitle : '',
      labels: labels,
      values: values,
    );
  } catch (_) {
    return null;
  }
}

/// 图表块：解析 ```chart JSON 并用 CustomPainter 绘制；失败时回退代码块。
class ChartBlock extends StatelessWidget {
  const ChartBlock({super.key, required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    final data = _parseChart(source);
    if (data == null) {
      return CodeBlock(code: source, language: 'chart');
    }
    final colors = context.colors;
    final palette = <Color>[
      colors.brand,
      colors.success,
      colors.warning,
      colors.danger,
      colors.brandText,
      colors.textSecondary,
    ];

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: colors.bgInput,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  data.title.trim().isEmpty ? '数据图表' : data.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: colors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                data.kind.name,
                style: TextStyle(fontSize: 11, color: colors.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 200,
            width: double.infinity,
            child: CustomPaint(
              painter: _ChartPainter(
                data: data,
                palette: palette,
                gridColor: colors.border,
                labelColor: colors.textTertiary,
              ),
              child: const SizedBox.expand(),
            ),
          ),
          if (data.kind == _ChartKind.pie)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Wrap(
                spacing: 12,
                runSpacing: 4,
                children: <Widget>[
                  for (var i = 0; i < data.labels.length; i++)
                    _LegendItem(
                      color: palette[i % palette.length],
                      label: data.labels[i],
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: colors.textTertiary),
        ),
      ],
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.data,
    required this.palette,
    required this.gridColor,
    required this.labelColor,
  });

  final _ChartData data;
  final List<Color> palette;
  final Color gridColor;
  final Color labelColor;

  static const double _leftPadding = 40;
  static const double _rightPadding = 8;
  static const double _topPadding = 10;
  static const double _bottomPadding = 26;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.values.isEmpty || size.width < 60 || size.height < 60) return;
    if (data.kind == _ChartKind.pie) {
      _paintPie(canvas, size);
    } else {
      _paintAxisChart(canvas, size);
    }
  }

  void _paintPie(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) / 2) - 8;
    if (radius <= 2) return;
    var total = 0.0;
    for (final value in data.values) {
      total += math.max(0.0, value);
    }
    if (total <= 0) return;
    final rect = Rect.fromCircle(center: center, radius: radius);
    var start = -math.pi / 2;
    for (var i = 0; i < data.values.length; i++) {
      final value = math.max(0.0, data.values[i]);
      if (value <= 0) continue;
      final sweep = (value / total) * math.pi * 2;
      final paint = Paint()
        ..color = palette[i % palette.length]
        ..style = PaintingStyle.fill;
      // 留一点缝隙，视觉上更容易区分扇区。
      final gap = sweep > 0.03 ? 0.014 : 0.0;
      canvas.drawArc(rect, start + gap / 2, sweep - gap, true, paint);
      start += sweep;
    }
  }

  void _paintAxisChart(Canvas canvas, Size size) {
    final plotWidth = size.width - _leftPadding - _rightPadding;
    final plotHeight = size.height - _topPadding - _bottomPadding;
    if (plotWidth <= 10 || plotHeight <= 10) return;

    final values = data.values;
    var maxValue = values.reduce(math.max);
    var minValue = math.min(0.0, values.reduce(math.min));
    if (maxValue <= minValue) maxValue = minValue + 1;
    final range = maxValue - minValue;
    double yFor(double value) =>
        _topPadding + plotHeight * (maxValue - value) / range;

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final value = maxValue - range * i / 3;
      final y = yFor(value);
      canvas.drawLine(
        Offset(_leftPadding, y),
        Offset(_leftPadding + plotWidth, y),
        gridPaint,
      );
      _paintText(
        canvas,
        _formatNumber(value),
        Offset(0, y - 6),
        labelColor,
        9.5,
        maxWidth: _leftPadding - 6,
        align: TextAlign.right,
      );
    }

    final slot = plotWidth / values.length;
    for (var i = 0; i < values.length; i++) {
      final label = _shortLabel(data.labels[i]);
      _paintText(
        canvas,
        label,
        Offset(_leftPadding + slot * i, _topPadding + plotHeight + 6),
        labelColor,
        9.5,
        maxWidth: slot,
        align: TextAlign.center,
      );
    }

    if (data.kind == _ChartKind.bar) {
      _paintBars(canvas, yFor, slot, values.length);
    } else {
      _paintLine(canvas, yFor, slot, values);
    }
  }

  void _paintBars(Canvas canvas, double Function(double) yFor, double slot,
      int count) {
    final baseY = yFor(math.min(0.0, data.values.reduce(math.min)));
    final barWidth = (slot * 0.56).clamp(4.0, 46.0).toDouble();
    for (var i = 0; i < count; i++) {
      final centerX = _leftPadding + slot * (i + 0.5);
      final y = yFor(data.values[i]);
      final top = math.min(y, baseY);
      final height = math.max((y - baseY).abs(), 1.5);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(centerX - barWidth / 2, top, barWidth, height),
        const Radius.circular(3),
      );
      canvas.drawRRect(
        rect,
        Paint()..color = palette[i % palette.length],
      );
    }
  }

  void _paintLine(
    Canvas canvas,
    double Function(double) yFor,
    double slot,
    List<double> values,
  ) {
    final points = <Offset>[
      for (var i = 0; i < values.length; i++)
        Offset(
          _leftPadding + slot * (i + 0.5),
          yFor(values[i]),
        ),
    ];
    if (points.isEmpty) return;
    final baseline = yFor(math.min(0.0, values.reduce(math.min)));
    final color = palette.first;

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    final fillPath = Path.from(path)
      ..lineTo(points.last.dx, baseline)
      ..lineTo(points.first.dx, baseline)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()..color = color.withValues(alpha: 0.12),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    final dotPaint = Paint()..color = color;
    for (final point in points) {
      canvas.drawCircle(point, 3, dotPaint);
    }
  }

  void _paintText(
    Canvas canvas,
    String text,
    Offset offset,
    Color color,
    double fontSize, {
    double? maxWidth,
    TextAlign align = TextAlign.left,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: fontSize),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth ?? double.infinity);
    var dx = offset.dx;
    if (maxWidth != null && align == TextAlign.center) {
      dx = offset.dx + (maxWidth - painter.width) / 2;
    } else if (maxWidth != null && align == TextAlign.right) {
      dx = offset.dx + (maxWidth - painter.width);
    }
    painter.paint(canvas, Offset(dx, offset.dy));
  }

  String _shortLabel(String label) {
    final trimmed = label.trim();
    if (trimmed.runes.length <= 6) return trimmed;
    return '${String.fromCharCodes(trimmed.runes.take(6))}…';
  }

  String _formatNumber(double value) {
    final abs = value.abs();
    if (abs >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M';
    }
    if (abs >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}k';
    }
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(1);
  }

  @override
  bool shouldRepaint(covariant _ChartPainter oldDelegate) {
    return oldDelegate.data != data ||
        oldDelegate.palette != palette ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.labelColor != labelColor;
  }
}
