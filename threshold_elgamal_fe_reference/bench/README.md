# threshold-elgamal benchmarks (Foundry)

This is a self-contained Foundry project that benchmarks **Fe-generated EVM code** for `ThresholdElection`.

Unlike the adjacent `zk-kit` benchmark harness, this project does **not** compare to a Solidity reference (this is a new scheme / contract).

## What it does

- Builds the Fe contract via `vm.ffi`:
  - **Fe → Sonatina** (`fe build --backend sonatina --optimize {0,1,2}` via `FE_SONA_OPT_LEVEL=0|1|2`)
  - **Fe → Yul → solc** (`fe build --backend yul --optimize 2 --solc /usr/bin/solc`)
- Deploys the resulting bytecode and runs gas benchmarks for:
  - `castVote(...)` (first vote + subsequent vote)
  - `closeVoting()`
  - `recordFinalResult(...)`

## Prereqs

- Foundry (`forge`)
- `fe` in your `PATH`
- `solc` in your `PATH` (`/usr/bin/solc` in this environment)

## Run

From `threshold_elgamal_fe_reference/bench`:

```bash
rm -rf out/fe

# Sonatina (pick optimization level 0/1/2):
FE_SONA_OPT_LEVEL=2 forge test --ffi --offline -vvv --gas-report --match-test testGas_bench_

# (Optional) also run the non-gas correctness checks:
FE_SONA_OPT_LEVEL=2 forge test --ffi --offline -vvv
```

## Report

- `../../FE_THRESHOLD_ELGAMAL_FOUNDRY_GAS_REPORT.md`
