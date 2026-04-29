# Agg ElGamal Quagmir Update Report

Date: 2026-04-23

Compiler under review:

- Directory: `/home/grant/workshop/fe-quagmir`
- Branch: `quagmir`
- Commit from handoff plan: `417e835ec1eb397cf1668151e57a47f2720b9693`
- Binary used: `/home/grant/workshop/fe-quagmir/target/debug/fe`
- Reported version: `fe 26.0.0`

Project:

- Directory: `/home/grant/workshop/agg-elgamal`
- Fe workspace: `/home/grant/workshop/agg-elgamal/threshold_elgamal_fe_reference`

## Baseline Failure

Initial validation command:

```sh
cd /home/grant/workshop/agg-elgamal/threshold_elgamal_fe_reference
timeout 120s /home/grant/workshop/fe-quagmir/target/debug/fe --color never check .
```

Observed diagnostic:

```text
error[16-0002]: move conflict in `fn ThresholdElection::recv[0][0]`
    src/election.fe:154:73

submitted.c2 was moved into bn254_g1::assert_valid_g1(...)
submitted was later passed to elgamal::add_ciphertexts(...)
```

## Local Updates

Updated `ingots/threshold_elgamal_fe/src/election.fe`:

- Kept the original `submitted: Ciphertext` available for aggregation.
- Validated temporary `G1Point` values rebuilt from `submitted.c1.x/y` and `submitted.c2.x/y`.
- This is the narrow ownership fix recommended by the adjacent project handoff.

Updated `ingots/threshold_elgamal_fe_tests/src/lib.fe`:

- Rebuilt temporary `G1Point` values from `agg.c1.x/y` before each `partial_decrypt(...)` call, avoiding field moves from `agg` before `remove_mask(ciphertext: agg, ...)`.
- Added `test_add_ciphertexts_with_identity_preserves_ballot` to cover identity ciphertext aggregation.

## Validation Results

Command:

```sh
cd /home/grant/workshop/agg-elgamal/threshold_elgamal_fe_reference
timeout 120s /home/grant/workshop/fe-quagmir/target/debug/fe --color never check .
```

Result: passed.

Command:

```sh
cd /home/grant/workshop/agg-elgamal/threshold_elgamal_fe_reference
timeout 120s /home/grant/workshop/fe-quagmir/target/debug/fe --color never test ingots/threshold_elgamal_fe_tests
```

Result:

```text
PASS test_invalid_g1_point_is_rejected
PASS test_vector_public_key_matches_secret_mul
PASS test_add_ciphertexts_with_identity_preserves_ballot
PASS test_contract_aggregate_matches_vector
PASS test_vectors_encrypt_aggregate_decrypt_roundtrip

test result: ok. 5 passed; 0 failed
```

Quagmir build commands were also checked:

```sh
timeout 120s /home/grant/workshop/fe-quagmir/target/debug/fe --color never build --contract ThresholdElection ingots/threshold_elgamal_fe
timeout 120s /home/grant/workshop/fe-quagmir/target/debug/fe --color never build --backend yul --optimize 2 --solc /usr/bin/solc --out-dir /tmp/agg-elgamal-yul-build --contract ThresholdElection ingots/threshold_elgamal_fe
```

Both fail with `runtime package has no root objects; refusing to emit target-only ...`.

The same source builds successfully with the neighboring non-quagmir compiler at `/home/grant/workshop/fe/target/debug/fe` on branch `master`. See `reports/QUAGMIR_BUILD_ROOT_OBJECTS_REPORT_2026-04-23.md`.

## Coverage Note

Coverage was thin around the patched contract validation path, so I tried to add a contract-level `#[test(should_revert)]` for an invalid ballot submitted through `ElectionMsg::CastVote`. That test currently hangs under the quagmir test runner and is not included in the committed runnable suite.

See `reports/QUAGMIR_REVERT_TEST_HANG_REPORT_2026-04-23.md` for the shareable compiler/test-runner repro.
