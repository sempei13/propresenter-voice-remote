# /// script
# requires-python = ">=3.12,<3.13"
# dependencies = [
#     "sounddevice>=0.4.6",
#     "numpy>=1.26",
#     "httpx>=0.27",
#     "webrtcvad-wheels>=2.0.14",
# ]
# ///
"""
ProPresenter Voice Remote: listens to the mic and drives ProPresenter by voice.

  "next slide"         next slide (the right-arrow key)
  "go back"            previous slide (the left-arrow key)
  "first slide"        slide 1 of the focused presentation
  "last slide"         final slide of the focused presentation
  "next presentation"  next item in the focused playlist, live

Speech goes to a local whisper.cpp server on port 2022 (see README).
Matches go straight to ProPresenter's API.

Run:  uv run ~/propresenter-voice-remote/voice_remote.py
Test without a mic:  uv run ~/propresenter-voice-remote/voice_remote.py --file clip.wav
"""

from __future__ import annotations

import argparse
import io
import os
import queue
import re
import subprocess
import sys
import time
import wave

import httpx
import numpy as np
import sounddevice as sd
import webrtcvad

SAMPLE_RATE = 16000
WHISPER_URL = "http://localhost:2022/v1/audio/transcriptions"

FRAME_MS = 30
FRAME_SAMPLES = SAMPLE_RATE * FRAME_MS // 1000
END_SILENCE_MS = 400   # pause that ends a phrase; short so the slide moves fast
MIN_SPEECH_MS = 240    # ignore coughs and clicks
MAX_PHRASE_MS = 8000   # cut long runs of talking so they don't pile up

# Each phrase matches any case and punctuation, with or without a space or
# hyphen ("next-slide", "goback"). Group names are the command names.
COMMAND_RE = re.compile(
    r"\b(?:"
    r"(?P<next_slide>next[\s-]*slides?)"
    r"|(?P<go_back>go[\s-]*back)"
    r"|(?P<first_slide>first[\s-]*slides?)"
    r"|(?P<last_slide>last[\s-]*slides?)"
    r"|(?P<next_presentation>next[\s-]*presentations?)"
    r")\b",
    re.IGNORECASE,
)
NON_SPEECH_RE = re.compile(r"\[[^\]]*\]|\([^)]*\)")


# ---------------- ProPresenter ----------------

def find_propresenter() -> str:
    """ProPresenter's API port changes between launches, so look it up live."""
    out = subprocess.run(
        ["lsof", "-iTCP", "-sTCP:LISTEN", "-P", "-n"], capture_output=True, text=True
    ).stdout
    ports = sorted({
        line.rsplit(":", 1)[1].split()[0]
        for line in out.splitlines()
        if line.lower().startswith("propresen")
    })
    for port in ports:
        base = f"http://localhost:{port}"
        try:
            r = httpx.get(f"{base}/version", timeout=2)
            if r.status_code == 200 and "ProPresenter" in r.text:
                print(f"ProPresenter found: {r.json().get('host_description')} on port {port}")
                return base
        except httpx.HTTPError:
            pass
    sys.exit("ProPresenter isn't running, or its Network API is turned off "
             "(ProPresenter > Settings > Network > Enable Network).")


def last_slide_path(base: str) -> str:
    """The last cue's index isn't exposed directly, so count the focused presentation's cues."""
    uuid = httpx.get(base + "/v1/presentation/focused", timeout=2).json()["uuid"]
    cues = httpx.get(f"{base}/v1/presentation/{uuid}", timeout=2).json()["presentation"]["total_cues"]
    return f"/v1/presentation/focused/{cues - 1}/trigger"


COMMANDS = {
    "next_slide": lambda base: "/v1/presentation/focused/next/trigger",
    "go_back": lambda base: "/v1/presentation/focused/previous/trigger",
    "first_slide": lambda base: "/v1/presentation/focused/0/trigger",
    "last_slide": last_slide_path,
    "next_presentation": lambda base: "/v1/playlist/focused/next/trigger",
}


def run_command(base: str, name: str) -> None:
    label = name.replace("_", " ").upper()
    try:
        r = httpx.get(base + COMMANDS[name](base), timeout=2)
        ok = r.status_code in (200, 204)
        print(f"  -> {label} {'sent' if ok else f'failed (HTTP {r.status_code})'}")
    except (httpx.HTTPError, KeyError, ValueError) as e:
        print(f"  -> {label} failed: {e}")


# ---------------- speech ----------------

def transcribe(audio: np.ndarray) -> str:
    buf = io.BytesIO()
    with wave.open(buf, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SAMPLE_RATE)
        wf.writeframes(audio.astype(np.int16).tobytes())
    r = httpx.post(
        WHISPER_URL,
        files={"file": ("phrase.wav", buf.getvalue(), "audio/wav")},
        timeout=15,
    )
    r.raise_for_status()
    text = NON_SPEECH_RE.sub("", r.json().get("text", "") or "")
    return " ".join(text.split())


def phrases(frames):
    """Group 30ms frames into phrases that end at a short pause."""
    vad = webrtcvad.Vad(2)
    voiced, voiced_ms, silence_ms, total_ms, active = [], 0, 0, 0, False
    for frame in frames:
        if len(frame) != FRAME_SAMPLES * 2:
            continue
        if vad.is_speech(frame, SAMPLE_RATE):
            voiced.append(frame)
            voiced_ms += FRAME_MS
            silence_ms = 0
            active = True
        elif active:
            voiced.append(frame)
            silence_ms += FRAME_MS
        if active:
            total_ms += FRAME_MS
        if active and (silence_ms >= END_SILENCE_MS or total_ms >= MAX_PHRASE_MS):
            if voiced_ms >= MIN_SPEECH_MS:
                yield np.frombuffer(b"".join(voiced), dtype=np.int16)
            voiced, voiced_ms, silence_ms, total_ms, active = [], 0, 0, 0, False
    if voiced and voiced_ms >= MIN_SPEECH_MS:
        yield np.frombuffer(b"".join(voiced), dtype=np.int16)


def mic_frames():
    q: queue.Queue[bytes] = queue.Queue()
    stream = sd.RawInputStream(
        samplerate=SAMPLE_RATE, channels=1, dtype="int16",
        blocksize=FRAME_SAMPLES, callback=lambda data, *_: q.put(bytes(data)),
    )
    with stream:
        while True:
            yield q.get()


def file_frames(path: str):
    with wave.open(path, "rb") as wf:
        if (wf.getframerate(), wf.getnchannels(), wf.getsampwidth()) != (SAMPLE_RATE, 1, 2):
            sys.exit("Test file must be 16 kHz mono 16-bit WAV.")
        data = wf.readframes(wf.getnframes())
    step = FRAME_SAMPLES * 2
    for i in range(0, len(data), step):
        yield data[i:i + step]
    yield b"\0" * step * (END_SILENCE_MS // FRAME_MS + 1)  # trailing pause


def main() -> None:
    ap = argparse.ArgumentParser(description="Control ProPresenter by voice.")
    ap.add_argument("--file", help="16 kHz mono WAV to test with instead of the mic")
    args = ap.parse_args()

    base = find_propresenter()
    try:
        httpx.post(WHISPER_URL, timeout=2)
    except httpx.HTTPError:
        sys.exit("Speech server isn't running: start the whisper.cpp server on localhost:2022 (see README).")

    quit_key = "Cmd+Q" if os.environ.get("VOICE_REMOTE_APP") else "Ctrl+C"
    print('Listening. Say "next slide", "go back", "first slide", "last slide", '
          f'or "next presentation". {quit_key} to quit.\n')
    source = file_frames(args.file) if args.file else mic_frames()
    try:
        for audio in phrases(source):
            t0 = time.monotonic()
            text = transcribe(audio)
            if not text:
                continue
            hits = [m.lastgroup for m in COMMAND_RE.finditer(text)]
            print(f'heard: "{text}"  ({time.monotonic() - t0:.1f}s)')
            for i, name in enumerate(hits):
                if i:
                    time.sleep(0.4)  # back-to-back triggers get merged into one by ProPresenter
                run_command(base, name)
    except KeyboardInterrupt:
        print("\nStopped.")


if __name__ == "__main__":
    main()
