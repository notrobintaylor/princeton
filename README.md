# princeton

### A guitar amp simulator, pedalboard and looper for Monome Norns

[![princeton – Norns Script Demo](https://img.youtube.com/vi/VqkFejb8owY/maxresdefault.jpg)](https://www.youtube.com/watch?v=VqkFejb8owY)

princeton is a guitar amp, pedalboard, and looper for Monome Norns. The amp sits in the middle: a small American combo from the early 1960s, recreated in code. Around it, four pedals before the input, bias tremolo and spring reverb after, and a 40-second stereo looper riding between them. What you loop washes through the same reverb as the live signal.

Plug a guitar into the left input. No preamp or interface required.

The looper carries the script. Four storage media (BBD, Cassette, Digital, Tape) colour the loop. Imprint sets how much of that colour gets baked in the moment you record; Wear sets how much further the loop erodes on every pass. Four playback modes (Overdub, Overwrite, Sample, Resample) and four direction modes (Forward, Reverse, Pendulum, Random) sit underneath. Tremolo and reverb stay on. The amp stays clean unless you push it past Volume 7. For harder distortion, reach for Push or Distort up the chain.

## What it does

**Looper.** A 40-second stereo buffer between tremolo and reverb, so anything you record sits in the same spring tank as the live string. Medium picks the storage type the loop pretends to be: BBD darkens and saturates, Cassette wobbles and crinkles, Digital quantises and drops samples, Tape softens and drifts. Imprint controls how strongly the medium colours the signal as it lands in the buffer (the first repeat already sounds like the medium). Wear controls how much further the medium erodes the loop on every subsequent pass; at 0 the loop is stable, at higher values it ages over time. Direction can run forward, reverse, pendulum, or random. Mode covers Overdub (layer), Overwrite (replace), Sample (one-shot, K2 retriggers), and Resample (record the loop output back into the buffer, including its own ageing). Speed transposes by an octave in either direction in Steps mode, or sweeps continuously in Smooth mode. The looper keeps running while you open the tuner or pedalboard.

**Pedalboard.** Four effects sit between the input and the amp, paired by character: Push and Distort handle gain, Warp and Repeat handle modulation. Each is independently bypassable. Open the pedalboard view from any other view with K2 (gain pair) or K3 (modulation pair) held; the active pair's label brightens.

**Amp.** A small American combo from the early 1960s. Volume below 5 stays clean; past 7 it begins to break up. Bass and Treble at 5 give the open Fender voice; below 3 they cut. The mid-scoop in the tone stack is fixed.

**Tremolo.** Bias-style amplitude modulation, always available at the output of the amp. Intensity defaults to 0, so nothing is happening until you turn it up. Up to 15 % the dry signal fades while the tremolo blends in; past 15 % it's pure tremolo with rising depth. Peaks stay at full amplitude. Speed defaults to 2.5 Hz and can sync to the Norns clock.

**Spring reverb.** Applied to the full stereo mix, live signal and loop together. Amount sets both send level and decay; Length adjusts decay independently if you want longer wash without more signal in the tank. Low Shelf and High Shelf colour the wet path. At 25 % Amount the spring tank sits behind the signal; turn it up for the long shimmer.

**Cab & Mic.** A 10" Jensen-style cabinet model with three mic positions (Center, Middle, Edge). Or, if you'd rather, load your own impulse responses (one per channel) and run those instead. Or bypass cabinet processing entirely for a raw DI tone or to feed an external cab.

**Limit.** An optional output compander after the cabinet, bypassed by default. Useful when sending princeton into another script's input or when the looper output needs a ceiling.

**Output.** Stereo throughout the post-amp section. Tremolo alternates between L and R (the classic bias-trem ping-pong). The spring reverb outputs a stereo pair via its allpass diffuser. Both Norns sends carry the full stereo signal, so princeton works as a stereo source in any fx_mod slot.

**Bypass.** Every stage can be bypassed independently: pedals, amp, tremolo, looper, reverb, cabinet, limit. The amp bypass also dims the panel lamp on screen; the others are toggled from PARAMS or via MIDI.

**Metronome.** A click track running independently of the signal path. Tempo, level, and chromatic pitch are set from PARAMS; Division locks the click to the Norns clock when one is running, or free-runs at the BPM field when the clock is stopped.

## Signal flow

```
                                    mono through pedals and amp
                                    ───────────────────────────

  guitar IN L ──► Push ──► Distort ──► Warp ──► Repeat
                                                  │
                                                  ▼
                                                 Amp
                                                  │
                             ───────────── stereo from here ─────────────
                                                  │
                                                  ▼
                                               Tremolo
                                                  │
                                                  ▼
                                                Looper
                                                  │
                                                  ▼
                                            Spring reverb
                                                  │
                                                  ▼
                                              Cab & Mic
                                                  │
                                                  ▼
                                             Master gain
                                                  │
                                                  ▼
                                                Limit
                                                  │
                                   ┌──────────────┼──────────────┐
                                   ▼              ▼              ▼
                                OUT L/R        SEND A         SEND B
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

When the pedalboard is open, **E1** selects between the two visible effects, **E2** selects a parameter, and **E3** changes its value. Looper transport (K2, K3) is disabled while the pedalboard or tuner is open. The loop keeps running in the background.

## Navigation

Any hold (2 s) navigates directly to the target view from wherever you are. Holding the key again while already in that view returns to the amp view.

| From | K1 hold | K2 hold | K3 hold |
|------|---------|---------|---------|
| Amp view | Tuner | Gain Pedals | Modulation Pedals |
| Tuner | Amp view | Gain Pedals | Modulation Pedals |
| Gain Pedals | Tuner | Amp view | Modulation Pedals |
| Modulation Pedals | Tuner | Gain Pedals | Amp view |

## Tuner

Hold K1 for 2 seconds from any view to open the tuner. The note name and octave appear at large size. An arrow points flat or sharp; a dot means in tune. Press K3 to mute the output while tuning. The looper keeps playing under the mute, so a tuning pause doesn't break the loop. Hold K1 again for the amp view, K2 for Gain Pedals, or K3 for Modulation Pedals.

Turn E3 while the tuner is open to adjust the reference pitch (420 to 460 Hz). The setting is saved with your PSET.

princeton's tuner runs its own pitch detector inside the engine on a boosted, band-limited copy of the input. Passive electric guitars sit too low for the Norns built-in pitch poll to track reliably; the in-engine version stays locked through string decay.

## Parameters

Parameters are listed in PARAMS menu order.

### Tuner

| Parameter | Default | Range |
|-----------|---------|-------|
| **Reference** | 440.0 Hz | 420–460 Hz |

Adjustable with E3 while the tuner is open. Saved with your PSET.

### Metro

| Parameter | Default | Range / Options |
|-----------|---------|-----------------|
| **Metro Enable** | Off | Off / On |
| **BPM** | 120 | 20–300 |
| **Division** | 1/4 | 1/1 / 1/2 / 1/4 / 1/8 / 1/16 |
| **Level** | 5.0 | 0–10 |
| **Pitch** | C3 | C0–B7 (chromatic) |

All five entries live in the PARAMS menu and are MIDI-mappable. Metro Enable and BPM are the most useful for footswitch / knob control. The click fires as a short sine-wave burst; pitch shifts relative to A4 (440 Hz) in semitones.

When the Norns clock is running, **Division** sets the click subdivision relative to the clock; the metro stays in lockstep with any synced effect. With the clock stopped the metro free-runs at the BPM field.

### Push

| Parameter | Default | Range / Options |
|-----------|---------|-----------------|
| **Push Enable** | Bypass | Bypass / Active |
| **Gain** | 5.0 | 0–10 |
| **Tone** | 5.0 | 0–10 |
| **Level** | 5.0 | 0–10 |
| **Mix** | 25 % | 0–100 % |

Overdrive with asymmetric diode clipping. Tone sweeps a high-pass filter from 100 Hz (warm, full) to 750 Hz (tight, cutting). Mix is a parallel wet/dry blend: at 0 % the effect is 100 % wet; at 100 % the dry signal is mixed back in 50/50. Useful for retaining pick attack and low-end body while adding saturation on top.

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
| **Rate** | 2.5 Hz | 0.1–25 Hz (exp) |
| **Depth** | 5 % | 0–100 % |
| **Rise/Fall** | 2.5 s | 0.01–5.0 s (exp) |
| **Mix** | 0 % | 0–100 % |
| **Synchronization** | Off | Off / 1/1 / 1/2 / 1/4 / 1/8 / 1/16 / 1/32 / 1/64 |
| **Synchronization Feel** | Note | Note / Dotted / Triplet |

Pitch vibrato via modulated delay. At 0 % Mix the effect is 100 % wet; increasing Mix blends in the dry signal, moving from pure vibrato toward a chorus character. Rise/Fall controls the onset time when bypass is lifted and the fade time when bypass is engaged.

Set **Synchronization** to a division to lock Rate to the Norns clock. See [Synchronization](#synchronization) for the full model.

### Repeat

| Parameter | Default | Range / Options |
|-----------|---------|-----------------|
| **Repeat Enable** | Bypass | Bypass / Active |
| **Time** | 250 ms | 1–1000 ms |
| **Feedback** | 50 % | 0–100 % |
| **Level** | 50 % | 0–100 % |
| **Color** | Bright | Bright / Dark |
| **Synchronization** | Off | Off / 1/1 / 1/2 / 1/4 / 1/8 / 1/16 / 1/32 / 1/64 |
| **Synchronization Feel** | Note | Note / Dotted / Triplet |

BBD-style analog delay with jitter and saturation in the feedback path. Color switches between a brighter and a darker feedback tone.

Set **Synchronization** to a division to lock Time to the Norns clock. See [Synchronization](#synchronization) for the full model.

### Amp

| Parameter | Default | Range / Options |
|-----------|---------|-----------------|
| **Amp Enable** | Active | Active / Bypass |
| **Volume** | 5.0 | 0–10 |
| **Bass** | 5.0 | 0–10 |
| **Treble** | 5.0 | 0–10 |
| **Master** | 7.5 | 0–10 |

A dedicated **Amp Enable** toggle lives in the PARAMS menu for MIDI mapping. Same behaviour as Reverb and Tremolo bypass.

### Tremolo

| Parameter | Default | Range / Options |
|-----------|---------|-----------------|
| **Tremolo Enable** | Active | Active / Bypass |
| **Speed** | 2.5 Hz | 0.1–25 Hz (exp) |
| **Intensity** | 0 % | 0–100 % |
| **Synchronization** | Off | Off / 1/1 / 1/2 / 1/4 / 1/8 / 1/16 / 1/32 / 1/64 |
| **Synchronization Feel** | Note | Note / Dotted / Triplet |

On the device, turn Intensity to 0 to silence the tremolo. A dedicated **Tremolo Enable** toggle lives in the PARAMS menu for MIDI mapping, same rationale as Reverb Enable.

Set **Synchronization** to a division to lock Speed to the Norns clock. The encoder strip then displays the division name (e.g. `1/8`, `1/4.`) instead of Hz. See [Synchronization](#synchronization) for the full model.

### Looper

| Parameter | Default | Range / Options |
|-----------|---------|-----------------|
| **Step Order** | Rec·Play·Dub | Rec·Play·Dub / Rec·Dub·Play |
| **Play From** | Start | Start / Cue |
| **Mode** | Overdub | Overdub / Overwrite / Sample / Resample |
| **Direction** | Forward | Forward / Reverse / Pendulum / Random |
| **Rec Level** | −2.5 dB | −40–0 dB |
| **Play Level** | −2.5 dB | −40–0 dB |
| **Fade Level** | −2.5 dB | −40–0 dB |
| **Speed** | 0 % | −100–+100 % |
| **Speed Control** | Steps | Steps / Smooth |

**Step Order** picks which K2 sequence the looper follows: `Rec → Play → Dub → Play …` (default) or `Rec → Dub → Play …`. K3 is unaffected.

**Play From** controls what happens when playback resumes after a stop. **Start** always returns to the beginning of the loop. **Cue** resumes from the position where the loop was stopped.

**Mode** selects how dub passes interact with the buffer. **Overdub** layers new material over existing. **Overwrite** replaces it. **Sample** stops after one playback pass; K2 retriggers from the **Play From** position. **Resample** records the loop output back into the buffer including the medium's degradation chain.

**Direction** sets the loop playback direction. **Forward** is conventional. **Reverse** plays the buffer backwards. **Pendulum** alternates forward and reverse at each loop boundary. **Random** flips direction unpredictably at each boundary for generative texture.

**Rec Level** and **Play Level** control recording gain (initial pass and overdub) and playback gain independently. **Fade Level** sets the gain curve at the loop boundary fade.

**Speed** is bipolar. In **Steps** mode it snaps to −100 % (half speed, octave down), 0 % (normal), or +100 % (double speed, octave up). In **Smooth** mode it moves continuously across the full range, exponentially mapped (`2 ^ (Speed/100)`). Speed affects both record and replay.

#### Medium

| Parameter | Default | Range / Options |
|-----------|---------|-----------------|
| **Medium** | Digital | BBD / Cassette / Digital / Tape |
| **Imprint** | 50 % | 0–100 % |
| **Wear** | 5 % | 0–100 % |
| **M: BBD Tone** | Bright | Bright / Dark |
| **M: Cassette Wow** | 5 % | 0–100 % |
| **M: Digital Glitch** | 0 % | 0–100 % |
| **M: Tape Wow** | 5 % | 0–100 % |

**Medium** picks the storage type the loop pretends to be. **Imprint** controls how strongly the medium colours the signal at the moment of recording: at 0 % the buffer captures your input clean, at 100 % the first repeat already has the mediums full character. **Wear** controls how much the medium degrades the loop on each subsequent pass: at 0 % the loop holds its captured state indefinitely, at higher values it erodes a little more every cycle. The two combine: a small Wear over a meaningful Imprint gives you a recording that lands aged and continues to age slowly. The four media, with their characteristic flavour:

- **BBD.** Bandwidth-limited LPF, op-amp bias, tanh saturation. Compander noise creeps in above 30 %. **M: BBD Tone** picks between two LPF curves (Bright or Dark).
- **Cassette.** LFO-modulated bandpass with slow wow and fast wonk, amplitude crinkle, a subtle FM artefact. **M: Cassette Wow** controls wow depth independently of Imprint and Wear.
- **Digital.** Quantisation steps and timing jitter. Random dropouts and skip-reads enter above 67 %. **M: Digital Glitch** scales dropout and skip rates independently of Imprint and Wear.
- **Tape.** Wide LPF with wow and flutter, misbias saturation, compander LPF, short print-through. **M: Tape Wow** controls wow depth.

Imprint and Wear apply on the destructive write side, but at different stages. Imprint colours the input as it enters the buffer (a one-shot effect at record time, scaled by the Imprint amount). Wear processes the buffer's existing content on every loop pass and folds the result back in (an accumulating effect over time, scaled by the Wear amount). Tape and Cassette also apply a small amount of wow on the read side, which is non-destructive (it modulates playback only and never writes back). With Imprint at 0 and Wear at 0, the buffer captures your input clean and holds it indefinitely.

```
Destructive write paths

  input  ──► Medium (scaled by Imprint) ──► BufWr ──► buffer        (one-shot at record)
  buffer ──BufRd──► Medium (scaled by Wear) ──► BufWr ──► buffer    (accumulates per pass)
                                                              ↺

Non-destructive read path (modulates playback only, never writes back)

  buffer ──BufRd──► Tape/Cas read-path wow ──► output → Spring reverb → ...
```

#### Quantization

| Parameter | Default | Range / Options |
|-----------|---------|-----------------|
| **Quantization** | Off | Off / 1/1 / 1/2 / 1/4 / 1/8 / 1/16 / 1/32 / 1/64 |
| **Quantization Feel** | Note | Note / Dotted / Triplet |

When the Norns clock is running and **Quantization** is set to a division, every K2 transition (record start, record end, play→dub, dub→play, stop) waits for the next beat boundary. **Off** is free-running. See [Synchronization](#synchronization) for how the division and feel combine.

### Reverb

| Parameter | Default | Range / Options |
|-----------|---------|-----------------|
| **Reverb Enable** | Active | Active / Bypass |
| **Amount** | 25 % | 0–100 % |
| **Length** | 2.5 s | 0.5–5.0 s |
| **Low Shelf** | 0 dB | −5–+5 dB |
| **High Shelf** | 0 dB | −5–+5 dB |

On the device, turn Amount to 0 to silence the reverb. A dedicated **Reverb Enable** toggle lives in the PARAMS menu for MIDI mapping. Useful when you want to kill the reverb instantly from a footswitch and restore it to the same Amount with a second press.

**Length** sets the spring tank decay independently of Amount, so you can keep the send level low and still get a long ring. **Low Shelf** at 250 Hz and **High Shelf** at 3500 Hz colour the wet path. Pull the high shelf down for a darker bloom; lift it for a brighter shimmer.

### Cab & Mic Simulation, IRs

| Parameter | Default | Options |
|-----------|---------|---------|
| **Cab Mode** | Cab & Mic Sim | Bypass / Cab & Mic Sim / IR |
| **Mic Position** | Middle | Center / Middle / Edge |
| **IR Left** | (none) | file path (.wav, 48 kHz) |
| **IR Right** | (none) | file path (.wav, 48 kHz) |

**Cab Mode** picks the cabinet processing path. **Bypass** removes all cabinet colour, useful for a raw DI tone or for feeding an external powered cab. **Cab & Mic Sim** runs the built-in Jensen 10" model at the **Mic Position** you set: Center is brightest and most present, Middle is balanced, Edge is darker and rounder. **IR** convolves the signal with impulse responses loaded via **IR Left** and **IR Right**.

In IR mode the left strip shows the loaded IR file names while the Mic Position parameter is selected. Mic Position is hidden from the PARAMS menu in IR mode; IR Left and IR Right are hidden in Cab & Mic Sim and Bypass modes.

**IR file requirements.** 48 kHz mono or stereo WAV (left channel is used). Only the first 2048 samples (≈ 42 ms) are convolved; longer tails are silently discarded. Convert with `ffmpeg -ar 48000 input.wav output.wav` or Audacity. A 44.1 kHz file will play back about 5 % fast and sharp, without an error message.

### Limit

| Parameter | Default | Range / Options |
|-----------|---------|-----------------|
| **Limit Enable** | Bypass | Bypass / Active |
| **Threshold** | −10 dB | −40–0 dB |
| **Ratio** | 4.0 :1 | 2.0–20.0 :1 |
| **Gain** | 0 dB | −20–+20 dB |
| **Attack** | 10 ms | 1–100 ms |
| **Decay** | 50 ms | 50–2000 ms |

Output compander after the cabinet. Bypassed by default. Engage it when sending into another script's input, or when looper peaks need a ceiling. Threshold sets the knee; signal above it is compressed at the chosen Ratio. Gain compensates for the level reduction. Attack and Decay shape the envelope follower.

## Synchronization

When the Norns clock is running and a stage's **Synchronization** parameter is set to a division (anything except **Off**), the stage's rate parameter is derived from the BPM instead of its standalone value:

- Tremolo Speed → derived from BPM
- Warp Rate → derived from BPM
- Repeat Time → derived from BPM (`1000 / Hz` ms)
- Looper Quantization → snaps K2 transitions to the next beat boundary

The conversion is `beats = base_beats × feel_multiplier`, where:

| Division | base_beats |
|---|---|
| `1/1` | 4 |
| `1/2` | 2 |
| `1/4` | 1 |
| `1/8` | 0.5 |
| `1/16` | 0.25 |
| `1/32` | 0.125 |
| `1/64` | 0.0625 |

| Feel | feel_multiplier |
|---|---|
| Note | × 1.0 |
| Dotted | × 1.5 |
| Triplet | × 2/3 |

Resulting `Hz = BPM / (beats × 60)`. At 120 BPM: `1/4 Note` = 2 Hz, `1/4 Dotted` = 1.33 Hz, `1/4 Triplet` = 3 Hz.

Each effect's range still applies (Tremolo 0.1–25 Hz, Warp 0.1–25 Hz, Repeat 1–1000 ms). When a synced division falls outside the effect's range, the encoder strip dims the value to indicate the clamp.

When the Norns clock source switches to **MIDI** (PARAMS > CLOCK > SOURCE), all four sync defaults activate automatically (`1/4` for Tremolo, Warp, Repeat, and Looper Quantization). Switching back to internal clock deactivates them. Stopping the clock holds the last derived values.

## Looper transport

```
idle ── K2 ──► rec ── K2 ──► play ── K2 ──► dub ── K2 ──► play …
                │
                └── K3 ──► idle (recording aborted, buffer cleared)

play / dub ── K3 ──► stop ── K3 ──► idle (buffer cleared)
stop ── K2 ──► play
```

The loop keeps running when you open the tuner or pedalboard. Transport keys (K2, K3) are inactive in those views; the loop is not affected.

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
3. Press K3 to enter MIDI learn mode (the entry flashes)
4. Send a CC from your MIDI controller
5. Norns assigns that CC to the parameter; the mapping is saved with your PSET

### What can be mapped

**Pedals, Amp, Tremolo, Looper, Reverb, Cab & Mic, Limit, Metro.** All continuous parameters respond to CC values scaled to their parameter range.

**Enable toggles** (Amp, Reverb, Tremolo, Limit, Push, Distort, Warp, Repeat). CC ≥ 64 enables (Active), CC < 64 bypasses. **Cab Mode** is a 3-way option (Bypass / Cab & Mic Sim / IR); the CC value is scaled to the option range.

**Synchronization.** Each stage's `Synchronization` (Tremolo / Warp / Repeat) and `Quantization` (Looper) is an option-type param mappable to a CC. Useful for tap-style division switching from a controller knob.

**Looper transport.** Each action is a trigger entry visible in both PARAMS and MAP:

| Entry | Action |
|---|---|
| Looper Rec/Play | Same as K2: idle → rec → play → dub → play … / stop → play |
| Looper Stop/Clear | Same as K3: play/dub → stop → idle (buffer cleared) |

### Notes

- MIDI mappings are stored per PSET; each preset can have its own mapping.
- Looper transport triggers respond on CC value ≥ 64. Send value 127 for reliable triggering.
- **Enable toggles** use CC ≥ 64 for Active and CC < 64 for Bypass. Your controller must send both values (latch or bi-directional CC). A toggle that always sends CC 127 will set the param to Active forever.
- **After upgrading** from a pre-release build (pre-0.3), delete `dust/data/princeton/princeton.pmap` and re-map your CCs. The param type change from `add_binary` to `add_option` breaks saved mappings silently.
- All MIDI input is on channel 1 by default. Change the channel in PARAMS > MIDI.

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
