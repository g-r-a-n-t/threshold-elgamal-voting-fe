# Agent Brief

Implement **threshold ElGamal in the exponent over BN254 G1** for a Fe 26 codebase.

## Hard requirements

- Curve: BN254 / alt_bn128 G1 only.
- Generator: `(1, 2)`.
- Public key: `H = sG`.
- Ciphertext format: `C = (C1, C2) = (kG, M + kH)`.
- Message encoding: `M = mG`, where `m` is a small integer in a bounded range.
- Homomorphic aggregation: componentwise group addition.
- Threshold decryption:
  - each share holder with scalar share `s_i` computes `D_i = s_i * C1`
  - combine with Lagrange coefficients at `x = 0`
  - recover `M = C2 - D`
  - recover `m` by bounded discrete-log search

## Recommended phase split

### Phase 1: minimal working path
Implement:
- contract deployment with election config
- ciphertext submission
- aggregate tally updates
- final result recording
- deterministic integration against the supplied JSON vectors

Do **not** block phase 1 on ZK proofs.

### Phase 2: correctness proofs
Implement:
- Chaum-Pedersen / DLEQ verification for decryption shares
- optional final decryption proof verification
- optional ballot-validity proofs for one-hot or bounded ballots

## Engineering decisions you should keep

- Keep the on-chain curve work on BN254 because the EVM exposes precompiles for it.
- Keep discrete-log recovery off-chain or in a very tightly bounded on-chain path only.
- Use the Python file as the ground-truth oracle.
- Treat the Fe scaffold as an API/storage plan, not as already-finished code.

## Contract scope suggestion

### Core storage
- election public key `H`
- tally ciphertext `(agg_c1, agg_c2)`
- ballot count
- election time window
- threshold metadata
- optional coordinator / admin
- optional map of partial decryptions keyed by participant index

### Core messages
- `CastVote`
- `GetAggregate`
- `CloseVoting`
- `RecordPartialDecryption` or `RecordFinalResult`

### Events
- `VoteCast`
- `ElectionClosed`
- `PartialDecryptionRecorded`
- `FinalResultRecorded`

## Definition of done

The implementation is good enough when:
1. every deterministic vector matches the Python reference,
2. encryption + aggregation + threshold decryption round-trips correctly,
3. invalid curve points are rejected,
4. the Fe contract preserves the aggregate tally exactly,
5. the off-chain client and the on-chain contract agree on the same point encodings.