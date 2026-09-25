#!/usr/bin/env python3
"""Create NIP-OA owner attestation ("auth") tags for your Buzz agents.

Runs locally. Reads your Buzz owner secret key (nsec1... or 64-hex) from a hidden prompt,
refuses unless it matches the expected owner pubkey, signs one tag per agent pubkey, and
writes auth-tags.json next to this script. The output contains only public data
(owner pubkey, conditions, signature) - never the secret key.

Usage: python3 sign-owner-proofs.py <owner_pubkey_hex> <agent_pubkey_hex>...
Self-test (no real key involved): python3 sign-owner-proofs.py --self-test
"""
import getpass, hashlib, json, os, secrets, sys

# --- BIP-340 Schnorr (reference implementation, pure Python) -------------------------
P = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F
N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
G = (0x79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798,
     0x483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8)

def _add(p1, p2):
    if p1 is None: return p2
    if p2 is None: return p1
    if p1[0] == p2[0] and p1[1] != p2[1]: return None
    if p1 == p2: lam = 3 * p1[0] * p1[0] * pow(2 * p1[1], P - 2, P) % P
    else: lam = (p2[1] - p1[1]) * pow(p2[0] - p1[0], P - 2, P) % P
    x = (lam * lam - p1[0] - p2[0]) % P
    return (x, (lam * (p1[0] - x) - p1[1]) % P)

def _mul(pt, n):
    r = None
    for i in range(256):
        if (n >> i) & 1: r = _add(r, pt)
        pt = _add(pt, pt)
    return r

def _b(x): return x.to_bytes(32, "big")
def _i(b): return int.from_bytes(b, "big")
def _th(tag, msg):
    t = hashlib.sha256(tag.encode()).digest()
    return hashlib.sha256(t + t + msg).digest()

def _lift_x(x):
    if x >= P: return None
    y_sq = (pow(x, 3, P) + 7) % P
    y = pow(y_sq, (P + 1) // 4, P)
    if pow(y, 2, P) != y_sq: return None
    return (x, y if y & 1 == 0 else P - y)

def pubkey_from_secret(sk):
    return _b(_mul(G, _i(sk))[0])

def schnorr_sign(msg, sk):
    d0 = _i(sk)
    if not 1 <= d0 <= N - 1: raise ValueError("invalid secret key")
    Pt = _mul(G, d0)
    d = d0 if Pt[1] % 2 == 0 else N - d0
    aux = secrets.token_bytes(32)
    t = bytes(a ^ b for a, b in zip(_b(d), _th("BIP0340/aux", aux)))
    k0 = _i(_th("BIP0340/nonce", t + _b(Pt[0]) + msg)) % N
    if k0 == 0: raise RuntimeError("bad nonce")
    R = _mul(G, k0)
    k = k0 if R[1] % 2 == 0 else N - k0
    e = _i(_th("BIP0340/challenge", _b(R[0]) + _b(Pt[0]) + msg)) % N
    sig = _b(R[0]) + _b((k + e * d) % N)
    if not schnorr_verify(msg, _b(Pt[0]), sig): raise RuntimeError("self-verify failed")
    return sig

def schnorr_verify(msg, pub, sig):
    Pt = _lift_x(_i(pub))
    r, s = _i(sig[:32]), _i(sig[32:])
    if Pt is None or r >= P or s >= N: return False
    e = _i(_th("BIP0340/challenge", sig[:32] + pub + msg)) % N
    R = _add(_mul(G, s), _mul(Pt, N - e))
    return R is not None and R[1] % 2 == 0 and R[0] == r

# --- bech32 (nsec) ---------------------------------------------------------------------
_C = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
def _polymod(v):
    g = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3]; c = 1
    for x in v:
        b = c >> 25; c = (c & 0x1ffffff) << 5 ^ x
        for i in range(5): c ^= g[i] if (b >> i) & 1 else 0
    return c
def decode_secret(s):
    s = s.strip()
    if len(s) == 64 and all(ch in "0123456789abcdefABCDEF" for ch in s): return bytes.fromhex(s)
    s = s.lower()
    if not s.startswith("nsec1"): raise ValueError("expected nsec1... or 64 hex chars")
    hrp, data = s.rsplit("1", 1); d = [_C.index(ch) for ch in data]
    if _polymod([ord(x) >> 5 for x in hrp] + [0] + [ord(x) & 31 for x in hrp] + d) != 1:
        raise ValueError("nsec checksum failed")
    acc = bits = 0; out = []
    for v in d[:-6]:
        acc = (acc << 5) | v; bits += 5
        while bits >= 8: bits -= 8; out.append((acc >> bits) & 255)
    return bytes(out[:32])

# --- NIP-OA ------------------------------------------------------------------------------
def auth_tag(owner_sk, agent_pub_hex, conditions=""):
    msg = hashlib.sha256(f"nostr:agent-auth:{agent_pub_hex}:{conditions}".encode()).digest()
    sig = schnorr_sign(msg, owner_sk)
    return ["auth", pubkey_from_secret(owner_sk).hex(), conditions, sig.hex()]

def main():
    if sys.argv[1:] == ["--self-test"]:
        sk = secrets.token_bytes(32); agent = pubkey_from_secret(secrets.token_bytes(32)).hex()
        tag = auth_tag(sk, agent)
        print(json.dumps({"owner_secret_hex": sk.hex(), "agent_pubkey": agent, "tag": tag}))
        return
    if len(sys.argv) < 3: sys.exit(__doc__)
    owner_pub, agents = sys.argv[1].lower(), [a.lower() for a in sys.argv[2:]]
    sk = decode_secret(getpass.getpass("Buzz owner secret key (nsec1..., hidden): "))
    if pubkey_from_secret(sk).hex() != owner_pub:
        sys.exit("That key does not match the expected owner pubkey; nothing written.")
    tags = {a: json.dumps(auth_tag(sk, a), separators=(",", ":")) for a in agents}
    del sk
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "auth-tags.json")
    with open(out, "w") as f: json.dump(tags, f, indent=1)
    print(f"Signed {len(tags)} owner proofs -> {out}")

if __name__ == "__main__":
    main()
