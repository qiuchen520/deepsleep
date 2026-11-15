/// 附件选择与解析实现。
///
/// - 通过 `file_picker` 选择本地文件（不读取原始字节，避免大文件占内存）；
/// - 纯文本类文件（txt / md / json / 代码等）直接读取并截断；
/// - docx 用 `archive` 解压 `word/document.xml` 后正则去标签抽取正文；
/// - 图片只保留引用（当前聊天模型无法直接读图，UI 侧负责提示）；
/// - 其它二进制文件保留为 document 引用。
///
/// 本文件依赖 Flutter 插件（file_picker），不参与纯 Dart 单测。
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';

import '../core/utils/ids.dart';
import '../core/utils/token_estimator.dart';
import '../data/models/chat_models.dart';
import 'contracts.dart';

/// 附件服务实现。
class AttachmentServiceImpl implements AttachmentService {
  AttachmentServiceImpl({
    this.maxFileSizeBytes = 15 * 1024 * 1024,
    this.maxTotalSizeBytes = 30 * 1024 * 1024,
    this.maxFiles = 6,
    this.maxTextBytes = 2 * 1024 * 1024,
    this.contextTokenBudget = 3000,
  });

  /// 单个文件大小上限（15MB）。
  final int maxFileSizeBytes;

  /// 一次选择的附件总大小上限（30MB）。
  final int maxTotalSizeBytes;

  /// 一次最多选择几个文件。
  final int maxFiles;

  /// 单个文本文件最多读取的字节数（2MB，超出截断）。
  final int maxTextBytes;

  /// 拼进提示词的附件文本 token 预算（约 3000）。
  final int contextTokenBudget;

  static const Set<String> _textExtensions = <String>{
    'txt',
    'text',
    'md',
    'markdown',
    'json',
    'jsonl',
    'csv',
    'tsv',
    'log',
    'yaml',
    'yml',
    'toml',
    'ini',
    'conf',
    'cfg',
    'xml',
    'html',
    'htm',
    'css',
    'scss',
    'less',
    'sql',
    'dart',
    'js',
    'mjs',
    'cjs',
    'ts',
    'tsx',
    'jsx',
    'vue',
    'py',
    'rb',
    'java',
    'kt',
    'kts',
    'swift',
    'm',
    'mm',
    'c',
    'h',
    'cc',
    'cpp',
    'cxx',
    'hpp',
    'cs',
    'go',
    'rs',
    'php',
    'pl',
    'lua',
    'r',
    'sh',
    'bash',
    'zsh',
    'fish',
    'bat',
    'ps1',
    'gradle',
    'properties',
    'gitignore',
    'env',
    'dockerfile',
    'makefile',
    'tex',
    'srt',
    'vtt',
  };

  static const Set<String> _imageExtensions = <String>{
    'png',
    'jpg',
    'jpeg',
    'gif',
    'webp',
    'bmp',
    'heic',
    'heif',
  };

  @override
  Future<List<AttachmentRef>> pickFiles() async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: false,
      );
    } catch (error) {
      throw ApiException(ApiErrorKind.unknown, '打开文件选择器失败：$error');
    }
    if (result == null || result.files.isEmpty) {
      return const <AttachmentRef>[];
    }

    final refs = <AttachmentRef>[];
    var totalSize = 0;
    var rejected = 0;
    for (final file in result.files) {
      if (refs.length >= maxFiles ||
          file.size > maxFileSizeBytes ||
          totalSize + file.size > maxTotalSizeBytes) {
        rejected++;
        continue;
      }
      final ref = await _toAttachment(file);
      if (ref == null) {
        rejected++;
        continue;
      }
      refs.add(ref);
      totalSize += file.size;
    }

    if (refs.isEmpty && rejected > 0) {
      throw ApiException(
        ApiErrorKind.invalidRequest,
        '文件过大或数量过多：单个文件不超过 ${_formatSize(maxFileSizeBytes)}，'
        '一次最多 $maxFiles 个、总计不超过 ${_formatSize(maxTotalSizeBytes)}',
      );
    }
    return refs;
  }

  @override
  Future<String> buildContext(List<AttachmentRef> attachments) async {
    final blocks = <String>[];
    for (final attachment in attachments) {
      final text = (attachment.extractedText ?? '').trim();
      if (text.isEmpty) {
        // 图片与无法抽文本的二进制文件不注入提示词，由 UI 提示用户。
        continue;
      }
      blocks.add('## 文件：${attachment.name}\n$text');
    }
    if (blocks.isEmpty) return '';

    var joined = blocks.join('\n\n');
    if (estimateTokens(joined) > contextTokenBudget) {
      joined = truncateToTokens(joined, contextTokenBudget);
      joined = '$joined\n\n…（附件内容较长，已按上下文预算截断）';
    }
    return joined;
  }

  @override
  bool isSupported(String fileName) {
    // 所有文件都能作为附件：可抽文本的会注入内容，其余作为 document 引用。
    // 真正是否可用由文件大小与模型能力决定。
    return fileName.trim().isNotEmpty;
  }

  // ---------------------------------------------------------------------------
  // 内部实现
  // ---------------------------------------------------------------------------

  Future<AttachmentRef?> _toAttachment(PlatformFile file) async {
    final name = file.name.trim().isEmpty ? 'file' : file.name.trim();
    final extension = _extensionOf(name);
    final path = file.path;
    final id = Ids.newId('att');

    if (_imageExtensions.contains(extension)) {
      return AttachmentRef(
        id: id,
        name: name,
        mime: _mimeOf(extension),
        size: file.size,
        kind: AttachmentKind.image,
        localPath: path,
      );
    }

    if (extension == 'docx') {
      String? text;
      if (path != null) text = await _readDocxText(path);
      return AttachmentRef(
        id: id,
        name: name,
        mime: _mimeOf(extension),
        size: file.size,
        kind: AttachmentKind.text,
        localPath: path,
        extractedText: _emptyToNull(text),
      );
    }

    if (_textExtensions.contains(extension)) {
      String? text;
      if (path != null) text = await _readTextFile(path);
      return AttachmentRef(
        id: id,
        name: name,
        mime: _mimeOf(extension),
        size: file.size,
        kind: AttachmentKind.text,
        localPath: path,
        extractedText: _emptyToNull(text),
      );
    }

    // 其它二进制文件：只保留引用，不抽文本。
    return AttachmentRef(
      id: id,
      name: name,
      mime: _mimeOf(extension),
      size: file.size,
      kind: AttachmentKind.document,
      localPath: path,
    );
  }

  /// 读取文本文件（最多 [maxTextBytes] 字节），失败时返回空字符串。
  Future<String> _readTextFile(String path) async {
    try {
      final file = File(path);
      final length = await file.length();
      final limit = length > maxTextBytes ? maxTextBytes : length;
      final raf = await file.open();
      List<int> bytes = const <int>[];
      try {
        bytes = await raf.read(limit);
      } finally {
        await raf.close();
      }
      var text = utf8.decode(bytes, allowMalformed: true);
      text = text.replaceAll('\u0000', '');
      if (length > maxTextBytes) {
        text = '$text\n\n…（文件超过 ${_formatSize(maxTextBytes)}，内容已截断）';
      }
      return text;
    } catch (_) {
      return '';
    }
  }

  /// 从 docx 中抽正文：解压 word/document.xml 后去标签。
  Future<String> _readDocxText(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      ArchiveFile? documentXml;
      for (final entry in archive.files) {
        if (entry.name == 'word/document.xml') {
          documentXml = entry;
          break;
        }
      }
      final xmlFile = documentXml;
      if (xmlFile == null) return '';
      final dynamic raw = xmlFile.content;
      final List<int> xmlBytes =
          raw is List<int> ? raw : const <int>[];
      if (xmlBytes.isEmpty) return '';
      final xml = utf8.decode(xmlBytes, allowMalformed: true);
      return _extractDocxPlainText(xml);
    } catch (_) {
      return '';
    }
  }

  String _extractDocxPlainText(String xml) {
    var text = xml;
    // 段落 / 换行 / 制表符先转成可读的分隔符，再去掉所有 XML 标签。
    text = text.replaceAll(RegExp(r'</w:p\s*>'), '\n');
    text = text.replaceAll(RegExp(r'<w:br[^>]*/>'), '\n');
    text = text.replaceAll(RegExp(r'<w:tab[^>]*/>'), '\t');
    text = text.replaceAll(RegExp(r'<[^>]+>'), '');
    text = _unescapeXml(text);
    text = text.replaceAll(RegExp(r'[ \t]+\n'), '\n');
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return text.trim();
  }

  String _unescapeXml(String text) {
    return text
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&');
  }

  String? _emptyToNull(String? text) {
    final trimmed = (text ?? '').trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String _extensionOf(String name) {
    final baseName = name.split(RegExp(r'[\\/]')).last;
    final dot = baseName.lastIndexOf('.');
    if (dot < 0 || dot == baseName.length - 1) {
      // 无扩展名的常见文本文件（Dockerfile / Makefile）按文本处理。
      final lower = baseName.toLowerCase();
      if (lower == 'dockerfile' || lower == 'makefile' || lower == 'license') {
        return 'txt';
      }
      return '';
    }
    return baseName.substring(dot + 1).toLowerCase();
  }

  String _mimeOf(String extension) {
    switch (extension) {
      case 'txt':
      case 'text':
      case 'log':
      case 'md':
      case 'markdown':
        return extension == 'md' || extension == 'markdown'
            ? 'text/markdown'
            : 'text/plain';
      case 'json':
      case 'jsonl':
        return 'application/json';
      case 'csv':
        return 'text/csv';
      case 'tsv':
        return 'text/tab-separated-values';
      case 'yaml':
      case 'yml':
        return 'application/yaml';
      case 'xml':
        return 'application/xml';
      case 'html':
      case 'htm':
        return 'text/html';
      case 'css':
        return 'text/css';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'bmp':
        return 'image/bmp';
      case 'heic':
      case 'heif':
        return 'image/heic';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'doc':
        return 'application/msword';
      case 'pdf':
        return 'application/pdf';
      default:
        return 'application/octet-stream';
    }
  }

  String _formatSize(int bytes) {
    if (bytes >= 1024 * 1024) {
      final mb = bytes / (1024 * 1024);
      return mb == mb.roundToDouble() ? '${mb.toInt()}MB' : '${mb.toStringAsFixed(1)}MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).round()}KB';
    return '${bytes}B';
  }
}
