# ShareDND

Automatic Do Not Disturb while the screen is being shared.

When the first screencast starts (any app sharing via the portal — Discord,
OBS, browsers, `niri msg action set-dynamic-cast-*`, ...), notification DND is
enabled. When the last screencast stops, notifications come back.

## How it works

- A headless service follows `niri msg -j event-stream` and reacts to
  `CastsChanged` / `CastStartedOrChanged` / `CastStopped` events — no polling.
- On every cast event it re-queries `niri msg -j casts` as the authoritative
  state, so missed or reordered events cannot desync it. The stream is wrapped
  in a shell retry loop and resends full state on reconnect.
- DND is toggled through the host IPC (`noctalia msg notification-dnd-set`),
  so the usual OSD feedback appears.

## Ownership rules

- If DND was **already on** before sharing started, the plugin leaves it on
  after sharing ends (it never took ownership). The
  "Always disable DND after sharing" setting overrides this.
- If DND was enabled manually *during* sharing while the plugin owned it, it
  will still be turned off when sharing ends (the plugin cannot tell the
  difference).

## Settings

- **Only active streams** — count only casts with `is_active: true`. Off by
  default: any open screencast session (even paused or showing nothing) keeps
  DND on.
- **Always disable DND after sharing** — force DND off when sharing ends,
  regardless of its state before sharing started.

## Requirements & limitations

- Requires **niri** (detection is niri IPC; on other compositors the plugin
  is inert and shows a warning at startup).
- There is no plugin-disable hook in the host: if you disable the plugin
  mid-share while it owns DND, DND stays on — toggle it manually.
