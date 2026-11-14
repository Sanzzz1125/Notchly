# Security

## Reporting a vulnerability
Please open a private security advisory on GitHub (Security → Report a vulnerability) rather than a public issue.

## Design
- No network service, no listening sockets, no auto-update, no remote code.
- No analytics or telemetry.
- Source is small and readable; build it yourself with `./build.sh`.
- Runs as a normal user process (no admin rights, no kernel extensions, no launch daemons).
- One helper (`bridge/MediaBridge.m`) is compiled on **your** machine at build time and loaded into `/usr/bin/perl` to read Now Playing. It only calls MediaRemote and prints JSON to Notchly.

## Honest limitations
- The app is **ad-hoc signed and not notarized**, because it is built locally. Build from source rather than trusting a binary from anyone.
- It is not sandboxed (it needs Apple Events, MediaRemote and the Downloads folder).
- It uses a private Apple framework (MediaRemote), which Apple may change at any time.
