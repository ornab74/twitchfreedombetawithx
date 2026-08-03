import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../core/result.dart';
import '../core/secure_log.dart';

final class VaultStatus {
  const VaultStatus({
    required this.exists,
    required this.unlocked,
    required this.rememberedUnlockAvailable,
  });
  final bool exists;
  final bool unlocked;
  final bool rememberedUnlockAvailable;
}

final class VaultRepository {
  VaultRepository({
    required SecureLog log,
    FlutterSecureStorage? secureStorage,
    File? databaseFile,
  }) : this._internal(
         log,
         secureStorage ??
             const FlutterSecureStorage(
               wOptions: WindowsOptions(useBackwardCompatibility: false),
             ),
         databaseFile,
       );

  VaultRepository._internal(this._log, this._secureStorage, this._databaseFile);

  static const String _rememberedKey = 'twitchfreedom.vuk.v1';
  static const String _metaSalt = 'kek_salt';
  static const String _metaWrappedVuk = 'wrapped_vuk';
  static const String _metaVerifier = 'verifier';
  static const String _metaActiveDek = 'active_dek';
  static const String _metaKdf = 'kdf_profile';
  static const String _metaCreatedAt = 'created_at';

  final SecureLog _log;
  final FlutterSecureStorage _secureStorage;
  final AesGcm _aes = AesGcm.with256bits();
  final Argon2id _argon2 = Argon2id(
    memory: 64 * 1024,
    parallelism: 2,
    iterations: 3,
    hashLength: 32,
  );
  final Hmac _hmac = Hmac.sha256();
  final Random _random = Random.secure();

  Database? _db;
  Uint8List? _vuk;
  final Map<int, Uint8List> _deks = <int, Uint8List>{};
  int _activeDekVersion = 0;
  File? _databaseFile;

  bool get isUnlocked => _db != null && _vuk != null && _activeDekVersion > 0;

  Future<File> _resolveDatabaseFile() async {
    if (_databaseFile != null) return _databaseFile!;
    final root = await getApplicationSupportDirectory();
    final directory = Directory(p.join(root.path, 'TwitchFreedom'));
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
    _databaseFile = File(p.join(directory.path, 'vault.sqlite3'));
    return _databaseFile!;
  }

  Future<VaultStatus> status() async {
    final file = await _resolveDatabaseFile();
    var remembered = false;
    try {
      remembered = await _secureStorage.containsKey(key: _rememberedKey);
    } catch (error) {
      // A locked or unavailable desktop keyring must not prevent password
      // unlock. Secure storage is an optional convenience only.
      _log.warning('OS secure storage unavailable during vault probe: $error');
    }
    return VaultStatus(
      exists: file.existsSync(),
      unlocked: isUnlocked,
      rememberedUnlockAvailable: remembered,
    );
  }

  Future<AppResult<void>> create({
    required String password,
    required bool rememberOnDevice,
  }) async {
    Uint8List? kek;
    Uint8List? generatedVuk;
    Uint8List? generatedDek;
    var adoptedKeyMaterial = false;
    try {
      if (password.length < 10) {
        return const AppError<void>(
          AppFailure(
            'weak_password',
            'Use at least 10 characters for the boot password.',
          ),
        );
      }
      final file = await _resolveDatabaseFile();
      if (file.existsSync()) {
        return const AppError<void>(
          AppFailure('vault_exists', 'A vault already exists.'),
        );
      }
      _open(file);
      _ensureSchema();

      final salt = _randomBytes(16);
      kek = await _deriveKek(password, salt);
      generatedVuk = _randomBytes(32);
      generatedDek = _randomBytes(32);
      final wrappedVuk = await _encrypt(
        generatedVuk,
        kek,
        utf8.encode('twitchfreedom:vuk:v1'),
      );
      final verifier = await _encrypt(
        utf8.encode('twitchfreedom-vault-verifier-v1'),
        generatedVuk,
        utf8.encode('meta:verifier'),
      );
      final wrappedDek = await _encrypt(
        generatedDek,
        generatedVuk,
        utf8.encode('dek:1'),
      );

      _db!.execute('BEGIN IMMEDIATE');
      try {
        _setMeta(_metaSalt, base64UrlEncode(salt));
        _setMeta(_metaWrappedVuk, base64UrlEncode(wrappedVuk));
        _setMeta(_metaVerifier, base64UrlEncode(verifier));
        _setMeta(_metaActiveDek, '1');
        _setMeta(
          _metaKdf,
          jsonEncode(<String, Object>{
            'algorithm': 'Argon2id',
            'memoryKiB': 65536,
            'parallelism': 2,
            'iterations': 3,
            'hashLength': 32,
          }),
        );
        _setMeta(_metaCreatedAt, DateTime.now().toUtc().toIso8601String());
        _db!.execute(
          'INSERT INTO wrapped_deks(version, envelope, created_at, retired_at) VALUES(?, ?, ?, NULL)',
          <Object?>[1, wrappedDek, DateTime.now().toUtc().toIso8601String()],
        );
        _db!.execute('COMMIT');
      } catch (_) {
        _db!.execute('ROLLBACK');
        rethrow;
      }

      _vuk = generatedVuk;
      _deks[1] = generatedDek;
      _activeDekVersion = 1;
      adoptedKeyMaterial = true;
      if (rememberOnDevice) {
        try {
          await _setRememberedUnlock(generatedVuk);
        } catch (error) {
          // The vault itself is already safely committed. Keep password
          // unlock working and fail closed by storing no device secret.
          _log.warning('Vault created without remembered unlock: $error');
        }
      }
      _hardenFilePermissions(file);
      _log.info(
        'Created encrypted vault with Argon2id + wrapped VUK + AES-256-GCM records.',
      );
      return const AppSuccess<void>(null);
    } catch (error) {
      await close();
      return AppError<void>(
        AppFailure(
          'vault_create_failed',
          'Could not create the encrypted vault.',
          cause: error,
        ),
      );
    } finally {
      _wipe(kek);
      if (!adoptedKeyMaterial) {
        _wipe(generatedVuk);
        _wipe(generatedDek);
      }
    }
  }

  Future<AppResult<void>> unlockWithPassword(String password) async {
    Uint8List? kek;
    List<int>? clearVuk;
    try {
      final file = await _resolveDatabaseFile();
      if (!file.existsSync()) {
        return const AppError<void>(
          AppFailure('vault_missing', 'No vault exists yet.'),
        );
      }
      _open(file);
      _ensureSchema();
      final saltText = _getMeta(_metaSalt);
      final wrappedText = _getMeta(_metaWrappedVuk);
      if (saltText == null || wrappedText == null) {
        throw const FormatException('Vault metadata is incomplete.');
      }
      final salt = base64Url.decode(saltText);
      kek = await _deriveKek(password, salt);
      clearVuk = await _decrypt(
        base64Url.decode(wrappedText),
        kek,
        utf8.encode('twitchfreedom:vuk:v1'),
      );
      await _finishUnlock(Uint8List.fromList(clearVuk));
      _log.info('Vault unlocked with boot password.');
      return const AppSuccess<void>(null);
    } catch (error) {
      await close();
      return AppError<void>(
        AppFailure(
          'unlock_failed',
          'The password could not authenticate this vault.',
          cause: error,
        ),
      );
    } finally {
      _wipe(kek);
      _wipe(clearVuk);
    }
  }

  Future<AppResult<void>> unlockRemembered() async {
    try {
      final encoded = await _secureStorage.read(key: _rememberedKey);
      if (encoded == null || encoded.isEmpty) {
        return const AppError<void>(
          AppFailure(
            'remembered_unlock_missing',
            'No operating-system unlock secret is stored.',
          ),
        );
      }
      final file = await _resolveDatabaseFile();
      if (!file.existsSync()) {
        return const AppError<void>(
          AppFailure('vault_missing', 'No vault exists yet.'),
        );
      }
      _open(file);
      _ensureSchema();
      await _finishUnlock(Uint8List.fromList(base64Url.decode(encoded)));
      _log.info('Vault unlocked through operating-system secure storage.');
      return const AppSuccess<void>(null);
    } catch (error) {
      await close();
      try {
        await _secureStorage.delete(key: _rememberedKey);
      } catch (deleteError) {
        _log.warning(
          'Could not clear rejected remembered unlock: $deleteError',
        );
      }
      return AppError<void>(
        AppFailure(
          'remembered_unlock_failed',
          'The stored unlock secret was rejected and removed.',
          cause: error,
        ),
      );
    }
  }

  Future<void> _finishUnlock(Uint8List vuk) async {
    final loaded = <int, Uint8List>{};
    List<int>? clearVerifier;
    var adoptedKeyMaterial = false;
    try {
      final verifierText = _getMeta(_metaVerifier);
      if (verifierText == null) {
        throw const FormatException('Missing verifier.');
      }
      clearVerifier = await _decrypt(
        base64Url.decode(verifierText),
        vuk,
        utf8.encode('meta:verifier'),
      );
      if (!_constantTimeEquals(
        clearVerifier,
        utf8.encode('twitchfreedom-vault-verifier-v1'),
      )) {
        throw StateError('Vault verifier mismatch.');
      }

      final active = int.tryParse(_getMeta(_metaActiveDek) ?? '') ?? 0;
      if (active <= 0) throw const FormatException('Missing active DEK.');
      final rows = _db!.select(
        'SELECT version, envelope FROM wrapped_deks WHERE retired_at IS NULL ORDER BY version',
      );
      for (final row in rows) {
        final version = row['version'] as int;
        final envelope = row['envelope'] as Uint8List;
        List<int>? clearDek;
        try {
          clearDek = await _decrypt(envelope, vuk, utf8.encode('dek:$version'));
          loaded[version] = Uint8List.fromList(clearDek);
        } finally {
          _wipe(clearDek);
        }
      }
      if (!loaded.containsKey(active)) {
        throw const FormatException('Active DEK could not be loaded.');
      }
      _clearKeyMaterial();
      _vuk = vuk;
      _deks.addAll(loaded);
      _activeDekVersion = active;
      adoptedKeyMaterial = true;
    } finally {
      _wipe(clearVerifier);
      if (!adoptedKeyMaterial) {
        _wipe(vuk);
        for (final dek in loaded.values) {
          _wipe(dek);
        }
      }
    }
  }

  Future<AppResult<void>> changePassword({
    required String newPassword,
    required bool rememberOnDevice,
  }) async {
    if (!isUnlocked) {
      return const AppError<void>(
        AppFailure('vault_locked', 'Unlock the vault first.'),
      );
    }
    if (newPassword.length < 10) {
      return const AppError<void>(
        AppFailure(
          'weak_password',
          'Use at least 10 characters for the boot password.',
        ),
      );
    }
    Uint8List? kek;
    try {
      final salt = _randomBytes(16);
      kek = await _deriveKek(newPassword, salt);
      final wrappedVuk = await _encrypt(
        _vuk!,
        kek,
        utf8.encode('twitchfreedom:vuk:v1'),
      );
      // Removing remembered unlock must happen before the password commit so
      // a failed OS-storage deletion can never leave an unwanted auto-unlock.
      if (!rememberOnDevice) await _setRememberedUnlock(null);
      _db!.execute('BEGIN IMMEDIATE');
      try {
        _setMeta(_metaSalt, base64UrlEncode(salt));
        _setMeta(_metaWrappedVuk, base64UrlEncode(wrappedVuk));
        _db!.execute('COMMIT');
      } catch (_) {
        _db!.execute('ROLLBACK');
        rethrow;
      }
      if (rememberOnDevice) await _setRememberedUnlock(_vuk);
      _log.info('Boot password changed by rewrapping the vault-unlock key.');
      return const AppSuccess<void>(null);
    } catch (error) {
      return AppError<void>(
        AppFailure(
          'password_change_failed',
          'Could not rewrap the vault key.',
          cause: error,
        ),
      );
    } finally {
      _wipe(kek);
    }
  }

  Future<AppResult<int>> rotateDataKey() async {
    if (!isUnlocked) {
      return const AppError<int>(
        AppFailure('vault_locked', 'Unlock the vault first.'),
      );
    }
    final oldVersion = _activeDekVersion;
    final newVersion = oldVersion + 1;
    final newDek = _randomBytes(32);
    try {
      final wrapped = await _encrypt(
        newDek,
        _vuk!,
        utf8.encode('dek:$newVersion'),
      );
      _db!.execute('BEGIN IMMEDIATE');
      try {
        _db!.execute(
          'INSERT INTO wrapped_deks(version, envelope, created_at, retired_at) VALUES(?, ?, ?, NULL)',
          <Object?>[
            newVersion,
            wrapped,
            DateTime.now().toUtc().toIso8601String(),
          ],
        );
        _setMeta(_metaActiveDek, '$newVersion');

        final rows = _db!.select(
          'SELECT record_id, logical_type, key_version, envelope FROM encrypted_records WHERE key_version != ?',
          <Object?>[newVersion],
        );
        for (final row in rows) {
          final oldKeyVersion = row['key_version'] as int;
          final oldDek = _deks[oldKeyVersion];
          if (oldDek == null) {
            throw StateError(
              'Missing DEK version $oldKeyVersion during rotation.',
            );
          }
          final recordId = row['record_id'] as String;
          final logicalType = row['logical_type'] as String;
          List<int>? clear;
          try {
            clear = await _decrypt(
              row['envelope'] as Uint8List,
              oldDek,
              utf8.encode('$logicalType:$recordId:$oldKeyVersion'),
            );
            final nextEnvelope = await _encrypt(
              clear,
              newDek,
              utf8.encode('$logicalType:$recordId:$newVersion'),
            );
            _db!.execute(
              'UPDATE encrypted_records SET key_version = ?, envelope = ?, updated_at = ? WHERE record_id = ?',
              <Object?>[
                newVersion,
                nextEnvelope,
                DateTime.now().toUtc().toIso8601String(),
                recordId,
              ],
            );
          } finally {
            _wipe(clear);
          }
        }
        _db!.execute(
          'DELETE FROM wrapped_deks WHERE version < ? AND version NOT IN '
          '(SELECT DISTINCT key_version FROM encrypted_records)',
          <Object?>[newVersion],
        );
        _db!.execute('COMMIT');
      } catch (_) {
        _db!.execute('ROLLBACK');
        rethrow;
      }

      _deks[newVersion] = newDek;
      _activeDekVersion = newVersion;
      final retiredVersions = _deks.keys
          .where((version) => version < newVersion)
          .toList(growable: false);
      for (final version in retiredVersions) {
        final retired = _deks.remove(version);
        _wipe(retired);
      }
      try {
        _db!.execute('PRAGMA wal_checkpoint(TRUNCATE)');
        _db!.execute('PRAGMA incremental_vacuum');
      } catch (error) {
        _log.warning('Rotated keys; deferred SQLite page cleanup: $error');
      }
      _log.info(
        'Transactionally rotated encrypted records to key version $newVersion.',
      );
      return AppSuccess<int>(newVersion);
    } catch (error) {
      _wipe(newDek);
      return AppError<int>(
        AppFailure(
          'dek_rotation_failed',
          'Could not rotate the data-encryption key.',
          cause: error,
        ),
      );
    }
  }

  Future<void> setRememberOnDevice(bool enabled) async {
    if (!isUnlocked) throw StateError('Vault is locked.');
    await _setRememberedUnlock(enabled ? _vuk : null);
  }

  Future<void> _setRememberedUnlock(Uint8List? vuk) async {
    if (vuk == null) {
      await _secureStorage.delete(key: _rememberedKey);
    } else {
      await _secureStorage.write(
        key: _rememberedKey,
        value: base64UrlEncode(vuk),
      );
    }
  }

  Future<void> putJson(
    String logicalType,
    String logicalId,
    Map<String, Object?> value,
  ) async {
    if (!isUnlocked) throw StateError('Vault is locked.');
    final recordId = await _obscuredId(logicalType, logicalId);
    final clear = utf8.encode(jsonEncode(value));
    try {
      final version = _activeDekVersion;
      final envelope = await _encrypt(
        clear,
        _deks[version]!,
        utf8.encode('$logicalType:$recordId:$version'),
      );
      _db!.execute(
        '''
      INSERT INTO encrypted_records(record_id, logical_type, key_version, envelope, updated_at)
      VALUES(?, ?, ?, ?, ?)
      ON CONFLICT(record_id) DO UPDATE SET
        logical_type = excluded.logical_type,
        key_version = excluded.key_version,
        envelope = excluded.envelope,
        updated_at = excluded.updated_at
      ''',
        <Object?>[
          recordId,
          logicalType,
          version,
          envelope,
          DateTime.now().toUtc().toIso8601String(),
        ],
      );
    } finally {
      _wipe(clear);
    }
  }

  Future<void> putBytes(
    String logicalType,
    String logicalId,
    Uint8List clear,
  ) async {
    if (!isUnlocked) throw StateError('Vault is locked.');
    final recordId = await _obscuredId(logicalType, logicalId);
    final version = _activeDekVersion;
    final envelope = await _encrypt(
      clear,
      _deks[version]!,
      utf8.encode('$logicalType:$recordId:$version'),
    );
    _db!.execute(
      '''
      INSERT INTO encrypted_records(record_id, logical_type, key_version, envelope, updated_at)
      VALUES(?, ?, ?, ?, ?)
      ON CONFLICT(record_id) DO UPDATE SET
        logical_type = excluded.logical_type,
        key_version = excluded.key_version,
        envelope = excluded.envelope,
        updated_at = excluded.updated_at
      ''',
      <Object?>[
        recordId,
        logicalType,
        version,
        envelope,
        DateTime.now().toUtc().toIso8601String(),
      ],
    );
  }

  /// Encrypts records independently, then commits their envelopes in one WAL
  /// transaction. This keeps per-record authentication while avoiding an
  /// expensive durable SQLite commit for every high-volume chat event.
  Future<void> putJsonBatch(
    String logicalType,
    Map<String, Map<String, Object?>> values,
  ) async {
    if (!isUnlocked) throw StateError('Vault is locked.');
    if (values.isEmpty) return;
    final version = _activeDekVersion;
    final prepared = <({String recordId, Uint8List envelope})>[];
    for (final entry in values.entries) {
      final recordId = await _obscuredId(logicalType, entry.key);
      final clear = utf8.encode(jsonEncode(entry.value));
      try {
        final envelope = await _encrypt(
          clear,
          _deks[version]!,
          utf8.encode('$logicalType:$recordId:$version'),
        );
        prepared.add((recordId: recordId, envelope: envelope));
      } finally {
        _wipe(clear);
      }
    }

    final updatedAt = DateTime.now().toUtc().toIso8601String();
    _db!.execute('BEGIN IMMEDIATE');
    try {
      for (final record in prepared) {
        _db!.execute(
          '''
          INSERT INTO encrypted_records(record_id, logical_type, key_version, envelope, updated_at)
          VALUES(?, ?, ?, ?, ?)
          ON CONFLICT(record_id) DO UPDATE SET
            logical_type = excluded.logical_type,
            key_version = excluded.key_version,
            envelope = excluded.envelope,
            updated_at = excluded.updated_at
          ''',
          <Object?>[
            record.recordId,
            logicalType,
            version,
            record.envelope,
            updatedAt,
          ],
        );
      }
      _db!.execute('COMMIT');
    } catch (_) {
      _db!.execute('ROLLBACK');
      rethrow;
    }
  }

  Future<Map<String, Object?>?> getJson(
    String logicalType,
    String logicalId,
  ) async {
    if (!isUnlocked) throw StateError('Vault is locked.');
    final recordId = await _obscuredId(logicalType, logicalId);
    final rows = _db!.select(
      'SELECT key_version, envelope FROM encrypted_records WHERE record_id = ? AND logical_type = ?',
      <Object?>[recordId, logicalType],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final version = row['key_version'] as int;
    final dek = _deks[version];
    if (dek == null) {
      throw StateError('Record references unavailable key version $version.');
    }
    List<int>? clear;
    try {
      clear = await _decrypt(
        row['envelope'] as Uint8List,
        dek,
        utf8.encode('$logicalType:$recordId:$version'),
      );
      return Map<String, Object?>.from(
        jsonDecode(utf8.decode(clear)) as Map<Object?, Object?>,
      );
    } finally {
      _wipe(clear);
    }
  }

  Future<Uint8List?> getBytes(String logicalType, String logicalId) async {
    if (!isUnlocked) throw StateError('Vault is locked.');
    final recordId = await _obscuredId(logicalType, logicalId);
    final rows = _db!.select(
      'SELECT key_version, envelope FROM encrypted_records WHERE record_id = ? AND logical_type = ?',
      <Object?>[recordId, logicalType],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final version = row['key_version'] as int;
    final dek = _deks[version];
    if (dek == null) {
      throw StateError('Record references unavailable key version $version.');
    }
    List<int>? clear;
    try {
      clear = await _decrypt(
        row['envelope'] as Uint8List,
        dek,
        utf8.encode('$logicalType:$recordId:$version'),
      );
      return Uint8List.fromList(clear);
    } finally {
      _wipe(clear);
    }
  }

  Future<List<Map<String, Object?>>> getAllJson(String logicalType) async {
    if (!isUnlocked) throw StateError('Vault is locked.');
    final rows = _db!.select(
      'SELECT record_id, key_version, envelope FROM encrypted_records WHERE logical_type = ? ORDER BY updated_at DESC',
      <Object?>[logicalType],
    );
    final result = <Map<String, Object?>>[];
    for (final row in rows) {
      final version = row['key_version'] as int;
      final dek = _deks[version];
      if (dek == null) continue;
      final recordId = row['record_id'] as String;
      List<int>? clear;
      try {
        clear = await _decrypt(
          row['envelope'] as Uint8List,
          dek,
          utf8.encode('$logicalType:$recordId:$version'),
        );
        result.add(
          Map<String, Object?>.from(
            jsonDecode(utf8.decode(clear)) as Map<Object?, Object?>,
          ),
        );
      } catch (error) {
        _log.warning('Skipped one unauthenticated $logicalType record: $error');
      } finally {
        _wipe(clear);
      }
    }
    return result;
  }

  Future<void> delete(String logicalType, String logicalId) async {
    if (!isUnlocked) throw StateError('Vault is locked.');
    final recordId = await _obscuredId(logicalType, logicalId);
    _db!.execute(
      'DELETE FROM encrypted_records WHERE record_id = ? AND logical_type = ?',
      <Object?>[recordId, logicalType],
    );
  }

  Future<void> deleteType(String logicalType) async {
    if (!isUnlocked) throw StateError('Vault is locked.');
    _db!.execute(
      'DELETE FROM encrypted_records WHERE logical_type = ?',
      <Object?>[logicalType],
    );
  }

  /// Forces sensitive deletions and key rotations out of SQLite's WAL.
  Future<void> purgeDeletedPages() async {
    if (!isUnlocked) throw StateError('Vault is locked.');
    _db!.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    _db!.execute('PRAGMA incremental_vacuum');
  }

  Future<void> close() async {
    final database = _db;
    _db = null;
    try {
      database?.close();
    } finally {
      _clearKeyMaterial();
    }
  }

  Future<void> destroyVault() async {
    await close();
    try {
      await _secureStorage.delete(key: _rememberedKey);
    } catch (error) {
      _log.warning(
        'OS secure-storage cleanup skipped while destroying vault: $error',
      );
    }
    final file = await _resolveDatabaseFile();
    for (final path in <String>[
      file.path,
      '${file.path}-wal',
      '${file.path}-shm',
    ]) {
      final candidate = File(path);
      if (candidate.existsSync()) candidate.deleteSync();
    }
  }

  void _open(File file) {
    final previous = _db;
    _db = null;
    try {
      previous?.close();
    } finally {
      _clearKeyMaterial();
    }
    _db = sqlite3.open(file.path);
    _db!.execute('PRAGMA journal_mode = WAL');
    _db!.execute('PRAGMA synchronous = FULL');
    _db!.execute('PRAGMA foreign_keys = ON');
    _db!.execute('PRAGMA trusted_schema = OFF');
    _db!.execute('PRAGMA secure_delete = ON');
    // Keep temporary query material in RAM. Persistent application records are
    // already independently encrypted before SQLite sees them.
    _db!.execute('PRAGMA temp_store = MEMORY');
    _db!.execute('PRAGMA cache_size = -8192');
    _db!.execute('PRAGMA busy_timeout = 5000');
  }

  void _ensureSchema() {
    _db!.execute('''
      CREATE TABLE IF NOT EXISTS vault_meta(
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    _db!.execute('''
      CREATE TABLE IF NOT EXISTS wrapped_deks(
        version INTEGER PRIMARY KEY,
        envelope BLOB NOT NULL,
        created_at TEXT NOT NULL,
        retired_at TEXT
      )
    ''');
    _db!.execute('''
      CREATE TABLE IF NOT EXISTS encrypted_records(
        record_id TEXT PRIMARY KEY,
        logical_type TEXT NOT NULL,
        key_version INTEGER NOT NULL REFERENCES wrapped_deks(version),
        envelope BLOB NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    _db!.execute(
      'CREATE INDEX IF NOT EXISTS idx_records_type_updated ON encrypted_records(logical_type, updated_at DESC)',
    );
  }

  void _setMeta(String key, String value) {
    _db!.execute(
      'INSERT INTO vault_meta(key, value) VALUES(?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value',
      <Object?>[key, value],
    );
  }

  String? _getMeta(String key) {
    final rows = _db!.select(
      'SELECT value FROM vault_meta WHERE key = ?',
      <Object?>[key],
    );
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<Uint8List> _deriveKek(String password, List<int> salt) async {
    final key = await _argon2.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );
    final extracted = await key.extractBytes();
    try {
      return Uint8List.fromList(extracted);
    } finally {
      key.destroy();
    }
  }

  Future<Uint8List> _encrypt(
    List<int> clear,
    List<int> keyBytes,
    List<int> aad,
  ) async {
    final box = await _aes.encrypt(
      clear,
      secretKey: SecretKey(keyBytes),
      aad: aad,
    );
    return Uint8List.fromList(box.concatenation());
  }

  Future<List<int>> _decrypt(
    List<int> envelope,
    List<int> keyBytes,
    List<int> aad,
  ) async {
    final box = SecretBox.fromConcatenation(
      envelope,
      nonceLength: _aes.nonceLength,
      macLength: _aes.macAlgorithm.macLength,
      copy: false,
    );
    return _aes.decrypt(box, secretKey: SecretKey(keyBytes), aad: aad);
  }

  Future<String> _obscuredId(String logicalType, String logicalId) async {
    final mac = await _hmac.calculateMac(
      utf8.encode('$logicalType\u0000$logicalId'),
      secretKey: SecretKey(_vuk!),
    );
    return base64UrlEncode(mac.bytes).replaceAll('=', '');
  }

  Uint8List _randomBytes(int count) {
    final bytes = Uint8List(count);
    for (var index = 0; index < count; index++) {
      bytes[index] = _random.nextInt(256);
    }
    return bytes;
  }

  bool _constantTimeEquals(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var index = 0; index < left.length; index++) {
      difference |= left[index] ^ right[index];
    }
    return difference == 0;
  }

  void _clearKeyMaterial() {
    _wipe(_vuk);
    for (final dek in _deks.values) {
      _wipe(dek);
    }
    _vuk = null;
    _deks.clear();
    _activeDekVersion = 0;
  }

  void _wipe(List<int>? bytes) {
    if (bytes == null) return;
    for (var index = 0; index < bytes.length; index++) {
      bytes[index] = 0;
    }
  }

  void _hardenFilePermissions(File file) {
    if (Platform.isWindows) return;
    try {
      final chmod = File('/bin/chmod').existsSync()
          ? '/bin/chmod'
          : '/usr/bin/chmod';
      if (File(chmod).existsSync()) {
        Process.runSync(chmod, <String>['600', file.path], runInShell: false);
      }
    } catch (_) {
      // Best effort. The application still relies on authenticated record encryption.
    }
  }
}
