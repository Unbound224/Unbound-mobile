import 'package:test/test.dart';
import 'package:unbound_mobile/domain/amount.dart';
import 'package:unbound_mobile/domain/credit_inventory.dart';
import 'package:unbound_mobile/domain/models.dart';

final now = DateTime.utc(2026, 11, 2);
EligibleAsset prog(String code, String issuer, {DateTime? exp}) =>
    EligibleAsset(
      asset: AssetRef(code, issuer),
      unitOfAccount: '1 $code = 1 USD',
      expiresAt: exp ?? DateTime.utc(2027, 1, 1),
      jurisdiction: 'Testland',
      refundPolicy: 'r',
      contact: 'c',
    );
Holding h(String code, String? issuer, String amt, {bool auth = true}) =>
    Holding(AssetRef(code, issuer), Amount.parse(amt), isAuthorized: auth);

void main() {
  test('only verified, unexpired, authorized holdings are usable; unknown issuers get no value', () {
    final dir = [
      prog('SHOP', 'GA'),
      prog('OLD', 'GB', exp: DateTime.utc(2026, 1, 1)),
      prog('FRZ', 'GC'),
    ];
    final r = CreditInventory.classify(
      [
        h('RANDOM', 'GZ', '100'),
        h('SHOP', 'GA', '10'),
        h('OLD', 'GB', '5'),
        h('FRZ', 'GC', '3', auth: false),
        h('XLM', null, '9999'),
        h('SHOP', 'GA', '0'),
      ],
      dir,
      now,
    );
    expect(
      [for (final p in r) '${p.holding.asset.code}:${p.status.name}'],
      ['SHOP:redeemable', 'FRZ:frozen', 'OLD:expired', 'RANDOM:unverified'],
    );
    expect(r.first.canExchange && r.first.canRedeem, isTrue);
    expect(
      r
          .where((p) => p.status != CreditStatus.redeemable)
          .any((p) => p.canExchange || p.canRedeem),
      isFalse,
    );
  });

  test('same code from a different issuer is NOT the verified asset', () {
    final r = CreditInventory.classify(
      [h('SHOP', 'GIMPOSTOR', '10')],
      [prog('SHOP', 'GA')],
      now,
    );
    expect(r.single.status, CreditStatus.unverified);
    expect(r.single.program, isNull);
  });
}
