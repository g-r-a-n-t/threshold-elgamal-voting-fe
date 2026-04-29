# Threshold ElGamal (BN254) — Foundry gas benchmarks (Fe)

This report captures Foundry gas benchmarks for the `ThresholdElection` contract in `threshold_elgamal_fe_reference/ingots/threshold_elgamal_fe`.

This project intentionally does **not** compare against a Solidity reference implementation (this is a new scheme / contract).

## Executive summary (verified)

- Bench harness: `threshold_elgamal_fe_reference/bench` (self-contained Foundry project).
- Two Fe compilation paths are benchmarked:
  - **Fe → Sonatina** (`fe build --backend sonatina --optimize {0,1,2}`)
  - **Fe → Yul → solc** (`fe build --backend yul --optimize 2 --solc /usr/bin/solc`)
- Primary cost driver is `castVote(...)` (2× `ec_mul` for validation + 2× `ec_add` for ciphertext aggregation + storage updates).

## Toolchain / environment (verified)

- Date: **2026-04-20**
- `fe`: **26.0.1**
- `forge`: **1.5.1-stable**
- `solc`: **0.8.34** (`/usr/bin/solc`)

## Scope

Benchmarked contract API:

- `castVote(uint256,uint256,uint256,uint256)`
- `getAggregate()`
- `closeVoting()`
- `recordFinalResult(int256,uint256,uint256)`

Bench inputs use the deterministic ciphertext vectors from `ingots/threshold_elgamal_fe_tests/src/lib.fe`:

- `castVote_first`: ballot 1 (vote=1, nonce=101)
- `castVote_after_1`: ballot 2 (vote=-1, nonce=202), after applying ballot 1 first
- `recordFinalResult`: uses the decoded tally `2` and decrypted message point `(m_x, m_y)` from the same vectors

## Methodology

The Foundry tests:

- Build Fe bytecode via `vm.ffi` (so benchmarks track the *current* source).
- Deploy the `.bin` artifacts directly (constructor args appended via `abi.encode(...)`).
- Use `vm.pauseGasMetering()` to exclude setup and calldata construction from the reported gas.
- Warm the target contract account (`extcodesize`) before the metered call (done while gas metering is paused).

## Benchmark results (gas)

| Operation | Sonatina `-O0` | Sonatina `-O2` | Fe→Yul→solc (`-O2`) |
|---|---:|---:|---:|
| `castVote_first` | 170,005 | 166,119 | 168,119 |
| `castVote_after_1` | 80,373 | 76,345 | 78,197 |
| `getAggregate` | 20,716 | 20,011 | 19,874 |
| `closeVoting` | 55,805 | 55,213 | 55,060 |
| `recordFinalResult` | 102,700 | 100,502 | 101,226 |

Notes:

- In Fe 26, `-O1` is currently an alias for `-O2` (so the Sonatina `-O1` results match `-O2` here).

## Reproducing

```bash
cd threshold_elgamal_fe_reference/bench

# Sonatina (0/1/2):
rm -rf out/fe
FE_SONA_OPT_LEVEL=0 forge test --ffi --offline --gas-report --match-test testGas_bench_

rm -rf out/fe
FE_SONA_OPT_LEVEL=2 forge test --ffi --offline --gas-report --match-test testGas_bench_
```

The Fe→Yul→solc variant is always built by the harness in `setUp()` using:

```bash
fe build --backend yul --optimize 2 --solc /usr/bin/solc --out-dir out/fe/yul --contract ThresholdElection ../ingots/threshold_elgamal_fe
```

## Source

- Bench harness: `threshold_elgamal_fe_reference/bench/test/ThresholdElgamalBench.t.sol`
- Contract: `threshold_elgamal_fe_reference/ingots/threshold_elgamal_fe/src/election.fe`

