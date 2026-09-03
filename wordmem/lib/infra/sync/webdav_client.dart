/// 从网络同步 - SyncStorage 六操作接口 + 坚果云 WebDAV 实现
///
/// 依赖隔离（施工文档 §3.5）：`webdav_client_plus` 只允许出现在本文件内，
/// 上层（repository / UI / 测试）只认 [SyncStorage] 抽象。
///
/// ⚠️ Task 0 实测结论（2026-09-03）：webdav_client_plus 2.0.0 的 `readDir`
/// 存在双重 decode bug（parseFiles 解码一次后 parse() 再解码一次，Dart 的
/// `Uri.decodeFull` 对含裸中文的字符串抛 ArgumentError），目录里只要出现
/// 非 ASCII 文件名必崩——**因此 [WebdavSyncStorage.list] 不用 readDir，
/// 改为原始 PROPFIND + 自解析 XML**，解码自控（仅在含 % 时解码一次，
/// 失败回退原文）。证据链见 `Task0_坚果云WebDAV实测记录_20260903.md`。
library;

import 'dart:typed_data';

import 'package:webdav_client_plus/webdav_client_plus.dart';
import 'package:xml/xml.dart';

import '../../domain/services/sync/sync_models.dart';

/// 远端目录条目（list 结果，自条目已过滤）
class RemoteFile {
  final String name;
  final bool isDir;
  final int? size;

  const RemoteFile({required this.name, required this.isDir, this.size});

  @override
  String toString() => 'RemoteFile($name, dir=$isDir, size=$size)';
}

/// 六操作抽象（ping / mkdir / write / read / list / delete）
abstract class SyncStorage {
  Future<void> ping();
  Future<void> mkdir(String path); // 幂等：已存在视为成功
  Future<void> write(String path, Uint8List bytes);
  Future<Uint8List> read(String path);
  Future<List<RemoteFile>> list(String dirPath);
  Future<void> delete(String path); // 幂等：不存在视为成功
}

/// 统一错误类型（上层按 [code] 映射 §5 文案；[debug] 严禁含凭据）
class SyncStorageException implements Exception {
  final SyncErrorCode code;
  final int? statusCode;
  final String debug; // 仅状态码/操作名，无 URL 带凭据、无密码

  const SyncStorageException(this.code, {this.statusCode, this.debug = ''});

  @override
  String toString() =>
      'SyncStorageException(${code.name}${statusCode == null ? '' : ' $statusCode'})';
}

/// 坚果云（或任意 BasicAuth WebDAV）实现
class WebdavSyncStorage implements SyncStorage {
  static const Duration _timeout = Duration(milliseconds: 15000); // §5：15s

  final WebdavClient _client;

  WebdavSyncStorage({
    required String url,
    required String user,
    required String password,
  })  : _client = WebdavClient(
          url: url,
          auth: BasicAuth(user: user, pwd: password),
        ) {
    _client.setConnectTimeout(_timeout.inMilliseconds);
    _client.setSendTimeout(_timeout.inMilliseconds);
    _client.setReceiveTimeout(_timeout.inMilliseconds);
    _client.setHeaders({'accept-charset': 'utf-8'});
  }

  // ───────────────────────── 六操作 ─────────────────────────

  @override
  Future<void> ping() async {
    try {
      await _client.ping();
    } catch (e) {
      throw _map(e, 'ping');
    }
  }

  @override
  Future<void> mkdir(String path) async {
    try {
      await _client.mkdir(path);
    } catch (e) {
      final mapped = _map(e, 'mkdir');
      // 已存在 → 幂等成功（405 或服务器语义 200 均覆盖）
      if (mapped.statusCode == 405 || mapped.code == SyncErrorCode.unknown) {
        try {
          await _client.mkdirAll(path);
          return;
        } catch (e2) {
          final m2 = _map(e2, 'mkdirAll');
          if (m2.statusCode == 405) return; // 确实已存在
          throw m2;
        }
      }
      throw mapped;
    }
  }

  @override
  Future<void> write(String path, Uint8List bytes) async {
    try {
      await _client.write(path, bytes);
    } catch (e) {
      throw _map(e, 'write');
    }
  }

  @override
  Future<Uint8List> read(String path) async {
    try {
      return await _client.read(path);
    } catch (e) {
      throw _map(e, 'read');
    }
  }

  @override
  Future<void> delete(String path) async {
    try {
      await _client.remove(path);
    } catch (e) {
      final mapped = _map(e, 'delete');
      if (mapped.code == SyncErrorCode.notFound) return; // 幂等
      throw mapped;
    }
  }

  /// PROPFIND 列目录（自解析，绕开包的 readDir 双重 decode bug）。
  /// 自条目（目录本身）会被过滤。
  @override
  Future<List<RemoteFile>> list(String dirPath) async {
    const body = '<?xml version="1.0" encoding="utf-8"?>'
        '<d:propfind xmlns:d="DAV:"><d:prop>'
        '<d:resourcetype/><d:getcontentlength/>'
        '</d:prop></d:propfind>';
    String xml;
    try {
      final resp = await _client.request<String>(
        'PROPFIND',
        target: dirPath,
        data: body,
        headers: {
          'Depth': '1',
          'Content-Type': 'application/xml;charset=UTF-8',
        },
      );
      xml = resp.data ?? '';
    } catch (e) {
      throw _map(e, 'list');
    }

    final target = _normalizeDir(dirPath);
    final result = <RemoteFile>[];
    try {
      final doc = XmlDocument.parse(xml);
      for (final respEl in doc.findAllElements('response', namespaceUri: '*')) {
        final hrefEl =
            respEl.findAllElements('href', namespaceUri: '*').firstOrNull;
        if (hrefEl == null) continue;
        final href = hrefEl.innerText;
        final isDir = respEl
            .findAllElements('collection', namespaceUri: '*')
            .isNotEmpty;
        int? size;
        final sizeEl = respEl
            .findAllElements('getcontentlength', namespaceUri: '*')
            .firstOrNull;
        if (sizeEl != null) size = int.tryParse(sizeEl.innerText.trim());

        // 自条目过滤：解码后 href 以目标目录路径结尾（坚果云 href 带
        // '/dav' 前缀，用后缀比对兼容；'wordmem/wordmem' 类极端命名会
        // 误过滤，实际不会出现——快照目录只由本 App 创建）
        final decoded = _safeDecode(href);
        if (decoded.endsWith(target)) continue;

        final name = _lastSegment(decoded);
        if (name.isEmpty) continue;
        result.add(RemoteFile(name: name, isDir: isDir, size: size));
      }
    } on FormatException catch (e) {
      throw SyncStorageException(SyncErrorCode.server,
          debug: 'list-parse: ${e.message}');
    } on ArgumentError {
      throw const SyncStorageException(SyncErrorCode.server,
          debug: 'list-parse: invalid xml');
    }
    return result;
  }

  // ───────────────────────── 内部工具 ─────────────────────────

  /// 仅在含 % 时解码一次；解码失败回退原文（快照名是 ASCII，不影响功能）
  static String _safeDecode(String s) {
    if (!s.contains('%')) return s;
    try {
      return Uri.decodeFull(s);
    } catch (_) {
      return s;
    }
  }

  static String _lastSegment(String path) {
    final parts = path.split('/');
    for (var i = parts.length - 1; i >= 0; i--) {
      if (parts[i].isNotEmpty) return parts[i];
    }
    return '';
  }

  static String _normalizeDir(String p) {
    var s = p.trim();
    if (!s.startsWith('/')) s = '/$s';
    if (!s.endsWith('/')) s = '$s/';
    return s;
  }

  /// 包异常 → 统一错误（§5 判定依据；只留状态码，不留明文）
  SyncStorageException _map(Object e, String op) {
    if (e is SyncStorageException) return e;
    if (e is WebdavException) {
      final code = e.statusCode;
      return SyncStorageException(_codeOf(code), statusCode: code, debug: op);
    }
    final s = e.toString();
    // Dio 网络层错误按字符串判定（避免引入 dio 依赖）：连接失败/超时 → network
    if (s.contains('SocketException') ||
        s.contains('TimeoutException') ||
        s.contains('Connection timed out') ||
        s.contains('connection error')) {
      return SyncStorageException(SyncErrorCode.network, debug: op);
    }
    return SyncStorageException(SyncErrorCode.unknown, debug: op);
  }

  static SyncErrorCode _codeOf(int? status) {
    switch (status) {
      case 401:
      case 403:
        return SyncErrorCode.auth;
      case 404:
        return SyncErrorCode.notFound;
      case 429:
      case 503:
        return SyncErrorCode.rateLimited;
      case 507:
        return SyncErrorCode.quota;
      default:
        if (status != null && status >= 500) return SyncErrorCode.server;
        return SyncErrorCode.unknown;
    }
  }
}
