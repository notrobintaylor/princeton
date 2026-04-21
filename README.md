# princeton

### A guitar amp simulator, pedalboard and looper for Monome Norns

[![princeton – Norns Script Demo](https://img.youtube.com/vi/VqkFejb8owY/maxresdefault.jpg)](https://www.youtube.com/watch?v=VqkFejb8owY)

princeton models a small 1960s American combo amp. Plug your electric guitar directly into the left norns input. No preamp needed.

The gain range runs from clean to light overdrive. The spring reverb and bias tremolo are always available. There is a looper between tremolo and reverb: what you loop also gets washed in spring reverb. Four stompbox-style effects sit before the amp.

## What it does

**Amp.** Two preamp stages, passive tone stack with a fixed mid scoop, power amp compression that blooms under hard picking. Volume below 5 stays clean. Past 7 the preamp stages begin to saturate.

**Tone stack.** Position 5 on Bass and Treble gives a moderate boost to the low and high bands — the typical Fender voice with the amp open. Turn below 3 to cut; keep at 5–7 for warmth and sparkle. The mid scoop is fixed and permanent.

**Tremolo.** Bias-style amplitude modulation. Speed and Intensity both default to 0. Up to Intensity 1.5 the effect blends in while the dry signal fades; past 1.5 pure tremolo with increasing depth. Peaks always remain at full amplitude. Tremolo can be bypassed independently without losing the Speed and Intensity settings.

**Looper.** 40-second stereo buffer, post-tremolo, pre-reverb. The spring reverb washes over the loop and the live signal equally. Forward and reverse. Half, normal, and double speed. Regular overdub layers new material over existing. Overwrite replaces it. The looper continues to run in the background while any other view (tuner, pedalboard, metro) is open.

**Spring reverb.** Applied to the full mix: live signal and loop together. Amount controls both send level and decay time together. At low values the spring tank is barely audible with a short decay. Turning it up increases both how much signal enters the tank and how long it rings — from a subtle shimmer at 2–3 to a long, washy bloom at 8–10. Reverb can be bypassed independently without losing the Amount setting.

**Pedalboard.** Four effects run before the amp. Push and Distort are a distortion pair; Warp and Repeat are a modulation pair. Each effect is independently bypassable. The active effect's label appears at full brightness.

**Amp bypass.** An Amp Enable toggle is available in the PARAMS menu and can be mapped to a MIDI footswitch. When bypassed, the preamp, tone stack, power amp, and cabinet are removed from the signal path. The panel lamp dims to indicate bypass. Every stage — pedals, amp, tremolo, looper, reverb, and cabinet — can be independently bypassed.

**Output.** Stereo. Tremolo alternates between L and R (classic bias-trem ping-pong). The spring reverb outputs a stereo pair via its allpass diffuser. Both norns sends carry the full stereo signal — princeton works as a stereo source in any fx_mod slot.

**Metronome.** A click track that runs independently of the main signal path. Tempo 20–300 BPM, adjustable level, and chromatic pitch. Controlled entirely from the PARAMS menu — BPM, Level, Pitch, and an Active/Bypass toggle (all MIDI-mappable).

## Signal flow

```
guitar → Push → Distort → Warp → Repeat
       → preamp → tone stack → power amp
       → tremolo (stereo) → looper (stereo) → spring reverb (stereo)
       → cabinet (10", 3 mic positions) → master → out L/R
                                                 → send A (stereo)
                                                 → send B (stereo)
```

## Controls

| Control | Function |
|---------|----------|
| **E2** | Select parameter |
| **E3** | Change value |
| **K1 hold 2s** | Tuner on / off (from any view) |
| **K2** | Looper: record → play → dub → play (amp view only) |
| **K2 hold 2s** | Gain Pedals (Push / Distort) on / off (from any view) |
| **K3** | Looper: stop → clear (double press) / Bypass toggle (pedalboard) / Mute (tuner) |
| **K3 hold 2s** | Modulation Pedals (Warp / Repeat) on / off (from any view) |

When the pedalboard is open, **E1** selects between the two visible effects, **E2** selects a parameter, and **E3** changes its value. Looper transport (K2, K3) is disabled while the pedalboard or tuner is open; the loop continues to run in the background.

## Navigation

Any hold (2 s) navigates directly to the target view from wherever you are. Holding the key again while already in that view returns to the amp view.

| From | K1 hold | K2 hold | K3 hold |
|------|---------|---------|---------|
| Amp view | Tuner | Gain Pedals | Modulation Pedals |
| Tuner | Amp view | Gain Pedals | Modulation Pedals |
| Gain Pedals | Tuner | Amp view | Modulation Pedals |
| Modulation Pedals | Tuner | Gain Pedals | Amp view |

## Tuner

Hold K1 for 2 seconds to open the tuner. The note name and octave are shown at large size. An arrow indicates flat or sharp; a dot indicates in tune. Press K3 to mute the output while tuning — the looper keeps playing. Hold K1 again to return to the amp view, K2 to open Gain Pedals, or K3 to open Modulation Pedals.

Turn E2 while the tuner is open to adjust the reference pitch (420–460 Hz). The setting is saved with your PSET.

## Parameters

Parameters are listed in PARAMS menu order.

### Tuner

| Parameter | Default | Range |
|-----------|---------|-------|
| **Reference** | 440.0 Hz | 420–460 Hz |

Adjustable with E2 while the tuner is open. Saved with your PSET.

### Metro

| Parameter | Default | Range / Options |
|-----------|---------|-----------------|
| **Metro Enable** | Bypass | Bypass / Active |
| **BPM** | 120 | 20–300 |
| **Level** | 5.0 | 0–10 |
| **Pitch** | C3 | C0–B7 (chromatic) |

All four entries live in the PARAMS menu and are MIDI-mappable. Metro Enable and BPM are the most useful for footswitch / knob control. The click fires as a short sine-wave burst; pitch shifts relative to A4 (440 Hz) in semitones.

### Push

| Parameter | Default | Range / Options |
|-----------|---------|-----------------|
| **Push Enable** | Bypass | Bypass / Active |
| **Gain** | 5.0 | 0–10 |
| **Tone** | 5.0 | 0–10 |
| **Level** | 5.0 | 0–10 |
| **Mix** | 2.5 | 0–10 |

Overdrive with asymmetric diode clipping. Tone sweeps a high-pass filter from 100 Hz (warm, full) to 750 Hz (tight, cutting). Mix is a parallel wet/dry blend: at 0 the effect is 100% wet; at 10 the dry signal is mixed back in 50/50. Useful for retaining pick attack and low-end body while adding saturation on top.

### Distort

| Parameter | Default | Range / Options |
|-----------|---------|-----------------|
| **Distort Enable** | Bypass | Bypass / Active |
| **Gain** | 5.0 | 0–10 |
| **Tone** | 7.5 | 0–10 |
| **Level** | 5.0 | 0–10 |
| **Low Cut** | Off | Off / 100 Hz / 250 Hz |

Hard clipping distortion. Tone sweeps a low-pass filter from 300 Hz (muffled, murky) to 5000 Hz (open, cutting). Low Cut applies a post-drive high-pass filter to remove accumulated sub-bass.

### Warp

| Parameter | Default | Range / Options |
|-----------|---------|-----------------|
| **Warp Enable** | Bypass | Bypass / Active |
| **Rate** | 2.5 | 0–10 |
| **Depth** | 2.5 | 0–10 |
| **Rise/Fall** | 5.0 | 0–10 |
| **Mix** | 0.0 | 0–10 |

Pitch vibrato via modulated delay. At 0 Mix the effect is 100% wet; increasing Mix blends in the dry signal, moving from pure vibrato toward a chorus character. Rise/Fall controls the onset time when bypass is lifted and the fade time when bypass is engaged.

### Repeat

| Parameter | Default | Range / Options |
|-----------|---------|-----------------|
| **Repeat Enable** | Bypass | Bypass / Active |
| **Time** | 7.5 | 0–10 |
| **Feedback** | 5.0 | 0–10 |
| **Level** | 5.0 | 0–10 |
| **Character** | Bright | Bright / Dark |

BBD-style analog delay with jitter and saturation in the feedback path. Character switches between a brighter and a darker feedback tone.

### Amp

| Parameter | Default | Range / Options |
|-----------|---------|-----------------|
| **Amp Enable** | Active | Active / Bypass |
| **Volume** | 7.5 | 0–10 |
| **Bass** | 5.0 | 0–10 |
| **Treble** | 5.0 | 0–10 |
| **Master** | 5.0 | 0–10 |

A dedicated **Amp Enable** toggle is available in the PARAMS menu for MIDI mapping — same behaviour as Reverb and Tremolo bypass.

### Tremolo

| Parameter | Default | Range / Options |
|-----------|---------|-----------------|
| **Tremolo Enable** | Active | Active / Bypass |
| **Speed** | 0.0 | 0–10 |
| **Intensity** | 0.0 | 0–10 |

On the device, turn Intensity to 0 to silence the tremolo. A dedicated **Tremolo Enable** toggle is available in the PARAMS menu for MIDI mapping — same rationale as Reverb Enable.

### Looper

| Parameter | Default | Range / Options |
|-----------|---------|-----------------|
| **Topology** | Digital | BBD / Cassette / Digital / Tape |
| **Character** | 0.0 | 0–10 |
| **Direction** | Forward | Forward / Reverse |
| **Dub Style** | Regular | Regular / Overwrite |
| **Play from** | Start | Start / Cue |
| **Dub Level** | −2.5 dB | −40–0 dB |
| **Level** | −2.5 dB | −40–0 dB |
| **Speed** | 1x | 0.5x / 1x / 2x |

**Play from** controls what happens when playback resumes after a stop. **Start** always returns to the beginning of the loop. **Cue** resumes from the position where the loop was stopped.

Speed affects both record and replay. At half speed the loop plays an octave lower and twice as long. At double speed an octave higher, half as long.

**Topology** selects the degradation circuit applied to the loop buffer on every write pass. **Character** controls the intensity — at 0 all circuits pass through transparently. Degradation accumulates on each loop pass:

- **BBD** — LPF roll-off, tanh saturation, high-end noise (above Character 5).
- **Cassette** — LFO-modulated BPF centre with slow wow, fast wonk, and crinkle amplitude noise.
- **Digital** — quantisation steps with random sample dropouts.
- **Tape** — exponential LPF with wow/flutter and gentle saturation.

### Reverb

| Parameter | Default | Range / Options |
|-----------|---------|-----------------|
| **Reverb Enable** | Active | Active / Bypass |
| **Amount** | 2.5 | 0–10 |

On the device, turn Amount to 0 to silence the reverb. A dedicated **Reverb Enable** toggle is available in the PARAMS menu for MIDI mapping — useful when you want to kill the reverb instantly from a footswitch and restore it to the same Amount with a second press.

### Speaker & Mic

| Parameter | Default | Options |
|-----------|---------|---------|
| **Speaker Enable** | Active | Active / Bypass |
| **Position** | Middle | Center / Middle / Edge |

**Speaker Enable** bypasses the cabinet simulation while keeping the preamp and tone stack active — useful for a raw DI tone or when running into an external powered cab. The grill area goes blank on screen when bypassed. Center is brightest and most present. Middle is balanced. Edge is darker and rounder.

## Looper transport

```
idle ── K2 ──► rec ── K2 ──► play ── K2 ──► dub ── K2 ──► play …
                │
                └── K3 ──► idle (recording aborted, buffer cleared)

play / dub ── K3 ──► stop ── K3 ──► idle (buffer cleared)
stop ── K2 ──► play
```

The loop keeps running when you open the tuner or pedalboard. Transport keys (K2, K3) are inactive in those views — the loop is not affected.

Transport icons at the bottom of the left display (framed in brackets when a looper parameter is selected):

- **●** recording
- **●+** overdubbing
- **▶** playing
- **■** stopped

## MIDI

Every parameter, bypass toggle, and looper transport action is available in the PARAMS menu and can be mapped to any MIDI CC using Norns' built-in MIDI learn.

### How to map a control

1. Open the PARAMS menu (press K1 from the main screen, navigate to PARAMS)
2. Scroll to the parameter or action you want to map
3. Press K3 to enter MIDI learn mode — the entry flashes
4. Send a CC from your MIDI controller
5. Norns assigns that CC to the parameter — the mapping is saved with your PSET

### What can be mapped

**Pedals / Amp / Tremolo / Looper / Reverb / Speaker & Mic** — all continuous parameters respond to CC values scaled to their parameter range.

**Enable toggles** (Amp, Speaker, Reverb, Tremolo, Push, Distort, Warp, Repeat) — CC ≥ 64 enables (Active), CC < 64 bypasses.

**Looper transport** — each action is a trigger entry visible in both PARAMS and MAP:

| Entry | Action |
|---|---|
| Looper Rec/Play | Same as K2: idle → rec → play → dub → play … / stop → play |
| Looper Stop/Clear | Same as K3: play/dub → stop → idle (buffer cleared) |

### Notes

- MIDI mappings are stored per PSET — each preset can have its own mapping.
- Looper transport triggers respond on CC value ≥ 64 (send value 127 for reliable triggering).
- **Enable toggles** use CC ≥ 64 → Active, CC < 64 → Bypass. Your controller must send both values (latch / bi-directional CC) — a toggle that always sends CC 127 will always set the param to Active and never back to Bypass.
- **After upgrading** from a pre-release build (pre-0.3), delete `dust/data/princeton/princeton.pmap` and re-map your CCs. The param type change from `add_binary` to `add_option` breaks saved mappings silently.
- All MIDI input is on channel 1 by default. Change the channel in PARAMS > MIDI.

## User stories

**Pedalboard**

- I want four effects before the amp so that I can shape the tone before it hits the preamp stages.
- I want Push and Distort on one key pair and Warp and Repeat on another so that distortion and modulation are logically separated.
- I want each effect independently bypassable so that I can toggle individual colours without leaving the pedalboard view.
- I want the active effect label to appear at full brightness so that I can see at a glance what is engaged without reading carefully.
- I want click-free bypass switching so that engaging or disengaging an effect doesn't interrupt the signal.
- I want Push into Distort to stack so that I can drive the Distort input harder for a thicker sound.
- I want Warp before Repeat in the chain so that pitch-modulated signal feeds the delay, creating slowly shifting repeats.

**Amp**

- I want to plug my guitar directly into norns so that I don't need an external preamp or audio interface.
- I want the volume knob to behave like a real amp so that low settings are clean and high settings break up naturally.
- I want a fixed mid scoop in the tone stack so that I get the scooped, open Fender character without having to dial it in.
- I want stereo output so that the ping-pong of the tremolo and the spatial width of the spring reverb are preserved at the output.
- I want to bypass the amp so that I can pass the guitar signal through with zero colouration.

**Tremolo**

- I want tremolo that defaults to off so that I don't have to turn it down every time I load the script.
- I want Speed and Intensity as separate controls so that I can set a rate without any modulation and bring it in gradually with Intensity.
- I want the peaks to stay at full amplitude when tremolo is engaged so that the overall level doesn't drop.
- I want a MIDI-mappable tremolo bypass so that I can kill and restore the tremolo from a footswitch without losing my Speed and Intensity settings.

**Looper**

- I want the looper between tremolo and reverb so that the spring reverb washes over the loop and the live guitar together, making the loop sit in the same acoustic space.
- I want record → play → dub on a single button so that I can capture a loop and layer over it without menu diving.
- I want a separate stop button so that I can freeze the loop mid-performance and re-enter playback at will.
- I want to clear the buffer with a second press of the stop button so that the clear action is deliberate and can't happen accidentally while a loop is playing.
- I want the loop to keep running when I open the tuner or pedalboard so that I can tune or adjust effects without interrupting the loop.
- I want Regular and Overwrite dub styles so that I can choose between layering and replacing what's already in the buffer.
- I want half and double speed so that I can transpose the loop by an octave in either direction, or change loop length without re-recording.
- I want reverse playback so that I can play melodic or textural material backwards against the live signal.
- I want independent Level and Dub Level so that I can control how loud the loop sits in the mix and how hot overdubs land separately.

**Reverb**

- I want a MIDI-mappable reverb bypass so that I can kill and restore the spring reverb from a footswitch without losing the Amount setting.

**Speaker & Mic**

- I want three mic positions on the cabinet so that I can choose between a bright on-axis sound, a balanced middle position, and a darker off-axis tone.
- I want to bypass the cabinet simulation independently so that I can use the preamp tone into an external cab or IR loader without double-amping.

**Tuner**

- I want a chromatic tuner accessible from any view so that I can tune between songs without leaving the script.
- I want a mute option in the tuner so that I can tune silently without stopping the looper.
- I want to navigate directly from the tuner to the pedalboard so that I don't have to pass through the amp view.

**Metro**

- I want a built-in metronome so that I can play to a click without an external device.
- I want the metronome MIDI-mappable so that I can start and stop it from a footswitch and control BPM from a knob.
- I want BPM, Level, and Pitch in the PARAMS menu so that I can adjust them and save them with each preset.

**Navigation**

- I want to reach the tuner, gain pedals, and modulation pedals from any view with a single hold so that I never have to navigate back to the amp view first.
- I want holding the same key again to return me to the amp view so that I always have a consistent exit gesture.

**MIDI**

- I want every parameter available as a MIDI-mappable control so that I can operate the script from a hardware controller without touching norns.
- I want bypass toggles for every effect available as MIDI triggers so that I can mute and unmute any stage from a footswitch.
- I want looper transport (record, play, dub, stop, clear) available as MIDI triggers so that I can control the looper hands-free while playing.
- I want MIDI mappings saved with my presets so that each saved setup remembers which controller CC does what.

## Install

Via Maiden: open `http://norns.local/maiden` and run:

```
;install https://github.com/notrobintaylor/princeton
```

Or via SSH:

```bash
ssh we@norns.local
cd ~/dust/code
git clone https://github.com/notrobintaylor/princeton
```
