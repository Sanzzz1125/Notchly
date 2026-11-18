#!/usr/bin/env python3
"""Fake Spotify accounts + Web API for testing Notchly's playlist features without touching a real account.
Dev tool only: python3 scripts/mock-spotify.py [port]. Control endpoints start with /_ ."""
import base64, hashlib, json, sys, threading, time, urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

S = {"challenge": None, "access": None, "refresh": "R1", "ttl": 3600, "adds": [], "created": [], "rl_hits": 0, "tokens_issued": 0, "refreshes": 0}
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
ME = {"id": "u1", "display_name": "Mock Listener"}

def playlists():
    out = []
    for i in range(120):                                  # 120 playlists: forces paging (50 per page)
        mine = i % 3 != 2                                   # every 3rd belongs to someone else
        collab = i % 9 == 2                                 # ...except a few collaborative ones
        out.append({"id": f"p{i}", "name": f"Mix {i}" if i else "Movzzzzzz", "collaborative": collab, "public": False,
                    "owner": {"id": "u1" if mine else "other"}, "images": [], "items": {"total": i}})
    return out
PL = playlists()

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def send(self, code, obj=None, headers=None):
        b = json.dumps(obj if obj is not None else {}).encode()
        self.send_response(code); self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(b)))
        for k, v in (headers or {}).items(): self.send_header(k, v)
        self.end_headers(); self.wfile.write(b)
    def body(self):
        n = int(self.headers.get("Content-Length") or 0); return self.rfile.read(n).decode() if n else ""
    def authed(self):
        return self.headers.get("Authorization", "") == f"Bearer {S['access']}" and S["access"] is not None
    def issue(self, refresh=None):
        S["tokens_issued"] += 1
        S["access"] = f"A{S['tokens_issued']}"
        out = {"access_token": S["access"], "token_type": "Bearer", "expires_in": S["ttl"], "scope": "x"}
        if refresh: out["refresh_token"] = refresh
        return out

    def do_GET(self):
        u = urllib.parse.urlparse(self.path); q = dict(urllib.parse.parse_qsl(u.query))
        if u.path == "/_state": return self.send(200, {k: S[k] for k in ("adds", "created", "tokens_issued", "refreshes")} | {"added_count": sum(len(a[1]) for a in S["adds"])})
        if u.path == "/_challenge": S["challenge"] = q["c"]; return self.send(200)
        if u.path == "/_expire": S["access"] = "EXPIRED"; return self.send(200)
        if u.path == "/_ttl": S["ttl"] = int(q["s"]); return self.send(200)
        if u.path == "/_revoke": S["refresh"] = None; S["access"] = "EXPIRED"; return self.send(200)
        if not self.authed(): return self.send(401, {"error": {"status": 401, "message": "The access token expired"}})
        if u.path == "/v1/me": return self.send(200, ME)
        if u.path == "/v1/me/playlists":
            off, lim = int(q.get("offset", 0)), int(q.get("limit", 20))
            page = PL[off:off + lim]
            return self.send(200, {"items": page, "total": len(PL), "next": "more" if off + lim < len(PL) else None})
        self.send(404, {"error": {"status": 404, "message": "not found"}})

    def do_POST(self):
        u = urllib.parse.urlparse(self.path); raw = self.body()
        if u.path == "/api/token":
            f = dict(urllib.parse.parse_qsl(raw))
            if f.get("grant_type") == "authorization_code":
                v = base64.urlsafe_b64encode(hashlib.sha256(f.get("code_verifier", "").encode()).digest()).decode().rstrip("=")
                if f.get("code") != "MOCKCODE" or v != S["challenge"] or f.get("redirect_uri") != "notchly://callback":
                    return self.send(400, {"error": "invalid_grant", "error_description": "bad code, verifier or redirect"})
                return self.send(200, self.issue(S["refresh"]))
            if f.get("grant_type") == "refresh_token":
                if S["refresh"] is None or f.get("refresh_token") != S["refresh"]: return self.send(400, {"error": "invalid_grant"})
                S["refreshes"] += 1
                return self.send(200, self.issue())          # no new refresh token: app must keep the old one
            return self.send(400, {"error": "unsupported_grant_type"})
        if not self.authed(): return self.send(401, {"error": {"status": 401, "message": "The access token expired"}})
        parts = u.path.strip("/").split("/")
        if len(parts) == 4 and parts[0] == "v1" and parts[1] == "playlists" and parts[3] == "items":
            pid = parts[2]; uris = json.loads(raw).get("uris", [])
            if len(uris) > 100: return self.send(400, {"error": {"status": 400, "message": "Maximum 100 items"}})
            if pid == "gone": return self.send(404, {"error": {"status": 404, "message": "Not found."}})
            if pid == "forbidden": return self.send(403, {"error": {"status": 403, "message": "Insufficient client scope"}})
            if pid == "ratelimit":
                S["rl_hits"] += 1
                if S["rl_hits"] == 1: return self.send(429, {"error": {"status": 429, "message": "slow down"}}, {"Retry-After": "1"})
            S["adds"].append((pid, uris)); return self.send(201, {"snapshot_id": "s"})
        if u.path in ("/v1/me/playlists", "/v1/users/u1/playlists"):
            d = json.loads(raw); pid = f"new{len(S['created'])+1}"; S["created"].append({"id": pid, "name": d.get("name"), "public": d.get("public")})
            return self.send(201, {"id": pid, "name": d.get("name")})
        self.send(404, {"error": {"status": 404, "message": "not found"}})

if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
