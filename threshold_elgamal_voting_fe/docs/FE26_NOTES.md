# Fe 26 Notes

## Toolchain target

This package targets Fe `v26.0.0`.

## Project layout

This pack uses a small Fe workspace (similar to `fe-zkkit` and other Fe repos):

- `fe.toml` (workspace root)
- `ingots/threshold_elgamal_voting_fe/` (main ingot)
- `ingots/threshold_elgamal_voting_fe_tests/` (test ingot)

## Important Fe syntax patterns used here

- `msg` declarations define the public ABI.
- `recv` blocks implement handlers.
- `uses (...)` declares explicit effects.
- `#[event]` marks event structs.
- `#[selector = sol("...")]` pins ABI selectors.

## BN254 precompiles in Fe 26

Fe 26 exposes EVM crypto precompiles through `std::evm::crypto` (notably
`ec_add`, `ec_mul`, `mulmod`, and `modexp`). This pack uses those wrappers for
BN254 G1 and scalar-field arithmetic so the contract code does not need to
manually assemble call data for precompile `staticcall`s.

## Recommended implementation tactic

1. Keep all BN254 math validated against the Python vectors.
2. Use the stdlib wrappers consistently (`std::evm::crypto::{ec_add, ec_mul}`).
3. Only after raw EC wrappers work, add proof verification or richer election
   logic.

## Suggested tests

- vector match for generator multiplication
- vector match for one vote encryption
- vector match for aggregated ciphertext
- reject invalid point coordinates
- aggregate tally matches Python reference
- threshold decryption matches Python reference
