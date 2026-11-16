/// Markdown 渲染封装。
///
/// 主题色适配（标题 / 引用 / 表格 / 行内代码）、把围栏代码块交给 [CodeBlock]
/// 与 [ChartBlock] 渲染、链接用 url_launcher 打开。样式表按 [AppColors] 实例
/// 缓存，避免流式刷新时重复解析整段历史消息。
///
/// [compact] 用于思考过程等次要文本：更小字号、更淡颜色、更紧的间距。
library;

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

import '../core/theme/app_theme.dart';
import 'chart_block.dart';
import 'code_block.dart';

/// 用系统浏览器 / 外部应用打开链接；失败时给出提示。
Future<void> openExternalUrl(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final uri = Uri.tryParse(url.trim());
  if (uri == null ||
      !uri.hasScheme ||
      !const <String>['http', 'https', 'mailto'].contains(uri.scheme)) {
    messenger?.showSnackBar(
      SnackBar(content: Text('无法打开链接：$url')),
    );
    return;
  }
  try {
    final launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!launched) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('没有可用的应用打开该链接')),
      );
    }
  } catch (_) {
    messenger?.showSnackBar(
      const SnackBar(content: Text('打开链接失败')),
    );
  }
}

AppColors? _cachedColors;
MarkdownStyleSheet? _cachedSheet;
MarkdownStyleSheet? _cachedCompactSheet;

MarkdownStyleSheet _buildSheet(AppColors colors, bool compact) {
  // fromTheme 会断言 textTheme.bodyMedium.fontSize != null；
  // 新版 Flutter 的默认 Typography 在该字段上可能为 null，这里显式给全。
  final baseTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    dividerColor: colors.border,
    textTheme: TextTheme(
      bodyMedium: TextStyle(
        fontSize: compact ? 13 : 15.5,
        height: 1.75,
        color: colors.textPrimary,
      ),
      bodySmall: TextStyle(fontSize: 12.5, color: colors.textSecondary),
      headlineSmall: TextStyle(fontSize: 20, color: colors.textPrimary),
      titleLarge: TextStyle(fontSize: 18, color: colors.textPrimary),
      titleMedium: TextStyle(fontSize: 16.5, color: colors.textPrimary),
      titleSmall: TextStyle(fontSize: 15.5, color: colors.textPrimary),
    ),
  );
  final base = MarkdownStyleSheet.fromTheme(baseTheme);
  final bodyColor = compact ? colors.textSecondary : colors.textPrimary;
  final bodySize = compact ? 13.0 : 15.5;
  final bodyHeight = compact ? 1.7 : 1.75;
  final headingColor = compact ? colors.textSecondary : colors.textPrimary;
  final codeSize = compact ? 12.0 : 13.0;
  return base.copyWith(
    p: TextStyle(fontSize: bodySize, height: bodyHeight, color: bodyColor),
    a: TextStyle(color: colors.brandText, decoration: TextDecoration.none),
    code: TextStyle(
      fontFamily: 'monospace',
      fontSize: codeSize,
      color: bodyColor,
      backgroundColor: colors.codeBg,
    ),
    h1: TextStyle(
      fontSize: compact ? 15 : 20,
      height: 1.4,
      fontWeight: FontWeight.w600,
      color: headingColor,
    ),
    h1Padding: const EdgeInsets.only(top: 8, bottom: 2),
    h2: TextStyle(
      fontSize: compact ? 14.5 : 18,
      height: 1.4,
      fontWeight: FontWeight.w600,
      color: headingColor,
    ),
    h2Padding: const EdgeInsets.only(top: 8, bottom: 2),
    h3: TextStyle(
      fontSize: compact ? 14 : 16.5,
      height: 1.4,
      fontWeight: FontWeight.w600,
      color: headingColor,
    ),
    h3Padding: const EdgeInsets.only(top: 6, bottom: 2),
    h4: TextStyle(
      fontSize: compact ? 13.5 : 15.5,
      height: 1.45,
      fontWeight: FontWeight.w600,
      color: headingColor,
    ),
    h4Padding: const EdgeInsets.only(top: 6, bottom: 2),
    h5: TextStyle(
      fontSize: compact ? 13 : 15,
      height: 1.45,
      fontWeight: FontWeight.w600,
      color: headingColor,
    ),
    h5Padding: const EdgeInsets.only(top: 4, bottom: 2),
    h6: TextStyle(
      fontSize: compact ? 13 : 14.5,
      height: 1.45,
      fontWeight: FontWeight.w600,
      color: compact ? colors.textTertiary : colors.textSecondary,
    ),
    h6Padding: const EdgeInsets.only(top: 4, bottom: 2),
    em: const TextStyle(fontStyle: FontStyle.italic),
    strong: const TextStyle(fontWeight: FontWeight.w600),
    del: TextStyle(
      color: colors.textTertiary,
      decoration: TextDecoration.lineThrough,
    ),
    blockquote: TextStyle(
      fontSize: compact ? 12.5 : 14.5,
      height: 1.65,
      color: compact ? colors.textTertiary : colors.textSecondary,
    ),
    blockquotePadding: const EdgeInsets.only(left: 12, top: 2, bottom: 2),
    blockquoteDecoration: BoxDecoration(
      border: Border(
        left: BorderSide(color: colors.border, width: 2),
      ),
    ),
    blockSpacing: compact ? 6 : 8,
    listIndent: compact ? 16 : 20,
    listBullet: TextStyle(color: colors.textTertiary),
    tableHead: TextStyle(
      fontSize: compact ? 12 : 13,
      fontWeight: FontWeight.w600,
      color: colors.textPrimary,
    ),
    tableBody: TextStyle(
      fontSize: compact ? 12 : 13,
      height: 1.5,
      color: colors.textPrimary,
    ),
    tableBorder: TableBorder.all(color: colors.border),
    tableColumnWidth: const IntrinsicColumnWidth(),
    tableCellsPadding: const EdgeInsets.symmetric(
      horizontal: 10,
      vertical: 5,
    ),
    tablePadding: const EdgeInsets.symmetric(vertical: 4),
    codeblockDecoration: const BoxDecoration(),
    codeblockPadding: EdgeInsets.zero,
    horizontalRuleDecoration: BoxDecoration(
      border: Border(top: BorderSide(color: colors.border)),
    ),
    checkbox: TextStyle(color: colors.textSecondary),
  );
}

MarkdownStyleSheet _styleSheetFor(AppColors colors, bool compact) {
  if (!identical(colors, _cachedColors)) {
    _cachedColors = colors;
    _cachedSheet = null;
    _cachedCompactSheet = null;
  }
  if (compact) {
    var sheet = _cachedCompactSheet;
    if (sheet == null) {
      sheet = _buildSheet(colors, true);
      _cachedCompactSheet = sheet;
    }
    return sheet;
  }
  var sheet = _cachedSheet;
  if (sheet == null) {
    sheet = _buildSheet(colors, false);
    _cachedSheet = sheet;
  }
  return sheet;
}

class _PreBlockBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    var raw = element.textContent;
    var language = '';
    final children = element.children;
    if (children != null) {
      for (final child in children) {
        if (child is md.Element && child.tag == 'code') {
          raw = child.textContent;
          final className = child.attributes['class'] ?? '';
          if (className.startsWith('language-')) {
            language = className.substring('language-'.length);
          }
          break;
        }
      }
    }
    var code = raw;
    if (code.endsWith('\n')) {
      code = code.substring(0, code.length - 1);
    }
    if (code.trim().isEmpty) return null;
    final normalized = normalizeLanguage(language);
    if (normalized == 'chart') {
      return ChartBlock(source: code);
    }
    return CodeBlock(code: code, language: normalized);
  }
}

/// 渲染一段 Markdown 文本。
class MarkdownView extends StatelessWidget {
  const MarkdownView({
    super.key,
    required this.data,
    this.onTapLink,
    this.selectable = true,
    this.compact = false,
    this.padding = EdgeInsets.zero,
  });

  final String data;

  /// 自定义链接回调；为空时用系统浏览器打开。
  final MarkdownTapLinkCallback? onTapLink;

  /// 是否允许长按选择文本。
  final bool selectable;

  /// 紧凑模式：小字号 + 淡色，用于思考过程等次要内容。
  final bool compact;

  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    if (data.trim().isEmpty) return const SizedBox.shrink();
    final colors = context.colors;
    return Padding(
      padding: padding,
      child: MarkdownBody(
        data: data,
        selectable: selectable,
        softLineBreak: true,
        fitContent: true,
        styleSheet: _styleSheetFor(colors, compact),
        builders: <String, MarkdownElementBuilder>{
          'pre': _PreBlockBuilder(),
        },
        onTapLink: (text, href, title) {
          final handler = onTapLink;
          if (handler != null) {
            handler(text, href, title);
          } else if (href != null && href.isNotEmpty) {
            openExternalUrl(context, href);
          }
        },
      ),
    );
  }
}
