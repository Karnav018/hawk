import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/features/account/presentation/widgets/profile_pieces.dart';

/// The plan card and the vault card are almost entirely numbers, and every one
/// of them is formatted by hand rather than by `intl`. These are the rules
/// that hand-formatting has to keep.
void main() {
  group('groupedCount', () {
    test('groups in threes with a comma, the way the design sets it', () {
      expect(groupedCount(0), '0');
      expect(groupedCount(842), '842');
      expect(groupedCount(1516), '1,516');
      expect(groupedCount(1204), '1,204');
      expect(groupedCount(10412), '10,412');
      expect(groupedCount(1000000), '1,000,000');
    });

    test('never emits a locale separator', () {
      // `NumberFormat` would render this as "1.516" in half of Europe, and
      // "1.516 files" beside "9.1 GB" reads as a decimal.
      expect(groupedCount(1516), isNot(contains('.')));
    });
  });

  group('byteLabel', () {
    test('keeps one decimal only where it carries information', () {
      expect(byteLabel(9772265046), '9.1 GB');
      // 15 GB is a plan limit and is exactly 15. "15.0 GB" claims a precision
      // the allowance does not have.
      expect(byteLabel(15 * 1024 * 1024 * 1024), '15 GB');
      expect(byteLabel(2 * 1024 * 1024 * 1024), '2 GB');
    });

    test('steps down through the units rather than printing 0.004 GB', () {
      expect(byteLabel(612 * 1024 * 1024), '612 MB');
      expect(byteLabel((4.5 * 1024 * 1024).round()), '4.5 MB');
      expect(byteLabel(700 * 1024), '700 KB');
    });
  });

  group('byteRatio', () {
    test('prints the unit once when both sides share it', () {
      expect(byteRatio(9772265046, 15 * 1024 * 1024 * 1024), '9.1 / 15 GB');
    });

    test('gives zero no unit at all', () {
      // An empty vault reads "0 / 15 GB". "0 KB / 15 GB" makes the smallest
      // possible number look like a measurement somebody took.
      expect(byteRatio(0, 15 * 1024 * 1024 * 1024), '0 / 15 GB');
    });

    test('prints both units when they differ', () {
      // "612 / 15 GB" would read as 612 GB of a 15 GB plan.
      expect(
        byteRatio(612 * 1024 * 1024, 15 * 1024 * 1024 * 1024),
        '612 MB / 15 GB',
      );
    });
  });
}
