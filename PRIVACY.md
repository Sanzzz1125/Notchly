# Privacy

Notchly runs **entirely on your Mac**. There is no server, no account, no analytics, no crash reporting and no telemetry.

## Network
The only outgoing requests are optional and can be switched off in **Settings → Privacy → Allow internet access**:

| Request | Why | Data sent |
|---|---|---|
| `https://lrclib.net/api/get` | Synced lyrics | Track title, artist, album |
| Spotify artwork URL | Album art for the player | Standard image request |

Everything else is local. You can verify this yourself: `grep -rn "URLSession" Sources/` lists every network call.

## Permissions (all optional, all revocable in System Settings → Privacy & Security)
| Permission | Used for | Stored? |
|---|---|---|
| Calendars / Reminders | Show events and to-dos in the notch | No – read live from macOS |
| Camera | Mirror tab only, while it is open | No – never recorded or saved |
| Automation (Spotify / Music) | Fallback now-playing and play/pause | No |
| Downloads folder | Notice a finished download (off by default) | No – file names only shown in an alert |

## Data on disk
Only your settings (UserDefaults), your Notes text and your app-launcher list. **Clipboard history and the file Tray are kept in memory only** and disappear when you quit.

## Now Playing
System-wide "Now Playing" is read through Apple's private MediaRemote framework (title, artist, artwork). This data stays in the app.
