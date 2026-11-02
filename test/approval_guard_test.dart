import 'package:test/test.dart';
import 'package:unbound_mobile/domain/amount.dart';
import 'package:unbound_mobile/domain/approval_guard.dart';
import 'package:unbound_mobile/domain/models.dart';

import 'models_test.dart' show quoteJson;

/// TEST ADAPTER: returns a canned summary. NOT an XDR decoder.
class FakeInspector implements TransactionInspector {
  FakeInspector(this.summary);
  TxSummary? summary;
  @override
  TxSummary inspect(String unsignedXdr) {
    final s = summary;
    if (s == null) throw StateError('undecodable');
    return s;
  }
}

final hash = 'a' * 64;
final t0 = DateTime.utc(2026, 11, 2, 12);

TxSummary good({
  String? passphrase,
  String op = 'pathPaymentStrictSend',
  AssetRef? send,
  AssetRef? dest,
  String sendAmount = '80.0000000',
  String destMin = '71.2800000',
  String destination = 'GME',
  String source = 'GME',
  String? h,
  int ops = 1,
  List<AssetRef> path = const [],
}) =>
    TxSummary(
      networkPassphrase: passphrase ?? testnetPassphrase,
      sourceAccount: source,
      operationType: op,
      sendAsset: send ?? const AssetRef('SHOP', 'GSHOP'),
      sendAmount: Amount.parse(sendAmount),
      destAsset: dest ?? const AssetRef('USDC', 'GUSDC'),
      destMin: Amount.parse(destMin),
      destination: destination,
      path: path,
      hash: h ?? hash,
      operationCount: ops,
    );

IntentView intent({IntentState state = IntentState.awaitingSignature, String quoteId = 'q_1', String? xdr = 'AAAA', String? txHash}) => IntentView(
      id: 'int_1',
      state: state,
      quoteId: quoteId,
      txHash: txHash ?? hash,
      unsignedXdr: xdr,
      failureReason: null,
      amountOutActual: null,
      ledger: null,
    );

void check(TxSummary? s, {IntentView? i, DateTime? now, Set<String> own = const {'GME'}}) {
  ApprovalGuard(FakeInspector(s)).check(
    quote: Quote.fromJson(quoteJson()),
    intent: i ?? intent(),
    ownAccounts: own,
    signingAccount: 'GME',
    now: now ?? t0,
  );
}

Matcher refusedWith(RefusalReason r) => throwsA(isA<ApprovalRefused>().having((e) => e.reasons, 'reasons', contains(r)));

void main() {
  test('approves when the decoded transaction matches the quote exactly', () {
    final ok = ApprovalGuard(FakeInspector(good())).check(
      quote: Quote.fromJson(quoteJson()),
      intent: intent(),
      ownAccounts: {'GME'},
      signingAccount: 'GME',
      now: t0,
    );
    expect(ok.expectedHash, hash);
  });

  group('refuses to sign', () {
    test('when the server swapped the destination to a foreign account', () => expect(() => check(good(destination: 'GATTACKER')), refusedWith(RefusalReason.foreignDestination)));
    test('when the floor was lowered', () => expect(() => check(good(destMin: '1.0000000')), refusedWith(RefusalReason.floorMismatch)));
    test('when the sell amount was raised', () => expect(() => check(good(sendAmount: '800.0000000')), refusedWith(RefusalReason.amountMismatch)));
    test('when assets differ', () => expect(() => check(good(dest: const AssetRef('USDC', 'GEVIL'))), refusedWith(RefusalReason.assetMismatch)));
    test('when the route differs', () => expect(() => check(good(path: const [AssetRef('JUNK', 'GJ')])), refusedWith(RefusalReason.routeMismatch)));
    test('when the network is not Testnet', () => expect(() => check(good(passphrase: 'Public Global Stellar Network ; September 2015')), refusedWith(RefusalReason.wrongNetwork)));
    test('when it is not a single path payment', () {
      expect(() => check(good(ops: 2)), refusedWith(RefusalReason.notSingleOperation));
      expect(() => check(good(op: 'payment')), refusedWith(RefusalReason.wrongOperation));
    });
    test('when the source account is not the signer', () => expect(() => check(good(source: 'GOTHER')), refusedWith(RefusalReason.wrongSource)));
    test('when the decoded hash differs from the advertised hash', () => expect(() => check(good(h: 'b' * 64)), refusedWith(RefusalReason.hashMismatch)));
    test('when the quote expired', () => expect(() => check(good(), now: t0.add(const Duration(minutes: 1))), refusedWith(RefusalReason.expired)));
    test('when the intent is not awaiting signature', () => expect(() => check(good(), i: intent(state: IntentState.submitted)), refusedWith(RefusalReason.wrongState)));
    test('when the intent belongs to another quote', () => expect(() => check(good(), i: intent(quoteId: 'q_other')), refusedWith(RefusalReason.quoteMismatch)));
    test('when the payload is missing', () => expect(() => check(good(), i: intent(xdr: null)), refusedWith(RefusalReason.missingPayload)));
    test('when the XDR cannot be decoded', () => expect(() => check(null), refusedWith(RefusalReason.inspectionFailed)));
  });
}
