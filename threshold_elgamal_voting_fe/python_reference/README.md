# Python reference

## Files

- `bn254_elgamal_reference.py` — full math reference
- `demo_output.txt` — deterministic demo output
- `test_vectors.json` — deterministic vectors for integration tests

## Sanity commands

```bash
python bn254_elgamal_reference.py
python bn254_elgamal_reference.py selftest
python bn254_elgamal_reference.py vectors
```

## What to compare in the vectors

At minimum, compare:
- public key coordinates
- each ballot ciphertext `(c1, c2)`
- aggregate ciphertext
- each partial decryption share
- combined decryption point
- final decoded tally