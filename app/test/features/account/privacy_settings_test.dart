import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/features/account/data/privacy_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Screen 2K's one live switch.
///
/// Crash reporting is the only row on that screen with a mechanism behind it,
/// which makes it the only one that can be got wrong. Two things matter: the
/// default is *on* (the report carries no file names and no content, so
/// opt-out is the honest shape), and the switch is readable synchronously —
/// Sentry's `beforeSend` runs on the error path and cannot await a
/// preference.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('reports are on before anything has been loaded', () {
    // A crash during startup, before `load()` has run, must still report.
    expect(PrivacySettings.crashReportsEnabled, isTrue);
  });

  test('turning it off is remembered', () async {
    await PrivacySettings.setCrashReports(enabled: false);
    expect(PrivacySettings.crashReportsEnabled, isFalse);

    // A fresh process reads it back.
    await PrivacySettings.load();
    expect(PrivacySettings.crashReportsEnabled, isFalse);
  });

  test('and turning it back on is too', () async {
    await PrivacySettings.setCrashReports(enabled: false);
    await PrivacySettings.setCrashReports(enabled: true);
    await PrivacySettings.load();
    expect(PrivacySettings.crashReportsEnabled, isTrue);
  });

  test('the switch takes effect immediately, not on the next launch', () async {
    // Dropping the event in `beforeSend` rather than skipping Sentry's init
    // is what makes this true: an SDK that was never initialised could not be
    // turned back on without a restart.
    await PrivacySettings.setCrashReports(enabled: false);
    expect(PrivacySettings.crashReportsEnabled, isFalse);
    await PrivacySettings.setCrashReports(enabled: true);
    expect(PrivacySettings.crashReportsEnabled, isTrue);
  });

  test('an untouched install defaults to on', () async {
    SharedPreferences.setMockInitialValues({});
    await PrivacySettings.load();
    expect(PrivacySettings.crashReportsEnabled, isTrue);
  });
}
