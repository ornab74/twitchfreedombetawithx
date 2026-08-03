import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:twitch_freedom_ultra/core/result.dart';
import 'package:twitch_freedom_ultra/core/secure_log.dart';
import 'package:twitch_freedom_ultra/security/vault.dart';

void main() {
  test(
    'vault encrypts records and cryptographically retires rotated keys',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'twitch-freedom-vault-test-',
      );
      addTearDown(() async {
        if (directory.existsSync()) await directory.delete(recursive: true);
      });
      final file = File('${directory.path}/vault.sqlite3');
      final vault = VaultRepository(log: SecureLog(), databaseFile: file);

      final created = await vault.create(
        password: 'correct horse battery staple',
        rememberOnDevice: false,
      );
      expect(created, isA<AppSuccess<void>>());
      await vault.putJson('secret', 'oauth', <String, Object?>{
        'accessToken': 'must-never-appear-in-the-database',
      });

      final rotated = await vault.rotateDataKey();
      expect(rotated, isA<AppSuccess<int>>());
      expect((rotated as AppSuccess<int>).value, 2);
      expect(
        await vault.getJson('secret', 'oauth'),
        containsPair('accessToken', 'must-never-appear-in-the-database'),
      );
      await vault.close();

      final rawDatabase = latin1.decode(file.readAsBytesSync());
      expect(rawDatabase, isNot(contains('must-never-appear-in-the-database')));
      final database = sqlite3.open(file.path, mode: OpenMode.readOnly);
      try {
        final wrappedKeyCount = database
            .select('SELECT COUNT(*) AS total FROM wrapped_deks')
            .single['total'];
        expect(wrappedKeyCount, 1);
        final activeVersion = database
            .select("SELECT value FROM vault_meta WHERE key = 'active_dek'")
            .single['value'];
        expect(activeVersion, '2');
      } finally {
        database.close();
      }

      final reopened = VaultRepository(log: SecureLog(), databaseFile: file);
      final unlocked = await reopened.unlockWithPassword(
        'correct horse battery staple',
      );
      expect(unlocked, isA<AppSuccess<void>>());
      expect(
        await reopened.getJson('secret', 'oauth'),
        containsPair('accessToken', 'must-never-appear-in-the-database'),
      );
      await reopened.destroyVault();
      expect(file.existsSync(), isFalse);
      expect(File('${file.path}-wal').existsSync(), isFalse);
      expect(File('${file.path}-shm').existsSync(), isFalse);
    },
  );
}
