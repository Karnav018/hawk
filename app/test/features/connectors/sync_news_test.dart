import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/features/connectors/domain/entities/storage_account.dart';
import 'package:knowra/src/features/connectors/domain/entities/storage_provider.dart';
import 'package:knowra/src/features/connectors/presentation/sync_news.dart';

/// The assistant snack's one real trigger: files the scheduled Drive sync
/// added on its own.
void main() {
  final seen = DateTime(2026, 9, 27, 6);

  StorageAccount drive({int added = 0, DateTime? at, String id = 'a'}) =>
      StorageAccount(
        id: id,
        provider: StorageProvider.googleDrive,
        lastSyncAdded: added,
        lastSyncAddedAt: at,
      );

  test('a sync that added files since the last news is news', () {
    final news = SyncNews.newsSince([
      drive(added: 3, at: seen.add(const Duration(hours: 6))),
    ], seen);
    expect(news?.message, 'Found 3 new files in Google Drive');
    expect(news?.at, seen.add(const Duration(hours: 6)));
  });

  test('one file is "file", not "files"', () {
    final news = SyncNews.newsSince([
      drive(added: 1, at: seen.add(const Duration(minutes: 1))),
    ], seen);
    expect(news?.message, 'Found 1 new file in Google Drive');
  });

  test('what was already announced is not news again', () {
    expect(SyncNews.newsSince([drive(added: 3, at: seen)], seen), isNull);
    expect(
      SyncNews.newsSince([
        drive(added: 3, at: seen.subtract(const Duration(days: 1))),
      ], seen),
      isNull,
    );
  });

  test('an account that never added anything says nothing', () {
    expect(SyncNews.newsSince([drive()], seen), isNull);
  });

  test('two accounts in one window are one piece of news', () {
    final news = SyncNews.newsSince([
      drive(added: 2, at: seen.add(const Duration(hours: 1))),
      drive(id: 'b', added: 5, at: seen.add(const Duration(hours: 2))),
    ], seen);
    expect(news?.added, 7);
    expect(news?.at, seen.add(const Duration(hours: 2)));
  });
}
