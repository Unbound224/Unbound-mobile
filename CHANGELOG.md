# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions are tagged by the maintainer. Not in any app
store; Testnet only.

## [Unreleased]

### Added
- Escrowed redemptions: local decode and verification of the Soroban `open_return` and `expire_refund` invocations
  before signing; escrow card with deadline; Check status; Take my credit back after the deadline.
- Wallet backup (recovery key behind an acknowledgement and device approval) and restore from a recovery key.
- Tests guarding the launcher identity (name, icons at every density) and the release workflow.

### Changed
- Release workflow publishes a normal latest release with the fixed asset `unbound-android.apk` (+ `.sha256`), so
  `releases/latest/download/unbound-android.apk` always serves the newest build.

## [0.1.0] - pre-release scaffold
- Wallet gate, inventory, exchange with quote review, status, native redemption, settings, secure signer.
