# Quagmir Revert Test Hang Report

Date: 2026-04-23

Compiler under review:

- Directory: `/home/grant/workshop/fe-quagmir`
- Branch: `quagmir`
- Commit from handoff plan: `417e835ec1eb397cf1668151e57a47f2720b9693`
- Binary used: `/home/grant/workshop/fe-quagmir/target/debug/fe`
- Reported version: `fe 26.0.0`

Project:

- Directory: `/home/grant/workshop/threshold-elgamal-voting-fe`
- Fe workspace: `/home/grant/workshop/threshold-elgamal-voting-fe/threshold_elgamal_voting_fe`

## Summary

While adding coverage for contract-level invalid ballot rejection, a new `#[test(should_revert)]` consistently timed out with no test-runner output. The same invalid point check passes quickly when tested directly outside the contract call path.

The hanging test is not left in the active test suite because it prevents normal validation. The current project suite passes without it.

## Repro Test

Add this test to `ingots/threshold_elgamal_voting_fe_tests/src/lib.fe`:

```fe
#[test(should_revert)]
fn test_contract_rejects_invalid_ballot_point()
uses (evm: mut Evm, call: mut Call)
{
    let coordinator = Address { inner: 1 }
    let voting_deadline: u256 = 1000000000000000000
    let threshold: u256 = 3
    let addr = evm
        .create2<ThresholdElection>(
            value: 0,
            args: (PUBLIC_KEY_X, PUBLIC_KEY_Y, threshold, voting_deadline, coordinator),
            salt: 1,
        )
    assert(addr.inner != 0)

    addr.call(
        ElectionMsg::CastVote { c1_x: 0, c1_y: 1, c2_x: B1_C2_X, c2_y: B1_C2_Y },
    )
}
```

Run:

```sh
cd /home/grant/workshop/threshold-elgamal-voting-fe/threshold_elgamal_voting_fe
timeout 60s /home/grant/workshop/fe-quagmir/target/debug/fe --color never test ingots/threshold_elgamal_voting_fe_tests --filter test_contract_rejects_invalid_ballot_point
```

Observed result:

```text
exit code 124 after 60 seconds
no stdout/stderr from the test runner
```

Expected result:

- The test should pass quickly because `CastVote` calls `bn254_g1::assert_valid_g1(...)`, and `(0, 1)` is not a valid BN254 G1 point.
- If the revert is considered wrong for some reason, the runner should fail the test normally instead of hanging silently.

## Controls

Direct invalid point revert test:

```sh
timeout 60s /home/grant/workshop/fe-quagmir/target/debug/fe --color never test ingots/threshold_elgamal_voting_fe_tests --filter test_invalid_g1_point_is_rejected
```

Result:

```text
PASS test_invalid_g1_point_is_rejected
test result: ok. 1 passed; 0 failed
```

Identity aggregation test:

```sh
timeout 60s /home/grant/workshop/fe-quagmir/target/debug/fe --color never test ingots/threshold_elgamal_voting_fe_tests --filter test_add_ciphertexts_with_identity_preserves_ballot
```

Result:

```text
PASS test_add_ciphertexts_with_identity_preserves_ballot
test result: ok. 1 passed; 0 failed
```

Full suite without the hanging repro test:

```sh
timeout 120s /home/grant/workshop/fe-quagmir/target/debug/fe --color never test ingots/threshold_elgamal_voting_fe_tests
```

Result:

```text
test result: ok. 5 passed; 0 failed
```

## Suspected Trigger

The likely trigger is a `#[test(should_revert)]` where the revert happens inside a deployed contract call, specifically through `std::evm::crypto::ec_mul` used by `bn254_g1::assert_valid_g1(...)`. A direct `#[test(should_revert)]` around the same invalid point helper does not hang.
