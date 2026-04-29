# Scheme Spec

## 1. Domain parameters

Use the BN254 / alt_bn128 G1 group.

- Field modulus `p`:
  `21888242871839275222246405745257275088696311157297823662689037894645226208583`
- Group order `q`:
  `21888242871839275222246405745257275088548364400416034343698204186575808495617`
- Curve equation:
  `Y^2 = X^3 + 3`
- Generator:
  `G = (1, 2)`

Represent the point at infinity as `(0, 0)` when serialized for EVM-facing code.
Internally, the Python reference uses `None`.

## 2. Public key

Let the master secret be `s in Z_q`.
The public key is:

`H = sG`

For threshold decryption, distribute Shamir shares `s_i = f(i)` for a degree
`t - 1` polynomial `f` with `f(0) = s`.

## 3. Message encoding

For a small integer tally value `m`, encode:

`M = mG`

This is exponential ElGamal / ElGamal in the exponent.

### Signed range support
For signed values, map `m` into `Z_q` by `m mod q`.
The final decryption step must recover `m` from a bounded interval like
`[-B, B]`.

### Multi-option ballots
For production voting, prefer one ciphertext bucket per option or per contest
slot. The reference code demonstrates the simpler single-signed-tally mode.

## 4. Encryption

Choose random `k in Z_q*`.

Compute:
- `C1 = kG`
- `C2 = M + kH`

Ciphertext:
`C = (C1, C2)`

## 5. Homomorphic aggregation

Given ciphertexts `C^(1) = (C1^(1), C2^(1))` and `C^(2) = (C1^(2), C2^(2))`,
aggregate them componentwise:

- `C1^(sum) = C1^(1) + C1^(2)`
- `C2^(sum) = C2^(1) + C2^(2)`

The aggregated ciphertext decrypts to the sum of the encoded messages.

## 6. Threshold decryption

Each participant with share scalar `s_i` computes:

`D_i = s_i * C1`

For any subset `T` of at least `t` participants, combine shares with Lagrange
coefficients at zero:

`lambda_i = prod_{j in T, j != i} (-j) / (i - j) mod q`

Then:

`D = sum_{i in T} lambda_i * D_i = s * C1`

Recover the plaintext point:

`M = C2 - D`

## 7. Final integer recovery

Recover the bounded integer `m` from `M = mG` by a discrete-log search over a
known range.

For small election tallies this is practical.
Do not use this pattern for large unrestricted message spaces.

## 8. DLEQ proof for correct decryption

To prove that a public share `Y_i = s_i G` and a partial decryption
`D_i = s_i C1` use the same exponent, use a Chaum-Pedersen proof.

### Prover
Pick random `w`.

- `T1 = wG`
- `T2 = wC1`
- `c = H(domain, G, Y_i, C1, D_i, T1, T2) mod q`
- `z = w + c * s_i mod q`

Proof is `(T1, T2, z)`.

### Verifier
Check:

- `zG == T1 + cY_i`
- `zC1 == T2 + cD_i`

The exact same proof form works for the final combined decryption using the
master public key `H = sG` and combined share point `D = sC1`.

## 9. EVM precompile layout

### ECADD (EIP-196)
- address: `0x06`
- input: `x1 || y1 || x2 || y2`
- total input length: 128 bytes
- output: `x3 || y3`

### ECMUL (EIP-196)
- address: `0x07`
- input: `x || y || scalar`
- total input length: 96 bytes
- output: `x' || y'`

### Pairing check (EIP-197)
- address: `0x08`
- optional for proof verification

### ModExp (EIP-198)
- address: `0x05`
- useful if you choose to compute inverses or more general modular exponentiation
  through the precompile rather than inline arithmetic

## 10. Practical split for Fe

### On-chain
- store `H`
- validate submitted points
- update aggregate `(agg_c1, agg_c2)` with ECADD
- record share submissions or the final result
- later, optionally verify DLEQ proofs

### Off-chain
- DKG / share provisioning
- ciphertext creation
- bounded discrete-log recovery
- proof generation

## 11. Security notes

- Reject invalid curve points.
- Use strong domain separation in transcript hashing.
- Do not reuse encryption nonces `k`.
- Use proof systems for ballot validity in any real voting deployment.
- Keep tally bounds explicit, because final integer recovery depends on them.
- Audit any production implementation.