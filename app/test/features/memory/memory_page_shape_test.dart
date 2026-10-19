import 'package:flutter_test/flutter_test.dart';
import 'package:knowra/src/features/memory/domain/repositories/memory_repository.dart';

/// QA-004. The library header printed "21 memories" on a 20-item page.
///
/// The cause was not the header — it was the contract. `MemoryPage` reported a
/// `total`, but Firestore has no cheap count, so the repository encoded "there
/// is another page" as `total + 1`. The header then printed the sentinel.
/// `hasMore` makes the thing that is actually known the thing that is carried.
void main() {
  test('a page carries hasMore, not a total', () {
    // A compile-time assertion as much as a runtime one: if anybody
    // reintroduces `total` on the wire shape, this stops building.
    const MemoryPage page = (items: [], hasMore: true, offset: 0);
    expect(page.hasMore, isTrue);
    expect(page.offset, 0);
  });
}
