import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../core/secure_log.dart';
import 'vault.dart';

/// Strict, encrypted thumbnail cache. Only Twitch CDN HTTPS images are
/// accepted, redirects are rejected, and payloads are bounded before they are
/// persisted as authenticated vault records.
final class ThumbnailStore {
  ThumbnailStore({
    required VaultRepository vault,
    required SecureLog log,
    http.Client? client,
  }) : _vault = vault,
       _log = log,
       _client = client ?? http.Client();

  static const int _maximumBytes = 1024 * 1024;
  static const List<int> _magic = <int>[0x54, 0x46, 0x54, 0x48, 0x01];
  static const int _headerBytes = 13;
  final VaultRepository _vault;
  final SecureLog _log;
  final http.Client _client;

  Future<Uint8List?> load(String channel) async {
    final normalized = _channel(channel);
    if (normalized == null) return null;
    final record = await _vault.getBytes('channel_thumbnail', normalized);
    if (record == null) return null;
    if (record.lengthInBytes < _headerBytes ||
        !_magic.indexed.every((entry) => record[entry.$1] == entry.$2)) {
      await _vault.delete('channel_thumbnail', normalized);
      return null;
    }
    final expiresAtMillis = ByteData.sublistView(
      record,
      _magic.length,
      _headerBytes,
    ).getInt64(0, Endian.big);
    if (expiresAtMillis <= DateTime.now().toUtc().millisecondsSinceEpoch) {
      await _vault.delete('channel_thumbnail', normalized);
      return null;
    }
    final bytes = Uint8List.sublistView(record, _headerBytes);
    if (_validImage(bytes)) return bytes;
    await _vault.delete('channel_thumbnail', normalized);
    return null;
  }

  Future<Uint8List?> fetchAndStore({
    required String channel,
    required String url,
    required bool followed,
  }) async {
    final normalized = _channel(channel);
    final uri = Uri.tryParse(url);
    if (normalized == null || !_allowedUri(uri)) return null;
    final cached = await load(normalized);
    if (cached != null) return cached;
    try {
      final request = http.Request('GET', uri!)
        ..followRedirects = false
        ..headers['Accept'] = 'image/avif,image/webp,image/jpeg,image/png';
      final response = await _client
          .send(request)
          .timeout(const Duration(seconds: 12));
      final length = response.contentLength;
      final type = response.headers['content-type']?.split(';').first.trim();
      if (response.statusCode != 200 ||
          length != null && length > _maximumBytes ||
          !const {'image/jpeg', 'image/png', 'image/webp'}.contains(type)) {
        await response.stream.drain<void>();
        return null;
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.stream) {
        if (builder.length + chunk.length > _maximumBytes) return null;
        builder.add(chunk);
      }
      final bytes = builder.takeBytes();
      if (!_validImage(bytes)) return null;
      final now = DateTime.now().toUtc();
      final expiresAt = now.add(
        followed ? const Duration(days: 30) : const Duration(hours: 24),
      );
      final record = Uint8List(_headerBytes + bytes.lengthInBytes)
        ..setRange(0, _magic.length, _magic)
        ..setRange(_headerBytes, _headerBytes + bytes.lengthInBytes, bytes);
      ByteData.sublistView(
        record,
        _magic.length,
        _headerBytes,
      ).setInt64(0, expiresAt.millisecondsSinceEpoch, Endian.big);
      await _vault.putBytes('channel_thumbnail', normalized, record);
      return bytes;
    } catch (error) {
      _log.warning('Thumbnail cache request failed for $normalized: $error');
      return null;
    }
  }

  String? _channel(String value) {
    final normalized = value.trim().toLowerCase();
    return RegExp(r'^[a-z0-9_]{3,25}$').hasMatch(normalized)
        ? normalized
        : null;
  }

  bool _allowedUri(Uri? uri) =>
      uri != null &&
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      uri.port == 443 &&
      (uri.host.toLowerCase() == 'jtvnw.net' ||
          uri.host.toLowerCase().endsWith('.jtvnw.net'));

  bool _validImage(List<int> bytes) {
    if (bytes.length < 12 || bytes.length > _maximumBytes) return false;
    final jpeg = bytes[0] == 0xff && bytes[1] == 0xd8 && bytes[2] == 0xff;
    final png =
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47;
    final webp =
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50;
    return jpeg || png || webp;
  }

  void dispose() => _client.close();
}
