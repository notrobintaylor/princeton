-- synth: Keys, the hands in front of the voice a voice mod (such as form) brings; it sits between
-- MIDI (port, channel, lpx CCs) and the voice, adding Hold, Retrig and Octaves.
-- What sounds and how notes are allocated is up to the voice itself (synth.voice).
local synth = {
  port    = 1,
  channel = 1,
  active  = function() return true end,
  voice   = nil, -- selected voice from package.loaded.voices
  hold    = false,
  retrig       = false,
  retrig_div   = 3,
  retrig_feel  = 1,
  retrig_gate  = 0.5,
  retrig_swing = 0,
  oct     = 1,
  reset   = 0,
}

synth.RETRIG_DIVS = { "1/4", "1/8", "1/16", "1/32" }
local RETRIG_BEATS = { 1, 0.5, 0.25, 0.125 }
local FEEL_MULT = { 1.0, 1.5, 2 / 3 }
-- A key arriving within this window of the last one still joins the held chord, even if all keys were up.
-- A later key while none are down starts a new chord.
local HOLD_WINDOW = 0.1
synth.CHANNELS = { "Omni" }
for ch = 1, 16 do synth.CHANNELS[ch + 1] = tostring(ch) end

local BEND_RANGE = 2
-- CCs from the lpx Launchpad mod: 69 Hold, 70 Retrig (>= 64 on), 71 Retrig Division, 72 Octaves,
-- 73 Octave Reset (Division and Octaves: value / 32 + 1 = choice 1..4; Reset: value = strikes).
local HOLD_CC, RETRIG_CC, DIV_CC, OCT_CC, RESET_CC = 69, 70, 71, 72, 73

local devs = {}

-- pass through to the selected voice (no voice: silence)
local function voice() return synth.voice end
function synth.note_on(note, vel) if voice() then voice().note_on(note, vel) end end
function synth.note_off(note, force) if voice() then voice().note_off(note, force) end end
function synth.sustain(down) if voice() then voice().sustain(down) end end
function synth.pressure(note, val) if voice() then voice().pressure(note, val) end end
local function bend(ratio) if voice() then voice().bend(ratio) end end

-- switch voice: the old one falls silent, the new one starts
function synth.set_voice(new)
  if synth.voice == new then return end
  synth.all_off()
  if synth.voice then synth.voice.stop() end
  synth.voice = new
  if new then new.start() end
end

local keys, latch, played = {}, {}, {}
local last_key = -1e9
local rt_gen, rt_live, rt_notes = 0, false, {}
-- Octaves: each new strike (or Retrig hit) climbs an octave and wraps after `oct` octaves.
-- Reset returns it to the starting octave after that many strikes.
local oct_step, strikes, cur_oct = 0, 0, 0

local function rt_off()
  for _, n in ipairs(rt_notes) do synth.note_off(n, true) end
  rt_notes = {}
end

local function rt_stop()
  rt_gen, rt_live = rt_gen + 1, false
  rt_off()
end

local function next_octave()
  local o = synth.oct > 1 and oct_step % synth.oct or 0
  strikes = strikes + 1
  if synth.reset > 0 and strikes >= synth.reset then
    oct_step, strikes = 0, 0
  else
    oct_step = oct_step + 1
  end
  return o
end

function synth.all_off()
  keys, latch, played, last_key = {}, {}, {}, -1e9
  oct_step, strikes, cur_oct = 0, 0, 0
  rt_stop()
  if voice() then voice().all_off() end
end

-- ── Keys: Hold, Retrig and Octaves between keyboard and voice ────────────────
-- `keys` are the keys really down and `latch` the chord Hold keeps, both mapping note -> velocity.
-- `played` records which note each key sounds (the key shifted by its octave).
local function pool()
  return synth.hold and latch or keys
end

-- Retrig: the held keys (or the Hold chord) restrike together on every step of the grid.
-- Swing: every second step arrives later by this fraction of a step.
local function rt_run()
  rt_gen, rt_live = rt_gen + 1, true
  local my = rt_gen
  clock.run(function()
    while true do
      local beats = RETRIG_BEATS[synth.retrig_div] * FEEL_MULT[synth.retrig_feel]
      clock.sync(beats)
      if rt_gen ~= my then return end
      local late = 0
      if synth.retrig_swing > 0 and math.floor(clock.get_beats() / beats + 0.5) % 2 == 1 then
        late = synth.retrig_swing * beats
        clock.sleep(late * clock.get_beat_sec())
        if rt_gen ~= my then return end
      end
      rt_off()
      if next(pool()) == nil then rt_live = false; return end
      local o = next_octave()
      for n, v in pairs(pool()) do
        local m = n + 12 * o
        if m <= 127 then
          synth.note_on(m, v)
          rt_notes[#rt_notes + 1] = m
        end
      end
      if synth.retrig_gate < 0.99 then
        -- a late step has less room before the next one
        clock.sleep(math.min(beats * synth.retrig_gate, (beats - late) * 0.95) * clock.get_beat_sec())
        if rt_gen ~= my then return end
        rt_off()
      end
    end
  end)
end

local function rt_kick()
  if synth.retrig and not rt_live and next(pool()) then rt_run() end
end

local function play(note, vel)
  local m = note + 12 * cur_oct
  if m > 127 then m = note end
  played[note] = m
  synth.note_on(m, vel)
end

local function stop(note, force)
  local m = played[note]
  if m == nil then return end
  played[note] = nil
  synth.note_off(m, force)
end

function synth.key_on(note, vel)
  local now = util.time()
  local new_strike = now - last_key > HOLD_WINDOW
  if synth.hold and next(keys) == nil and new_strike then
    if not synth.retrig then
      for n in pairs(latch) do stop(n, true) end
    end
    latch = {}
  end
  last_key = now
  keys[note] = vel
  if synth.hold then latch[note] = vel end
  if synth.retrig then
    rt_kick()
  else
    -- keys struck together share one octave
    if new_strike then cur_oct = next_octave() end
    stop(note, true)
    play(note, vel)
  end
end

function synth.key_off(note)
  keys[note] = nil
  if not synth.retrig and not (synth.hold and latch[note]) then stop(note) end
end

-- silence the voice and restart from whatever the keys and held chord say now
local function restart()
  rt_stop()
  played = {}
  if voice() then voice().release_held() end
  if synth.retrig then
    rt_kick()
  else
    for n, v in pairs(pool()) do play(n, v) end
  end
end

function synth.set_hold(on)
  synth.hold = on
  latch = {}
  if on then for n, v in pairs(keys) do latch[n] = v end end
  restart()
end

function synth.set_retrig(on)
  synth.retrig = on
  restart()
end

function synth.set_octaves(n)
  synth.oct = n
  oct_step, strikes = 0, 0
end

-- ── MIDI ─────────────────────────────────────────────────────────
function synth.midi_event(data)
  local msg = midi.to_msg(data)
  if synth.channel > 1 and msg.ch ~= synth.channel - 1 then return end
  if msg.type == "note_on" and msg.vel > 0 then
    if synth.active() then synth.key_on(msg.note, msg.vel / 127) end
  elseif msg.type == "note_off" or msg.type == "note_on" then
    synth.key_off(msg.note)
  elseif msg.type == "cc" and msg.cc == 64 then
    synth.sustain(msg.val >= 64)
  elseif msg.type == "cc" and msg.cc == HOLD_CC then
    params:set("synth_hold", msg.val >= 64 and 2 or 1)
  elseif msg.type == "cc" and msg.cc == RETRIG_CC then
    params:set("synth_retrig", msg.val >= 64 and 2 or 1)
  elseif msg.type == "cc" and msg.cc == DIV_CC then
    params:set("synth_retrig_div", msg.val // 32 + 1)
  elseif msg.type == "cc" and msg.cc == OCT_CC then
    params:set("synth_octaves", msg.val // 32 + 1)
  elseif msg.type == "cc" and msg.cc == RESET_CC then
    params:set("synth_reset", math.min(msg.val, 64))
  elseif msg.type == "pitchbend" then
    bend(2 ^ ((msg.val - 8192) / 8192 * BEND_RANGE / 12))
  elseif msg.type == "key_pressure" then
    synth.pressure(msg.note, msg.val / 127)
  elseif msg.type == "channel_pressure" then
    synth.pressure(nil, msg.val / 127)
  end
end

function synth.port_names()
  local names = { "All" }
  for i = 1, #midi.vports do names[i + 1] = i .. " " .. midi.vports[i].name end
  return names
end

function synth.midi_connect(port)
  synth.all_off()
  bend(1)
  for _, d in ipairs(devs) do d.event = nil end
  devs = {}
  synth.port = port
  for i = 1, #midi.vports do
    if port == 0 or port == i then
      local d = midi.connect(i)
      d.event = synth.midi_event
      devs[#devs + 1] = d
    end
  end
end

function synth.set_channel(ch)
  synth.all_off()
  bend(1)
  synth.channel = ch
end

function synth.cleanup()
  synth.set_voice(nil)
  for _, d in ipairs(devs) do d.event = nil end
  devs = {}
end

return synth
