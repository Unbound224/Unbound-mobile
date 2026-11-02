<img src="./brand/icon.svg" alt="Unbound logo" width="144" />

# unbound-mobile

> Unbound — Turn stranded value into something usable.

**Status: pure-Dart domain, flow and API-client layers implemented and tested. There is NO Flutter UI yet, no secure signer and no XDR decoder. See "Status" below.** This repo is one of **exactly four meaningful independent codebases** in the Unbound Stellar-native project. It is not a placeholder created merely to increase Drips Wave submissions.

## Owns
Consumer asset inventory, issuer discovery, offers, approvals, wallet/secure signing, redemption status, transaction receipts

## Why it is separate
It has a distinct runtime/toolchain, external interface, tests, release cadence and maintainership boundary. Its siblings depend on its delivered interface, but implementation responsibilities must not be duplicated.

## Sibling repositories
- `unbound-core` — Merchant onboarding, verified issuer/redemption policies, listings and reservations, user accounts, authorization, canonical operational data, dispute workflow
- `unbound-stellar` — Native Stellar asset issuance integration, account trustlines, issuer flags, order-book/path quoting, transactions, indexing/reconciliation, typed integration SDK
- `unbound-site` — Public consumer landing, official store badges, merchant issuer console, merchant redemption operations, docs and partner onboarding

## Architecture and development context
Start with:
- `AGENTS.md` — coding agent rules;
- `docs/PRD.md` — product purpose and MVP;
- `docs/SRD.md` — user/system requirements, APIs and state;
- `docs/ARCHITECTURE.md` — four-repository responsibilities, data and execution paths;
- `docs/TECHNICAL_BUILD.md` — recommended bootstrap, testing, phases;
- `docs/SECURITY.md` — security/trust boundaries;
- `docs/BRAND.md` — approved flat logo and flexible UI direction;
- `docs/ROADMAP.md` — milestone acceptance gates.

## Status (honest)
This is now a **Flutter 3.47 app** (Android + iOS scaffolding, Riverpod 3, go_router). Verified with `flutter analyze` and
`flutter test` (119 tests including widget tests). **It has never been run on a device or emulator**, never built as an
APK/IPA, and never connected to a running unbound-core or Testnet. The sandbox had no emulator.

| Layer | State |
|---|---|
| Pure rules: exact `Amount`, strict contract models, `QuoteReview` (re-derived slippage floor), `CreditInventory`, honest status text | Implemented, tested |
| `ApprovalGuard` + **`StellarXdrInspector`** (stellar_flutter_sdk): decodes the unsigned envelope locally and compares it to the quote | Implemented; tested against **real XDR produced by unbound-stellar's builders** (`test/fixtures/transactions.v1.json`), including hash reproduction |
| **`SecureWalletSigner`**: key in Android Keystore / iOS Keychain via `flutter_secure_storage`, approval before signing, Testnet only | Implemented; **Dart signing equals the TypeScript-signed fixture byte for byte** (tested with an in-memory store). Platform keystore itself unverified |
| `LocalAuthApproval` (biometric / device credential, fails closed) | Written; **unverified on a device** |
| Durable `FilePendingStore` (idempotency keys / in-flight ids, atomic writes) | Implemented, tested |
| `HttpCoreApi`: quotes, intents, submit, redemptions, portfolio, targets, wallet challenge/verify | Implemented; tested over loopback HTTP against a stub (not the real core) |
| `ExchangeFlow` / `RedemptionFlow` (persisted keys, double-tap guard, no re-sign on unknown outcome, snapshot + polling, stale/offline, resume) | Implemented, tested |
| **Screens**: wallet gate + sign-in, inventory, exchange input, quote review (live countdown), status, redemption, settings/security (wipe wallet) | Implemented; widget-tested incl. full journeys with real fixture XDR, expiry, guard refusal, cancelled signing, unknown outcome, failure |
| Accessibility | Large tap targets, labelled controls and tooltips; **no TalkBack/VoiceOver audit performed** |
| Wallet backup / recovery, seed export, multiple wallets, localisation, push notifications | **Not built** |
| Device / integration tests (`integration_test/`), store listings | **None.** Not in any app store |

## Quick start
```
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter run --dart-define=API_URL=http://10.0.2.2:3001   # Android emulator -> host core (never done in the sandbox)
```

## Layout
`lib/domain` (pure rules), `lib/flows` (orchestration + ports), `lib/integrations` (HTTP, XDR, signer, stores), `lib/app` + `lib/features` (Riverpod + screens), `test/` (`test/support/fakes.dart` and `test/app/harness.dart` are test adapters only).

## Security notes
No secrets in the repo. The app never sees or sends a secret key: the signer port returns only a signed envelope.
The only network is Testnet; any other passphrase is refused by the review and the guard.

## Sibling versions
Targets `unbound-core` HTTP v1 (OpenAPI `1.0.0-draft`, branch `main`, untagged).

## Minimal integration contract
Always test the dependency path stated in ARCHITECTURE.md. Every new public endpoint/ABI/package message must be versioned and covered by consumer fixtures. See `docs/SRD.md` and `docs/TECHNICAL_BUILD.md`.

## Drips Wave
Stellar is essential: Native asset issuance: merchant issuance identity and redemption promise live off-chain, asset code+issuer on Stellar. Approval/eligibility for Wave depends on substantive open-source implementation and organizer review, not repo count.


## Official project identity

The project uses the **approved flat SVG logo** in [`brand/icon.svg`](./brand/icon.svg), with an editable transparent vector mark in [`brand/mark.svg`](./brand/mark.svg). The [512 px GitHub organization avatar](./brand/org-avatar.png) is in the same directory. This logo is shared by all four project repositories. UI design remains intentionally flexible.
