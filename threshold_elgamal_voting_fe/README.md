# Threshold ElGamal Voting Fe Reference Pack

This package is designed to be handed directly to an implementation agent.

## Assumption

This pack assumes **Fe** means the EVM smart-contract language **Fe v26.0.0**.

## What is in here

- `python_reference/bn254_elgamal_reference.py`
  - working reference math over BN254 G1
  - threshold key splitting with Shamir shares
  - exponential ElGamal encryption
  - homomorphic ciphertext addition
  - threshold decryption by Lagrange interpolation in the exponent
  - bounded signed discrete-log recovery for the final tally
  - Chaum-Pedersen / DLEQ proofs for partial and final decryption
- `python_reference/test_vectors.json`
  - deterministic vectors for cross-checking a contract/client implementation
- `fe.toml`
  - Fe workspace root
- `ingots/threshold_elgamal_voting_fe/`
  - Fe ingot: contract + BN254 G1 + threshold ElGamal voting helpers
- `ingots/threshold_elgamal_voting_fe_tests/`
  - Fe ingot: deterministic vector + contract integration tests
- `docs/`
  - implementation brief
  - scheme spec
  - Fe notes
  - references

## Recommended system boundary

### Off-chain
Use off-chain code for:
- distributed key generation or provisioning of threshold shares
- ballot encryption
- ballot-validity proofs
- decryption-share proof generation
- final bounded discrete-log recovery

### On-chain (Fe)
Use Fe for:
- election configuration and public-key storage
- accepting ciphertext submissions
- maintaining an encrypted running tally
- recording decryption shares or the final decrypted result
- later, optionally verifying DLEQ proofs and ballot-validity proofs

## Why BN254 here

The EVM has native precompiles for BN254 / alt_bn128 point addition, scalar multiplication, and pairing checks. That makes BN254 the practical curve choice for a Fe contract that wants to do on-chain elliptic-curve work.

## Important caveats

- Fe is still early and marked as not production-ready by its own docs.
- The Python file is the correctness oracle; the Fe ingot implements the same path and includes vector tests for regression safety.
- This pack does **not** implement ballot-validity ZK proofs. It documents where they fit and leaves room for them in the contract interface.

## Quick start

### Python reference
```bash
python3 python_reference/bn254_elgamal_reference.py
python3 python_reference/bn254_elgamal_reference.py selftest
python3 python_reference/bn254_elgamal_reference.py vectors
```

### Fe quick commands
```bash
cd threshold_elgamal_voting_fe
fe test ingots/threshold_elgamal_voting_fe_tests
fe build

# If you want to force the Yul backend:
fe build --backend yul
```

## Files the agent should read first

1. `docs/AGENT_BRIEF.md`
2. `docs/SCHEME_SPEC.md`
3. `python_reference/test_vectors.json`
4. `python_reference/bn254_elgamal_reference.py`
5. `ingots/threshold_elgamal_voting_fe/src/election.fe`
6. `ingots/threshold_elgamal_voting_fe/src/bn254_g1.fe`

