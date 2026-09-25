#!/usr/bin/env python3
"""Publish owner-signed kind:30177 managed-agent records so Buzz Desktop lists your AWS agents
as your (shared) agents. Runs locally; your secret key is read from a hidden prompt, used to
sign, and never written anywhere.

Usage:
  python3 publish-owner-records.py <relay wss url> <owner_pubkey_hex> <respond_to> <agent_pubkey>=<Name> ...
  python3 publish-owner-records.py --test-key <relay wss url> <respond_to> <agent_pubkey>=<Name> ...
      (signs with a throwaway key: the relay should reject it as a non-member, proving the
       request format and signatures are accepted up to the membership check)
"""
import base64, getpass, hashlib, importlib.util, json, os, secrets, sys, time, urllib.error, urllib.request, uuid

_here = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("sop", os.path.join(_here, "sign-owner-proofs.py"))
sop = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(sop)

def sign_event(sk, kind, tags, content, created_at=None):
    pub = sop.pubkey_from_secret(sk).hex()
    created_at = created_at or int(time.time())
    ser = json.dumps([0, pub, created_at, kind, tags, content], separators=(",", ":"), ensure_ascii=False)
    eid = hashlib.sha256(ser.encode()).digest()
    return {"id": eid.hex(), "pubkey": pub, "created_at": created_at, "kind": kind,
            "tags": tags, "content": content, "sig": sop.schnorr_sign(eid, sk).hex()}

def post_event(sk, http_base, event):
    url = f"{http_base}/events"
    body = json.dumps(event, separators=(",", ":"), ensure_ascii=False).encode()
    auth = sign_event(sk, 27235, [["u", url], ["method", "POST"], ["nonce", str(uuid.uuid4())],
                                  ["payload", hashlib.sha256(body).hexdigest()]], "")
    req = urllib.request.Request(url, data=body, method="POST", headers={
        "Content-Type": "application/json", "User-Agent": "buzz-owner-records/1.0",
        "Authorization": "Nostr " + base64.b64encode(json.dumps(auth, separators=(",", ":")).encode()).decode()})
    try:
        with urllib.request.urlopen(req, timeout=20) as r: return r.status, r.read().decode()[:300]
    except urllib.error.HTTPError as e: return e.code, e.read().decode()[:300]

def main():
    args = sys.argv[1:]
    test = args[:1] == ["--test-key"]
    if test:
        relay, respond_to, pairs = args[1], args[2], args[3:]
        sk = secrets.token_bytes(32)
    else:
        if len(args) < 4: sys.exit(__doc__)
        relay, owner_pub, respond_to, pairs = args[0], args[1].lower(), args[2], args[3:]
        sk = sop.decode_secret(getpass.getpass("Buzz owner secret key (nsec1..., hidden): "))
        if sop.pubkey_from_secret(sk).hex() != owner_pub:
            sys.exit("That key does not match the expected owner pubkey; nothing published.")
    if respond_to not in ("owner-only", "anyone"): sys.exit("respond_to must be owner-only or anyone")
    http_base = relay.replace("wss://", "https://").replace("ws://", "http://").rstrip("/")
    ok = 0
    for pair in pairs:
        agent_pub, name = pair.split("=", 1)
        content = json.dumps({"name": name, "parallelism": 1, "respond_to": respond_to}, separators=(",", ":"))
        ev = sign_event(sk, 30177, [["d", agent_pub.lower()]], content)
        status, text = post_event(sk, http_base, ev)
        print(f"{name:<10} HTTP {status}  {text}")
        ok += 200 <= status < 300
    del sk
    print(f"published {ok}/{len(pairs)}")

if __name__ == "__main__":
    main()
