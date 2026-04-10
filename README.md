# princeton

### A guitar amp simulator, pedalboard and looper for Monome Norns

princeton models a small 1960s American combo amp. Plug your electric guitar directly into the left norns input. No preamp needed.

The gain range runs from clean to light overdrive. The spring reverb and bias tremolo are always available. There is a looper between tremolo and reverb: what you loop also gets washed in spring reverb. Four stompbox-style effects sit before the amp.

## What it does

**Amp.** Two preamp stages, passive tone stack with a fixed mid scoop, power amp compression that blooms under hard picking. Volume below 5 stays clean. Past 7 the preamp stages begin to saturate.

**Tone stack.** Position 5 on Bass and Treble gives a moderate boost to the low and high bands — the typical Fender voice with the amp open. Turn below 3 to cut; keep at 5–7 for warmth and sparkle. The mid scoop is fixed and permanent.

**Tremolo.** Bias-style amplitude modulation. Speed and Intensity both default to 0. Up to Intensity 1.5 the effect blends in while the dry signal fades; past 1.5 pure tremolo with increasing depth. Peaks always remain at full amplitude. Tremolo can be bypassed independently without losing the Speed and Intensity settings.

**Looper.** 40-second stereo buffer, post-tremolo, pre-reverb. The spring reverb washes over the loop and the live signal equally. Forward and reverse. Half, normal, and double speed. Regular overdub layers new material over existing. Overwrite replaces it. The looper continues to run in the background while any other view (tuner, pedalboard, metro) is open.

**Spring reverb.** Applied to the full mix: live signal and loop together. Amount controls both send level and decay time together. At low values the spring tank is barely audible with a short decay. Turning it up increases both how much signal enters the tank and how long it rings — from a subtle shimmer at 2–3 to a long, washy bloom at 8–10. Reverb can be bypassed independently without losing the Amount setting.

**Pedalboard.** Four effects run before the amp. Push and Distort are a distortion pair; Warp and Repeat are a modulation pair. Each effect is independently bypassable. The active effect's label appears at full brightness.

**Amp bypass.** An Amp Enable toggle is available in the PARAMS menu and can be mapped to a MIDI footswitch. When the amp is bypassed the preamp, tone stack, power amp, and cabinet are all removed from the signal path; tremolo, looper, and spring reverb remain active. The panel lamp dims to indicate bypass.

**Output.** Stereo. Warp produces a stereo chorus spread (L/R detuned independently). Tremolo alternates between L and R (classic bias-trem ping-pong). The spring reverb outputs a stereo pair via its allpass diffuser. Both norns sends carry full signal.

**Metronome.** A click track that runs independently of the main signal path. Tempo 20–300 BPM, adjustable level, and chromatic pitch. Controlled entirely from the PARAMS menu — BPM, Level, Pitch, and an Active/Bypass toggle (all MIDI-mappable).

## Signal flow

```
guitar → Push → Distort → Warp (→ stereo) → Repeat
       → preamp → tone stack → power amp
       → cabinet (10", 3 mic positions)
       → tremolo (stereo) → looper (stereo) → spring reverb (stereo) → master → out L/R
```

## Controls

| Control | Function |
|---------|----------|
| **E2** | Select parameter |
| **E3** | Change value |
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

### Amp

| Parameter | Default | Range |
|-----------|---------|-------|
| **Volume** | 7.5 | 0–10 |
| **Bass** | 5.0 | 0–10 |
| **Treble** | 5.0 | 0–10 |
| **Master** | 5.0 | 0–10 |
| **Amp Enable** | Active | Active / Bypass |

A dedicated **Amp Enable** toggle is available in the PARAMS menu for MIDI mapping — same behaviour as Reverb and Tremolo bypass.

### Reverb

| Parameter | Default | Range |
|-----------|---------|-------|
| **Amount** | 2.5 | 0–10 |

On the device, turn Amount to 0 to silence the reverb. A dedicated **Reverb Enable** toggle is available in the PARAMS menu for MIDI mapping — useful when you want to kill the reverb instantly from a footswitch and restore it to the same Amount with a second press.

### Tremolo

| Parameter | Default | Range |
|-----------|---------|-------|
| **Speed** | 0.0 | 0–10 |
| **Intensity** | 0.0 | 0–10 |

On the device, turn Intensity to 0 to silence the tremolo. A dedicated **Tremolo Enable** toggle is available in the PARAMS menu for MIDI mapping — same rationale as Reverb Enable.

### Mic & Speaker

| Parameter | Default | Options |
|-----------|---------|---------|
| **Mic Position** | Middle | Center / Middle / Edge |
| **Speaker Enable** | Active | Active / Bypass |

Center is brightest and most present. Middle is balanced. Edge is darker and rounder. **Speaker Enable** bypasses the cabinet simulation while keeping the preamp and tone stack active — useful for a raw DI tone or when running into an external cab. The grill area goes blank on screen when bypassed.

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

### Looper

| Parameter | Default | Range / Options |
|-----------|---------|-----------------|
| **Direction** | Forward | Forward / Reverse |
| **Dub Style** | Regular | Regular / Overwrite |
| **Dub Vol** | −2.5 dB | −40–0 dB |
| **Loop Vol** | −2.5 dB | −40–0 dB |
| **Speed** | 1x | 0.5x / 1x / 2x |

Speed affects playback only. At half speed the loop plays an octave lower and twice as long. At double speed an octave higher, half as long.

### Push

| Parameter | Default | Range |
|-----------|---------|-------|
| **Gain** | 5.0 | 0–10 |
| **Tone** | 5.0 | 0–10 |
| **Level** | 5.0 | 0–10 |
| **Mix** | 2.5 | 0–10 |

Overdrive with asymmetric diode clipping. Tone sweeps a high-pass filter from 100 Hz (warm, full) to 750 Hz (tight, cutting). Mix is a parallel wet/dry blend: at 0 the effect is 100% wet; at 10 the dry signal is mixed back in 50/50. Useful for retaining pick attack and low-end body while adding saturation on top.

### Distort

| Parameter | Default | Range / Options |
|-----------|---------|-----------------|
| **Gain** | 5.0 | 0–10 |
| **Tone** | 7.5 | 0–10 |
| **Level** | 5.0 | 0–10 |
| **Low Cut** | Off | Off / 100 Hz / 250 Hz |

Hard clipping distortion. Tone sweeps a low-pass filter from 300 Hz (muffled, murky) to 5000 Hz (open, cutting). Low Cut applies a post-drive high-pass filter to remove accumulated sub-bass.

### Warp

| Parameter | Default | Range |
|-----------|---------|-------|
| **Rate** | 2.5 | 0–10 |
| **Depth** | 2.5 | 0–10 |
| **Rise** | 5.0 | 0–10 |
| **Mix** | 0.0 | 0–10 |

Stereo pitch vibrato with independent L/R LFO detuning. At 0 Mix the effect is 100% wet pitch-shifted signal; increasing Mix blends in the dry mono signal, moving from pure vibrato toward a chorus/flange character. Rise controls how long the effect takes to reach full depth after bypass is lifted.

### Repeat

| Parameter | Default | Range / Options |
|-----------|---------|-----------------|
| **Time** | 5.0 | 0–10 |
| **Feedback** | 5.0 | 0–10 |
| **Level** | 5.0 | 0–10 |
| **Character** | Bright | Bright / Dark |

BBD-style analog delay with jitter and saturation in the feedback path. Character switches between a brighter and a darker feedback tone.

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

**Amp / Reverb / Tremolo / Looper / Pedals** — all continuous parameters respond to CC values scaled to their parameter range.

**Enable toggles** (Amp, Speaker, Reverb, Tremolo, Push, Distort, Warp, Repeat) — CC ≥ 64 enables (Active), CC < 64 bypasses.

**Looper transport** — each action is a separate trigger entry:

| PARAMS entry | Action |
|---|---|
| Loop Rec/Play | Same as K2: idle → rec → play → dub → play … / stop → play |
| Loop Stop/Clear | Same as K3: play/dub → stop → idle (buffer cleared) |

### Notes

- MIDI mappings are stored per PSET — each preset can have its own mapping.
- Looper transport triggers respond on CC value ≥ 64 (send value 127 for reliable triggering).
- **Enable toggles** use CC ≥ 64 → Active, CC < 64 → Bypass. Your controller must send both values (latch / bi-directional CC) — a toggle that always sends CC 127 will always set the param to Active and never back to Bypass.
- **After upgrading** from a version where enable params were binary (pre-1.2), delete `dust/data/princeton/princeton.pmap` and re-map your CCs. The param type change from `add_binary` to `add_option` breaks saved mappings silently.
- All MIDI input is on channel 1 by default. Change the channel in PARAMS > MIDI.

## User stories

**Amp**

- I want to plug my guitar directly into norns so that I don't need an external preamp or audio interface.
- I want the volume knob to behave like a real amp so that low settings are clean and high settings break up naturally.
- I want a fixed mid scoop in the tone stack so that I get the scooped, open Fender character without having to dial it in.
- I want three mic positions on the cabinet so that I can choose between a bright on-axis sound, a balanced middle position, and a darker off-axis tone.
- I want stereo output so that the stereo spread of Warp, the ping-pong of the tremolo, and the spatial width of the spring reverb are preserved at the output.
- I want to bypass the amp so that I can use the looper and reverb as a standalone effect chain without the amp colouration.
- I want to bypass the cabinet simulation independently so that I can use the preamp tone into an external cab or IR loader without double-amping.

**Tremolo**

- I want tremolo that defaults to off so that I don't have to turn it down every time I load the script.
- I want Speed and Intensity as separate controls so that I can set a rate without any modulation and bring it in gradually with Intensity.
- I want the peaks to stay at full amplitude when tremolo is engaged so that the overall level doesn't drop.
- I want a MIDI-mappable tremolo bypass so that I can kill and restore the tremolo from a footswitch without losing my Speed and Intensity settings.

**Reverb**

- I want a MIDI-mappable reverb bypass so that I can kill and restore the spring reverb from a footswitch without losing the Amount setting.

**Looper**

- I want the looper between tremolo and reverb so that the spring reverb washes over the loop and the live guitar together, making the loop sit in the same acoustic space.
- I want record → play → dub on a single button so that I can capture a loop and layer over it without menu diving.
- I want a separate stop button so that I can freeze the loop mid-performance and re-enter playback at will.
- I want to clear the buffer with a second press of the stop button so that the clear action is deliberate and can't happen accidentally while a loop is playing.
- I want the loop to keep running when I open the tuner or pedalboard so that I can tune or adjust effects without interrupting the loop.
- I want Regular and Overwrite dub styles so that I can choose between layering and replacing what's already in the buffer.
- I want half and double speed so that I can transpose the loop by an octave in either direction, or change loop length without re-recording.
- I want reverse playback so that I can play melodic or textural material backwards against the live signal.
- I want independent Loop Vol and Dub Vol so that I can control how loud the loop sits in the mix and how hot overdubs land separately.

**Pedalboard**

- I want four effects before the amp so that I can shape the tone before it hits the preamp stages.
- I want Push and Distort on one key pair and Warp and Repeat on another so that distortion and modulation are logically separated.
- I want each effect independently bypassable so that I can toggle individual colours without leaving the pedalboard view.
- I want the active effect label to appear at full brightness so that I can see at a glance what is engaged without reading carefully.
- I want click-free bypass switching so that engaging or disengaging an effect doesn't interrupt the signal.
- I want Push into Distort to stack so that I can drive the Distort input harder for a thicker sound.
- I want Warp before Repeat in the chain so that pitch-modulated signal feeds the delay, creating slowly shifting repeats.

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
- I want bypass toggles for reverb and tremolo available as MIDI triggers so that I can mute and unmute those effects from a footswitch.
- I want looper transport (record, play, dub, stop, clear) available as MIDI triggers so that I can control the looper hands-free while playing.
- I want view navigation available as MIDI triggers so that I can switch between tuner, amp, and pedalboard from my controller.
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

## Changelog

### 1.3

- **Push Mix.** Parallel wet/dry blend (0–10, default 2.5). At 0 the effect is 100% wet; increasing Mix blends in the unprocessed signal.
- **Warp Mix.** Same parallel blend for Warp (0–10, default 0). Moves from pure vibrato to chorus/flange character as the dry signal returns.
- **Distort Low Cut.** Post-drive high-pass filter option: Off / 100 Hz / 250 Hz. Removes accumulated sub-bass from high-gain settings.
- **Stereo output.** The output is now full stereo. Warp produces an independent L/R chorus spread; tremolo alternates L/R (bias-trem ping-pong); spring reverb outputs a stereo pair. The previous Dual-Mono / Stereo switch in PARAMS has been removed.
- **Looper stereo.** The 40-second loop buffer now captures and plays back the full stereo signal from the tremolo stage.
- **Metronome (PARAMS only).** BPM (20–300, integer), Level (0–10), Pitch (C0–B7 chromatic), and a Metro Enable toggle — all MIDI-mappable. The click is a short sine-wave burst; pitch is relative to A4. No dedicated on-device view — everything lives in the PARAMS menu.

### 1.2

- **Spring reverb redesigned.** New architecture with pre-delay (8 ms), three-channel AllpassL dispersion, BPF twang resonance, and two AllpassN diffusion stages for a truer spring character — chirp on transients, bloom on long decays. Decay range extended so the full 0–10 sweep is useful.
- **Noise floor lowered.** Input band-limiting (40 Hz–7.5 kHz) applied before all gain stages. Per-stage anti-aliasing filters added on Push and Distort. No noise gate required.
- **Push Tone reimplemented.** Tone now sweeps a high-pass filter from 100 Hz (warm, full) to 750 Hz (tight, cutting) — pre-drive, so it shapes the harmonic content before clipping.
- **Distort refined.** Tone sweep narrowed to 300–5000 Hz; gain range adjusted to 20–800. More musical response across the full sweep.
- **Cabinet tuned to Jensen C10R.** A bass resonance peak at 120 Hz (+3.5 dB) is now applied before the mic-position EQ in all three positions. Center-mic presence peak moved to 3200 Hz for more attack and definition.
- **PARAMS: text values.** Enable toggles show "Active" / "Bypass" instead of a checkbox. Mic Position, Loop Direction, Loop Speed, Loop Dub Style, and Repeat Character display their option names.
- **Defaults adjusted.** Volume 7.5 (was 5.0), Mic Position Middle (was Center), Distort Tone 7.5 (was 5.0), Distort Level 5.0 (was 2.5).

### 1.1

- **Looper persists across views.** The loop no longer stops when the tuner opens. The loop runs in the background while any view (tuner, pedalboard) is active; transport controls are simply inactive in those views.
- **Looper clear via double press.** K3 first press stops the loop; a second K3 press clears the buffer. The loop can no longer be cleared accidentally by a hold gesture while playing.
- **Global view navigation.** K1 / K2 / K3 held for 2 s navigates directly to the tuner / gain pedals / modulation pedals from any view. Holding the same key again returns to the amp view. No need to pass through the amp view when switching between tuner and pedalboard.
- **Amp Enable toggle.** The amp bypass is now a proper MIDI-mappable toggle in PARAMS, consistent with Reverb and Tremolo. Volume range is 0–10; the Volume-below-0 bypass trick from 1.0 is removed.
- **Speaker Enable toggle.** Bypasses the cabinet simulation while keeping the preamp and tone stack active. Useful for routing into an external cab or IR loader. The grill area goes blank on screen when bypassed.
- **Reverb bypass (MIDI).** A dedicated Reverb Enable toggle is available in PARAMS for MIDI mapping. Kills the reverb send instantly — the spring tail rings out naturally. Restores the stored Amount on a second press. On the device, turn Amount to 0 instead.
- **Tremolo bypass (MIDI).** Same for tremolo. Toggle via MIDI footswitch preserves Speed and Intensity. On the device, turn Intensity to 0 instead.
- **Pedal bypasses MIDI-mappable.** Push, Distort, Warp, and Repeat bypass toggles are now available in PARAMS and can be mapped to MIDI footswitches individually.
- **Full MIDI control.** All parameters, bypass toggles, looper transport actions, and view navigation triggers are available in the PARAMS menu and can be mapped to MIDI CC via Norns' built-in MIDI learn. Mappings are saved per PSET.

### 1.0

Initial release.

- Amp simulation based on a 1960s American combo with Jensen C10R cabinet
- Three cabinet mic positions: Center, Middle, Edge
- Passive tone stack with fixed mid scoop
- Bias-style tremolo: dry/wet blend up to Intensity 1.5, then depth increases; peaks always at full amplitude
- 60-second mono looper: record, overdub, stop, reverse, half and double speed
- Spring reverb applied post-looper to live signal and loop equally
- Chromatic tuner with mute and direct navigation to pedalboard views
- Pedalboard with four effects: Push (overdrive), Distort (hard clipping), Warp (pitch vibrato), Repeat (BBD delay)
- Click-free bypass switching via XFade on all four effects and amp
- Amp bypass via Volume below 0 (replaced by Amp Enable toggle in 1.1)
- Push / Distort on K2 hold; Warp / Repeat on K3 hold; navigate between all views without returning to amp
- Design matrix GUI: fixed pixel grid, snap alignment, icon-based pedal display
- Active pedal state indicated by label brightness
- Looper disabled while pedalboard is open
