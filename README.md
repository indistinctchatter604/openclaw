# OpenClaw — Android/Termux Fork

> 🦞 Unofficial Android compatibility fork of [OpenClaw](https://github.com/openclaw/openclaw)  
> All credit to the original OpenClaw team and contributors.

---

## ⚠️ Early Stages — Expect Bugs

This fork is actively being developed and tested on Android. Core functionality works but you will encounter rough edges. If something breaks, open an issue and we'll work through it.

**What works:**
- Gateway running as a foreground process in tmux
- Telegram channel
- Agent conversations
- Doctor, onboard, and CLI commands

**What doesn't work:**
- Systemd service management (expected — Android has no systemd)
- macOS/iOS skills (Apple Notes, iMessage, Bear, etc.)
- UI build (dashboard shows a protocol mismatch warning — cosmetic only)
- Browser tools

---

## What's Different From Upstream

| Upstream | This Fork |
|----------|-----------|
| Throws fatal error on Android platform | Graceful no-op — gateway runs fine |
| `npm install` hits native compile (~30 min on ARM) | `--legacy-peer-deps` skips the conflict |
| No Termux path/env setup | Full env config for Termux |
| Config split across multiple files | Unified via `OPENCLAW_CONFIG_PATH` |
| `openclaw gateway start` fails on Android | Use `openclaw gateway` or `openclaw-gateway` |

---

## Requirements

- Android 8+ (API 26+)
- [Termux](https://f-droid.org/packages/com.termux/) from F-Droid (not Play Store)
- Node.js 22+ (`pkg install nodejs-lts`)
- An API key from one of the supported providers

---

## Install

One command from inside Termux:

```bash
pkg install git nodejs-lts -y && bash <(curl -fsSL https://raw.githubusercontent.com/indistinctchatter604/openclaw/termux-android-fix/termux-openclaw-setup.sh)
```

The installer will:
- Clone this repo to `~/git/openclaw`
- Install dependencies
- Apply the Android compatibility patch to dist files
- Create the `openclaw` and `openclaw-gateway` launchers in `~/bin`
- Set up environment variables in `~/.bashrc`
- Write a default config and auth scaffold

---

## Post-Install Setup

### 1. Add your API key

```bash
nano ~/.openclaw/state/agents/main/agent/auth-profiles.json
```

Replace `REPLACE_WITH_YOUR_API_KEY` with your key. Choose a provider:

| Provider | Free Tier | Notes |
|----------|-----------|-------|
| [Anthropic](https://console.anthropic.com) | No | Best experience, Haiku is cheap |
| [OpenRouter](https://openrouter.ai) | Trial credits | Recommended — access to many models |
| [Groq](https://console.groq.com) | Yes (limited) | Rate limits may cause issues |

For OpenRouter, also update the provider and model:

```bash
# Change provider in auth file to "openrouter", then set model:
openclaw config set agents.defaults.model.primary 'openrouter/deepseek/deepseek-chat-v3-0324'
```

### 2. Reload your shell

```bash
source ~/.bashrc
```

### 3. Run doctor

```bash
openclaw doctor
```

> **Note:** `Missing requirements: 47` is expected. Those are macOS/desktop skills that don't apply to Android.

### 4. Start the gateway

```bash
openclaw-gateway
```

This starts the gateway in a tmux session. Detach with `Ctrl+B D`. Reattach with `tmux attach -t openclaw`.

### 5. Onboard

```bash
openclaw onboard
```

Follow the prompts to configure channels (Telegram, WhatsApp, etc).

---

## Running the Gateway

The gateway runs as a foreground process in tmux — Android has no systemd.

```bash
openclaw-gateway          # start in tmux
tmux attach -t openclaw   # reattach
tmux kill-session -t openclaw  # stop
```

Ignore the `Gateway service not installed` message — that's the no-op patch working correctly.

---

## Local Model Support (Ollama)

If you have a PC with a GPU, you can run a local model via [Ollama](https://ollama.ai) and point openclaw at it:

```bash
openclaw config set agents.defaults.model.primary 'ollama/llama3.3'
```

The gateway on your phone will connect to Ollama on your PC over your local network. This gives you zero API costs and no rate limits. Setup guide coming soon.

---

## Patches Submitted Upstream

Changes in this fork that have been submitted as PRs to the original repo:

- [#23326](https://github.com/openclaw/openclaw/pull/23326) — `fix(daemon): graceful degradation on unsupported platforms` — prevents fatal throw on Android

---

## Known Issues

- **UI freshness warning** — The dashboard shows a protocol mismatch. This is cosmetic. The gateway works fine.
- **Gateway token resets** — Fixed by `OPENCLAW_CONFIG_PATH`. If you see this, ensure the env var is set.
- **Groq free tier** — TPM limits are too low for openclaw's compaction. Use OpenRouter or Anthropic.
- **tmux PATH** — If `openclaw` is not found inside tmux, run `export PATH="${HOME}/bin:${PATH}"`.

---

## Contributing

Found a bug on Android? Open an issue with:
- Your Android version
- Termux version (`echo $TERMUX_VERSION`)
- Node version (`node --version`)
- The full error output

PRs welcome. If a fix applies to all platforms, we'll submit it upstream too.

---

## Credits

- [OpenClaw](https://github.com/openclaw/openclaw) — the original project, all the hard work
- All upstream contributors and maintainers
