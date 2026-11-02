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
This repo is currently a **pure Dart package** (`unbound_mobile`), not a runnable Flutter app. The Flutter SDK
was downloaded in the build sandbox but could not be run (its first run needed a global git config change that
was not permitted), so **nothing here has been compiled or run under Flutter, on a device or on an emulator.**
All code is pure Dart (3.13) and is verified with `dart analyze` and `dart test` only.

| Layer | State |
|---|---|
| `Amount` (exact 7-decimal integers, no doubles) | Implemented, tested |
| Strict contract models (quote, intent, redemption, eligible asset; unknown states/versions/networks rejected) | Implemented, tested |
| `QuoteReview`: re-derives the slippage floor, rejects expired/odd quotes, builds the disclosure text (issuers, floor, fee, slippage) | Implemented, tested |
| `ApprovalGuard`: before signing, compares the DECODED transaction with the quote (assets, amount, floor, route, destination is own wallet, network, hash) | Implemented, tested using a test inspector |
| `CreditInventory`: holdings without a verified, unexpired, authorized issuer program are shown as unusable | Implemented, tested |
| Status text: nothing says complete/redeemed before the ledger/merchant confirmed | Implemented, tested |
| `HttpCoreApi` against unbound-core `/v1` (bearer token + `Idempotency-Key` headers, error envelope, unknown-outcome errors) | Implemented; tested over real loopback HTTP against a local stub (not the real core) |
| `ExchangeFlow` / `RedemptionFlow`: persisted idempotency keys, double-tap guard, no re-sign on unknown outcome, polling with backoff, stale/offline handling, resume | Implemented, tested with labeled fakes |
| **Flutter app, screens, Riverpod, go_router, theming** | **Not built** |
| **Secure key storage / on-device signing** (`WalletSigner` port) | **Not built.** Only a test fake exists |
| **Stellar XDR decoder** (`TransactionInspector` port) | **Not built.** Without it the guard cannot run in production; do not ship signing until it exists |
| **Durable `PendingStore`** | **Not built.** Only an in-memory store, so crash-resume is verified in tests but not on a device |
| Wallet challenge/verify login against core | Not built (core endpoints exist) |
| Balances (`BalanceSource` port) | Not built; no real implementation |
| Device / integration tests, store listings | None. The app is not in any app store |

## Quick start
```
dart pub get
dart format --output=none --set-exit-if-changed lib test
dart analyze
dart test
```

## Layout
`lib/domain` (pure rules), `lib/flows` (orchestration + ports), `lib/integrations` (HTTP client), `test/` (incl. `test/support/fakes.dart`, test adapters only).

## Security notes
No secrets in the repo. The app never sees or sends a secret key: the signer port returns only a signed envelope.
The only network is Testnet; any other passphrase is refused by the review and the guard.

## Sibling versions
Targets `unbound-core` HTTP v1 (OpenAPI `1.0.0-draft`, branch `claude/drips-wave-maintainer-projects-iwucl5`, untagged).

## Minimal integration contract
Always test the dependency path stated in ARCHITECTURE.md. Every new public endpoint/ABI/package message must be versioned and covered by consumer fixtures. See `docs/SRD.md` and `docs/TECHNICAL_BUILD.md`.

## Drips Wave
Stellar is essential: Native asset issuance: merchant issuance identity and redemption promise live off-chain, asset code+issuer on Stellar. Approval/eligibility for Wave depends on substantive open-source implementation and organizer review, not repo count.


## Official project identity

The project uses the **approved flat SVG logo** in [`brand/icon.svg`](./brand/icon.svg), with an editable transparent vector mark in [`brand/mark.svg`](./brand/mark.svg). The [512 px GitHub organization avatar](./brand/org-avatar.png) is in the same directory. This logo is shared by all four project repositories. UI design remains intentionally flexible.
