#!/usr/bin/env python3
"""
Reference implementation of threshold ElGamal in the exponent over BN254 G1.

What this file is for
---------------------
- A correctness oracle for an implementation agent.
- A portable math reference for ciphertext aggregation, threshold decryption,
  and Chaum-Pedersen / DLEQ proofs of correct decryption.
- Deterministic test-vector generation.

What this file is not
---------------------
- Not audited.
- Not constant-time.
- Not a production DKG, wallet, or voting client.
- Not a zero-knowledge ballot-validity system. Ballot validity is left as a
  higher-layer concern.

Domain
------
This implementation uses the BN254 / alt_bn128 G1 group exposed by the EVM
precompiles defined by EIP-196 and EIP-197. The generator is (1, 2). Messages
are encoded as points M = m * G. Because decryption yields a point, the final
integer tally is recovered by a bounded discrete-log search over a small range.

The code supports signed tallies in a bounded interval [-B, B]. For a ballot
system with multiple options, the usual pattern is to encrypt one ciphertext per
option and tally each bucket independently.
"""
from __future__ import annotations

from dataclasses import dataclass
from hashlib import sha256
import json
import math
import secrets
import sys
from typing import Dict, Iterable, Optional, Sequence, Tuple

# BN254 / alt_bn128 parameters used by the EVM precompiles.
FIELD_MODULUS = 21888242871839275222246405745257275088696311157297823662689037894645226208583
GROUP_ORDER = 21888242871839275222246405745257275088548364400416034343698204186575808495617
CURVE_B = 3
GENERATOR = (1, 2)

Point = Optional[Tuple[int, int]]  # None means the point at infinity.


@dataclass(frozen=True)
class Ciphertext:
    c1: Point
    c2: Point


@dataclass(frozen=True)
class DLEQProof:
    t1: Point
    t2: Point
    z: int


def mod_inv(value: int, modulus: int) -> int:
    value %= modulus
    if value == 0:
        raise ZeroDivisionError("modular inverse of zero")
    return pow(value, -1, modulus)


def is_on_curve(point: Point) -> bool:
    if point is None:
        return True
    x, y = point
    if not (0 <= x < FIELD_MODULUS and 0 <= y < FIELD_MODULUS):
        return False
    return (y * y - (x * x * x + CURVE_B)) % FIELD_MODULUS == 0


def point_neg(point: Point) -> Point:
    if point is None:
        return None
    x, y = point
    return (x, (-y) % FIELD_MODULUS)


def point_add(lhs: Point, rhs: Point) -> Point:
    if lhs is None:
        return rhs
    if rhs is None:
        return lhs

    x1, y1 = lhs
    x2, y2 = rhs

    if x1 == x2 and (y1 + y2) % FIELD_MODULUS == 0:
        return None

    if lhs == rhs:
        if y1 % FIELD_MODULUS == 0:
            return None
        slope = (3 * x1 * x1) * mod_inv(2 * y1, FIELD_MODULUS)
    else:
        slope = (y2 - y1) * mod_inv(x2 - x1, FIELD_MODULUS)

    slope %= FIELD_MODULUS
    x3 = (slope * slope - x1 - x2) % FIELD_MODULUS
    y3 = (slope * (x1 - x3) - y1) % FIELD_MODULUS
    return (x3, y3)


def scalar_mul(scalar: int, point: Point = GENERATOR) -> Point:
    scalar %= GROUP_ORDER
    if point is None or scalar == 0:
        return None

    result: Point = None
    addend: Point = point

    while scalar:
        if scalar & 1:
            result = point_add(result, addend)
        addend = point_add(addend, addend)
        scalar >>= 1
    return result


def serialize_scalar(value: int) -> bytes:
    return value.to_bytes(32, "big")


def serialize_point(point: Point) -> bytes:
    if point is None:
        return b"\x00" * 64
    x, y = point
    return serialize_scalar(x) + serialize_scalar(y)


def point_to_json(point: Point) -> Dict[str, str]:
    if point is None:
        return {"x": "0", "y": "0", "infinity": "true"}
    x, y = point
    return {"x": str(x), "y": str(y), "infinity": "false"}


def hash_challenge(domain: bytes, *items: object) -> int:
    h = sha256()
    h.update(domain)
    for item in items:
        if isinstance(item, bytes):
            h.update(item)
        elif isinstance(item, int):
            h.update(serialize_scalar(item))
        elif item is None or isinstance(item, tuple):
            h.update(serialize_point(item))  # type: ignore[arg-type]
        else:
            raise TypeError(f"unsupported challenge item: {type(item)!r}")
    return int.from_bytes(h.digest(), "big") % GROUP_ORDER


def prove_dleq(
    secret: int,
    base1: Point,
    base2: Point,
    point1: Point,
    point2: Point,
    *,
    nonce: Optional[int] = None,
    domain: bytes = b"dleq-v1",
) -> DLEQProof:
    """
    Prove log_base1(point1) == log_base2(point2) == secret.

    The proof is a Chaum-Pedersen proof in additive notation:
        t1 = w * base1
        t2 = w * base2
        c  = H(domain, base1, point1, base2, point2, t1, t2)
        z  = w + c * secret mod q

    Verification checks:
        z * base1 == t1 + c * point1
        z * base2 == t2 + c * point2
    """
    if nonce is None:
        nonce = secrets.randbelow(GROUP_ORDER - 1) + 1
    t1 = scalar_mul(nonce, base1)
    t2 = scalar_mul(nonce, base2)
    challenge = hash_challenge(domain, base1, point1, base2, point2, t1, t2)
    z = (nonce + challenge * (secret % GROUP_ORDER)) % GROUP_ORDER
    return DLEQProof(t1=t1, t2=t2, z=z)


def verify_dleq(
    proof: DLEQProof,
    base1: Point,
    base2: Point,
    point1: Point,
    point2: Point,
    *,
    domain: bytes = b"dleq-v1",
) -> bool:
    challenge = hash_challenge(domain, base1, point1, base2, point2, proof.t1, proof.t2)
    lhs1 = scalar_mul(proof.z, base1)
    rhs1 = point_add(proof.t1, scalar_mul(challenge, point1))
    lhs2 = scalar_mul(proof.z, base2)
    rhs2 = point_add(proof.t2, scalar_mul(challenge, point2))
    return lhs1 == rhs1 and lhs2 == rhs2


def lagrange_coeff_at_zero(index: int, indices: Sequence[int]) -> int:
    numerator = 1
    denominator = 1
    for other in indices:
        if other == index:
            continue
        numerator = (numerator * (-other % GROUP_ORDER)) % GROUP_ORDER
        denominator = (denominator * ((index - other) % GROUP_ORDER)) % GROUP_ORDER
    return (numerator * mod_inv(denominator, GROUP_ORDER)) % GROUP_ORDER


def combine_partial_points(partials: Dict[int, Point]) -> Point:
    indices = sorted(partials.keys())
    if not indices:
        return None
    acc: Point = None
    for index in indices:
        coeff = lagrange_coeff_at_zero(index, indices)
        acc = point_add(acc, scalar_mul(coeff, partials[index]))
    return acc


def evaluate_polynomial(coefficients: Sequence[int], x: int) -> int:
    acc = 0
    power = 1
    for coefficient in coefficients:
        acc = (acc + coefficient * power) % GROUP_ORDER
        power = (power * x) % GROUP_ORDER
    return acc


def generate_threshold_key(
    participants: int,
    threshold: int,
    *,
    secret: Optional[int] = None,
    coefficients: Optional[Sequence[int]] = None,
) -> Dict[str, object]:
    if participants < threshold:
        raise ValueError("participants must be >= threshold")
    if threshold < 1:
        raise ValueError("threshold must be >= 1")

    if secret is None:
        secret = secrets.randbelow(GROUP_ORDER - 1) + 1

    if coefficients is None:
        coefficients = [secret] + [secrets.randbelow(GROUP_ORDER) for _ in range(threshold - 1)]
    else:
        coefficients = list(coefficients)
        if len(coefficients) != threshold:
            raise ValueError("coefficient count must match threshold")
        coefficients[0] = secret

    shares = {index: evaluate_polynomial(coefficients, index) for index in range(1, participants + 1)}
    public_shares = {index: scalar_mul(share, GENERATOR) for index, share in shares.items()}

    return {
        "participants": participants,
        "threshold": threshold,
        "secret": secret,
        "coefficients": list(coefficients),
        "public_key": scalar_mul(secret, GENERATOR),
        "shares": shares,
        "public_shares": public_shares,
    }


def encode_signed_scalar(message: int) -> int:
    return message % GROUP_ORDER


def encode_message_point(message: int) -> Point:
    return scalar_mul(encode_signed_scalar(message), GENERATOR)


def encrypt_signed(message: int, public_key: Point, *, nonce: Optional[int] = None) -> Ciphertext:
    if nonce is None:
        nonce = secrets.randbelow(GROUP_ORDER - 1) + 1
    message_point = encode_message_point(message)
    c1 = scalar_mul(nonce, GENERATOR)
    c2 = point_add(message_point, scalar_mul(nonce, public_key))
    return Ciphertext(c1=c1, c2=c2)


def add_ciphertexts(ciphertexts: Iterable[Ciphertext]) -> Ciphertext:
    acc1: Point = None
    acc2: Point = None
    for ciphertext in ciphertexts:
        acc1 = point_add(acc1, ciphertext.c1)
        acc2 = point_add(acc2, ciphertext.c2)
    return Ciphertext(c1=acc1, c2=acc2)


def partial_decrypt(share_scalar: int, c1: Point) -> Point:
    return scalar_mul(share_scalar, c1)


def decrypt_with_secret(secret: int, ciphertext: Ciphertext) -> Point:
    mask = scalar_mul(secret, ciphertext.c1)
    return point_add(ciphertext.c2, point_neg(mask))


def remove_mask(ciphertext: Ciphertext, combined_share: Point) -> Point:
    return point_add(ciphertext.c2, point_neg(combined_share))


def discrete_log_signed(target: Point, bound: int) -> Optional[int]:
    """
    Recover m from target = m * G for m in [-bound, bound].

    Uses a bounded baby-step / giant-step search by shifting the interval to
    [0, 2*bound].
    """
    if bound < 0:
        raise ValueError("bound must be >= 0")
    if target is None:
        return 0

    shift = scalar_mul(bound, GENERATOR)
    shifted = point_add(target, shift)
    limit = 2 * bound
    step = int(math.isqrt(limit)) + 1

    table: Dict[Point, int] = {}
    baby: Point = None
    for j in range(step):
        table[baby] = j
        baby = point_add(baby, GENERATOR)

    giant_factor = point_neg(scalar_mul(step, GENERATOR))
    gamma = shifted
    for i in range(step + 1):
        j = table.get(gamma)
        if j is not None:
            scalar = i * step + j
            if scalar <= limit:
                return scalar - bound
        gamma = point_add(gamma, giant_factor)

    return None


def prove_partial_decryption(
    share_scalar: int,
    public_share: Point,
    c1: Point,
    partial_share: Point,
    *,
    nonce: Optional[int] = None,
) -> DLEQProof:
    return prove_dleq(
        share_scalar,
        GENERATOR,
        c1,
        public_share,
        partial_share,
        nonce=nonce,
        domain=b"partial-decryption-v1",
    )


def verify_partial_decryption(
    proof: DLEQProof,
    public_share: Point,
    c1: Point,
    partial_share: Point,
) -> bool:
    return verify_dleq(
        proof,
        GENERATOR,
        c1,
        public_share,
        partial_share,
        domain=b"partial-decryption-v1",
    )


def prove_final_decryption(
    secret: int,
    public_key: Point,
    c1: Point,
    combined_share: Point,
    *,
    nonce: Optional[int] = None,
) -> DLEQProof:
    return prove_dleq(
        secret,
        GENERATOR,
        c1,
        public_key,
        combined_share,
        nonce=nonce,
        domain=b"final-decryption-v1",
    )


def verify_final_decryption(
    proof: DLEQProof,
    public_key: Point,
    c1: Point,
    combined_share: Point,
) -> bool:
    return verify_dleq(
        proof,
        GENERATOR,
        c1,
        public_key,
        combined_share,
        domain=b"final-decryption-v1",
    )


def deterministic_vectors() -> Dict[str, object]:
    """
    Stable vectors for contract and client integration tests.
    """
    secret = 0x1234567890ABCDEF112233445566778899AABBCCDDEEFF0011223344556677
    coefficients = [
        secret,
        0x99887766554433221100AABBCCDDEEFF,
        0x7766554433221100FFEEDDCCBBAA9988,
    ]
    votes = [1, -1, 1, 0, 1]
    nonces = [101, 202, 303, 404, 505]
    selected_indices = [1, 3, 5]
    proof_nonces = {1: 9001, 3: 9003, 5: 9005}
    final_nonce = 9999

    key = generate_threshold_key(5, 3, secret=secret, coefficients=coefficients)
    public_key = key["public_key"]  # type: ignore[assignment]

    ballots = []
    ciphertexts = []
    for vote, nonce in zip(votes, nonces):
        ciphertext = encrypt_signed(vote, public_key, nonce=nonce)
        ballots.append(
            {
                "vote": vote,
                "nonce": str(nonce),
                "ciphertext": {
                    "c1": point_to_json(ciphertext.c1),
                    "c2": point_to_json(ciphertext.c2),
                },
            }
        )
        ciphertexts.append(ciphertext)

    aggregate = add_ciphertexts(ciphertexts)

    partials: Dict[int, Point] = {}
    partial_entries = []
    for index in selected_indices:
        share_scalar = key["shares"][index]  # type: ignore[index]
        public_share = key["public_shares"][index]  # type: ignore[index]
        share_point = partial_decrypt(share_scalar, aggregate.c1)
        proof = prove_partial_decryption(
            share_scalar,
            public_share,
            aggregate.c1,
            share_point,
            nonce=proof_nonces[index],
        )
        assert verify_partial_decryption(proof, public_share, aggregate.c1, share_point)
        partials[index] = share_point
        partial_entries.append(
            {
                "index": index,
                "share_scalar": str(share_scalar),
                "public_share": point_to_json(public_share),
                "partial_share": point_to_json(share_point),
                "proof": {
                    "t1": point_to_json(proof.t1),
                    "t2": point_to_json(proof.t2),
                    "z": str(proof.z),
                },
            }
        )

    combined_share = combine_partial_points(partials)
    message_point = remove_mask(aggregate, combined_share)
    decoded_tally = discrete_log_signed(message_point, bound=len(votes))
    assert decoded_tally == sum(votes)

    final_proof = prove_final_decryption(
        key["secret"],  # type: ignore[arg-type]
        public_key,
        aggregate.c1,
        combined_share,
        nonce=final_nonce,
    )
    assert verify_final_decryption(final_proof, public_key, aggregate.c1, combined_share)

    return {
        "curve": {
            "name": "bn254_g1",
            "field_modulus_p": str(FIELD_MODULUS),
            "group_order_q": str(GROUP_ORDER),
            "generator": point_to_json(GENERATOR),
        },
        "key_material": {
            "participants": key["participants"],
            "threshold": key["threshold"],
            "master_secret": str(key["secret"]),
            "polynomial_coefficients": [str(x) for x in key["coefficients"]],  # type: ignore[index]
            "public_key": point_to_json(public_key),
            "shares": {str(k): str(v) for k, v in key["shares"].items()},  # type: ignore[index]
            "public_shares": {
                str(k): point_to_json(v) for k, v in key["public_shares"].items()  # type: ignore[index]
            },
        },
        "ballots": ballots,
        "aggregate_ciphertext": {
            "c1": point_to_json(aggregate.c1),
            "c2": point_to_json(aggregate.c2),
        },
        "partial_decryptions": partial_entries,
        "combined_share": point_to_json(combined_share),
        "decrypted_message_point": point_to_json(message_point),
        "decoded_tally": decoded_tally,
        "final_decryption_proof": {
            "t1": point_to_json(final_proof.t1),
            "t2": point_to_json(final_proof.t2),
            "z": str(final_proof.z),
        },
    }


def demo_lines() -> Sequence[str]:
    vectors = deterministic_vectors()
    return [
        "Threshold ElGamal in the exponent over BN254 G1",
        f"public key H = {vectors['key_material']['public_key']}",
        f"votes       = {[b['vote'] for b in vectors['ballots']]}",
        f"tally       = {vectors['decoded_tally']}",
        f"agg.c1      = {vectors['aggregate_ciphertext']['c1']}",
        f"agg.c2      = {vectors['aggregate_ciphertext']['c2']}",
        f"combined D  = {vectors['combined_share']}",
        "partial proofs verified = true",
        "final proof verified    = true",
    ]


def main(argv: Sequence[str]) -> int:
    if len(argv) >= 2 and argv[1] == "vectors":
        output = json.dumps(deterministic_vectors(), indent=2)
        print(output)
        return 0

    if len(argv) >= 2 and argv[1] == "selftest":
        for _ in range(10):
            key = generate_threshold_key(5, 3)
            votes = [secrets.choice([-1, 0, 1]) for _ in range(8)]
            ciphertexts = [encrypt_signed(v, key["public_key"]) for v in votes]  # type: ignore[index]
            aggregate = add_ciphertexts(ciphertexts)
            chosen = [1, 2, 4]
            partials = {
                i: partial_decrypt(key["shares"][i], aggregate.c1)  # type: ignore[index]
                for i in chosen
            }
            combined_share = combine_partial_points(partials)
            message_point = remove_mask(aggregate, combined_share)
            decoded = discrete_log_signed(message_point, bound=len(votes))
            assert decoded == sum(votes)
        print("selftest ok")
        return 0

    for line in demo_lines():
        print(line)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
