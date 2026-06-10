# DoriCall 🍎

Office desk-call for small teams on macOS — click a teammate's name, an apple-man card pops up on their screen with a chime, they answer 「收到 👌」 or 「等会 🫷」 and you see it instantly.

**Zero server. Zero accounts.** Peers find each other over the office LAN via Bonjour (`_doricall._tcp`), messages are single-line JSON over short-lived TCP connections, with AWDL as a fallback when Wi-Fi has client isolation. Proxy-safe: connections never go through the system proxy (Clash etc.).

This is the software v1 of a desk-gadget project — the future version is an ESP32-powered 3D-printed apple-man whose core rises and glows when you're called. The menu-bar app keeps the same interaction: call → glow (rising-core animation) → respond.

## Features

- 🔔 Call a person — floating card over everything (even fullscreen apps) + per-person sound
- 👍 Silent thumbs-up
- 💬 One-line text messages
- 📢 Broadcast to everyone online
- 🫷 "In a bit" reply for busy moments
- 🔕 Do-not-disturb with auto-reply
- Menu-bar resident, launch-at-login, no windows to keep open

## Build

```bash
bash build.sh   # → build/DoriCall.app + build/DoriCall.zip
```

Requires Xcode / Swift 5.9+, targets macOS 13+.

Run two instances side-by-side for testing:

```bash
build/DoriCall.app/Contents/MacOS/DoriCall --whoami andrea --dock
build/DoriCall.app/Contents/MacOS/DoriCall --whoami zhangwei --dock
```

(`--whoami` overrides identity without persisting; `--dock` shows a Dock icon for debugging.)

## Install

See [安装说明.md](安装说明.md) (in Chinese — drag to /Applications, right-click → Open, pick your name once, allow local network).
