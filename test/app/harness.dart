import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:stellar_flutter_sdk/stellar_flutter_sdk.dart' as s;
import 'package:unbound_mobile/app/app.dart';
import 'package:unbound_mobile/app/providers.dart';
import 'package:unbound_mobile/domain/amount.dart';
import 'package:unbound_mobile/domain/models.dart';
import 'package:unbound_mobile/flows/ports.dart';
import 'package:unbound_mobile/integrations/secure_wallet_signer.dart';

import '../support/fakes.dart';

// TEST ADAPTERS: in-memory keystore and an auto-approving "biometric".
class MemSecrets implements SecretStore {
  final Map<String, String> m = {};
  @override
  Future<String?> read(String key) async => m[key];
  @override
  Future<void> write(String key, String value) async => m[key] = value;
  @override
  Future<void> delete(String key) async => m.remove(key);
}

class AutoApproval implements UserApproval {
  AutoApproval([this.answer = true]);
  bool answer;
  @override
  Future<bool> confirm(String reason) async => answer;
}

final fixtures = jsonDecode(
  File('test/fixtures/transactions.v1.json').readAsStringSync(),
) as Map<String, Object?>;
Map<String, Object?> get fxSettlement =>
    fixtures['settlement']! as Map<String, Object?>;
Map<String, Object?> get fxReturn =>
    fixtures['redemptionReturn']! as Map<String, Object?>;
Quote get fxQuote => Quote.fromJson(fixtures['quote']! as Map<String, Object?>);
String get fxUser =>
    (fixtures['accounts']! as Map<String, Object?>)['user']! as String;
String get fxIssuer =>
    (fixtures['accounts']! as Map<String, Object?>)['issuer']! as String;
String get fxTarget =>
    (fixtures['accounts']! as Map<String, Object?>)['targetIssuer']! as String;

/// The synthetic fixture user key (derived from a public label) so REAL fixture XDR can be signed.
String fixtureUserSeed() => s.KeyPair.fromSecretSeedList(
  s.Util.hash(Uint8List.fromList(utf8.encode('unbound-fixture:user'))),
).secretSeed;

HoldingView holding(String code, String issuer, String bal, HoldingStatus st) =>
    HoldingView(
      wallet: fxUser,
      asset: AssetRef(code, issuer),
      balance: Amount.parse(bal),
      status: st,
      unitOfAccount: st == HoldingStatus.redeemable
          ? '1 $code = 1 USD (synthetic)'
          : null,
      expiresAt: st == HoldingStatus.redeemable
          ? DateTime.utc(2027, 11, 2)
          : null,
      contact: st == HoldingStatus.redeemable
          ? 'redemptions@example.invalid'
          : null,
    );

class Rig {
  Rig({bool withWallet = true, bool fixtureKey = true}) {
    if (withWallet) {
      secrets.m['unbound.wallet.seed.v1'] = fixtureKey
          ? fixtureUserSeed()
          : s.KeyPair.random().secretSeed;
    }
    api.portfolioResult = PortfolioView(
      holdings: [holding('SHOP', fxIssuer, '100', HoldingStatus.redeemable)],
      notice: 'Only REDEEMABLE credit can be exchanged or redeemed.',
    );
    api.targets = [AssetRef('USDC', fxTarget)];
  }
  final secrets = MemSecrets();
  final approval = AutoApproval();
  final api = FakeCoreApi();
  final store = InMemoryPendingStore();
  DateTime now = fxQuote.issuedAt;

  List<Override> get overrides => [
    secretStoreProvider.overrideWithValue(secrets),
    userApprovalProvider.overrideWithValue(approval),
    coreApiProvider.overrideWithValue(api),
    pendingStoreProvider.overrideWithValue(store),
    clockProvider.overrideWithValue(() => now),
    flowTimingProvider.overrideWithValue(
      FlowTiming(delay: (_) async {}, maxPolls: 3),
    ),
  ];

  Future<void> pump(WidgetTester tester, {bool signedIn = true}) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: overrides,
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const UnboundApp(),
      ),
    );
    await tester.pumpAndSettle();
    if (signedIn && secrets.m.isNotEmpty) {
      container.read(sessionTokenProvider.notifier).set('session-token');
      await tester.pumpAndSettle();
    }
  }
}
