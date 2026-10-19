import '../entities/plan_summary.dart';
import '../entities/receipt.dart';
import '../entities/store_product.dart';
import '../entities/subscription.dart';

/// A purchase the device holds, as reported by the store SDK.
typedef HeldPurchase = ({String productId, String token, String store});

/// Domain-owned contract. Every method throws an `AppException`.
abstract interface class BillingRepository {
  /// The current plan and its allowances. Live, because a renewal, a lapse or
  /// a refund arrives as a store notification that writes Firestore — the app
  /// is not involved, so it has to be watching.
  Stream<Subscription> watchSubscription();

  /// The signed-in user's receipts, newest first — screen 2J.
  Stream<List<Receipt>> watchReceipts();

  /// What can be bought, with store-formatted prices.
  ///
  /// Returns an empty list where purchases are unavailable — an emulator, a
  /// build with no store products configured — rather than throwing, so the
  /// paywall can explain itself instead of erroring.
  Future<List<StoreProduct>> products();

  /// What each tier includes, from the table the backend enforces.
  ///
  /// Available wherever the backend is, including a device with no store —
  /// the free plan still has to be described. Empty when it cannot be
  /// reached; the paywall then shows plans without their feature lines
  /// rather than lines it made up.
  Future<Map<Tier, PlanSummary>> plans();

  /// Runs the store's purchase flow and grants the tier once the server has
  /// validated it with the store.
  ///
  /// Throws `AppException.cancelled()` when the user dismisses the sheet.
  Future<Subscription> buy(StoreProduct product);

  /// Re-validates what this device already owns.
  ///
  /// Required by both stores as a visible action, and the only way onto a new
  /// phone. Returns the restored plan, or free if there was nothing.
  Future<Subscription> restore();
}
