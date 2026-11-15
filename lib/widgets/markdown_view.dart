/// Markdown 渲染封装。
///
/// 主题色适配（标题 / 引用 / 表格 / 行内代码）、把围栏代码块交给 [CodeBlock]
/// 与 [ChartBlock] 渲染、链接用 url_launcher 打开。样式表按 [AppColors] 实例
/// 缓存，避免流式刷新时重复解析整段历史消息。
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

MarkdownStyleSheet _styleSheetFor(AppColors colors) {
  if (identical(colors, _cachedColors) && _cachedSheet != null) {
    return _cachedSheet!;
  }
  final base = MarkdownStyleSheet.fromTheme(
    ThemeData.light(useMaterial3: true),
  );
  final sheet = base.copyWith(
    p: TextStyle(fontSize: 15, height: 1.7, color: colors.textPrimary),
    a: TextStyle(color: colors.brandText, decoration: TextDecoration.none),
    code: TextStyle(
      fontFamily: 'monospace',
      fontSize: 13,
      color: colors.textPrimary,
      backgroundColor: colors.codeBg,
    ),
    h1: TextStyle(
      fontSize: 22,
      height: 1.5,
      fontWeight: FontWeight.w600,
      color: colors.textPrimary,
    ),
    h2: TextStyle(
      fontSize: 19,
      height: 1.5,
      fontWeight: FontWeight.w600,
      color: colors.textPrimary,
    ),
    h3: TextStyle(
      fontSize: 17,
      height: 1.5,
      fontWeight: FontWeight.w600,
      color: colors.textPrimary,
    ),
    h4: TextStyle(
      fontSize: 15.5,
      height: 1.5,
      fontWeight: FontWeight.w600,
      color: colors.textPrimary,
    ),
    h5: TextStyle(
      fontSize: 15,
      height: 1.5,
      fontWeight: FontWeight.w600,
      color: colors.textPrimary,
    ),
    h6: TextStyle(
      fontSize: 14.5,
      height: 1.5,
      fontWeight: FontWeight.w600,
      color: colors.textSecondary,
    ),
    em: const TextStyle(fontStyle: FontStyle.italic),
    strong: const TextStyle(fontWeight: FontWeight.w600),
    del: TextStyle(
      color: colors.textSecondary,
      decoration: TextDecoration.lineThrough,
    ),
    blockquote: TextStyle(
      fontSize: 14.5,
      height: 1.6,
      color: colors.textSecondary,
    ),
    blockquotePadding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
    blockquoteDecoration: BoxDecoration(
      color: colors.bgHover,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      border: Border(
        left: BorderSide(color: colors.borderStrong, width: 3),
      ),
    ),
    blockSpacing: 10,
    listIndent: 20,
    listBullet: TextStyle(color: colors.textSecondary),
    tableHead: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: colors.textPrimary,
    ),
    tableBody: TextStyle(
      fontSize: 13,
      height: 1.5,
      color: colors.textPrimary,
    ),
    tableBorder: TableBorder.all(color: colors.border),
    tableColumnWidth: const IntrinsicColumnWidth(),
    tableCellsPadding: const EdgeInsets.symmetric(
      horizontal: 10,
      vertical: 6,
    ),
    tablePadding: const EdgeInsets.symmetric(vertical: 6),
    codeblockDecoration: const BoxDecoration(),
    codeblockPadding: EdgeInsets.zero,
    horizontalRuleDecoration: BoxDecoration(
      border: Border(top: BorderSide(color: colors.border)),
    ),
    checkbox: TextStyle(color: colors.textSecondary),
  );
  _cachedColors = colors;
  _cachedSheet = sheet;
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
    this.padding = EdgeInsets.zero,
  });

  final String data;

  /// 自定义链接回调；为空时用系统浏览器打开。
  final MarkdownTapLinkCallback? onTapLink;

  /// 是否允许长按选择文本。
  final bool selectable;

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
        styleSheet: _styleSheetFor(colors),
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
