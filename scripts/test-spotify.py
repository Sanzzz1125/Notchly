#!/usr/bin/env python3
"""End-to-end test of Notchly's Spotify features against scripts/mock-spotify.py (never touches a real account).
Run: ./build.sh && python3 scripts/test-spotify.py     (stdlib only; needs notifyutil + open, i.e. macOS)"""
import json, os, re, subprocess, sys, time, urllib.parse, urllib.request

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
BIN = os.path.join(ROOT, "build/Notchly.app/Contents/MacOS/Notchly")
PORT = 8765
MOCK = f"http://127.0.0.1:{PORT}"
LOG = os.path.join(ROOT, "build", "spotify-test.log")
results = []

def check(name, ok, detail=""):
    results.append(ok); print(("PASS  " if ok else "FAIL  ") + name + (f"   [{detail}]" if detail and not ok else ""))

def post(name): subprocess.run(["notifyutil", "-p", f"notchly.debug.spotify.{name}"], check=True)
def log(): return open(LOG).read() if os.path.exists(LOG) else ""
def get(path): return json.load(urllib.request.urlopen(MOCK + path))
def wait_for(pattern, since, timeout=8):
    end = time.time() + timeout
    while time.time() < end:
        m = re.search(pattern, log()[since:])
        if m: return m
        time.sleep(0.15)
    return None
def run(hook, pattern, timeout=8):
    n = len(log()); post(hook); m = wait_for(pattern, n, timeout); return m.group(0) if m else "(no output)"

subprocess.run(["pkill", "-x", "Notchly"]); time.sleep(0.5)
mock = subprocess.Popen([sys.executable, os.path.join(ROOT, "scripts/mock-spotify.py"), str(PORT)]); time.sleep(0.8)
open(LOG, "w").close()
app = subprocess.Popen([BIN, "-factoryDefaults", "YES", "-onboarded", "YES", "-debugHooks", "YES", "-spotifyEnabled", "YES", "-allowNetwork", "YES",
                        "-spotifyClientID", "MOCKCLIENT", "-spotifyAPI", MOCK + "/v1", "-spotifyAccounts", MOCK, "-spotifyNoBrowser", "YES", "-demoMode", "NO"],
                       stdout=open(LOG, "w"), stderr=subprocess.DEVNULL)
for _ in range(60):                       # wait until the app answers (first launch after a build can be slow)
    post("status"); time.sleep(0.25)
    if "STATUS" in log(): break
try:
    check("PKCE challenge matches the RFC 7636 test vector", "OK" in run("pkce", r"PKCE.*"))

    # --- sign-in edge cases before a real sign-in
    subprocess.run(["open", "notchly://callback?code=x&state=forged"]); time.sleep(1.0)
    r = run("status", r"STATUS.*")
    check("forged callback (wrong state) is rejected", "signedIn=false" in r and "unexpected" in r, r)

    n = len(log()); post("signin"); m = wait_for(r"SPOTIFY_AUTH_URL (\S+)", n)
    check("sign-in builds an authorize URL with PKCE + state", bool(m) and "code_challenge_method=S256" in m.group(1) and "state=" in m.group(1))
    q = dict(urllib.parse.parse_qsl(urllib.parse.urlparse(m.group(1)).query)) if m else {}
    check("authorize URL asks for playlist scopes and the notchly:// redirect",
          q.get("redirect_uri") == "notchly://callback" and "playlist-modify-private" in q.get("scope", "") and q.get("client_id") == "MOCKCLIENT")
    subprocess.run(["open", "notchly://callback?error=access_denied&state=" + q.get("state", "")]); time.sleep(1.0)
    check("user pressing Cancel in Spotify is handled", "cancelled" in run("status", r"STATUS.*").lower())

    # --- real sign-in
    n = len(log()); post("signin"); m = wait_for(r"SPOTIFY_AUTH_URL (\S+)", n)
    q = dict(urllib.parse.parse_qsl(urllib.parse.urlparse(m.group(1)).query))
    urllib.request.urlopen(MOCK + "/_challenge?c=" + urllib.parse.quote(q["code_challenge"]))
    subprocess.run(["open", "notchly://callback?code=MOCKCODE&state=" + q["state"]]); time.sleep(1.5)
    st = run("status", r"STATUS.*")
    check("token exchange with PKCE verifier succeeds and user is shown", "signedIn=true" in st and "Mock Listener" in st, st)

    # --- API behaviour
    r = run("lists", r"LISTS.*")
    mine = [i for i in range(120) if (i % 3 != 2) or (i % 9 == 2)]
    check("playlist list pages through 120 and keeps only addable ones", f"LISTS {len(mine)} " in r and "first=Movzzzzzz" in r, r)
    check("add one song", "OK" in run("add.ok", r"ADD ok.*"))
    check("add 250 songs is split into batches of 100", "OK" in run("add.big", r"ADD big.*") and get("/_state")["added_count"] == 251, str(get("/_state")["added_count"]))
    check("rate limit (429, Retry-After 1s) is waited out and retried", "OK" in run("add.ratelimit", r"ADD ratelimit.*", 10))
    check("deleted playlist gives a clear message", "Playlist not found" in run("add.gone", r"ADD gone.*"))
    check("403 gives a clear message", "refused" in run("add.forbidden", r"ADD forbidden.*"))
    r = run("create", r"CREATE.*")
    check("create playlist (unicode + emoji name, private)", "CREATE OK new1" in r and get("/_state")["created"][0]["public"] is False and "🎧" in get("/_state")["created"][0]["name"], r)

    # --- token lifecycle
    urllib.request.urlopen(MOCK + "/_expire")
    r = run("add.ok", r"ADD ok.*")
    check("expired access token is refreshed silently and the call retried", "OK" in r and get("/_state")["refreshes"] == 1, r)
    r = run("add.ok", r"ADD ok.*")
    check("refresh token is kept (second refresh path still works)", "OK" in r)
    urllib.request.urlopen(MOCK + "/_revoke")
    r = run("add.ok", r"ADD ok.*")
    st = run("status", r"STATUS.*")
    check("revoked login → clear message and signed out (no crash)", "sign-in expired" in r.lower() or "sign in again" in r.lower(), r)
    check("…and the app really is signed out", "signedIn=false" in st, st)
    check("app still alive after all of that", app.poll() is None)
finally:
    app.terminate(); mock.terminate()
    subprocess.run(["pkill", "-x", "Notchly"])
print(f"\n{sum(results)}/{len(results)} checks passed")
sys.exit(0 if all(results) else 1)
