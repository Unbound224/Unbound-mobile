import 'amount.dart';
import 'models.dart';

/// A raw on-chain holding as read by a [BalanceSource].
class Holding {
  const Holding(this.asset, this.balance, {this.isAuthorized = true});
  final AssetRef asset;
  final Amount balance;
  final bool isAuthorized;
}

/// Port: reads wallet balances (Horizon via the stellar layer). Test adapters are labeled.
abstract class BalanceSource {
  Future<List<Holding>> balances(String publicKey);
}

enum CreditStatus {
  /// Verified, active issuer program with unexpired policy: can be exchanged or redeemed.
  redeemable,

  /// Issuer program exists but its policy has expired: not usable.
  expired,

  /// Issuer revoked the holder's authorization on-chain: frozen.
  frozen,

  /// No verified issuer. Never presented as having value.
  unverified,
}

class CreditPosition {
  const CreditPosition(this.holding, this.status, this.program);
  final Holding holding;
  final CreditStatus status;
  final EligibleAsset? program;

  bool get canExchange => status == CreditStatus.redeemable;
  bool get canRedeem => status == CreditStatus.redeemable;
}

/// Classifies holdings against the issuer directory. "No issuer means no usable store credit."
class CreditInventory {
  static List<CreditPosition> classify(
    List<Holding> holdings,
    List<EligibleAsset> directory,
    DateTime now,
  ) {
    final byAsset = {for (final p in directory) p.asset: p};
    final out = <CreditPosition>[];
    for (final h in holdings) {
      if (h.asset.issuer == null) {
        continue; // native XLM is not a merchant credit
      }
      if (h.balance.isZero) continue;
      final p = byAsset[h.asset];
      final CreditStatus s;
      if (p == null) {
        s = CreditStatus.unverified;
      } else if (!p.expiresAt.isAfter(now)) {
        s = CreditStatus.expired;
      } else if (!h.isAuthorized) {
        s = CreditStatus.frozen;
      } else {
        s = CreditStatus.redeemable;
      }
      out.add(CreditPosition(h, s, p));
    }
    // Usable credit first, then by code for stable ordering.
    out.sort((a, b) {
      final r = (a.canExchange ? 0 : 1).compareTo(b.canExchange ? 0 : 1);
      return r != 0 ? r : a.holding.asset.key.compareTo(b.holding.asset.key);
    });
    return out;
  }
}
