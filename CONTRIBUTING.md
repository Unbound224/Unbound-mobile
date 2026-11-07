# Contributing to Unbound-mobile

Thanks for helping build Unbound. This repository is the Flutter consumer wallet. It holds the user's Testnet key in the platform keystore and never sends it anywhere. It decodes every unsigned transaction locally and checks it against the quote before asking for approval. It is one of four repositories with clear boundaries (see [`docs/ARCHITECTURE.md`](./docs/ARCHITECTURE.md)).

## Ground rules

- **Financial truth first.** Never show money as settled before the ledger confirms it. Never claim liquidity, fiat cash-out,
  partners, store listings or Mainnet availability that do not exist.
- **Testnet and synthetic data only.** No real funds, real customer data or secret keys in code, tests, fixtures, screenshots or issues.
- **Show real work.** Screenshots come from the real software. Test adapters are clearly labelled as test adapters.
- **Test the failure paths**, not only the happy path.

## Set up

Requires the Flutter stable SDK with Dart 3.13 or newer.

```bash
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze --fatal-infos
flutter test                   # the same steps CI runs
```

## Picking work (Drips Wave)

We take part in the [Stellar Wave Program](https://www.drips.network/wave/stellar). Work is tracked in
[issues labelled `Stellar Wave`](https://github.com/Unbound224/Unbound-mobile/issues?q=is%3Aopen+label%3A%22Stellar+Wave%22).

| Label | Meaning | Wave points |
|---|---|---|
| `trivial` | Small, clearly bounded change with obvious acceptance criteria | 100 |
| `medium` | Standard feature or logic touching several parts of the codebase | 150 |
| `high` | Complex engineering such as an integration or an architectural change | 200 |

Points are Drips' scale. We tag honestly and never promise a reward; payouts follow Drips' own rules and review.

How to claim an issue:

1. Read the whole issue: summary, context, scope, implementation notes and acceptance criteria.
2. Comment that you want it, with a sentence on your approach. A maintainer will assign it to you.
3. Open a draft PR early if the scope is unclear. Ask questions in the issue, not in private.
4. One issue per PR. Do not bundle unrelated changes.

Issues that are inactive for seven days after assignment go back to the pool.

## Pull requests

1. Branch from `main` and keep the change small and focused.
2. Use [Conventional Commits](https://www.conventionalcommits.org) (`feat:`, `fix:`, `docs:`, `test:`, `ci:`).
3. Add tests for new behavior and its failure paths.
4. If you change how the app reads the API or decodes XDR, update the fixtures copied from `Unbound-stellar` and describe the impact on `Unbound-core` and `Unbound-stellar` in the PR.
5. Fill in the pull request template, link the issue (`Closes #123`) and show the evidence: the check output, and for ledger changes a Testnet
   transaction hash when relevant.

What reviewers look for: the acceptance criteria in the issue are met one by one, `npm run check` is green, failure paths are tested, no secrets or
real data appear anywhere, and the diff does not touch unrelated files.

## Conduct and security

Everyone participating agrees to the [Code of Conduct](./CODE_OF_CONDUCT.md). Report vulnerabilities privately as described in
[`SECURITY.md`](./SECURITY.md). Questions go in [Discussions](https://github.com/Unbound224/Unbound-mobile/discussions).
