# Quagmir Build Root Objects Report

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
- Contract: `ThresholdElection`
- Main ingot: `ingots/threshold_elgamal_fe`

## Summary

After fixing the quagmir move-checking diagnostics in source and tests, `fe check` and `fe test` pass under quagmir, but `fe build` fails for both Sonatina and Yul backends with a root-object discovery error.

This appears to be quagmir-specific for this project: the neighboring non-quagmir compiler in `/home/grant/workshop/fe` on branch `master` builds the same source successfully with both Sonatina and Yul.

## Quagmir Repro

Compiler-generated debug report:

```text
reports/quagmir-build-root-objects-report.tar.gz
```

Generated with:

```sh
timeout 120s /home/grant/workshop/fe-quagmir/target/debug/fe --color never build --report --report-failed-only --report-out reports/quagmir-build-root-objects-report.tar.gz --contract ThresholdElection ingots/threshold_elgamal_fe
```

Sonatina:

```sh
cd /home/grant/workshop/agg-elgamal/threshold_elgamal_fe_reference
timeout 120s /home/grant/workshop/fe-quagmir/target/debug/fe --color never build --contract ThresholdElection ingots/threshold_elgamal_fe
```

Observed:

```text
Error: Failed to compile Sonatina bytecode: runtime package has no root objects; refusing to emit target-only Sonatina bytecode
```

Yul:

```sh
cd /home/grant/workshop/agg-elgamal/threshold_elgamal_fe_reference
timeout 120s /home/grant/workshop/fe-quagmir/target/debug/fe --color never build --backend yul --optimize 2 --solc /usr/bin/solc --out-dir /tmp/agg-elgamal-yul-build --contract ThresholdElection ingots/threshold_elgamal_fe
```

Observed:

```text
Error: Failed to emit Yul: runtime package has no root objects; refusing to emit target-only Yul
```

Equivalent failing forms:

```sh
/home/grant/workshop/fe-quagmir/target/debug/fe --color never build .
/home/grant/workshop/fe-quagmir/target/debug/fe --color never build ingots/threshold_elgamal_fe
/home/grant/workshop/fe-quagmir/target/debug/fe --color never build --ingot threshold_elgamal_fe .
```

All produce the same root-object failure.

## Controls

Quagmir type-check:

```sh
timeout 120s /home/grant/workshop/fe-quagmir/target/debug/fe --color never check .
```

Result: passed.

Quagmir test:

```sh
timeout 120s /home/grant/workshop/fe-quagmir/target/debug/fe --color never test ingots/threshold_elgamal_fe_tests
```

Result:

```text
test result: ok. 5 passed; 0 failed
```

Non-quagmir Sonatina build control:

```sh
cd /home/grant/workshop/agg-elgamal/threshold_elgamal_fe_reference
timeout 120s /home/grant/workshop/fe/target/debug/fe --color never build --contract ThresholdElection ingots/threshold_elgamal_fe
```

Result:

```text
Wrote /home/grant/workshop/agg-elgamal/threshold_elgamal_fe_reference/ingots/threshold_elgamal_fe/out/ThresholdElection.bin
Wrote /home/grant/workshop/agg-elgamal/threshold_elgamal_fe_reference/ingots/threshold_elgamal_fe/out/ThresholdElection.runtime.bin
Wrote /home/grant/workshop/agg-elgamal/threshold_elgamal_fe_reference/ingots/threshold_elgamal_fe/out/ThresholdElection.abi.json
```

Non-quagmir Yul build control:

```sh
cd /home/grant/workshop/agg-elgamal/threshold_elgamal_fe_reference
timeout 120s /home/grant/workshop/fe/target/debug/fe --color never build --backend yul --optimize 2 --solc /usr/bin/solc --out-dir /tmp/agg-elgamal-master-yul-build --contract ThresholdElection ingots/threshold_elgamal_fe
```

Result:

```text
Wrote /tmp/agg-elgamal-master-yul-build/ThresholdElection.bin
Wrote /tmp/agg-elgamal-master-yul-build/ThresholdElection.runtime.bin
Wrote /tmp/agg-elgamal-master-yul-build/ThresholdElection.abi.json
```

## Suspected Area

The build path appears to lose or filter out runtime root objects for an ingot target containing `pub contract ThresholdElection`, even though the same contract is discoverable enough for `fe check` and for the test ingot to deploy it with `evm.create2<ThresholdElection>(...)`.
