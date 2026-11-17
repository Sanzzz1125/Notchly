# Security

## Reporting a vulnerability
Please open a private security advisory on GitHub (Security → Report a vulnerability) rather than a public issue.

## Design
- No network service, no listening sockets, no auto-update, no remote code.
- No analytics or telemetry.
- Source is small and readable; build it yourself with `./build.sh`.
- Runs as a normal user process (no admin rights, no kernel extensions, no launch daemons).
- Debug aids (`-demoMode`, `-debugHooks`, `-factoryDefaults`) only act on launch arguments or local Darwin notifications and are off unless you pass them.
- One helper (`bridge/MediaBridge.m`) is compiled on **your** machine at build time and loaded into `/usr/bin/perl` to read Now Playing. It only calls MediaRemote and prints JSON to Notchly.

## Things that run code you configure
- **Custom shortcuts** of type *Shell command* execute `/bin/zsh -c <your text>` as you when you press the tile. Notchly never creates or changes them on its own; they are stored in your user defaults.
- The Dark Mode / Mute tiles run short AppleScript snippets; Do Not Disturb runs a Shortcut you name.

## Honest limitations
- The app is **ad-hoc signed and not notarized**, because it is built locally. Build from source rather than trusting a binary from anyone. If you share the zip from `scripts/package.sh`, share its `.sha256` too so people can check it.
- It is not sandboxed (it needs Apple Events, MediaRemote and the Downloads folder).
- It uses a private Apple framework (MediaRemote), which Apple may change at any time.
