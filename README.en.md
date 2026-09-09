# Codex Pulse

[中文](README.md) | **English**

A lightweight macOS menu bar app for viewing your Codex 5-hour and 7-day usage limits in real time.

> Not an official OpenAI application. For personal use and learning purposes only.

## Features

- Display usage directly in the menu bar, for example: `5h: 99% - 7d: 99%`
- Show 5-hour and 7-day percentages and countdowns
- Use `HH:MM` countdowns with system SF Symbols
- Always show complete usage data in the menu, even when all menu bar display options are disabled
- Four display options that do not close the menu when clicked:
  - `5h percentage`
  - `7d percentage`
  - `5h countdown`
  - `7d countdown`
- Include a “Launch at Login” switch, disabled by default, using the native macOS login item mechanism
- Refresh once per minute by default; usage events trigger an immediate update and restart the refresh countdown
- Run entirely as a menu bar app without a Dock icon or main window
- Support Chinese and English, following the system preferred language; English is used for unsupported languages

## Screenshots

Menu bar status:

![Menu bar status](docs/images/status-bar.png)

Menu:

![Menu](docs/images/menu.png)

## Login and data source

The app does not provide its own login page and does not store your password or API key. It starts the local:

```text
codex app-server
```

It then requests usage data through Codex App Server and listens for usage update events. Login is handled by the ChatGPT / Codex client installed on your Mac.

Before first use, install and sign in to the ChatGPT desktop app or Codex CLI. For Codex CLI, run `codex login` and complete the login flow in your browser.

Official documentation:

- [Codex CLI Quickstart](https://learn.chatgpt.com/docs/codex/cli)
- [Codex Authentication](https://learn.chatgpt.com/docs/auth)
- [Codex App Server](https://learn.chatgpt.com/docs/app-server)

### Using the app as another user

Each user needs to:

1. Install the ChatGPT desktop app or Codex CLI on their own Mac
2. Sign in with their own ChatGPT account
3. Install and run Codex Pulse

The app never uses the developer's account and does not require anyone to copy or share authentication files. It displays the usage data of the account currently signed in on that Mac.

## Requirements

- macOS 26.5 or later
- An Intel + Apple Silicon Universal build is provided
- ChatGPT desktop app or Codex CLI installed and signed in
- Xcode, only if building from source

## Build and run from source

```bash
git clone https://github.com/ScorpioQ/CodexData.git
cd CodexData
chmod +x script/build_and_run.sh
./script/build_and_run.sh --verify
```

You can also open `CodexData.xcodeproj` in Xcode and run the project directly.

Common commands:

```bash
./script/build_and_run.sh run       # Build and run
./script/build_and_run.sh --verify  # Build, run, and verify the process
./script/build_and_run.sh --logs    # Build, run, and show logs
```

Build a Universal Release DMG:

```bash
./script/package_release.sh 0.1.0
```

The output is `dist/CodexPulse-0.1.0-universal.dmg`. By default this creates an unsigned development package. Configure Apple Developer ID signing and notarization before distributing it publicly.

For the complete certificate, private key, Developer ID signing, Apple notarization, Universal DMG, and GitHub Release workflow, see the [release guide](docs/RELEASE.md).

## Privacy and security

- The app has no own server
- The app only requests usage percentages and reset times
- The app does not read chat content
- The app does not store account passwords, API keys, or OAuth credentials
- Do not package or commit local Codex authentication files

The current implementation depends on the Codex App Server interface, so compatibility may be affected if Codex changes that interface. Code signing and notarization are still required before distributing a production DMG; the included script is also suitable for local development and verification.

## Project status

This is an early version for personal use. Issues and pull requests are welcome.
