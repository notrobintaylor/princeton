# princeton

### A guitar amp simulator, pedalboard and looper for Monome Norns

princeton models a small 1960s American combo amp. Plug your electric guitar directly into the left norns input. No preamp needed.

The gain range runs from clean to light overdrive. The spring reverb and bias tremolo are always available. There is a looper between tremolo and reverb: what you loop also gets washed in spring reverb. Four stompbox-style effects sit before the amp.

## What it does

**Amp.** Two preamp stages, passive tone stack with a fixed mid scoop, power amp compression that blooms under hard picking. Volume below 5 stays clean. Past 7 the preamp stages begin to saturate.

**Tone stack.** Bass and Treble are 0 dB at position 5. The mid scoop is fixed and permanent. This is the Fender voice.

**Tremolo.** Bias-style amplitude modulation. Speed and Intensity both default to 0. Up to Intensity 1.5 the effect blends in while the dry signal fades; past 1.5 pure tremolo with increasing depth. Peaks always remain at full amplitude.

**Looper.** 60-second mono buffer, post-tremolo, pre-reverb. The spring reverb washes over the loop and the live signal equally. Forward and reverse. Half, normal, and double speed. Regular overdub layers new material over existing. Overwrite replaces it.

**Spring reverb.** Applied to the full mix: live signal and loop together. Amount controls both send level and decay time together. At low values the spring tank is barely audible with a short decay. Turning it up increases both how much signal enters the tank and how long it rings — from a subtle shimmer at 2–3 to a long, washy bloom at 8–10.

**Pedalboard.** Four effects run before the amp. Push and Distort are a distortion pair; Warp and Repeat are a modulation pair. Each effect is independently bypassable. The active effect's label appears at full brightness.

**Amp bypass.** Turn Volume below 0 to bypass the preamp, tone stack, power amp, and cabinet. Tremolo, looper, and spring reverb remain active. The panel lamp dims to indicate bypass. The parameter display shows Bypass.

**Output.** Dual mono. Both outputs carry the same signal.

## Signal flow

```
guitar → Push → Distort → Warp → Repeat
       → preamp → tone stack → power amp
       → cabinet (10", 3 mic positions)
       → tremolo → looper → spring reverb → master → out (dual mono)
```

## Controls

| Control | Function |
|---------|----------|
| **E2** | Select parameter |
| **E3** | Change value |
| **K1 hold 2s** | Tuner on / off |
| **K2** | Looper: record → play → dub → play |
| **K2 hold 2s** | Gain Pedals (Push / Distort) on / off |
| **K3** | Looper: stop / Bypass toggle (when pedalboard open) |
| **K3 hold 2s** | Modulation Pedals (Warp / Repeat) on / off |

When the pedalboard is open, **E1** selects between the two visible effects, **E2** selects a parameter, and **E3** changes its value. The looper is not accessible while the pedalboard is open.

## Navigation

| From | K1 hold | K2 hold | K3 hold |
|------|---------|---------|---------|
| Amp view | Tuner | Gain Pedals | Modulation Pedals |
| Tuner | Amp view | Gain Pedals | Modulation Pedals |
| Gain Pedals | Tuner | Amp view | Modulation Pedals |
| Modulation Pedals | Tuner | Gain Pedals | Amp view |

## Tuner

Hold K1 for 2 seconds to open the tuner. The note name and octave are shown at large size. An arrow indicates flat or sharp; a dot indicates in tune. Press K3 to mute the output while tuning. Hold K1 again to return to the amp view, K2 to open the Verzerrer, or K3 to open the Modulationen.

## Parameters

### Amp

| Parameter | Default | Range |
|-----------|---------|-------|
| **Volume** | 5.0 | −0.1 (Bypass) – 10 |
| **Bass** | 5.0 | 0–10 |
| **Treble** | 5.0 | 0–10 |
| **Master** | 5.0 | 0–10 |

Turn Volume below 0 to engage amp bypass.

### Reverb

| Parameter | Default | Range |
|-----------|---------|-------|
| **Amount** | 2.5 | 0–10 |

### Tremolo

| Parameter | Default | Range |
|-----------|---------|-------|
| **Speed** | 0.0 | 0–10 |
| **Intensity** | 0.0 | 0–10 |

### Mic

| Parameter | Default | Options |
|-----------|---------|---------|
| **Axis** | Center | Center / Middle / Edge |

Center is brightest. Edge is darker and rounder.

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

Overdrive with a strong low-cut.

### Distort

| Parameter | Default | Range |
|-----------|---------|-------|
| **Gain** | 5.0 | 0–10 |
| **Tone** | 5.0 | 0–10 |
| **Level** | 2.5 | 0–10 |

Hard clipping distortion and a post-distortion LP filter.

### Warp

| Parameter | Default | Range |
|-----------|---------|-------|
| **Rate** | 3.0 | 0–10 |
| **Depth** | 5.0 | 0–10 |
| **Rise** | 3.0 | 0–10 |

BBD-style pitch vibrato, 100% wet. Rise controls how long the effect takes to reach full depth after bypass is lifted.

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

any state ── K3 ──► stop ── K2 ──► play
any state ── K3 hold 2s ──► idle (buffer cleared)
```

Transport icons at the bottom of the left display (framed in brackets when a looper parameter is selected):

- **●** recording
- **●+** overdubbing
- **▶** playing
- **■** stopped

## User stories

**Amp**

- I want to plug my guitar directly into norns so that I don't need an external preamp or audio interface.
- I want the volume knob to behave like a real amp so that low settings are clean and high settings break up naturally.
- I want a fixed mid scoop in the tone stack so that I get the scooped, open Fender character without having to dial it in.
- I want three mic positions on the cabinet so that I can choose between a bright on-axis sound, a balanced middle position, and a darker off-axis tone.
- I want dual mono output so that both norns sends carry signal and stereo effects downstream receive input on both channels.
- I want to bypass the amp so that I can use the looper and reverb as a standalone effect chain without the amp colouration.

**Tremolo**

- I want tremolo that defaults to off so that I don't have to turn it down every time I load the script.
- I want Speed and Intensity as separate controls so that I can set a rate without any modulation and bring it in gradually with Intensity.
- I want the peaks to stay at full amplitude when tremolo is engaged so that the overall level doesn't drop.

**Looper**

- I want the looper between tremolo and reverb so that the spring reverb washes over the loop and the live guitar together, making the loop sit in the same acoustic space.
- I want record → play → dub on a single button so that I can capture a loop and layer over it without menu diving.
- I want a separate stop button so that I can freeze the loop mid-performance and re-enter playback at will.
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
- I want a mute option in the tuner so that I can tune silently without cutting the looper.
- I want to navigate directly from the tuner to the pedalboard so that I don't have to pass through the amp view.

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
- Amp bypass via Volume below 0: bypasses preamp, tone stack, power amp, and cabinet
- Push / Distort on K2 hold; Warp / Repeat on K3 hold; navigate between all views without returning to amp
- Design matrix GUI: fixed pixel grid, snap alignment, icon-based pedal display
- Active pedal state indicated by label brightness
- Looper disabled while pedalboard is open
