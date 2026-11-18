# Privacy

Notchly runs **entirely on your Mac**. There is no server, no account, no analytics, no crash reporting and no telemetry.

## Network
Every outgoing request is optional. **Settings → Privacy → Allow internet access** switches all of them off at once.

| Request | Why | Data sent | Default |
|---|---|---|---|
| `https://lrclib.net/api/search` | Synced lyrics | Track title, artist | On |
| Spotify artwork URL | Album art for the player | A standard image request to the URL Spotify gives | On |
| `https://geocoding-api.open-meteo.com` | Find your city's coordinates (Weather) | The city name you typed, once | **Off** |
| `https://api.open-meteo.com` | Forecast (Weather) | Those coordinates | **Off** |
| `https://accounts.spotify.com` | Sign in to Spotify (PKCE), refresh the sign-in | Your Client ID, a one-time code, your refresh token | **Off** |
| `https://api.spotify.com` | List your playlists, add songs, create playlists | Your access token, playlist IDs, song IDs, playlist names you type | **Off** |

Spotify playlists need their own opt-in (Settings → Privacy, or Settings → Music → Playlists) and only contact Spotify when you press a button: nothing runs in the background. The sign-in token is stored in your macOS Keychain, never in preferences.

Weather needs its own opt-in (Settings → Privacy → *Show weather*) in addition to the master switch. Open-Meteo needs no account or API key, and Notchly never reads your system location.

Everything else is local. Verify it yourself: `grep -rn "URLSession" Sources/` lists every network call.

## Permissions (all optional, all revocable in System Settings → Privacy & Security)
Notchly does not ask for any of these at launch. The welcome tour and each tab explain the permission and ask only when you press **Allow**.

| Permission | Used for | Stored? |
|---|---|---|
| Calendars / Reminders | Show events and to-dos in the notch | No. Read live from macOS |
| Camera | Mirror tab only, while it is open | No. Never recorded or saved |
| Automation: Spotify / Music | Fallback now-playing, play/pause, and (Spotify) reading the playing song’s ID when you add it to a playlist | No |
| Automation: System Events | Only if you press the Dark Mode or Mute tiles | No |
| Downloads folder | Notice a finished download (off by default) | No. File names only shown in an alert |

Notchly never needs Accessibility, Full Disk Access or Screen Recording.

## Data on disk
- Settings (UserDefaults), your Notes, your app-launcher list and your custom shortcuts.
- **Your Stash** of Spotify songs (title, artist, song ID, artwork link) in `~/Library/Application Support/Notchly/stash.json`. Delete songs in the app or remove the file.
- **Pinned clipboard snippets** (only the ones you pin; unpin to remove).
- **Everything else in the clipboard history, and the file Tray, is kept in memory only** and disappears when you quit.
- Clipboard items that password managers mark as concealed or transient are ignored.

## Now Playing
System-wide "Now Playing" is read through Apple's private MediaRemote framework (title, artist, artwork). This data stays in the app.

## Custom shortcuts
Shortcuts you create (apps, websites, Shortcuts-app automations, shell commands) run only when you press them and with your own permissions.
