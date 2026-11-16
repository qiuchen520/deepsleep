/// 代码块组件：语言标签 + 复制按钮 + 横向滚动 + 正则轻量高亮。
///
/// 不引入任何语法高亮依赖：每种语言用「注释 / 字符串 / 数字 / 关键字」四条
/// 正则拼成一个带命名捕获组的正则，按命中分组上色；未知语言退化为纯等宽文本。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_theme.dart';

const String _stringPattern =
    r'''(?:'(?:\\.|[^'\\\n])*'|"(?:\\.|[^"\\\n])*"|`(?:\\.|[^`\\])*`)''';

/// 各语言的注释正则。
const Map<String, String> _commentPatterns = <String, String>{
  'dart': r'//[^\n]*|/\*[\s\S]*?\*/',
  'javascript': r'//[^\n]*|/\*[\s\S]*?\*/',
  'typescript': r'//[^\n]*|/\*[\s\S]*?\*/',
  'java': r'//[^\n]*|/\*[\s\S]*?\*/',
  'kotlin': r'//[^\n]*|/\*[\s\S]*?\*/',
  'c': r'//[^\n]*|/\*[\s\S]*?\*/',
  'cpp': r'//[^\n]*|/\*[\s\S]*?\*/',
  'go': r'//[^\n]*|/\*[\s\S]*?\*/',
  'rust': r'//[^\n]*|/\*[\s\S]*?\*/',
  'csharp': r'//[^\n]*|/\*[\s\S]*?\*/',
  'php': r'//[^\n]*|/\*[\s\S]*?\*/|#[^\n]*',
  'python': r'#[^\n]*',
  'bash': r'#[^\n]*',
  'yaml': r'#[^\n]*',
  'ruby': r'#[^\n]*',
  'sql': r'--[^\n]*|/\*[\s\S]*?\*/',
  'html': r'<!--[\s\S]*?-->',
  'css': r'/\*[\s\S]*?\*/',
};

/// 各语言的关键字（大小写敏感；SQL 例外，见 [_buildSpec]）。
const Map<String, List<String>> _keywords = <String, List<String>>{
  'dart': <String>[
    'abstract', 'as', 'assert', 'async', 'await', 'break', 'case', 'catch',
    'class', 'const', 'continue', 'covariant', 'default', 'deferred', 'do',
    'dynamic', 'else', 'enum', 'export', 'extends', 'extension', 'external',
    'factory', 'false', 'final', 'finally', 'for', 'Function', 'get', 'hide',
    'if', 'implements', 'import', 'in', 'interface', 'is', 'late', 'library',
    'mixin', 'new', 'null', 'on', 'operator', 'part', 'required', 'rethrow',
    'return', 'sealed', 'set', 'show', 'static', 'super', 'switch', 'sync',
    'this', 'throw', 'true', 'try', 'typedef', 'var', 'void', 'when', 'while',
    'with', 'yield',
  ],
  'python': <String>[
    'and', 'as', 'assert', 'async', 'await', 'break', 'class', 'continue',
    'def', 'del', 'elif', 'else', 'except', 'False', 'finally', 'for', 'from',
    'global', 'if', 'import', 'in', 'is', 'lambda', 'None', 'nonlocal', 'not',
    'or', 'pass', 'raise', 'return', 'True', 'try', 'while', 'with', 'yield',
    'match', 'case',
  ],
  'javascript': <String>[
    'async', 'await', 'break', 'case', 'catch', 'class', 'const', 'continue',
    'debugger', 'default', 'delete', 'do', 'else', 'export', 'extends',
    'false', 'finally', 'for', 'from', 'function', 'get', 'if', 'import',
    'in', 'instanceof', 'let', 'new', 'null', 'of', 'return', 'set', 'static',
    'super', 'switch', 'this', 'throw', 'true', 'try', 'typeof', 'undefined',
    'var', 'void', 'while', 'with', 'yield',
  ],
  'typescript': <String>[
    'abstract', 'any', 'as', 'async', 'await', 'boolean', 'break', 'case',
    'catch', 'class', 'const', 'continue', 'declare', 'default', 'delete',
    'do', 'else', 'enum', 'export', 'extends', 'false', 'finally', 'for',
    'from', 'function', 'get', 'if', 'implements', 'import', 'in', 'infer',
    'instanceof', 'interface', 'is', 'keyof', 'let', 'namespace', 'never',
    'new', 'null', 'number', 'of', 'private', 'protected', 'public', 'readonly',
    'return', 'satisfies', 'set', 'static', 'string', 'super', 'switch',
    'this', 'throw', 'true', 'try', 'type', 'typeof', 'undefined', 'unknown',
    'var', 'void', 'while', 'yield',
  ],
  'java': <String>[
    'abstract', 'assert', 'boolean', 'break', 'byte', 'case', 'catch', 'char',
    'class', 'const', 'continue', 'default', 'do', 'double', 'else', 'enum',
    'extends', 'final', 'finally', 'float', 'for', 'if', 'implements',
    'import', 'instanceof', 'int', 'interface', 'long', 'native', 'new',
    'package', 'private', 'protected', 'public', 'record', 'return', 'sealed',
    'short', 'static', 'strictfp', 'super', 'switch', 'synchronized', 'this',
    'throw', 'throws', 'transient', 'try', 'var', 'void', 'volatile', 'while',
  ],
  'kotlin': <String>[
    'abstract', 'annotation', 'as', 'break', 'by', 'catch', 'class',
    'companion', 'const', 'constructor', 'continue', 'crossinline', 'data',
    'delegate', 'do', 'else', 'enum', 'external', 'false', 'final', 'finally',
    'for', 'fun', 'get', 'if', 'import', 'in', 'infix', 'init', 'inline',
    'inner', 'interface', 'internal', 'is', 'lateinit', 'noinline', 'null',
    'object', 'open', 'operator', 'out', 'override', 'package', 'private',
    'protected', 'public', 'reified', 'return', 'sealed', 'set', 'super',
    'suspend', 'tailrec', 'this', 'throw', 'true', 'try', 'typealias', 'val',
    'var', 'vararg', 'when', 'where', 'while',
  ],
  'c': <String>[
    'auto', 'break', 'case', 'char', 'const', 'continue', 'default', 'do',
    'double', 'else', 'enum', 'extern', 'float', 'for', 'goto', 'if', 'inline',
    'int', 'long', 'register', 'restrict', 'return', 'short', 'signed',
    'sizeof', 'static', 'struct', 'switch', 'typedef', 'union', 'unsigned',
    'void', 'volatile', 'while',
  ],
  'cpp': <String>[
    'auto', 'bool', 'break', 'case', 'catch', 'char', 'class', 'const',
    'constexpr', 'continue', 'default', 'delete', 'do', 'double', 'else',
    'enum', 'explicit', 'extern', 'false', 'final', 'float', 'for', 'friend',
    'if', 'inline', 'int', 'long', 'namespace', 'new', 'noexcept', 'nullptr',
    'override', 'private', 'protected', 'public', 'return', 'short', 'signed',
    'sizeof', 'static', 'struct', 'switch', 'template', 'this', 'throw',
    'true', 'try', 'typedef', 'typename', 'union', 'unsigned', 'using',
    'virtual', 'void', 'volatile', 'while',
  ],
  'go': <String>[
    'break', 'case', 'chan', 'const', 'continue', 'default', 'defer', 'else',
    'fallthrough', 'false', 'for', 'func', 'go', 'goto', 'if', 'import',
    'interface', 'map', 'nil', 'package', 'range', 'return', 'select',
    'struct', 'switch', 'true', 'type', 'var',
  ],
  'rust': <String>[
    'as', 'async', 'await', 'break', 'const', 'continue', 'crate', 'dyn',
    'else', 'enum', 'extern', 'false', 'fn', 'for', 'if', 'impl', 'in', 'let',
    'loop', 'match', 'mod', 'move', 'mut', 'pub', 'ref', 'return', 'self',
    'Self', 'static', 'struct', 'super', 'trait', 'true', 'type', 'unsafe',
    'use', 'where', 'while',
  ],
  'csharp': <String>[
    'abstract', 'as', 'async', 'await', 'base', 'bool', 'break', 'byte',
    'case', 'catch', 'char', 'class', 'const', 'continue', 'decimal',
    'default', 'delegate', 'do', 'double', 'else', 'enum', 'event',
    'explicit', 'extern', 'false', 'finally', 'fixed', 'float', 'for',
    'foreach', 'goto', 'if', 'implicit', 'in', 'int', 'interface', 'internal',
    'is', 'lock', 'long', 'namespace', 'new', 'null', 'object', 'operator',
    'out', 'override', 'params', 'private', 'protected', 'public', 'readonly',
    'record', 'ref', 'return', 'sealed', 'short', 'sizeof', 'static', 'string',
    'struct', 'switch', 'this', 'throw', 'true', 'try', 'typeof', 'uint',
    'ulong', 'unchecked', 'unsafe', 'ushort', 'using', 'var', 'virtual',
    'void', 'volatile', 'while',
  ],
  'php': <String>[
    'abstract', 'and', 'array', 'as', 'break', 'callable', 'case', 'catch',
    'class', 'clone', 'const', 'continue', 'declare', 'default', 'do', 'echo',
    'else', 'elseif', 'empty', 'enddeclare', 'endfor', 'endforeach', 'endif',
    'endswitch', 'endwhile', 'enum', 'eval', 'exit', 'extends', 'false',
    'final', 'finally', 'fn', 'for', 'foreach', 'function', 'global', 'goto',
    'if', 'implements', 'include', 'include_once', 'instanceof', 'interface',
    'isset', 'list', 'match', 'namespace', 'new', 'null', 'or', 'print',
    'private', 'protected', 'public', 'readonly', 'require', 'require_once',
    'return', 'static', 'switch', 'throw', 'trait', 'true', 'try', 'unset',
    'use', 'var', 'while', 'yield',
  ],
  'ruby': <String>[
    'alias', 'and', 'begin', 'break', 'case', 'class', 'def', 'defined', 'do',
    'else', 'elsif', 'end', 'ensure', 'false', 'for', 'if', 'in', 'module',
    'next', 'nil', 'not', 'or', 'redo', 'rescue', 'retry', 'return', 'self',
    'super', 'then', 'true', 'undef', 'unless', 'until', 'when', 'while',
    'yield',
  ],
  'sql': <String>[
    'select', 'from', 'where', 'join', 'left', 'right', 'inner', 'outer', 'on',
    'group', 'by', 'order', 'having', 'limit', 'offset', 'insert', 'into',
    'values', 'update', 'set', 'delete', 'create', 'table', 'index', 'drop',
    'alter', 'add', 'primary', 'key', 'foreign', 'references', 'not', 'null',
    'default', 'distinct', 'as', 'and', 'or', 'in', 'exists', 'between',
    'like', 'is', 'case', 'when', 'then', 'else', 'end', 'union', 'all',
    'count', 'sum', 'avg', 'min', 'max', 'asc', 'desc', 'with', 'returning',
  ],
  'bash': <String>[
    'if', 'then', 'else', 'elif', 'fi', 'for', 'while', 'until', 'do', 'done',
    'case', 'esac', 'function', 'in', 'select', 'return', 'exit', 'local',
    'export', 'unset', 'readonly', 'declare', 'source', 'alias', 'echo', 'cd',
    'set', 'eval', 'exec', 'trap', 'shift', 'test',
  ],
  'yaml': <String>['true', 'false', 'null', 'yes', 'no', 'on', 'off'],
};

/// 少数语言用自定义“关键字”正则（例如 HTML 标签、CSS 选择器、YAML 键名）。
const Map<String, String> _customKeywordPatterns = <String, String>{
  'html': r'</?[a-zA-Z][\w:-]*',
  'css': r'[.#][A-Za-z_][\w-]*|@[A-Za-z-]+',
  'yaml': r'[A-Za-z_][\w-]*(?=\s*:)',
  'json': r'\b(?:true|false|null)\b',
};

/// 常见别名 -> 规范语言名。
const Map<String, String> _aliases = <String, String>{
  'js': 'javascript',
  'jsx': 'javascript',
  'mjs': 'javascript',
  'cjs': 'javascript',
  'node': 'javascript',
  'ts': 'typescript',
  'tsx': 'typescript',
  'py': 'python',
  'python3': 'python',
  'sh': 'bash',
  'shell': 'bash',
  'zsh': 'bash',
  'console': 'bash',
  'shellscript': 'bash',
  'yml': 'yaml',
  'htm': 'html',
  'xml': 'html',
  'vue': 'html',
  'c++': 'cpp',
  'cc': 'cpp',
  'cxx': 'cpp',
  'h': 'cpp',
  'hpp': 'cpp',
  'kt': 'kotlin',
  'kts': 'kotlin',
  'rs': 'rust',
  'cs': 'csharp',
  'golang': 'go',
  'rb': 'ruby',
  'md': 'markdown',
  'text': 'plain',
  'txt': 'plain',
  'plaintext': 'plain',
  'log': 'plain',
};

class _HighlightSpec {
  const _HighlightSpec(this.pattern);

  final RegExp pattern;
}

final Map<String, _HighlightSpec?> _specCache = <String, _HighlightSpec?>{};

/// 把 `language-xxx` / 别名统一成规范语言名；无法识别时返回 null。
String? normalizeLanguage(String? raw) {
  if (raw == null) return null;
  var language = raw.trim().toLowerCase();
  if (language.isEmpty) return null;
  if (language.startsWith('language-')) {
    language = language.substring('language-'.length);
  }
  return _aliases[language] ?? language;
}

_HighlightSpec? _buildSpec(String language) {
  final comment = _commentPatterns[language];
  final keywords = _keywords[language];
  final customKeyword = _customKeywordPatterns[language];
  if (comment == null && keywords == null && customKeyword == null) {
    return null;
  }
  final buffer = StringBuffer();
  if (comment != null) {
    buffer.write('(?<comment>(?:$comment))|');
  }
  buffer.write('(?<string>$_stringPattern)|');
  buffer.write(r'(?<number>\b\d+(?:\.\d+)?\b)');
  if (customKeyword != null) {
    buffer.write('|(?<keyword>$customKeyword)');
  } else if (keywords != null && keywords.isNotEmpty) {
    buffer.write('|(?<keyword>\\b(?:${keywords.join('|')})\\b)');
  }
  return _HighlightSpec(
    RegExp(
      buffer.toString(),
      multiLine: true,
      caseSensitive: language != 'sql',
    ),
  );
}

_HighlightSpec? _specFor(String? language) {
  if (language == null) return null;
  if (_specCache.containsKey(language)) return _specCache[language];
  final spec = _buildSpec(language);
  _specCache[language] = spec;
  return spec;
}

List<InlineSpan> _highlight(
  String code,
  _HighlightSpec? spec,
  TextStyle baseStyle,
  AppColors colors,
) {
  if (spec == null) {
    return <InlineSpan>[TextSpan(text: code, style: baseStyle)];
  }
  final spans = <InlineSpan>[];
  var index = 0;
  for (final match in spec.pattern.allMatches(code)) {
    if (match.start > index) {
      spans.add(
        TextSpan(text: code.substring(index, match.start), style: baseStyle),
      );
    }
    final text = match.group(0) ?? '';
    var style = baseStyle;
    if (match.namedGroup('comment') != null) {
      style = baseStyle.copyWith(
        color: colors.textTertiary,
        fontStyle: FontStyle.italic,
      );
    } else if (match.namedGroup('string') != null) {
      style = baseStyle.copyWith(color: colors.success);
    } else if (match.namedGroup('number') != null) {
      style = baseStyle.copyWith(color: colors.warning);
    } else if (match.namedGroup('keyword') != null) {
      style = baseStyle.copyWith(
        color: colors.brandText,
        fontWeight: FontWeight.w600,
      );
    }
    spans.add(TextSpan(text: text, style: style));
    index = match.end;
  }
  if (index < code.length) {
    spans.add(TextSpan(text: code.substring(index), style: baseStyle));
  }
  return spans;
}

/// 代码块：顶部语言标签 + 复制按钮，正文横向滚动并轻量高亮。
class CodeBlock extends StatefulWidget {
  const CodeBlock({super.key, required this.code, this.language});

  final String code;
  final String? language;

  @override
  State<CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<CodeBlock> {
  bool _copied = false;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    setState(() => _copied = true);
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.code.isEmpty) return const SizedBox.shrink();
    final colors = context.colors;
    final language = normalizeLanguage(widget.language);
    final spec = _specFor(language);
    final label = language ?? 'text';
    final baseStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: 13,
      height: 22 / 13,
      color: colors.textPrimary,
    );
    final spans = _highlight(widget.code, spec, baseStyle, colors);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.codeBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            color: colors.codeBanner,
            padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
            child: Row(
              children: <Widget>[
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    height: 20 / 13,
                    color: colors.textSecondary,
                  ),
                ),
                const Spacer(),
                InkWell(
                  onTap: _copy,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      _copied ? Icons.check_rounded : Icons.copy_rounded,
                      size: 14,
                      color:
                          _copied ? colors.success : colors.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(16),
            child: SelectableText.rich(
              TextSpan(children: spans),
              style: baseStyle,
            ),
          ),
        ],
      ),
    );
  }
}
