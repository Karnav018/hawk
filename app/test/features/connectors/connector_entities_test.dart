import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/features/connectors/domain/entities/index_job.dart';
import 'package:knowra/src/features/connectors/domain/entities/storage_account.dart';
import 'package:knowra/src/features/connectors/domain/entities/storage_provider.dart';

void main() {
  group('StorageAccount.statusLine', () {
    StorageAccount account({
      ConnectorState state = ConnectorState.connected,
      int files = 0,
      int bytes = 0,
    }) => StorageAccount(
      id: 'a',
      provider: StorageProvider.googleDrive,
      state: state,
      fileCount: files,
      bytes: bytes,
    );

    test('matches the design, thousands separator and all', () {
      // "10,412 FILES · 148 GB" — this is set in the metadata face and
      // the separator has to be exact.
      expect(
        account(files: 10412, bytes: 148 * 1024 * 1024 * 1024).statusLine,
        '10,412 FILES · 148 GB',
      );
    });

    test('keeps one decimal only while it means something', () {
      expect(
        account(
          files: 412,
          bytes: (8.2 * 1024 * 1024 * 1024).round(),
        ).statusLine,
        '412 FILES · 8.2 GB',
      );
    });

    test('a problem outranks the file count', () {
      // Somebody whose access was revoked needs to see that, not "10,412
      // FILES" — the count is describing an index they can no longer refresh.
      expect(
        account(state: ConnectorState.revoked, files: 10412).statusLine,
        'ACCESS REVOKED',
      );
      expect(
        account(state: ConnectorState.error, files: 10412).statusLine,
        'NEEDS ATTENTION',
      );
    });

    test('a connected account with nothing indexed yet is not "0 FILES"', () {
      expect(account().statusLine, 'CONNECTED');
    });
  });

  group('ConnectorCatalog', () {
    ConnectorOption option({StorageAccount? account}) => ConnectorOption(
      provider: StorageProvider.googleDrive,
      isConfigured: true,
      account: account,
    );

    test('a revoked account does not count as connected', () {
      // It still occupies a row on 3F, but it must not satisfy "you have
      // storage connected" — otherwise Continue is enabled for somebody with
      // no working connection.
      final revoked = option(
        account: const StorageAccount(
          id: 'a',
          provider: StorageProvider.googleDrive,
          state: ConnectorState.revoked,
        ),
      );
      expect(revoked.isConnected, isFalse);
    });

    test('the limit note appears only when the plan is the blocker', () {
      expect(
        const ConnectorCatalog(
          limit: 1,
          used: 1,
          canConnectMore: false,
        ).limitNote,
        'Your plan connects one account. Upgrade to add more.',
      );
      expect(const ConnectorCatalog(limit: 1, used: 0).limitNote, isNull);
      // Unlimited never nags.
      expect(
        const ConnectorCatalog(used: 9, canConnectMore: true).limitNote,
        isNull,
      );
    });
  });

  group('IndexJob', () {
    IndexJob job({
      int total = 0,
      int processed = 0,
      DateTime? startedAt,
      IndexJobState state = IndexJobState.processing,
    }) => IndexJob(
      id: 'j',
      state: state,
      totalFiles: total,
      processed: processed,
      startedAt: startedAt,
    );

    test('a job that discovered nothing does not render NaN', () {
      expect(job().fraction, 0);
    });

    test('fraction cannot exceed one', () {
      // The worker reports discovered-so-far as the total while enumerating,
      // so processed briefly overtaking it is normal, not a bug.
      expect(job(total: 10, processed: 14).fraction, 1.0);
    });

    test('no estimate until the sample is worth trusting', () {
      final started = DateTime(2026, 8, 29, 10);
      final now = started.add(const Duration(seconds: 30));

      // Nine files in is not enough to extrapolate from; an estimate that
      // swings from 30 seconds to nine minutes is worse than none.
      expect(
        job(
          total: 500,
          processed: 9,
          startedAt: started,
        ).estimateRemaining(now: now),
        isNull,
      );
      expect(
        job(
          total: 500,
          processed: 100,
          startedAt: started,
        ).estimateRemaining(now: now),
        isNotNull,
      );
    });

    test('extrapolates from measured throughput', () {
      final started = DateTime(2026, 8, 29, 10);
      // 100 files in 60s → 400 remaining should be about 240s.
      final estimate = job(
        total: 500,
        processed: 100,
        startedAt: started,
      ).estimateRemaining(now: started.add(const Duration(seconds: 60)));
      expect(estimate!.inSeconds, closeTo(240, 2));
    });

    test('no estimate once the job is over', () {
      final started = DateTime(2026, 8, 29, 10);
      expect(
        job(
          total: 500,
          processed: 500,
          startedAt: started,
          state: IndexJobState.complete,
        ).estimateRemaining(now: started.add(const Duration(minutes: 5))),
        isNull,
      );
    });
  });

  group('ScopeLevel and ConnectorState parsing', () {
    test('an unknown scope is the narrow one', () {
      // Fail closed: a value we do not recognise must never be read as
      // permission to delete files.
      expect(ScopeLevel.parse('something-new'), ScopeLevel.read);
      expect(ScopeLevel.parse(null), ScopeLevel.read);
      expect(ScopeLevel.parse('manage'), ScopeLevel.manage);
    });

    test('wire names match the backend', () {
      expect(StorageProvider.googleDrive.wireName, 'google_drive');
      expect(ScopeLevel.manage.wireName, 'manage');
      expect(ConnectorState.parse('revoked'), ConnectorState.revoked);
    });
  });
}
