# ProPresenter Voice Remote

Say "next slide" and ProPresenter advances. Hands-free slide control for when you're presenting.

It listens to your mic, transcribes what you say with a local Whisper server, and sends what it hears to ProPresenter's API. Everything runs on your own Mac. Nothing goes to the cloud.

## What you can say

| Say | What happens |
|---|---|
| "next slide" | Next slide in the focused presentation (same as the right arrow key) |
| "go back" | Previous slide (same as the left arrow key) |
| "first slide" | Jumps to slide 1 of the focused presentation |
| "last slide" | Jumps to the final slide of the focused presentation |
| "next presentation" | Puts the next item in the focused playlist live, on its first slide |

## What you need

- **macOS** with **ProPresenter** (tested on ProPresenter 21.4), with its Network API turned on: ProPresenter > Settings > Network > Enable Network.
- **[uv](https://docs.astral.sh/uv/)**, which installs the Python bits automatically on first run.
- A **[whisper.cpp](https://github.com/ggml-org/whisper.cpp) server** on `localhost:2022` that serves the OpenAI-style `/v1/audio/transcriptions` route. For example, `whisper-server --port 2022 --inference-path /v1/audio/transcriptions -m ggml-base.en.bin`.

## Run it

```bash
uv run voice_remote.py
```

Your terminal app will ask for microphone access the first time. It prints everything it hears. Say a command and ProPresenter follows. Press Ctrl+C to quit.

You don't have to tell it ProPresenter's port. ProPresenter can change ports between launches, so the app finds it by itself every time it starts.

## Mac app

```bash
chmod +x app/build.sh   # GitHub downloads drop the "runnable" setting
app/build.sh
```

This builds **ProPresenter Voice Remote.app** and installs it in `/Applications`. Launch it like any app. A small window shows what it hears and what it sent. The **Listening** switch (or Cmd-L) turns the mic fully off and back on. Quitting the app stops everything. macOS asks for microphone access the first time. The app carries its own copy of `voice_remote.py`, so run `app/build.sh` again after you change the script. The icon is drawn by `app/icon/make_icon.swift`.

### MIDI control

While the app is open, it shows up to other apps as a MIDI device named **ProPresenter Voice Remote**. Send it a Note On (any channel):

| Note | Does |
|---|---|
| 60 | Toggle listening |
| 61 | Listening on |
| 62 | Listening off |

MIDI works even while listening is off, so a ProPresenter macro (or Companion, or a Stream Deck) can switch it back on. For macros, use 61 and 62 rather than the toggle, so a macro always ends in the state you expect.

In ProPresenter: Settings > MIDI, add the "ProPresenter Voice Remote" device as an output, then add a Communication > MIDI > Note On action to a macro or slide. The device keeps the same ID every launch, so ProPresenter recognizes it after the app restarts.

## Test without talking

```bash
say -o test.wav --data-format=LEI16@16000 "Let's get started. Next slide."
uv run voice_remote.py --file test.wav
```

This really does press next slide in ProPresenter. Swap in any of the other commands to test them.

## How it behaves

- A short pause (0.4 s) ends a phrase. The slide moves about 1 to 1.5 seconds after you stop talking.
- Commands work anywhere in a sentence. Phrases like "the next steps" or "going back" don't trigger anything.
- Several commands in one breath run in order: "next slide, next slide" moves two slides.
- Everyday phrases can trigger it. "Let's go back to Genesis" or "like I said on the last slide" will move the slides.
- It hears speakers too. If a video or another app in the room says a command, it will act on it.

## License

MIT
