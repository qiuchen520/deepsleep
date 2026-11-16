/// Markdown 渲染封装。
///
/// 尺寸对齐 DeepSeek Demo（docs/UI_SPEC.md）：正文 16/28、段落间距 16、
/// h1 700 24/34、h2 700 22/32、h3 700 20/30、h4 600 16/28、列表缩进 18、
/// 引用左侧 2px 竖线、表格 15/25。围栏代码块交给 [CodeBlock] / [ChartBlock]。
///
/// [compact] 用于思考过程：14/24 次要文字。
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
  // fromTheme 会断言 textTheme.bodyMedium.fontSize != null；新版 Flutter 的
  // 默认 Typography 在该字段上可能为 null，这里显式给全，避免发布版灰屏。
  final baseTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    dividerColor: colors.border,
    textTheme: TextTheme(
      bodyMedium: TextStyle(
        fontSize: compact ? 14 : 16,
        height: compact ? 24 / 14 : 28 / 16,
        color: colors.textPrimary,
      ),
      bodySmall: const TextStyle(fontSize: 12.5),
      headlineSmall: const TextStyle(fontSize: 20),
      titleLarge: const TextStyle(fontSize: 18),
      titleMedium: const TextStyle(fontSize: 16),
      titleSmall: const TextStyle(fontSize: 15),
    ),
  );
  final base = MarkdownStyleSheet.fromTheme(baseTheme);
  // 引用左侧竖线：令牌里没有 #ADB2B8，用三级文字半透明近似。
  final quoteLine = colors.textTertiary.withValues(alpha: 0.6);
  return base.copyWith(
    p: TextStyle(
      fontSize: compact ? 14 : 16,
      height: compact ? 24 / 14 : 28 / 16,
      color: compact ? colors.textSecondary : colors.textPrimary,
    ),
    a: TextStyle(
      color: colors.brandText,
      decoration: TextDecoration.none,
    ),
    code: TextStyle(
      fontFamily: 'monospace',
      fontSize: compact ? 13 : 14,
      height: 22 / 14,
      color: compact ? colors.textSecondary : colors.textPrimary,
      backgroundColor: colors.bgHover,
    ),
    h1: TextStyle(
      fontSize: compact ? 16 : 24,
      height: compact ? 1.5 : 34 / 24,
      fontWeight: FontWeight.w700,
      color: compact ? colors.textSecondary : colors.textPrimary,
    ),
    h1Padding: EdgeInsets.only(top: compact ? 8 : 16),
    h2: TextStyle(
      fontSize: compact ? 15 : 22,
      height: compact ? 1.5 : 32 / 22,
      fontWeight: FontWeight.w700,
      color: compact ? colors.textSecondary : colors.textPrimary,
    ),
    h2Padding: EdgeInsets.only(top: compact ? 8 : 16),
    h3: TextStyle(
      fontSize: compact ? 14.5 : 20,
      height: compact ? 1.5 : 30 / 20,
      fontWeight: FontWeight.w700,
      color: compact ? colors.textSecondary : colors.textPrimary,
    ),
    h3Padding: EdgeInsets.only(top: compact ? 6 : 16),
    h4: TextStyle(
      fontSize: compact ? 14 : 16,
      height: compact ? 24 / 14 : 28 / 16,
      fontWeight: FontWeight.w600,
      color: compact ? colors.textSecondary : colors.textPrimary,
    ),
    h4Padding: EdgeInsets.only(top: compact ? 6 : 8),
    h5: TextStyle(
      fontSize: compact ? 14 : 16,
      height: compact ? 24 / 14 : 28 / 16,
      fontWeight: FontWeight.w600,
      color: compact ? colors.textSecondary : colors.textPrimary,
    ),
    h5Padding: EdgeInsets.only(top: compact ? 4 : 8),
    h6: TextStyle(
      fontSize: compact ? 14 : 16,
      height: compact ? 24 / 14 : 28 / 16,
      fontWeight: FontWeight.w600,
      color: compact ? colors.textTertiary : colors.textPrimary,
    ),
    h6Padding: EdgeInsets.only(top: compact ? 4 : 8),
    em: const TextStyle(fontStyle: FontStyle.italic),
    strong: const TextStyle(fontWeight: FontWeight.w600),
    del: TextStyle(
      color: colors.textTertiary,
      decoration: TextDecoration.lineThrough,
    ),
    blockquote: TextStyle(
      fontSize: compact ? 14 : 16,
      height: compact ? 24 / 14 : 28 / 16,
      color: compact ? colors.textTertiary : colors.textSecondary,
    ),
    blockquotePadding: const EdgeInsets.only(left: 14),
    blockquoteDecoration: BoxDecoration(
      border: Border(left: BorderSide(color: quoteLine, width: 2)),
    ),
    blockSpacing: compact ? 8 : 16,
    listIndent: 18,
    listBullet: TextStyle(color: colors.textSecondary),
    tableHead: TextStyle(
      fontSize: 15,
      height: 25 / 15,
      fontWeight: FontWeight.w500,
      color: colors.textPrimary,
    ),
    tableBody: TextStyle(
      fontSize: 15,
      height: 25 / 15,
      color: colors.textPrimary,
    ),
    tableBorder: TableBorder(
      bottom: BorderSide(color: colors.borderStrong),
      horizontalInside: BorderSide(color: colors.border),
    ),
    tableColumnWidth: const IntrinsicColumnWidth(),
    tableCellsPadding: const EdgeInsets.symmetric(
      horizontal: 16,
      vertical: 10,
    ),
    tablePadding: const EdgeInsets.symmetric(vertical: 6),
    codeblockDecoration: const BoxDecoration(),
    codeblockPadding: EdgeInsets.zero,
    horizontalRuleDecoration: BoxDecoration(
      border: Border(top: BorderSide(color: colors.borderStrong)),
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
  /// 'pre' 是块级元素：必须返回 true，否则框架会按行内元素记账并在
  /// 「文档以代码块结尾」时触发 _inlines 断言。
  @override
  bool isBlockElement() => true;

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

  /// 紧凑模式：14/24 次要文字，用于思考过程。
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
