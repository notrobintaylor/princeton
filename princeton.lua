-- princeton
--
-- Amp sim based on a combo.
-- Tuner, effects and looper.

engine.name = "Princeton"

-- princeton is a small guitar combo that would like to be more than one, with pedals in front and a
-- rack behind. Lua allows only 200 locals in a main chunk and princeton sits close, so many
-- constants live in tables.

local initing = true

local sprites = include("lib/sprites")
local sprites_device = include("lib/sprites_device")
local sprite = include("lib/sprite")
local cabinet = include("lib/cabinet")
local sync    = include("lib/sync")
local scales  = include("lib/scales")
local tune   = include("lib/tune")
local looper  = include("lib/looper")
local looper_params = include("lib/looper_params")
local looper_ui = include("lib/looper_ui")
local lfo     = include("lib/lfo")
local env     = include("lib/env")
local trigs   = include("lib/trigger")
local seq     = include("lib/seq")
local modrack = include("lib/modrack")
local lifecycle = include("lib/lifecycle")
local nam     = include("lib/nam")
local chstrip = include("lib/strip")
local control = include("lib/control")
local midimap = include("lib/midimap")
local synth   = include("lib/synth")
-- Voices from voice mods (e.g. "form"), selectable in Route next to Mono and Stereo.
local VOICES  = (package.loaded.voices and package.loaded.voices.list) or {}
local fmt     = include("lib/fmt")
local menu_rows = include("lib/menu_rows")

-- The cabinet's knobs and the looper pane's rows in panel order. Names, ranges and formatting
-- come from the params themselves, so the panes read exactly what PARAMS reads.
local PARAMS_DEF = {
  { id="amp_volume",        cat="Amp"     },
  { id="amp_bass",          cat="Amp"     },
  { id="amp_treble",        cat="Amp"     },
  { id="amp_master",        cat="Amp"     },
  { id="tremolo_intensity", cat="Tremolo" },
  { id="tremolo_speed",     cat="Tremolo" },
  { id="reverb_amount",     cat="Reverb"  },
  { id="reverb_length",     cat="Reverb"  },
  { id="mic_position",      cat="Mic"     },
  { id="amp_mid",           cat="Amp"     },
}
local LOOPER_DEF = {}
for _, id in ipairs({ "looper_medium", "looper_wear", "looper_direction", "looper_dub_level", "looper_level",
                      "looper_fade_level", "looper_speed", "looper_quant_div", "looper_quant_feel" }) do
  LOOPER_DEF[#LOOPER_DEF + 1] = { id = id, cat = "Loop" }
end
local MIC_NAMES  = { "Center", "Middle", "Edge" }
local DIR_NAMES  = looper_params.DIR_NAMES

local sel = 1

local function amp_is_bypassed()
  return params:get("amp_enable") == 1
end

local AMP_NAM_KNOBS = { 1, 2, 10, 3, 4, 5, 6, 7, 8 }

-- The amp slot holds the classic amp, a NAM profile or the channel strip. NAM counts only where its
-- plugin is installed, so a PSET from another norns falls back to the classic amp.
local function amp_kind()
  local v = params.lookup["amp_type"] and params:get("amp_type") or 1
  if v == 3 then return "strip" end
  return (v == 2 and nam.available()) and "nam" or "int"
end

-- The strip has neither tremolo nor speaker, so both leave the chain while it stands in.
local function dev_hidden(abbr)
  local kind = amp_kind()
  if kind == "strip" then return abbr == "TRM" or abbr == "CAB" end
  if abbr ~= "CAB" or params.lookup["amp_nam_cab"] == nil or kind ~= "nam" then return false end
  local mode = params:get("amp_nam_cab")
  if mode == 1 then return nam.full_rig(params:get("amp_model")) end
  return mode == 3
end

local function step_visible(i, d, list)
  local dir = d > 0 and 1 or -1
  for _ = 1, math.abs(d) do
    local j = i + dir
    while list[j] and dev_hidden(list[j].abbr) do j = j + dir end
    if not list[j] then break end
    i = j
  end
  return i
end

local view_group = 0
local view_pane  = {[0]=1, [1]=1, [3]=1, [4]=1}
local gui_mode   = 1
local perf_sel   = 1
local perf_param = {}
local mod_open   = false
local studio_sel = 1
local focus_absorb = {}
local dev_param_sel = {}
local studio_apply
local cab_sel_id
local cab_refresh
local RACK_PANES = (function()
  local t = { { kind = "tune" }, { kind = "count" } }
  for i = 1, env.NUM  do t[#t + 1] = { kind = "env",  idx = i } end
  for i = 1, lfo.NUM  do t[#t + 1] = { kind = "lfo",  idx = i } end
  for i = 1, seq.NUM  do t[#t + 1] = { kind = "seq",  idx = i } end
  for i = 1, trigs.N  do t[#t + 1] = { kind = "trig", idx = i } end
  return t
end)()
local MOD_PANE_1 = 3
local refresh_tune
local lfo_strip_sel = {1, 1, 1, 1, 1, 1, 1, 1}
local seq_strip_sel = {1, 1}
local count_strip_sel = 1

local PEDALS = {
  {
    name       = "Push",
    display    = "Push",
    params     = {
      { id="push_gain",  name="Gain",  kind="drive",  default=5 },
      { id="push_tone",  name="Tone",  kind="amount", default=50, scale=0.1 },
      { id="push_level", name="Level", kind="level",  default=0 },
      { id="push_comp",  name="Comp",  kind="amount", default=50, scale=0.1 },
    },
    psel       = 1,
    bypass_cmd = "push_bypass",
    enable_id  = "push_enable",
    subsynth   = "push",
  },
  {
    name       = "Distort",
    display    = "Distort",
    params     = {
      { id="distort_gain",    name="Gain",     kind="drive",  default=5 },
      { id="distort_tone",    name="Tone",     kind="amount", default=75, scale=0.1 },
      { id="distort_level",   name="Level",    kind="level",  default=0 },
      { id="distort_lowcut",  name="Low Cut",  kind="hz",     default=20, lo=20, hi=1000 },
    },
    psel       = 1,
    bypass_cmd = "distort_bypass",
    enable_id  = "distort_enable",
    subsynth   = "distort",
  },
  {
    name       = "Warp",
    display    = "Warp",
    params     = {
      { id="warp_rate",  name="Rate",      kind="rate",   default=2.5, lo=0.1, hi=25 },
      { id="warp_depth", name="Depth",     kind="amount", default=25 },
      { id="warp_rise",  name="Rise/Fall", kind="s",      default=2.5, lo=0.01, hi=5 },
      { id="warp_mix",   name="Mix",       kind="amount", default=100 },
    },
    psel       = 1,
    bypass_cmd = "warp_bypass",
    enable_id  = "warp_enable",
  },
  {
    name       = "Repeat",
    display    = "Repeat",
    params     = {
      { id="repeat_time",           name="Time",      kind="ms",     default=500, lo=1, hi=1000 },
      { id="repeat_feedback",       name="Feedback",  kind="amount", default=50 },
      { id="repeat_level",          name="Level",     kind="level",  default=0 },
      { id="repeat_characteristic", name="Tone",      default=0, options={"Bright","Dark"} },
      { id="repeat_mod_depth",      name="Mod Depth", kind="amount", default=10 },
      { id="repeat_mod_rate",       name="Mod Rate",  kind="rate",   default=2.5, lo=0.1, hi=25 },
    },
    psel       = 1,
    bypass_cmd = "repeat_bypass",
    enable_id  = "repeat_enable",
  },
}

local function cur_pedal_sel()
  if view_group == 3 then return view_pane[3] end
  return 1
end

local function cur_pedal() return PEDALS[cur_pedal_sel()] end

local clock_running = true

-- ── Mod targets ──────────────────────────────────────────────

local bld_synced, bld_send_block
local BLD_RATIOS  = { { 1, 1 }, { 1, 2 }, { 2, 1 }, { 2, 3 }, { 3, 2 }, { 3, 4 }, { 4, 3 }, { 1, -1 }, { 1, -2 }, { 2, -1 }, { 4, -1 } }
local function bld_send_ratio(i)
  local q = BLD_RATIOS[util.clamp(i, 1, #BLD_RATIOS)]
  engine.bld_ratio_a(q[1]); engine.bld_ratio_b(q[2])
end
local BLD_BLOCKS   = { 2.512, 6.31, 15.85, 39.81, 100, 251.2, 631, 1585, 3981, 10000 }
-- Everything a mod source may turn lives here, TARGET_PARAMS for continuous targets and
-- TRIG_TARGETS for actions. The Build helpers come first because three Build targets need them when
-- sending.
local TARGET_PARAMS = {
  {label="Off"},
  {label="Cut: Threshold",    id="cut_thresh",       send=function(v) engine.cut_thresh(control.db(v)) end},
  {label="Cut: Attack",       id="cut_attack",       send=function(v) engine.cut_attack(v) end},
  {label="Cut: Hold",         id="cut_hold",         send=function(v) engine.cut_hold(math.floor(v)) end},
  {label="Cut: Release",      id="cut_release",      send=function(v) engine.cut_release(v) end},
  {label="Cut: Range",        id="cut_range",        send=function(v) engine.cut_range(control.db(v)) end},
  {label="Cut: Margin",       id="cut_hyst",         send=function(v) engine.cut_hyst(v) end},
  {label="Fray: Drive",       id="fray_drive",       send=function(v) engine.fray_drive(v) end},
  {label="Fray: Comp",        id="fray_comp",        send=function(v) engine.fray_comp(v * 0.1) end},
  {label="Fray: Stab",        id="fray_stab",        send=function(v) engine.fray_stab(v * 0.1) end},
  {label="Fray: Octave",      id="fray_octave",      send=function(v) engine.fray_octave(v * 0.1) end},
  {label="Fray: Gate",        id="fray_gate",        send=function(v) engine.fray_gate(v * 0.1) end},
  {label="Fray: Tone",        id="fray_tone",        send=function(v) engine.fray_tone(v * 0.1) end},
  {label="Fray: Level",      id="fray_volume",      send=function(v) engine.fray_volume(control.amp(v)) end},
  {label="Push: Gain",         id="push_gain",         send=function(v) engine.push_gain(v) end},
  {label="Push: Tone",         id="push_tone",         send=function(v) engine.push_tone(v * 0.1) end},
  {label="Push: Level",        id="push_level",        send=function(v) engine.push_level(control.amp(v)) end},
  {label="Push: Comp",         id="push_comp",         send=function(v) engine.push_comp(v * 0.1) end},
  {label="Distort: Gain",      id="distort_gain",      send=function(v) engine.distort_gain(v) end},
  {label="Distort: Tone",      id="distort_tone",      send=function(v) engine.distort_tone(v * 0.1) end},
  {label="Distort: Level",     id="distort_level",     send=function(v) engine.distort_level(control.amp(v)) end},
  {label="Warp: Rate",         id="warp_rate",         send=function(v) engine.warp_rate(v) end},
  {label="Warp: Depth",        id="warp_depth",        send=function(v) engine.warp_depth(math.floor(v)) end},
  {label="Warp: Rise/Fall",    id="warp_rise",         send=function(v) engine.warp_rise(v) end},
  {label="Warp: Mix",          id="warp_mix",          send=function(v) engine.warp_mix(math.floor(v)) end},
  {label="Repeat: Time",       id="repeat_time",       send=function(v) engine.repeat_time(math.floor(v)) end},
  {label="Repeat: Feedback",   id="repeat_feedback",   send=function(v) engine.repeat_feedback(math.floor(v)) end},
  {label="Repeat: Level",      id="repeat_level",      send=function(v) engine.repeat_level(control.amp(v)) end},
  {label="Repeat: Mod Depth",  id="repeat_mod_depth",  send=function(v) engine.repeat_mod_depth(math.floor(v)) end},
  {label="Repeat: Mod Rate",   id="repeat_mod_rate",   send=function(v) engine.repeat_mod_rate(v) end},
  {label="Amp: Volume",        id="amp_volume",        send=function(v) engine.amp_volume(v) end},
  {label="Amp: Bass",          id="amp_bass",          send=function(v) engine.amp_bass(v <= 50 and v * 0.05 or 2.5 + (v - 50) * 0.15) end},
  {label="Amp: Treble",        id="amp_treble",        send=function(v) engine.amp_treble(v * 0.1) end},
  {label="Amp: Master",        id="amp_master",        send=function(v) engine.amp_master(control.amp(v)) end},
  {label="Amp: Rectifier",     id="amp_rectifier",     mn=1,    mx=3,     st=1,    send=function(v) engine.amp_rectifier(math.floor(v + 0.5) - 1) end},
  {label="Tremolo: Speed",     id="tremolo_speed",     send=function(v) engine.tremolo_speed(v) end},
  {label="Tremolo: Intensity", id="tremolo_intensity", send=function(v) engine.tremolo_intensity(math.floor(v)) end},
  {label="Hold 1: Size", id="hold1_size", send=function(v) engine.hold_size(1, v * 0.1) end},
  {label="Hold 1: Density", id="hold1_density", send=function(v) engine.hold_density(1, 1 + v * 0.09) end},
  {label="Hold 1: Spread", id="hold1_spread", send=function(v) engine.hold_spread(1, v * 0.1) end},
  {label="Hold 1: Pitch", id="hold1_pitch", send=function(v) engine.hold_pitch(1, v) end},
  {label="Hold 1: Pitch Mix", id="hold1_pmix", send=function(v) engine.hold_pmix(1, v) end},
  {label="Hold 1: Reverse Mix", id="hold1_rev", send=function(v) engine.hold_rev(1, v) end},
  {label="Hold 1: Gain", id="hold1_gain", send=function(v) engine.hold_gain(1, v) end},
  {label="Hold 1: Level", id="hold1_level", send=function(v) engine.hold_level(1, control.amp(v)) end},
  {label="Hold 1: Movement", id="hold1_move", send=function(v) engine.hold_move(1, v * 0.1) end},
  {label="Hold 2: Size", id="hold2_size", send=function(v) engine.hold_size(2, v * 0.1) end},
  {label="Hold 2: Density", id="hold2_density", send=function(v) engine.hold_density(2, 1 + v * 0.09) end},
  {label="Hold 2: Spread", id="hold2_spread", send=function(v) engine.hold_spread(2, v * 0.1) end},
  {label="Hold 2: Pitch", id="hold2_pitch", send=function(v) engine.hold_pitch(2, v) end},
  {label="Hold 2: Pitch Mix", id="hold2_pmix", send=function(v) engine.hold_pmix(2, v) end},
  {label="Hold 2: Reverse Mix", id="hold2_rev", send=function(v) engine.hold_rev(2, v) end},
  {label="Hold 2: Gain", id="hold2_gain", send=function(v) engine.hold_gain(2, v) end},
  {label="Hold 2: Level", id="hold2_level", send=function(v) engine.hold_level(2, control.amp(v)) end},
  {label="Hold 2: Movement", id="hold2_move", send=function(v) engine.hold_move(2, v * 0.1) end},
  {label="Loop: Rec Level",  id="looper_dub_level",  send=function(v) engine.looper_dub_level(control.amp(v)) end},
  {label="Loop: Play Level", id="looper_level",      send=function(v) engine.looper_level(control.amp(v)) end},
  {label="Loop: Fade Level", id="looper_fade_level", send=function(v) engine.looper_fade_level(control.amp(v)) end},
  {label="Loop: Speed",      id="looper_speed",      mn=-100, mx=100,   st=1,    send=function(v)
    local ratio
    if params:get("looper_speed_control") == 1 then
      if v < 0 then ratio = 0.5 elseif v > 0 then ratio = 2.0 else ratio = 1.0 end
    else ratio = 2^(v/100) end
    engine.looper_speed(ratio)
  end},
  {label="Loop: Imprint",    id="looper_imprint",    send=function(v) engine.looper_imprint(math.floor(v)) end},
  {label="Loop: Wear",       id="looper_wear",       send=function(v) engine.looper_wear(math.floor(v)) end},
  {label="Loop: Cassette Wow", id="looper_wow_cas",    send=function(v) engine.looper_wow_cas(math.floor(v)) end},
  {label="Loop: CD Errors",  id="looper_cd_errors",  send=function(v) engine.looper_cd_errors(math.floor(v)) end},
  {label="Loop: Chip Crush", id="looper_chip_crush", send=function(v) engine.looper_chip_crush(math.floor(v)) end},
  {label="Loop: Tape Wow",   id="looper_wow_tape",   send=function(v) engine.looper_wow_tape(math.floor(v)) end},
  {label="Reverb: Amount",     id="reverb_amount",     send=function(v) engine.reverb_amount(math.floor(v)) end},
  {label="Reverb: Length",     id="reverb_length",     send=function(v) engine.reverb_length(v) end},
  {label="Reverb: Low Shelf",  id="reverb_low_shelf",  send=function(v) engine.reverb_low_shelf(v * 0.05) end},
  {label="Reverb: High Shelf", id="reverb_high_shelf", send=function(v) engine.reverb_high_shelf(v * 0.05) end},
  {label="Reverb: Dwell",      id="reverb_dwell",      send=function(v) engine.reverb_dwell(v * 0.1) end},
  {label="Reverb: Drip",       id="reverb_drip",       send=function(v) engine.reverb_drip(v * 0.1) end},
  {label="Cab & Mic: Level",     id="cab_level",         send=function(v) engine.cab_level(control.amp(v)) end},
  {label="Count: Division",    id="count_div",         mn=1,    mx=5,     st=1,    send=function(v) lfo.count.div = math.floor(v+0.5) end},
  {label="Count: Level",       id="count_level",       send=function(v) lfo.count.level = v end},
  {label="Count: Length",      id="count_length",      send=function(v) lfo.count.length = math.floor(v + 0.5) end},
  {label="Count: Root",        id="count_root",        mn=0,    mx=12,    st=1,    send=function(v)
    local p = math.floor(v + 0.5)
    if p <= 0 then lfo.count.root = 0; return end
    local tonic = ((lfo.target_base["count_root"] or params:get("count_root")) - 1) % 12
    lfo.count.root = scales.quantize_root(p, tonic, params:get("count_scale"))
  end},
  {label="Count: Register",    id="count_register",    mn=1,    mx=8,     st=1,    send=function(v) lfo.count.register = math.floor(v + 0.5) end},
  {label="Count: Scale",       id="count_scale",       mn=1,    mx=8,     st=1,    send=function(v) lfo.count.scale  = math.floor(v + 0.5) end},
  {label="Count: Chords",      id="count_chords",      mn=1,    mx=4,     st=1,    send=function(v) lfo.count.chords = math.floor(v + 0.5) end},
  {label="Count: Scale Play",  id="count_scale_play",  mn=1,    mx=8,     st=1,    send=function(v) lfo.count.play   = math.floor(v + 0.5) end},
  {label="Count: Scale Degree",id="count_degree",      mn=1,    mx=15,    st=1,    send=function(v) lfo.count.degree = math.floor(v + 0.5) end},
  {label="LFO 1: Rate",        id="lfo1_rate",         send=function(v) lfo.mod.rate[1]  = v end},
  {label="LFO 2: Rate",        id="lfo2_rate",         send=function(v) lfo.mod.rate[2]  = v end},
  {label="LFO 3: Rate",        id="lfo3_rate",         send=function(v) lfo.mod.rate[3]  = v end},
  {label="LFO 4: Rate",        id="lfo4_rate",         send=function(v) lfo.mod.rate[4]  = v end},
  {label="LFO 5: Rate",        id="lfo5_rate",         send=function(v) lfo.mod.rate[5]  = v end},
  {label="LFO 6: Rate",        id="lfo6_rate",         send=function(v) lfo.mod.rate[6]  = v end},
  {label="LFO 7: Rate",        id="lfo7_rate",         send=function(v) lfo.mod.rate[7]  = v end},
  {label="LFO 8: Rate",        id="lfo8_rate",         send=function(v) lfo.mod.rate[8]  = v end},
  {label="LFO 1: Depth",       id="lfo1_depth",        send=function(v) lfo.mod.depth[1] = v end},
  {label="LFO 2: Depth",       id="lfo2_depth",        send=function(v) lfo.mod.depth[2] = v end},
  {label="LFO 3: Depth",       id="lfo3_depth",        send=function(v) lfo.mod.depth[3] = v end},
  {label="LFO 4: Depth",       id="lfo4_depth",        send=function(v) lfo.mod.depth[4] = v end},
  {label="LFO 5: Depth",       id="lfo5_depth",        send=function(v) lfo.mod.depth[5] = v end},
  {label="LFO 6: Depth",       id="lfo6_depth",        send=function(v) lfo.mod.depth[6] = v end},
  {label="LFO 7: Depth",       id="lfo7_depth",        send=function(v) lfo.mod.depth[7] = v end},
  {label="LFO 8: Depth",       id="lfo8_depth",        send=function(v) lfo.mod.depth[8] = v end},
  {label="Tremolo: Division",  id="tremolo_sync_div",  mn=2,    mx=#sync.DIV_OPTS,     st=1,    send=function(v)
    local new_v = math.floor(v+0.5)
    if lfo.sync_override["tremolo_sync_div"] ~= new_v then
      lfo.sync_override["tremolo_sync_div"] = new_v
      sync.push_all(initing, clock_running, lfo.sync_override)
    end
  end},
  {label="Tremolo: Feel", id="tremolo_sync_feel", mn=1,    mx=3,     st=1,    send=function(v)
    local new_v = math.floor(v+0.5)
    if lfo.sync_override["tremolo_sync_feel"] ~= new_v then
      lfo.sync_override["tremolo_sync_feel"] = new_v
      sync.push_all(initing, clock_running, lfo.sync_override)
    end
  end},
  {label="Warp: Division",     id="warp_sync_div",     mn=2,    mx=#sync.DIV_OPTS,     st=1,    send=function(v)
    local new_v = math.floor(v+0.5)
    if lfo.sync_override["warp_sync_div"] ~= new_v then
      lfo.sync_override["warp_sync_div"] = new_v
      sync.push_all(initing, clock_running, lfo.sync_override)
    end
  end},
  {label="Warp: Feel",    id="warp_sync_feel",    mn=1,    mx=3,     st=1,    send=function(v)
    local new_v = math.floor(v+0.5)
    if lfo.sync_override["warp_sync_feel"] ~= new_v then
      lfo.sync_override["warp_sync_feel"] = new_v
      sync.push_all(initing, clock_running, lfo.sync_override)
    end
  end},
  {label="Repeat: Division",   id="repeat_sync_div",   mn=2,    mx=#sync.DIV_OPTS,     st=1,    send=function(v)
    local new_v = math.floor(v+0.5)
    if lfo.sync_override["repeat_sync_div"] ~= new_v then
      lfo.sync_override["repeat_sync_div"] = new_v
      sync.push_all(initing, clock_running, lfo.sync_override)
    end
  end},
  {label="Repeat: Feel",  id="repeat_sync_feel",  mn=1,    mx=3,     st=1,    send=function(v)
    local new_v = math.floor(v+0.5)
    if lfo.sync_override["repeat_sync_feel"] ~= new_v then
      lfo.sync_override["repeat_sync_feel"] = new_v
      sync.push_all(initing, clock_running, lfo.sync_override)
    end
  end},
  {label="Loop: Quantize Division",   id="looper_quant_div",  mn=2,    mx=#sync.DIV_OPTS,     st=1,    send=function(v)
    local new_v = math.floor(v+0.5)
    if lfo.sync_override["looper_quant_div"] ~= new_v then
      lfo.sync_override["looper_quant_div"] = new_v
      looper.quant_led_restart()
    end
  end},
  {label="Loop: Quantize Feel", id="looper_quant_feel", mn=1,    mx=3,     st=1,    send=function(v)
    local new_v = math.floor(v+0.5)
    if lfo.sync_override["looper_quant_feel"] ~= new_v then
      lfo.sync_override["looper_quant_feel"] = new_v
      looper.quant_led_restart()
    end
  end},
}

for i = 1, lfo.NUM do
  TARGET_PARAMS[#TARGET_PARAMS+1] = {label="LFO "..i..": Phase",     id="lfo"..i.."_phase",     mn=1, mx=4,   st=1,   send=function(v) lfo.mod.phase[i]     = math.floor(v + 0.5) end}
  TARGET_PARAMS[#TARGET_PARAMS+1] = {label="LFO "..i..": Steps",     id="lfo"..i.."_steps",     mn=1, mx=16,  st=1,   send=function(v) lfo.mod.steps[i]     = math.floor(v + 0.5) end}
  TARGET_PARAMS[#TARGET_PARAMS+1] = {label="LFO "..i..": Stability", id="lfo"..i.."_stability", send=function(v) lfo.mod.stability[i] = v end}
  TARGET_PARAMS[#TARGET_PARAMS+1] = {label="LFO "..i..": Rate Slew", id="lfo"..i.."_rate_slew", send=function(v) lfo.mod.rate_slew[i] = v end}
  TARGET_PARAMS[#TARGET_PARAMS+1] = {label="LFO "..i..": Sync Div",  id="lfo"..i.."_sync_div",  mn=2, mx=#sync.DIV_OPTS,   st=1,   send=function(v) lfo.mod.sync_div[i]  = math.floor(v + 0.5) end}
  TARGET_PARAMS[#TARGET_PARAMS+1] = {label="LFO "..i..": Sync Feel", id="lfo"..i.."_sync_feel", mn=1, mx=3,   st=1,   send=function(v) lfo.mod.sync_feel[i] = math.floor(v + 0.5) end}
end

for i = 1, seq.NUM do
  TARGET_PARAMS[#TARGET_PARAMS+1] = {label="Walk "..i..": Rate",      id="seq"..i.."_rate",      send=function(v) seq.mod.rate[i]      = v end}
  TARGET_PARAMS[#TARGET_PARAMS+1] = {label="Walk "..i..": Steps",     id="seq"..i.."_steps",     mn=2,   mx=16,  st=1,   send=function(v) seq.mod.steps[i]     = math.floor(v + 0.5) end}
  TARGET_PARAMS[#TARGET_PARAMS+1] = {label="Walk "..i..": Rate Slew", id="seq"..i.."_rate_slew", send=function(v) seq.mod.rate_slew[i] = v end}
  TARGET_PARAMS[#TARGET_PARAMS+1] = {label="Walk "..i..": Sync Div",  id="seq"..i.."_sync_div",  mn=2, mx=#sync.DIV_OPTS,   st=1,   send=function(v) seq.mod.sync_div[i]  = math.floor(v + 0.5) end}
  TARGET_PARAMS[#TARGET_PARAMS+1] = {label="Walk "..i..": Sync Feel", id="seq"..i.."_sync_feel", mn=1,   mx=3,   st=1,   send=function(v) seq.mod.sync_feel[i] = math.floor(v + 0.5) end}
end

for i = 1, trigs.N do
  TARGET_PARAMS[#TARGET_PARAMS+1] = {label="Trigger "..i..": Rate",        id="trig"..i.."_rate",        send=function(v) trigs.mod.rate[i]        = v end}
  TARGET_PARAMS[#TARGET_PARAMS+1] = {label="Trigger "..i..": Chance", id="trig"..i.."_chance", send=function(v) trigs.mod.chance[i] = v end}
  TARGET_PARAMS[#TARGET_PARAMS+1] = {label="Trigger "..i..": Sync Div",    id="trig"..i.."_sync_div",    mn=2,   mx=#sync.DIV_OPTS, st=1, send=function(v) trigs.mod.sync_div[i]  = math.floor(v + 0.5) end}
  TARGET_PARAMS[#TARGET_PARAMS+1] = {label="Trigger "..i..": Sync Feel",   id="trig"..i.."_sync_feel",   mn=1,   mx=3,   st=1,   send=function(v) trigs.mod.sync_feel[i] = math.floor(v + 0.5) end}
end

TARGET_PARAMS[#TARGET_PARAMS+1] = {label="Tape: Speed",    id="tape_speed",    mn=1, mx=3,  st=1,   send=function(v) engine.tape_speed(math.floor(v + 0.5) - 1) end}
TARGET_PARAMS[#TARGET_PARAMS+1] = {label="Tape: Drive",    id="tape_drive",    send=function(v) engine.tape_drive(v) end}
TARGET_PARAMS[#TARGET_PARAMS+1] = {label="Tape: Bias",     id="tape_bias",     mn=1, mx=3,  st=1,   send=function(v) engine.tape_bias(math.floor(v + 0.5) - 1) end}
TARGET_PARAMS[#TARGET_PARAMS+1] = {label="Tape: Hiss",     id="tape_hiss",     send=function(v) engine.tape_hiss(v * 0.1) end}
TARGET_PARAMS[#TARGET_PARAMS+1] = {label="Tape: Wow",      id="tape_wow",      send=function(v) engine.tape_wow(v * 0.1) end}
TARGET_PARAMS[#TARGET_PARAMS+1] = {label="Tape: Azimuth",  id="tape_azimuth",  send=function(v) engine.tape_azimuth(v * 0.1) end}
TARGET_PARAMS[#TARGET_PARAMS+1] = {label="Tape: Magnetism", id="tape_mag",     send=function(v) engine.tape_mag(v * 0.1) end}
TARGET_PARAMS[#TARGET_PARAMS+1] = {label="Build: Block",       id="bld_block",   mn=1,  mx=10,     st=1,   send=function(v) bld_send_block(math.floor(v + 0.5)) end}
TARGET_PARAMS[#TARGET_PARAMS+1] = {label="Build: Ratio",       id="bld_ratio",   mn=1,  mx=11,     st=1,   send=function(v) bld_send_ratio(math.floor(v + 0.5)) end}
TARGET_PARAMS[#TARGET_PARAMS+1] = {label="Build: Time",        id="bld_time",    send=function(v) bld_send_block(nil, v) end}
TARGET_PARAMS[#TARGET_PARAMS+1] = {label="Build: Feedback",    id="bld_fb",      send=function(v) engine.bld_fb(v) end}
TARGET_PARAMS[#TARGET_PARAMS+1] = {label="Build: Mix",         id="bld_mix",     send=function(v) engine.bld_mix(v) end}
TARGET_PARAMS[#TARGET_PARAMS+1] = {label="Build: Spread",      id="bld_spread",  send=function(v) engine.bld_spread(v) end}
TARGET_PARAMS[#TARGET_PARAMS+1] = {label="Build: Low Cut",     id="bld_lowcut",  send=function(v) engine.bld_lowcut(v) end}
TARGET_PARAMS[#TARGET_PARAMS+1] = {label="Build: High Cut",    id="bld_highcut", send=function(v) engine.bld_highcut(v) end}
TARGET_PARAMS[#TARGET_PARAMS+1] = {label="Amp: Mid",           id="amp_mid",     send=function(v) engine.amp_mid(v * 0.1) end}
TARGET_PARAMS[#TARGET_PARAMS+1] = {label="Amp: Mid Freq",      id="amp_mid_freq", send=function(v) engine.amp_mid_freq(v) end}
TARGET_PARAMS[#TARGET_PARAMS+1] = {label="Mesmerize: Size",      id="evp_size",       send=function(v) engine.evp_size(10 + v * 2.9) end}
TARGET_PARAMS[#TARGET_PARAMS+1] = {label="Mesmerize: Pre-Delay", id="evp_predelay",   send=function(v) engine.evp_predelay(v) end}
TARGET_PARAMS[#TARGET_PARAMS+1] = {label="Mesmerize: Decay",     id="evp_decay",      send=function(v) engine.evp_decay(v) end}
TARGET_PARAMS[#TARGET_PARAMS+1] = {label="Mesmerize: Damping",   id="evp_damping",    send=function(v) engine.evp_damping(v) end}
TARGET_PARAMS[#TARGET_PARAMS+1] = {label="Mesmerize: Tilt",      id="evp_tilt",       send=function(v) engine.evp_tilt(v) end}
TARGET_PARAMS[#TARGET_PARAMS+1] = {label="Mesmerize: Mix",       id="evp_mix",        send=function(v) engine.evp_mix(v) end}
TARGET_PARAMS[#TARGET_PARAMS+1] = {label="Mesmerize: Spread",    id="evp_spread",     send=function(v) engine.evp_spread(v * 2) end}
TARGET_PARAMS[#TARGET_PARAMS+1] = {label="Mesmerize: Saturation", id="evp_saturation", send=function(v) engine.evp_saturation(v) end}
TARGET_PARAMS[#TARGET_PARAMS+1] = {label="Mesmerize: Width",     id="evp_width",      send=function(v) engine.evp_width(v * 2) end}
TARGET_PARAMS[#TARGET_PARAMS+1] = {label="Mesmerize: Low Cut",   id="evp_lowcut",     send=function(v) engine.evp_lowcut(v) end}
TARGET_PARAMS[#TARGET_PARAMS+1] = {label="Build: Octave",        id="bld_octave",     send=function(v) engine.bld_octave(v) end}
TARGET_PARAMS[#TARGET_PARAMS+1] = {label="Build: Smear",         id="bld_smear",      send=function(v) engine.bld_smear(v) end}
TARGET_PARAMS[#TARGET_PARAMS+1] = {label="Build: Crossfeed",     id="bld_xfeed",      send=function(v) engine.bld_xfeed(v) end}
TARGET_PARAMS[#TARGET_PARAMS+1] = {label="Strip: Drive",          id="strip_gain",    send=function(v) engine.strip_gain(10 ^ ((v - 5) / 10)) end}
TARGET_PARAMS[#TARGET_PARAMS+1] = {label="Strip: Even Harmonics", id="strip_even",    send=function(v) engine.strip_even(v * 0.1) end}
TARGET_PARAMS[#TARGET_PARAMS+1] = {label="Strip: Odd Harmonics",  id="strip_odd",     send=function(v) engine.strip_odd(v * 0.1) end}
TARGET_PARAMS[#TARGET_PARAMS+1] = {label="Strip: Low Cut",        id="strip_lowcut",  send=function(v) engine.strip_lowcut(v) end}
TARGET_PARAMS[#TARGET_PARAMS+1] = {label="Strip: High Cut",       id="strip_highcut", send=function(v) engine.strip_highcut(v) end}
TARGET_PARAMS[#TARGET_PARAMS+1] = {label="Strip: Level",          id="strip_level",   send=function(v) engine.strip_level(control.amp(v)) end}

local DEVICE_NAMES     = {}
local DEVICE_PARAMS    = {}
local TARGET_DEVICE_OF = {}
for i = 2, #TARGET_PARAMS do
  local t = TARGET_PARAMS[i]
  if t.id then
    local dev_name, short_name = t.label:match("^(.-): (.+)$")
    if dev_name then
      local di
      for ix, dn in ipairs(DEVICE_NAMES) do
        if dn == dev_name then di = ix; break end
      end
      if not di then
        DEVICE_NAMES[#DEVICE_NAMES + 1] = dev_name
        di = #DEVICE_NAMES
        DEVICE_PARAMS[di] = {}
      end
      DEVICE_PARAMS[di][#DEVICE_PARAMS[di] + 1] = { global_idx = i, short = short_name }
      TARGET_DEVICE_OF[i] = di
    end
  end
end

local TRIG_TARGETS = (function()
  local function toggle(id)
    return function()
      focus_absorb[id] = true
      params:set(id, 3 - params:get(id))
    end
  end
  local t = {
    { label = "Off" },
    { label = "Cut: Toggle",     id = "trig_cut_toggle",     action = toggle("cut_enable") },
    { label = "Fray: Toggle",    id = "trig_fray_toggle",    action = toggle("fray_enable") },
    { label = "Push: Toggle",    id = "trig_push_toggle",    action = toggle("push_enable") },
    { label = "Distort: Toggle", id = "trig_distort_toggle", action = toggle("distort_enable") },
    { label = "Warp: Toggle",    id = "trig_warp_toggle",    action = toggle("warp_enable") },
    { label = "Repeat: Toggle",  id = "trig_repeat_toggle",  action = toggle("repeat_enable") },
    { label = "Amp: Toggle",     id = "trig_amp_toggle",     action = toggle("amp_enable") },
    { label = "Tremolo: Toggle", id = "trig_tremolo_toggle", action = toggle("tremolo_enable") },
    { label = "Hold 1: Toggle",  id = "trig_hold1_toggle",   action = toggle("hold1_enable") },
    { label = "Hold 1: Recapture", id = "trig_hold1_recapture", action = function() engine.hold_recapture(1) end },
    { label = "Hold 2: Toggle",  id = "trig_hold2_toggle",   action = toggle("hold2_enable") },
    { label = "Hold 2: Recapture", id = "trig_hold2_recapture", action = function() engine.hold_recapture(2) end },
    { label = "Loop: Rec",     id = "trig_looper_rec",     action = function() focus_absorb["@loop"] = true; looper.step() end },
    { label = "Loop: Clear",   id = "trig_looper_clear",   action = function() focus_absorb["@loop"] = true; looper.force_clear() end },
    { label = "Loop: Undo",    id = "trig_looper_undo",    action = function() focus_absorb["@loop"] = true; looper.undo() end },
    { label = "Reverb: Toggle",  id = "trig_reverb_toggle",  action = toggle("reverb_enable") },
    { label = "Reverb: Freeze",  id = "trig_reverb_freeze",  action = toggle("reverb_freeze") },
  }
  for i = 1, lfo.NUM do
    t[#t + 1] = { label = "LFO " .. i .. ": Randomize", id = "trig_lfo" .. i .. "_randomize", lfo_idx = i,
                  action = function() params:set("lfo" .. i .. "_randomize", 1) end }
  end
  for i = 1, seq.NUM do
    t[#t + 1] = { label = "Walk " .. i .. ": Randomize", id = "trig_seq" .. i .. "_randomize",
                  action = function() params:set("seq" .. i .. "_randomize", 1) end }
  end
  t[#t + 1] = { label = "Tape: Toggle",     id = "trig_tape_toggle",    action = toggle("tape_enable") }
  t[#t + 1] = { label = "Tape: Stop/Start", id = "trig_tape_transport", action = function() params:set("tape_transport", 1) end }
  t[#t + 1] = { label = "Build: Toggle",    id = "trig_bld_toggle",     action = toggle("bld_enable") }
  t[#t + 1] = { label = "Build: Freeze",    id = "trig_bld_freeze",     action = function() params:set("bld_freeze", 3 - params:get("bld_freeze")) end }
  t[#t + 1] = { label = "Mesmerize: Toggle",  id = "trig_evp_toggle",     action = toggle("evp_enable") }
  t[#t + 1] = { label = "Mesmerize: Freeze",  id = "trig_evp_freeze",     action = function() params:set("evp_freeze", 3 - params:get("evp_freeze")) end }
  return t
end)()

local count_active = false
local count_clock_gen = 0
local count_step   = 0
local count_flash  = 0

local k_clock = {}

local B = { DIM=0, MED=5, FULL=15 }

local GROUP_MAX = {[0]=2, [1]=#RACK_PANES, [3]=4, [4]=5}

local COUNT_STRIP = {
  {name="BPM",      id="count_bpm",     typ="ctrl", step=1,  fmt=function(v) return string.format("%d", v) end},
  {name="Division", id="count_div",     typ="opt",  nmax=5,  fmt=function(v) return sync.COUNT_DIV_OPTS[v] end},
  {name="Root",     id="count_root",     typ="opt", nmax=12, fmt=function(v) return scales.NOTE_NAMES[v] end},
  {name="Register", id="count_register", typ="opt", nmax=8,  fmt=function(v) return tostring(v - 1) end},
  {name="Scale",    id="count_scale",    typ="opt",  nmax=8,  fmt=function(v) return scales.SCALE_NAMES[v] end},
  {name="Degree",   id="count_degree",     typ="opt", nmax=15, fmt=function(v) return tostring(v) end},
  {name="Play",     id="count_scale_play", typ="opt", nmax=8, fmt=function(v) return params:lookup_param("count_scale_play").options[v] end},
  {name="Chords",   id="count_chords",     typ="opt", nmax=4, fmt=function(v) return ({"Off","Octaves","Power","Triads"})[v] end},
  {name="Level",    id="count_level",   typ="ctrl", step=0.5, fmt=function(v) return control.level_str(v) end},
  {name="Length",   id="count_length",  typ="ctrl", step=1,  fmt=function(v) return string.format("%dms",math.floor(v)) end},
  {name="Position", id="count_position", typ="opt",  nmax=2,  fmt=function(v) return ({"Parallel","Inline"})[v] end},
}

-- Every readout uses the param's own formatter, so the screen reads what PARAMS reads. A live
-- value (modulation, a moving Hold) goes through the same formatter.
local function fmt_param(id, v_in)
  -- NAM profile names outgrow the strip, so it shows the list position instead
  if id == "amp_model" then
    return (v_in or params:get(id)) .. "/" .. #params:lookup_param(id).options
  end
  if id == "looper_speed" then
    local v = v_in or params:get(id)
    if params:get("looper_speed_control") == 1 then
      if v < 0 then return "-100%" elseif v > 0 then return "+100%" else return "+0%" end
    end
    return string.format("%+d%%", math.floor(v))
  end
  local s = sync.fmt(id, clock_running)
  if s then return s end
  if v_in == nil then return params:string(id) end
  local p = params:lookup_param(id)
  if p.options then return p.options[util.clamp(math.floor(v_in + 0.5), 1, #p.options)] end
  if p.formatter and p.controlspec then
    return p.formatter({ controlspec = p.controlspec, get = function() return v_in end })
  end
  return tostring(v_in)
end
local function fmt_def_val(def, idx, v_in) return fmt_param(def[idx].id, v_in) end
local function fmt_val(idx) return fmt_param(PARAMS_DEF[idx].id) end

local PARAM_DEF_OF = {}
for i, e in ipairs(PARAMS_DEF) do PARAM_DEF_OF[e.id] = { def = PARAMS_DEF, idx = i } end
for i, e in ipairs(LOOPER_DEF) do PARAM_DEF_OF[e.id] = { def = LOOPER_DEF, idx = i } end

local function snap_val(v, step)
  if step == 1 then return math.floor(v + 0.5)
  else return math.floor(v * 10 + 0.5) / 10 end
end

-- ── Build: time and sync ─────────────────────────────────────
-- Build's Time knob snaps in twelfths of a doubling, like semitones, so short times stay as fine as
-- long ones. The block (BLD_BLOCKS) sets the ceiling, and a sync division is accepted only while
-- its time fits.
local function bld_steps(z)
  return math.ceil(12 * math.log(BLD_BLOCKS[util.clamp(z, 1, #BLD_BLOCKS)], 2))
end

local function bld_ms(z, pos)
  local n = bld_steps(z)
  return math.min(2 ^ (math.floor(util.clamp(pos, 0, 1) * n + 0.5) / 12), BLD_BLOCKS[util.clamp(z, 1, #BLD_BLOCKS)])
end

local function bld_pos(z, ms)
  if ms >= BLD_BLOCKS[util.clamp(z, 1, #BLD_BLOCKS)] then return 1 end
  return util.clamp(math.floor(12 * math.log(math.max(ms, 1), 2) + 0.5) / bld_steps(z), 0, 1)
end

bld_synced = function()
  return clock_running and params:get("bld_time_sync_div") > 1
end

bld_send_block = function(z, pos)
  z = util.clamp(z or params:get("bld_block"), 1, #BLD_BLOCKS)
  engine.bld_block(z)
  if bld_synced() then return end
  local ms = bld_ms(params:get("bld_block"), params:get("bld_time"))
  engine.bld_time(pos and bld_ms(z, pos) or math.min(ms, BLD_BLOCKS[z]))
end

sync.PARAM_MAP.bld_time = {
  div = "bld_time_sync_div", feel = "bld_time_sync_feel",
  in_range = function(hz) local ms = 1000.0 / hz; return ms >= 1 and ms <= BLD_BLOCKS[params:get("bld_block")] end,
  value_fn = function(hz) return util.clamp(1000.0 / hz, 1, BLD_BLOCKS[params:get("bld_block")]) end,
  base = function() return bld_ms(params:get("bld_block"), params:get("bld_time")) end,
}

-- ── Modulated values in the strip ────────────────────────────
-- A modulated knob shows its live value marked M, and its base value (dimmer, marked B) for two
-- seconds after you turn it. mod_live holds each send's last value, valid only while its source
-- runs.
local mod_live, base_touch, hold_live = {}, {}, { {}, {} }
local strip_live, strip_mark = false, nil
for _, t in ipairs(TARGET_PARAMS) do
  if t.id and t.send then
    local send = t.send
    t.send = function(v) mod_live[t.id] = v; send(v) end
  end
end

local function source_running(id)
  local o = lfo.target_owner[id]
  if o == nil then return false end
  if type(o) == "number" then return lfo.is_enabled(o) end
  local kind, n = tostring(o):match("^(%a+)_(%d+)$")
  if kind == "env" then return env.is_enabled(tonumber(n)) end
  if kind == "seq" then return seq.is_enabled(tonumber(n)) end
  return false
end

-- Hold's Size, Density and Spread read in percent, while the engine and its Movement polls keep
-- their own 0..10 (Density 1..10) scale; these two tables translate either way.
local HOLD_E = { size = function(v) return v * 0.1 end, density = function(v) return 1 + v * 0.09 end,
           spread = function(v) return v * 0.1 end }
local HOLD_P = { size = function(e) return e * 10 end, density = function(e) return (e - 1) / 0.09 end,
                 spread = function(e) return e * 10 end }

local function hold_moving(id)
  local hi, name = id:match("^hold(%d)_(%a+)$")
  if not (hi and (name == "size" or name == "density" or name == "spread")) then return nil end
  if params:get("hold" .. hi .. "_enable") ~= 2 then return nil end
  return tonumber(hi), name, params:get("hold" .. hi .. "_move") > 0
end

local function live_value(id)
  local running = source_running(id)
  local v = running and mod_live[id] or nil
  if not running then mod_live[id] = nil end
  local hi, name, moving = hold_moving(id)
  if hi and (running or moving) then
    local e = hold_live[hi][name]
    return e and HOLD_P[name](e) or v
  end
  return v
end

-- While a Hold pad moves (Move > 0), Size, Density and Spread carry the (M) like a modulated
-- target. The 20 Hz check below asks constantly, so the ids sit prebuilt in a table instead of
-- being assembled on every look.
local HOLD_MARK_IDS = (function()   -- immediately invoked, so the loop takes no main-chunk locals
  local t = {}
  for idx = 1, 2 do
    t[idx] = { move = "hold" .. idx .. "_move",
      "hold" .. idx .. "_size", "hold" .. idx .. "_density", "hold" .. idx .. "_spread" }
  end
  return t
end)()

local function hold_move_marks()
  for idx = 1, 2 do
    local ids = HOLD_MARK_IDS[idx]
    local moving = params:get(ids.move) > 0
    for _, id in ipairs(ids) do
      local want   = moving or lfo.target_owner[id] ~= nil
      local marked = params:lookup_param(id).name:find("%(M%)") ~= nil
      if want and not marked then lfo.mark_modulated(id)
      elseif marked and not want then lfo.unmark_modulated(id) end
    end
  end
end

local function strip_val(id, str, lv)
  local _, _, moving = hold_moving(id)
  strip_mark = (source_running(id) or moving) and "M" or nil
  local v = live_value(id)
  strip_live = v ~= nil
  if v == nil then return str, lv end
  local t = base_touch[id]
  if t and util.time() - t < 2 then strip_mark = "B"; return str, B.MED end
  return fmt_param(id, v), B.FULL
end

local function edit_param(id, d)
  base_touch[id] = util.time()
  local m = sync.PARAM_MAP[id]
  if m and params:get(m.div) > 1 then
    params:set(m.div, sync.step_div(id, params:get(m.div), d, params:get(m.feel), clock.get_tempo()))
    return
  end
  params:delta(id, d)
end

-- ── Tap tempo (Warp, Repeat, Tremolo, Count) ─────────────────
-- Tap K2 in time and the device takes the average of the last five taps, while a long pause starts
-- afresh. Under a sync division the clock has the say, so tapping stays silent.
local tap = { ID = { warp = "warp_rate", ["repeat"] = "repeat_time", tremolo = "tremolo_speed", count = "count_bpm" },
              DEV = { WRP = "warp", RPT = "repeat", TRM = "tremolo", CNT = "count" },
              DIV_OPTS = {}, times = {}, mean = {}, flash = {}, clamped = {}, last_div = {} }
for i = 2, #sync.DIV_OPTS do tap.DIV_OPTS[i - 1] = sync.DIV_OPTS[i] end

function tap.synced(prefix)
  return clock_running and params.lookup[prefix .. "_sync_div"] ~= nil and params:get(prefix .. "_sync_div") > 1
end

function tap.apply(prefix)
  local mean = tap.mean[prefix]
  if not mean or tap.synced(prefix) then return end
  local id = tap.ID[prefix]
  if prefix == "count" then params:set(id, util.round(60 / mean)); return end
  local m  = sync.PARAM_MAP[id]
  local hz = sync.hz_df(60 / mean, params:get(prefix .. "_tap_div") + 1, params:get(prefix .. "_tap_feel"))
  local v  = snap_val(m.value_fn(hz), params:lookup_param(id).controlspec.step)
  tap.clamped[id] = (not m.in_range(hz)) and v or nil
  params:set(id, v)
end

function tap.hit(prefix)
  if tap.synced(prefix) then return end
  local now = util.time()
  local ts  = tap.times[prefix] or {}
  local gap = ts[#ts] and (now - ts[#ts])
  if gap and (gap > 2 or (#ts >= 2 and gap > 2 * tap.mean[prefix])) then ts = {} end
  ts[#ts + 1] = now
  while #ts > 5 do table.remove(ts, 1) end
  tap.times[prefix] = ts
  if #ts >= 2 then
    tap.mean[prefix] = (ts[#ts] - ts[1]) / (#ts - 1)
    tap.apply(prefix)
  end
  tap.flash[tap.ID[prefix]] = now + 0.08
  clock.run(function() clock.sleep(0.09); redraw() end)
  redraw()
end

function tap.forget(prefix)
  tap.times[prefix] = nil
  tap.mean[prefix]  = nil
end

function tap.level(id, default)
  local f = tap.flash[id]
  if f and util.time() < f then return B.DIM end
  local c = tap.clamped[id]
  local m = sync.PARAM_MAP[id]
  if c and params:get(id) == c and not (m and params:get(m.div) > 1) then return B.MED end
  return default
end

local function draw_icon_filled_circle(cx, y)
  screen.rect(cx - 5, y - 2, 10, 4)
  screen.rect(cx - 2, y - 5, 4, 10)
  screen.rect(cx - 4, y - 4, 2, 2)
  screen.rect(cx + 2, y - 4, 2, 2)
  screen.rect(cx - 4, y + 2, 2, 2)
  screen.rect(cx + 2, y + 2, 2, 2)
  screen.fill()
end

local function draw_icon_record(cx, y, lv)
  screen.level(lv)
  draw_icon_filled_circle(cx, y)
end

local function draw_icon_dub(cx, y, lv)
  screen.level(lv)
  draw_icon_filled_circle(cx, y)
  screen.line_width(1)
  local px, py = cx + 8, y - 3
  screen.move(px-2, py); screen.line(px+1, py); screen.stroke()
  screen.move(px, py-2); screen.line(px, py+1); screen.stroke()
end

local function draw_icon_play(cx, y, lv)
  screen.level(lv)
  for d = -5, 4 do
    screen.rect(cx - 4, y + d, 10 - 2 * math.abs(d + 0.5), 1)
  end
  screen.fill()
end

local function draw_icon_stop(cx, y, lv)
  screen.level(lv); screen.rect(cx-4, y-4, 8, 8); screen.fill()
end

local function draw_strip(cat, name, val_str, val_lv, val_str2)
  val_lv = val_lv or B.FULL
  name = (name:gsub("^%(M%) ", ""))
  local mark = strip_mark
  strip_mark = false
  screen.level(B.DIM); screen.rect(0, 0, cabinet.LEFT_W, 64); screen.fill()
  screen.font_size(8); screen.font_face(0)
  screen.level(B.MED);  screen.move(cabinet.LEFT_CX,  8); screen.text_center(cat)
  local name2
  local sp = name:find(" ")
  if sp then name, name2 = name:sub(1, sp - 1), name:sub(sp + 1) end
  local vy = 26
  screen.level(B.MED); screen.move(cabinet.LEFT_CX, 17); screen.text_center(name)
  if name2 then
    screen.level(B.MED); screen.move(cabinet.LEFT_CX, 26); screen.text_center(name2)
    vy = 35
  end
  if val_str then
    val_str = val_str:gsub("(%-?%d+)%.%d+(%s*%%)", "%1%2")
    val_str = val_str:gsub("(%d)%s+([%a%%])", "%1%2")
  end
  if mark and val_str then
    local wm = screen.text_extents(mark)
    local x  = cabinet.LEFT_CX - math.floor((wm + 5 + screen.text_extents(val_str)) / 2)
    screen.level(B.MED); screen.move(x, vy); screen.text(mark)
    screen.level(val_lv); screen.move(x + wm + 5, vy); screen.text(val_str)
  else
    screen.level(val_lv); screen.move(cabinet.LEFT_CX, vy); screen.text_center(val_str)
  end
  if val_str2 then
    screen.level(val_lv); screen.move(cabinet.LEFT_CX, vy + 9); screen.text_center(val_str2)
  end
end

local function draw_looper_state_icon()
  if     looper.state == looper.REC  then draw_icon_record(cabinet.LEFT_CX, cabinet.ICON_Y, B.FULL)
  elseif looper.state == looper.DUB  then draw_icon_dub(cabinet.LEFT_CX, cabinet.ICON_Y, B.FULL)
  elseif looper.state == looper.PLAY then draw_icon_play(cabinet.LEFT_CX, cabinet.ICON_Y, B.FULL)
  elseif looper.state == looper.STOP then draw_icon_stop(cabinet.LEFT_CX, cabinet.ICON_Y, B.MED)
  end
end

local function draw_left_strip()
  local cm          = params:get("cab_mode")
  local id, devname = cab_sel_id()
  local pd          = PARAM_DEF_OF[id]
  local knob        = (pd and pd.def == PARAMS_DEF) and pd.idx or nil
  if id == "mic_position" and cm == 1 then
    screen.level(B.DIM); screen.rect(0, 0, cabinet.LEFT_W, 64); screen.fill()
    screen.font_size(8); screen.font_face(0)
    screen.level(B.MED)
    screen.move(cabinet.LEFT_CX,  8); screen.text_center("Cab & Mic")
    screen.move(cabinet.LEFT_CX, 17); screen.text_center("Simulation")
    screen.move(cabinet.LEFT_CX, 26); screen.text_center("Off")
  elseif knob then
    draw_strip(PARAMS_DEF[knob].cat, params:lookup_param(id).name, strip_val(id, fmt_val(knob), sync.val_level(id, clock_running)))
  else
    draw_strip(devname, params:lookup_param(id).name, strip_val(id, fmt_param(id), sync.val_level(id, clock_running)))
  end
end

local SEG7 = { ["0"]="abcdef", ["1"]="bc", ["2"]="abged", ["3"]="abgcd", ["4"]="fgbc",
               ["5"]="afgcd", ["6"]="afgedc", ["7"]="abc", ["8"]="abcdefg", ["9"]="abcdfg" }

-- The seven segments sit ready as fixed offsets. Each digit is drawn in two fills, all ghost
-- segments then all lit ones, however many segments are burning.
SEG7.rect = { a = {1, 0, 3, 1}, g = {1, 4, 3, 1}, d = {1, 8, 3, 1},
              f = {0, 1, 1, 3}, b = {4, 1, 1, 3}, e = {0, 5, 1, 3}, c = {4, 5, 1, 3} }

local function draw_seg7(x, y, ch, lit, ghost)
  local on = SEG7[ch] or ""
  for pass = 1, 2 do
    screen.level(pass == 1 and ghost or lit)
    for k, r in pairs(SEG7.rect) do
      if (on:find(k, 1, true) ~= nil) == (pass == 2) then
        screen.rect(x + r[1], y + r[2], r[3], r[4])
      end
    end
    screen.fill()
  end
end

-- Count in the same 37 x 60 box as Tune: the tempo display on top, then the four beats, two
-- jacks and the clicking speaker at the bottom.
local function draw_metro_half(ox, oy, focused)
  oy = oy - 1
  local lv  = focused and B.FULL or B.MED
  local bpm
  if clock_running then bpm = math.floor(clock.get_tempo() + 0.5)
  else bpm = params:get("count_bpm") end
  local digits = string.format("%3d", util.clamp(bpm, 0, 999))
  cabinet.frame(ox, oy, cabinet.HALF_W, cabinet.H, lv)
  screen.level(1); screen.rect(ox + 4, oy + 5, 29, 19); screen.fill()
  local pulse = count_active and util.time() - count_flash < 0.1
  screen.level(pulse and B.FULL or 4)
  screen.rect(ox + 4, oy + 4, 29, 1); screen.rect(ox + 4, oy + 24, 29, 1)
  screen.rect(ox + 3, oy + 5, 1, 19); screen.rect(ox + 33, oy + 5, 1, 19); screen.fill()
  local lit = count_active and 13 or 9
  for i = 1, 3 do
    local ch = digits:sub(i, i)
    draw_seg7(ox + 8 + (i - 1) * 7, oy + 10, ch ~= " " and ch or "", lit, 2)
  end
  screen.level(3)
  for i = 0, 3 do screen.rect(ox + 8 + i * 6, oy + 28, 3, 2) end
  screen.fill()
  screen.level(B.MED)
  screen.rect(ox + 5, oy + 33, 5, 3); screen.rect(ox + 27, oy + 33, 5, 3); screen.fill()
  screen.level(0)
  screen.rect(ox + 6, oy + 34, 3, 1); screen.rect(ox + 28, oy + 34, 3, 1); screen.rect(ox + 29, oy + 33, 1, 3); screen.fill()
  screen.level(4)
  for y = oy + 38, oy + 56, 3 do
    for x = ox + 6, ox + 30, 3 do screen.rect(x, y, 1, 1) end
  end
  screen.fill()
end

local function draw_group1_pane()
  if mod_open and modrack.view() == "empty" then modrack.draw_empty(); return end
  screen.clear()
  -- Group 1 shows Tune | Count; the mod sources appear only in the rack editor, one at a time.
  local p       = view_pane[1]
  local is_left = (p % 2) == 1
  local src     = RACK_PANES[p]

  if src.kind == "tune" or src.kind == "count" then
    tune.draw_half(cabinet.CAB.x, cabinet.CAB.y, is_left)
    draw_metro_half(cabinet.CAB.x + cabinet.CAB.w - cabinet.HALF_W, cabinet.CAB.y, not is_left)
    if is_left then
      draw_strip("Tune", "Reference", fmt_param("tune_ref"), B.FULL)
    else
      local ms = COUNT_STRIP[count_strip_sel]
      draw_strip("Count", ms.name, ms.fmt(params:get(ms.id)), B.FULL)
    end
  elseif src.kind == "env" then
    modrack.draw_source("env", src.idx)
    local idx       = src.idx
    local strip_idx = env.strip_sel[idx]
    local es        = env.STRIP[strip_idx]
    local id  = "env" .. idx .. es.suf
    local v1  = es.fmt(params:get(id), idx)
    local v2  = nil
    if es.suf == "_target_param" then
      local sp = v1:find(" ")
      if sp then v1, v2 = v1:sub(1, sp - 1), v1:sub(sp + 1) end
    end
    draw_strip("Sense " .. idx, es.name, v1, B.FULL, v2)
  elseif src.kind == "seq" then
    local idx       = src.idx
    local strip_idx = seq.strip_resolve(idx, seq_strip_sel[idx])
    local ss        = seq.STRIP[strip_idx]
    local sel_step  = ss.suf:match("^_step_(%d+)$")
    sel_step = sel_step and tonumber(sel_step) or nil
    modrack.draw_source("seq", idx, sel_step)
    local id  = "seq" .. idx .. ss.suf
    local v1  = ss.fmt(params:get(id), idx)
    local v2  = nil
    if ss.suf == "_target_param" then
      local sp = v1:find(" ")
      if sp then v1, v2 = v1:sub(1, sp - 1), v1:sub(sp + 1) end
    end
    draw_strip("Walk " .. idx, ss.name, v1, B.FULL, v2)
  elseif src.kind == "trig" then
    modrack.draw_source("trig", src.idx)
    local idx       = src.idx
    local strip_idx = trigs.strip_fn.resolve(idx, trigs.strip_sel[idx])
    local ts        = trigs.STRIP[strip_idx]
    local id  = "trig" .. idx .. ts.suf
    local v1  = ts.fmt(params:get(id), idx)
    draw_strip("Trigger " .. idx, ts.name, v1, B.FULL)
  else
    modrack.draw_source("lfo", src.idx)
    local idx       = src.idx
    local strip_idx = lfo.strip_resolve(idx, lfo_strip_sel[idx])
    local ls        = lfo.STRIP[strip_idx]
    local id  = "lfo" .. idx .. ls.suf
    local v1  = ls.fmt(params:get(id), idx)
    local v2  = nil
    if ls.suf == "_shape" or ls.suf == "_target_param" then
      local sp = v1:find(" ")
      if sp then v1, v2 = v1:sub(1, sp - 1), v1:sub(sp + 1) end
    end
    draw_strip("LFO " .. idx, ls.name, v1, B.FULL, v2)
  end
  screen.update()
end

local function draw_pedalboard()
  screen.clear()

  local psel = cur_pedal_sel()
  local pd   = cur_pedal()
  local p    = pd.params[pd.psel]
  local vstr = fmt_param(p.id)
  draw_strip(pd.name, params:lookup_param(p.id).name, strip_val(p.id, vstr, tap.level(p.id, sync.val_level(p.id, clock_running))))

  -- ── Two pedals, flush with the edges of the shared cabinet ───
  local OX1 = cabinet.CAB.x
  local OX2 = cabinet.CAB.x + cabinet.CAB.w - cabinet.HALF_W
  local py  = cabinet.CAB.y

  if view_pane[3] >= 3 then
    local fk3 = (psel == 3) and pd.psel or nil
    local fk4 = (psel == 4) and pd.psel or nil
    sprites.draw_pedal(OX1, py, PEDALS[3].name, params:get(PEDALS[3].enable_id) == 1, fk3)
    sprites.draw_pedal(OX2, py, PEDALS[4].name, params:get(PEDALS[4].enable_id) == 1, fk4)
  else
    local fk1 = (psel == 1) and pd.psel or nil
    local fk2 = (psel == 2) and pd.psel or nil
    sprites.draw_pedal(OX1, py, PEDALS[1].name, params:get(PEDALS[1].enable_id) == 1, fk1)
    sprites.draw_pedal(OX2, py, PEDALS[2].name, params:get(PEDALS[2].enable_id) == 1, fk2)
  end

  screen.update()
end

local function draw_looper_pane()
  looper_ui.draw_pane()
end

local PERF_DEVICES = {
  { abbr="TUN", name="Tune",     enable="tune_mute", active=function() return tune.muted end,
    params={"tune_ref"} },
  { abbr="CUT", name="Cut",       enable="cut_enable", sprite="cut",
    params={"cut_thresh","cut_attack","cut_hold","cut_release","cut_range","cut_hyst","cut_detect"} },
  { abbr="FRY", name="Fray",      enable="fray_enable", sprite="fray",
    params={"fray_drive","fray_comp","fray_stab","fray_octave","fray_octave_mode","fray_gate","fray_tone","fray_volume"} },
  { abbr="PSH", name="Push",      enable="push_enable",
    params={"push_gain","push_tone","push_level","push_comp"} },
  { abbr="DST", name="Distort",   enable="distort_enable",
    params={"distort_gain","distort_tone","distort_level","distort_lowcut"} },
  { abbr="WRP", name="Warp",      enable="warp_enable",
    params={"warp_rate","warp_depth","warp_rise","warp_mix","warp_sync_div","warp_sync_feel"} },
  { abbr="RPT", name="Repeat",    enable="repeat_enable",
    params={"repeat_time","repeat_feedback","repeat_level","repeat_characteristic","repeat_mod_depth","repeat_mod_rate","repeat_sync_div","repeat_sync_feel"} },
  { abbr="AMP", name="Amp",       enable="amp_enable",
    params={"amp_volume","amp_bass","amp_treble","amp_master"},
    params_int={"amp_volume","amp_bass","amp_treble","amp_master"},
    params_nam={"amp_model","amp_volume","amp_bass","amp_mid","amp_treble","amp_master"},
    params_strip=chstrip.IDS },
  { abbr="TRM", name="Tremolo",   enable="tremolo_enable",
    params={"tremolo_intensity","tremolo_speed","tremolo_sync_div","tremolo_sync_feel"} },
  { abbr="HD1", name="Hold 1",    enable="hold1_enable", parallel=true,
    params={"hold1_size","hold1_density","hold1_spread","hold1_move","hold1_pitch","hold1_pmix","hold1_rev","hold1_shape","hold1_interp","hold1_gain","hold1_level","hold1_rise","hold1_fall"} },
  { abbr="HD2", name="Hold 2",    enable="hold2_enable",
    params={"hold2_size","hold2_density","hold2_spread","hold2_move","hold2_pitch","hold2_pmix","hold2_rev","hold2_shape","hold2_interp","hold2_gain","hold2_level","hold2_rise","hold2_fall"} },
  { abbr="LOP", name="Loop",    active=function() return looper.state ~= looper.IDLE end,
    params={"looper_medium","looper_wear","looper_direction","looper_dub_level","looper_level","looper_fade_level","looper_speed","looper_quant_div","looper_quant_feel"} },
  { abbr="RVB", name="Reverb",    enable="reverb_enable",
    params={"reverb_amount","reverb_length","reverb_low_shelf","reverb_high_shelf"} },
  { abbr="CAB", name="Cab & Mic", enable="cab_mode",
    params={"mic_position","cab_level"} },
  { abbr="TPE", name="Tape",      enable="tape_enable", sprite="tape",
    params={"tape_speed","tape_drive","tape_bias","tape_hiss","tape_wow","tape_mag","tape_azimuth","tape_down","tape_up"} },
  { abbr="BLD", name="Build",     enable="bld_enable", sprite="build",
    params={"bld_ratio","bld_block","bld_time","bld_fb","bld_octave","bld_smear","bld_xfeed","bld_mix"} },
  { abbr="MSM", name="Mesmerize",   enable="evp_enable", sprite="envelop",
    params={"evp_size","evp_predelay","evp_decay","evp_damping","evp_tilt","evp_mix"} },
}

local PERF_INDEX_OF = {}
for i, dev in ipairs(PERF_DEVICES) do PERF_INDEX_OF[dev.abbr] = i end

local FOCUS_DEVICE_OF = {}
local FOCUS_IDS       = {}
for di, dev in ipairs(PERF_DEVICES) do
  if dev.enable and not FOCUS_DEVICE_OF[dev.enable] then
    FOCUS_DEVICE_OF[dev.enable] = di
    FOCUS_IDS[#FOCUS_IDS + 1]   = dev.enable
  end
end
local FOCUS_LOOP = "@loop"
if PERF_INDEX_OF.LOP then
  FOCUS_DEVICE_OF[FOCUS_LOOP] = PERF_INDEX_OF.LOP
  FOCUS_IDS[#FOCUS_IDS + 1]   = FOCUS_LOOP
end
local function focus_value(id)
  if id == FOCUS_LOOP then return looper.state end
  return params:get(id)
end

local COUNT_DEVICE = { abbr="CNT", name="Count", enable="count_enable",
  params={"count_bpm","count_div","count_root","count_register","count_scale","count_degree",
          "count_scale_play","count_chords","count_level","count_length","count_position"} }

local ROUTE_DEVICE = { abbr="RTE", name="Route", enable="signal_input", sprite="route", cycle=2 + #VOICES, inverted=true,
  active=function() return true end,
  params={"signal_input","input_trim","fx_send_a_source","fx_send_a_level","fx_send_b_source","fx_send_b_level"} }

local DEV_GROUP = 4
local STUDIO_DEVICES = {
  { abbr="RTE", group=DEV_GROUP, pane=1, slot=1, wide=true },
  { abbr="TUN", group=1, pane=1 },
  { abbr="CNT", group=1, pane=2 },
  { abbr="CUT", group=DEV_GROUP, pane=2, slot=1 },
  { abbr="FRY", group=DEV_GROUP, pane=2, slot=2 },
  { abbr="PSH", group=3, pane=1 },
  { abbr="DST", group=3, pane=2 },
  { abbr="WRP", group=3, pane=3 },
  { abbr="RPT", group=3, pane=4 },
  { abbr="AMP", group=0, pane=1, cab=true },
  { abbr="TRM", group=0, pane=1, cab=true },
  { abbr="HD1", group=DEV_GROUP, pane=3, slot=1 },
  { abbr="HD2", group=DEV_GROUP, pane=3, slot=2 },
  { abbr="LOP", group=0, pane=2 },
  { abbr="RVB", group=0, pane=1, cab=true },
  { abbr="CAB", group=0, pane=1, cab=true },
  { abbr="TPE", group=DEV_GROUP, pane=4, slot=1, wide=true },
  { abbr="BLD", group=DEV_GROUP, pane=5, slot=1, rack=true },
  { abbr="MSM", group=DEV_GROUP, pane=5, slot=2, rack=true },
}
for _, e in ipairs(STUDIO_DEVICES) do
  e.dev = (e.abbr == "CNT") and COUNT_DEVICE or (e.abbr == "RTE") and ROUTE_DEVICE or PERF_DEVICES[PERF_INDEX_OF[e.abbr]]
end
local STUDIO_INDEX_OF = {}
for i, e in ipairs(STUDIO_DEVICES) do STUDIO_INDEX_OF[e.abbr] = i end

local function focus_studio_device(abbr)
  local i = STUDIO_INDEX_OF[abbr]
  if not i then return end
  studio_sel = i
  studio_apply()
end

local function focus_device(id)
  local di = FOCUS_DEVICE_OF[id]
  if not di then return end
  perf_sel = di
  focus_studio_device(PERF_DEVICES[di].abbr)
  if not mod_open then redraw() end
end

local function focus_param(id)
  if mod_open or (_menu and _menu.mode) then return end
  for di, dev in ipairs(PERF_DEVICES) do
    for idx, pid in ipairs(dev.params or {}) do
      if pid == id then
        perf_sel = di
        perf_param[di] = idx
        dev_param_sel[dev.abbr] = idx
        focus_studio_device(dev.abbr)
        redraw()
        return
      end
    end
  end
end

local function perf_active(dev)
  if dev.placeholder then return false end
  if dev.active then return dev.active() end
  return params:get(dev.enable) == 2
end
local function perf_pid()
  local dev = PERF_DEVICES[perf_sel]
  return dev.params[perf_param[perf_sel] or 1]
end

-- ── The stage chain ──────────────────────────────────────────
-- The performance view spells the instrument as a chain of abbreviations, bright for on and dim for
-- off. The layout is cached until an amp-type change adds or removes Cab & Mic, and its sizes live
-- in a table because of the locals limit.
local CHAIN = { X = cabinet.CAB.x, W = 128 - cabinet.CAB.x, LH = 9, Y0 = 8, ARROW_W = 2 }

local function draw_chain_arrow(x, y)
  screen.rect(x,     y - 4, 1, 1)
  screen.rect(x + 1, y - 3, 1, 1)
  screen.rect(x,     y - 2, 1, 1)
  screen.fill()
end

CHAIN.GAP = 3

local function chain_units(all)
  local units, i = {}, 1
  while i <= #PERF_DEVICES do
    if not all and dev_hidden(PERF_DEVICES[i].abbr) then
      i = i + 1
    elseif PERF_DEVICES[i].parallel and PERF_DEVICES[i + 1] then
      units[#units + 1] = { parts = { {d=i, pre=0}, {div=true, pre=CHAIN.GAP}, {d=i+1, pre=CHAIN.GAP} } }
      i = i + 2
    else
      units[#units + 1] = { parts = { {d=i, pre=0} } }
      i = i + 1
    end
  end
  for k, u in ipairs(units) do
    if k < #units then u.parts[#u.parts + 1] = { arrow = true, pre = CHAIN.GAP } end
  end
  return units
end

CHAIN.ROWS = { 2, 3, 3, 2, 3, 3 }

local function chain_span(units, i, j)
  local w = 0
  for k = i, j do w = w + units[k].w + ((k > i) and CHAIN.GAP or 0) end
  return w
end

local chain_cache
local function chain_layout()
  if chain_cache then return chain_cache end
  screen.font_size(8); screen.font_face(0)
  local units = chain_units()
  for _, u in ipairs(units) do
    local w = 0
    for _, p in ipairs(u.parts) do
      if p.arrow then
        p.w = CHAIN.ARROW_W
      elseif p.div then
        p.w = 1
      else
        p.text = PERF_DEVICES[p.d].abbr
        p.w    = screen.text_extents(p.text)
      end
      w = w + p.pre + p.w
    end
    u.w = w
  end
  local lines, i = {}, 1
  local function emit(a, b)
    local ln = { units = {}, w = chain_span(units, a, b) }
    for k = a, b do ln.units[#ln.units + 1] = units[k] end
    local last = units[b].parts[#units[b].parts]
    ln.trail = last.arrow and (last.pre + last.w) or 0
    lines[#lines + 1] = ln
  end
  local rows = { table.unpack(CHAIN.ROWS) }
  for k, u in ipairs(chain_units(true)) do
    for _, p in ipairs(u.parts) do
      if p.d and dev_hidden(PERF_DEVICES[p.d].abbr) then
        local r, acc = 1, 0
        while CHAIN.ROWS[r] and acc + CHAIN.ROWS[r] < k do acc = acc + CHAIN.ROWS[r]; r = r + 1 end
        if rows[r] then rows[r] = rows[r] - 1 end
      end
    end
  end
  for _, count in ipairs(rows) do
    if i > #units then break end
    local j = math.min(i + count - 1, #units)
    emit(i, j)
    i = j + 1
  end
  if i <= #units then emit(i, #units) end
  chain_cache = lines
  return lines
end

local function draw_chain()
  local lines = chain_layout()
  screen.font_size(8); screen.font_face(0)
  local y0 = CHAIN.Y0
  for li, ln in ipairs(lines) do
    -- every row is centred as if it ended in an arrow, so the last row lines up with the rest
    local x = math.floor(CHAIN.X + (CHAIN.W - ln.w + ln.trail - CHAIN.GAP - CHAIN.ARROW_W) / 2 + 0.5)
    local y = y0 + (li - 1) * CHAIN.LH
    for ui, u in ipairs(ln.units) do
      if ui > 1 then x = x + CHAIN.GAP end
      for _, p in ipairs(u.parts) do
        x = x + p.pre
        if p.arrow then
          screen.level(B.MED)
          draw_chain_arrow(x, y)
        elseif p.div then
          screen.level(B.MED)
          screen.rect(x, y - 5, 1, 5); screen.fill()
        else
          screen.level(perf_active(PERF_DEVICES[p.d]) and B.FULL or B.MED)
          screen.move(x, y); screen.text(p.text)
          if p.d == perf_sel then
            screen.level(B.FULL)
            screen.rect(x - 2, y - 5, 1, 1); screen.fill()
          end
        end
        x = x + p.w
      end
    end
  end
end

local function draw_performance()
  screen.clear()
  local dev = PERF_DEVICES[perf_sel]
  if dev.abbr == "LOP" then
    local li = perf_param[perf_sel] or 1
    local lp = LOOPER_DEF[li]
    draw_strip(lp.cat, params:lookup_param(lp.id).name, strip_val(lp.id, fmt_def_val(LOOPER_DEF, li), sync.val_level(lp.id, clock_running)))
  elseif dev.abbr == "TUN" then
    local cx  = cabinet.LEFT_CX
    local tlv = tune.muted and B.FULL or B.MED
    screen.font_size(8); screen.font_face(0)
    screen.level(B.MED); screen.move(cx, 8); screen.text_center("Tune")
    screen.font_size(16); screen.level(tlv)
    screen.move(cx, 27); screen.text_center(tune.note)
    screen.font_size(8)
    if tune.note ~= "--" then
      screen.level(tlv)
      screen.move(cx + 11, 17); screen.text(tostring(tune.octave))
      tune.draw_strobe(cx, 32, true)
    end
  else
    local pid = perf_pid()
    if pid then
      draw_strip(dev.name, params:lookup_param(pid).name, strip_val(pid, fmt_param(pid), tap.level(pid, B.FULL)))
    else
      draw_strip(dev.name, "Not built", "--", B.MED)
    end
  end
  draw_chain()
  screen.update()
end

local function perf_enc(n, d)
  if n == 1 then
    perf_sel = step_visible(perf_sel, d, PERF_DEVICES)
  elseif n == 2 then
    local dev = PERF_DEVICES[perf_sel]
    if #dev.params > 0 then
      perf_param[perf_sel] = util.clamp((perf_param[perf_sel] or 1) + util.clamp(d, -1, 1), 1, #dev.params)
    end
  elseif n == 3 then
    local pid = perf_pid()
    if pid then edit_param(pid, d) end
  end
  if refresh_tune then refresh_tune() end
  redraw()
end

-- ── Hold: the grains ─────────────────────────────────────────
-- Hold's grains are small strokes drifting over the waveform, each swelling, fading and brightening
-- the column it passes. The picture tells rather than measures, since Lua rolls its own grains from
-- the engine's knobs.
local GRAIN_MAX = 20
local hold_grains = { {}, {} }

-- Creates the Hold pads' polls and returns them per pad. Whether they run is up to the poll
-- guard in init (only while the pad is on).
local function hold_polls_make()
  local by_pad = { {}, {} }
  for idx = 1, 2 do
    for _, name in ipairs({ "size", "density", "spread" }) do
      local pl = poll.set("hold" .. idx .. "_" .. name .. "_m", function(v) hold_live[idx][name] = v end)
      pl.time = 1 / 15
      table.insert(by_pad[idx], pl)
    end
  end
  return by_pad
end

local function hold_value(idx, name)
  return hold_live[idx][name] or HOLD_E[name](params:get("hold" .. idx .. "_" .. name))
end

local function hold_grain_tick(idx)
  local p  = "hold" .. idx .. "_"
  if params:get(p .. "enable") ~= 2 then hold_grains[idx] = {}; hold_live[idx] = {}; return end
  local g       = hold_grains[idx]
  local density = hold_value(idx, "density")
  local size    = hold_value(idx, "size")
  local spread  = hold_value(idx, "spread") * 0.1
  local pitch   = params:get(p .. "pitch")
  local pmix    = params:get(p .. "pmix") * 0.01
  local rev     = params:get(p .. "rev") * 0.01
  local want    = util.clamp(math.floor(3 + density * 1.6), 1, GRAIN_MAX)
  local band    = 2 + spread * 18

  for i = #g, 1, -1 do
    local q = g[i]
    q.age = q.age + 1
    q.x   = q.x + q.vx
    if q.age > q.ttl or q.x < 1 or q.x > 31 then table.remove(g, i) end
  end
  local born = 0
  while #g < want and born < 3 do
    local back = math.random() < rev
    local mid  = (math.random() < pmix) and (23 - (pitch / 24) * 16) or 23
    g[#g + 1] = {
      x   = back and (22 + math.random() * 8) or (2 + math.random() * 8),
      y   = util.clamp(mid + (math.random() - 0.5) * band, 2, 44),
      vx  = back and -0.5 or 0.5,
      len = 1 + math.floor(size * 0.6 + 0.5),
      age = 0,
      ttl = math.floor(6 + size * 2),
    }
    born = born + 1
  end
end

local hold_wave = { {}, {} }
local hold_scope = { peaks = {} }

-- Hold in the 37 x 60 box: the window with grains drifting over the waveform on top, then the
-- param dots and icon, the footswitch at the bottom. The frame lights when this Hold is
-- selected, the rocker while it holds.
local function draw_hold_grains(x, y, idx, focused, dev)
  local ox, oy = x, y - 1
  local lv = focused and B.FULL or B.MED
  local on = params:get("hold" .. idx .. "_enable") == 2
  cabinet.frame(ox, oy, cabinet.HALF_W, cabinet.H, lv)
  screen.level(1); screen.rect(ox + 3, oy + 3, 31, 26); screen.fill()
  screen.level(on and B.FULL or 4)
  screen.rect(ox + 2, oy + 2, 33, 1); screen.rect(ox + 2, oy + 29, 33, 1)
  screen.rect(ox + 2, oy + 3, 1, 26); screen.rect(ox + 34, oy + 3, 1, 26); screen.fill()
  local cols, mid = {}, oy + 15
  if on then
    local peak = 3 + math.min(control.amp(params:get("hold" .. idx .. "_level")), 2) * 6
    for _, q in ipairs(hold_grains[idx]) do
      local t   = q.age / q.ttl
      local env = (t < 0.3) and (t / 0.3) or ((1 - t) / 0.7)
      local glv = math.floor(peak * env + 0.5)
      local step = (q.vx > 0) and 1 or -1
      for k = 0, q.len - 1 do
        local c = math.floor((math.floor(q.x) - k * step - 1) * 26 / 30 + 0.5)
        if c >= 0 and c <= 26 and glv > (cols[c] or 0) then cols[c] = glv end
      end
    end
  end
  local w = on and hold_wave[idx] or hold_scope.peaks
  for c = 0, 26 do
    local db = 20 * math.log(math.max(w[c + 1] or 0, 1e-6), 10)
    local h = math.floor(util.clamp((db + 48) / 48, 0, 1) * 12 + 0.5)
    screen.level(math.max(3, cols[c] or 0))
    screen.rect(ox + 5 + c, mid - h, 1, 2 * h + 1); screen.fill()
  end
  local sel = dev_param_sel[dev.abbr] or 1
  for k = 1, #dev.params do
    local r, i = (k <= 7) and 0 or 1, (k <= 7) and (k - 1) or (k - 8)
    screen.level(k == sel and B.FULL or 3)
    screen.rect(ox + 5 + i * 3 + r, oy + 32 + r * 3, 2, 2); screen.fill()
  end
  screen.level(lv)
  screen.rect(ox + 28, oy + 32, 3, 1); screen.rect(ox + 27, oy + 33, 5, 3); screen.rect(ox + 28, oy + 36, 3, 1); screen.fill()
  -- The footswitch as on Fray: a grey plate on top, below it the rocker, lit while Hold holds.
  local px, py = ox + 3, oy + 39
  screen.level(B.MED)
  screen.rect(px, py, 31, 1); screen.rect(px, py + 17, 31, 1)
  screen.rect(px, py + 1, 1, 16); screen.rect(px + 30, py + 1, 1, 16); screen.fill()
  screen.level(4); screen.rect(px + 2, py + 2, 27, 1); screen.fill()
  screen.level(3); screen.rect(px + 2, py + 3, 27, 2); screen.fill()
  screen.level(on and B.FULL or B.MED)
  for k = 0, 9 do
    local yy = py + 6 + k
    if k % 4 == 3 then screen.rect(px + 2, yy, 1, 1); screen.rect(px + 28, yy, 1, 1)
    else screen.rect(px + 2, yy, 27, 1) end
  end
  screen.fill()
end

-- ── Tape: transport and reels ────────────────────────────────
-- Tape is a machine you can stop, with K2 spinning the transport down and up at the inertia set by
-- Up and Down. The reels turn at that rate, each built once as a point set so only its spokes move.
local tape = { running = true, rate = 1, angle = 0 }
tape.REV = { 0.35, 0.7, 1.4 }

function tape.toggle()
  tape.running = not tape.running
  engine.tape_run(tape.running and 1 or 0)
  redraw()
end

function tape.tick(dt)
  if tape.running and params:get("tape_enable") == 2 then
    tape.rate = tape.rate + (1 - tape.rate) * (1 - math.exp(-dt * 4.16 / math.max(params:get("tape_up"), 0.05)))
  else
    tape.rate = math.max(0, tape.rate - dt / math.max(params:get("tape_down"), 0.05))
  end
  tape.angle = (tape.angle + tape.rate * tape.REV[params:get("tape_speed")] * dt * 2 * math.pi) % (2 * math.pi)
end

tape.REELS = { { cx = 20, cy = 19, pack = 9 }, { cx = 59, cy = 19, pack = 5.5 } }
tape.SPOKE = math.rad(8)
tape.LED_DB = { -42, -33, -26, -20, -14, -8 }
tape.lvl = { 0, 0, 0, 0 }

local function tape_reel_build(r)
  r.runs, r.spoke = {}, {}
  for dy = -12, 12 do
    for dx = -12, 12 do
      local d = math.sqrt(dx * dx + dy * dy)
      if d <= 11.5 then
        local lv
        if d > 10.5 then lv = 5
        elseif d < 1 then lv = 0
        elseif d < 2.5 then lv = dy < 0 and 8 or (dy > 0 and 3 or 5)
        elseif d < r.pack - 1 then lv = 2
        elseif d < r.pack then lv = 4
        else lv = 1 end
        if lv > 0 then
          r.runs[lv] = r.runs[lv] or {}
          table.insert(r.runs[lv], { dx, dy })
        end
        if d > 2.5 and d < 10.5 then table.insert(r.spoke, { dx, dy, math.atan(dy, dx) }) end
      end
    end
  end
end

local function draw_tape_reels(x, y)
  for i, r in ipairs(tape.REELS) do
    if not r.runs then tape_reel_build(r) end
    for lv, pts in pairs(r.runs) do
      screen.level(lv)
      sprite.rects(pts, x + r.cx, y + r.cy)
      screen.fill()
    end
    screen.level(B.MED)
    local rot = tape.angle + (i - 1) * 0.7
    for _, q in ipairs(r.spoke) do
      for k = 0, 2 do
        local dt = (q[3] - rot - k * 2 * math.pi / 3 + math.pi) % (2 * math.pi) - math.pi
        if math.abs(dt) < tape.SPOKE then screen.rect(x + r.cx + q[1], y + r.cy + q[2], 1, 1) break end
      end
    end
    screen.fill()
  end
  local on = params:get("tape_enable") == 2 and tape.running
  for ch = 1, 4 do
    local db = 20 * math.log(math.max(tape.lvl[ch], 1e-6), 10)
    local lx = (ch <= 2 and 7 or 70) + ((ch - 1) % 2) * 3
    for k = 1, 6 do
      local lit = on and db > tape.LED_DB[k]
      screen.level(lit and (k >= 5 and B.FULL or 8) or 2)
      screen.rect(x + lx, y + 52 - k * 2, 2, 1); screen.fill()
    end
  end
end

-- Build shows its two lines as two bands of level columns, the newest entering on the left. Each
-- column holds the loudest level of one eleventh of the line time, so the picture crosses once per
-- trip around the line.
local bld_lv = { hist = { {}, {} }, acc = { 0, 0 }, t = { 0, 0 } }
bld_lv.RAILS = { [3] = 17, [4] = 21, [5] = 60, [6] = 64, [7] = 68, [8] = 72 }
bld_lv.FADER_ID = { [3] = "bld_time", [4] = "bld_fb", [5] = "bld_octave", [6] = "bld_smear", [7] = "bld_xfeed", [8] = "bld_mix" }
bld_lv.COLS = 11

local function bld_line_ms()
  local q  = BLD_RATIOS[params:get("bld_ratio")]
  local ms = bld_ms(params:get("bld_block"), params:get("bld_time"))
  local m  = math.max(q[1], math.abs(q[2]))
  return { ms * q[1] / m, ms * math.abs(q[2]) / m }, q[2] < 0
end

local function bld_level_in(k, v, dt)
  if params:get("bld_enable") ~= 2 or params:get("bld_freeze") == 2 then return end
  local h  = bld_lv.hist[k]
  local iv = bld_line_ms()[k] / 1000 / bld_lv.COLS
  if iv < dt then
    for c = 1, bld_lv.COLS do h[c] = v end
    return
  end
  bld_lv.acc[k] = math.max(bld_lv.acc[k], v)
  bld_lv.t[k] = bld_lv.t[k] + dt
  if bld_lv.t[k] >= iv then
    table.insert(h, 1, bld_lv.acc[k])
    h[bld_lv.COLS + 1] = nil
    bld_lv.acc[k], bld_lv.t[k] = 0, 0
  end
end

local function draw_build_overlay(x, y, focus_knob)
  local on  = params:get("bld_enable") == 2
  local frz = params:get("bld_freeze") == 2
  for k, id in pairs(bld_lv.FADER_ID) do
    local rx  = bld_lv.RAILS[k]
    local cy  = 21 - math.floor(params:get_raw(id) * 15 + 0.5)
    screen.level(focus_knob == k and B.FULL or B.MED)
    screen.rect(x + rx - 1, y + cy - 1, 3, 2); screen.fill()
    screen.level(3)
    screen.rect(x + rx - 1, y + cy + 1, 3, 1); screen.fill()
  end
  screen.level(frz and B.FULL or 2)
  screen.rect(x + 9, y + 13, 3, 2); screen.fill()
  local _, rev = bld_line_ms()
  for col = 0, bld_lv.COLS - 1 do
    for row = 0, 5 do
      local k   = row < 3 and 1 or 2
      local idx = (k == 2 and rev) and (bld_lv.COLS - col) or (col + 1)
      local v   = on and (bld_lv.hist[k][idx] or 0) or 0
      local db  = 20 * math.log(math.max(v, 1e-6), 10)
      local n   = util.clamp(math.ceil((db + 48) / 16), 0, 3)
      local d   = k == 1 and (2 - row) or (row - 3)
      local lv  = 2
      if d < n then lv = ({ 13, 9, 6 })[d + 1] end
      if frz and lv > 2 then lv = math.max(3, lv - 6) end
      screen.level(lv)
      screen.rect(x + 25 + col * 3, y + 5 + row * 3 + (row >= 3 and 1 or 0), 2, 2); screen.fill()
    end
  end
end

-- Mesmerize paints its reverb as rings on water: every 0.45 s, depending on the level the
-- engine reports, a drop falls and draws a flat ring that grows and fades. Size makes the rings
-- faster, Decay lets them linger, Freeze holds them in place.
local evp = { rings = {}, spawn = 0, level = 0 }

local function evp_tick(dt)
  if params:get("evp_freeze") == 2 then return end
  local size  = (10 + params:get("evp_size") * 2.9) / 100
  local decay = params:get("evp_decay") / 100
  local speed = 8 * (0.5 + size * 0.5)
  local fade  = math.exp(-dt * (4 - 3.6 * decay))
  local keep  = {}
  for _, r in ipairs(evp.rings) do
    r.r = r.r + speed * dt
    r.a = r.a * fade
    if r.r < 22 and r.a > 0.04 then keep[#keep + 1] = r end
  end
  evp.rings = keep
  evp.spawn = evp.spawn - dt
  if evp.spawn <= 0 then
    evp.spawn = 0.45
    local db = 20 * math.log(math.max(evp.level, 1e-6), 10)
    local a  = util.clamp((db + 60) / 45, 0, 1)
    if a > 0.05 then table.insert(evp.rings, { r = 0.5, a = a }) end
  end
end

local function draw_envelop_overlay(x, y)
  local x0, y0, x1, y1 = x + 25, y + 5, x + 56, y + 22
  screen.level(params:get("evp_freeze") == 2 and B.FULL or 2)
  screen.rect(x + 9, y + 13, 3, 2); screen.fill()
  screen.level(params:get("evp_enable") == 2 and B.FULL or 3)
  screen.rect(x0 - 1, y0 - 1, x1 - x0 + 3, 1); screen.fill()
  screen.rect(x0 - 1, y1 + 1, x1 - x0 + 3, 1); screen.fill()
  screen.rect(x0 - 1, y0, 1, y1 - y0 + 1); screen.fill()
  screen.rect(x1 + 1, y0, 1, y1 - y0 + 1); screen.fill()
  local cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
  for _, r in ipairs(evp.rings) do
    local lv = math.floor(2 + r.a * 13 + 0.5)
    if r.a > 0.04 then
      screen.level(lv)
      local n = math.max(8, math.floor(r.r * 5))
      for k = 0, n - 1 do
        local t  = k * 2 * math.pi / n
        local px = math.floor(cx + r.r * math.cos(t) + 0.5)
        local py = math.floor(cy + r.r * 0.55 * math.sin(t) + 0.5)
        if px >= x0 and px <= x1 and py >= y0 and py <= y1 then screen.rect(px, py, 1, 1); screen.fill() end
      end
    end
  end
end

-- Route reads top to bottom, the way the signal flows, from the input on the left down to the sends
-- A and B. It uses only straight lines and right angles, and where wires cross the horizontal line
-- leaves a gap.
local ROUTE = {
  GLYPH = { L = { "#..", "#..", "#..", "#..", "###" }, R = { "##.", "#.#", "##.", "#.#", "#.#" },
            A = { ".#.", "#.#", "###", "#.#", "#.#" }, B = { "##.", "#.#", "##.", "#.#", "##." },
            v = { "#.#", ".#." },
            jack  = { ".###.", "#...#", "#.#.#", "#...#", ".###." },
            voice = { "#############", "#..###.###..#", "#..###.###..#", "#..###.###..#",
                      "#...#...#...#", "#...#...#...#", "#############" },
            dn  = { "#...#", ".#.#.", "..#.." },
            inf = { ".#...#.", "#.#.#.#", ".#...#." },
            up  = { "..#..", ".#.#.", "#...#" } },
  SRC     = { "dn", "inf", "up" },     -- input, loop, output (fx_send_*_source 1..3)
  SRC_COL = { 6, 19, 32 },
  OUT_COL = { 11, 28 },
  TOP = 6, KNEE = 28, BOT = 45,
}

local function draw_route(x, y)
  local G = ROUTE.GLYPH
  local L0, R0 = x + 1, x + 42
  local T, K, BT = y + ROUTE.TOP, y + ROUTE.KNEE, y + ROUTE.BOT
  local function glyph(g, gx, gy)
    for j, row in ipairs(G[g]) do
      for i = 1, #row do
        if row:sub(i, i) == "#" then screen.rect(gx + i - 1, gy + j - 1, 1, 1) end
      end
    end
  end
  local function vline(cx, a, b) screen.rect(cx, math.min(a, b), 1, math.abs(b - a) + 1) end
  local function hline(a, b, ry) screen.rect(math.min(a, b), ry, math.abs(b - a) + 1, 1) end

  screen.level(0)
  for k, c in ipairs(ROUTE.OUT_COL) do
    glyph("v", L0 + c - 1, BT + 1); glyph(("LR"):sub(k, k), L0 + c - 1, BT + 4)
    glyph("v", R0 + c - 1, BT + 1); glyph(("AB"):sub(k, k), R0 + c - 1, BT + 4)
  end
  local sig = params:get("signal_input")
  if sig == 2 then
    for _, c in ipairs(ROUTE.OUT_COL) do glyph("jack", L0 + c - 2, T); vline(L0 + c, T + 6, BT) end
  else
    local mid = math.floor((ROUTE.OUT_COL[1] + ROUTE.OUT_COL[2]) / 2)
    -- A voice sits as a small keyboard above the line; it is taller than the jack, so it grows
    -- upward to keep the line starting at the same spot.
    if sig == 1 then glyph("jack", L0 + mid - 2, T) else glyph("voice", L0 + mid - 6, T - 2) end
    vline(L0 + mid, T + 6, K); hline(L0 + ROUTE.OUT_COL[1], L0 + ROUTE.OUT_COL[2], K)
    for _, c in ipairs(ROUTE.OUT_COL) do vline(L0 + c, K, BT) end
  end
  screen.fill()

  -- Every glyph up here shares the jack's baseline, one row above where the lines begin, so
  -- exactly one pixel stays free beneath each.
  local srcs = { params:get("fx_send_a_source"), params:get("fx_send_b_source") }
  for s, c in ipairs(ROUTE.SRC_COL) do
    local g = G[ROUTE.SRC[s]]
    screen.level((s == srcs[1] or s == srcs[2]) and 0 or sprites_device.INV.KNOB)
    glyph(ROUTE.SRC[s], R0 + c - math.floor(#g[1] / 2), T + 5 - #g)
    screen.fill()
  end
  local path, knee, verts = {}, {}, {}
  for k = 1, 2 do path[k] = { R0 + ROUTE.SRC_COL[srcs[k]], R0 + ROUTE.OUT_COL[k] } end
  local function span(p) return math.min(p[1], p[2]), math.max(p[1], p[2]) end
  local a0, a1 = span(path[1])
  local b0, b1 = span(path[2])
  local overlap = path[1][1] ~= path[2][1] and a0 <= b1 and b0 <= a1
  knee[1], knee[2] = overlap and K - 2 or K, overlap and K + 2 or K
  for k = 1, 2 do verts[k] = { { path[k][1], T + 6, knee[k] }, { path[k][2], knee[k], BT } } end
  screen.level(0)
  for k = 1, 2 do
    for _, v in ipairs(verts[k]) do vline(v[1], v[2], v[3]) end
  end
  for k = 1, 2 do
    local lo, hi = span(path[k])
    for gx = lo, hi do
      local gap = false
      for _, v in ipairs(verts[3 - k]) do
        if v[1] > lo and v[1] < hi and v[2] < knee[k] and knee[k] < v[3] and math.abs(gx - v[1]) <= 1 then gap = true end
      end
      if not gap then screen.rect(gx, knee[k], 1, 1) end
    end
  end
  screen.fill()
end

local function draw_device_body(x, y, w, h, dev, focused, focus_knob, idx, rack)
  if dev.inverted then
    screen.level(focused and sprites_device.INV.BG or sprites_device.INV.BG_DIM)
    screen.rect(x, y - 1, w, h); screen.fill()
  end
  if dev.sprite then
    sprites_device.draw(dev.sprite, x, rack and y or (y - 1), perf_active(dev), focus_knob, dev.inverted, focused)
    if dev.sprite == "route" then draw_route(x, y - 1) end
    if dev.sprite == "tape" then draw_tape_reels(x, y - 1) end
    if dev.sprite == "build" then draw_build_overlay(x, rack and y or (y - 1), focus_knob) end
    if dev.sprite == "envelop" then draw_envelop_overlay(x, rack and y or (y - 1)) end
    return
  end
  if idx then draw_hold_grains(x, y, idx, focused, dev) end
end

local function draw_device_pane()
  screen.clear()
  local e   = STUDIO_DEVICES[studio_sel]
  local dev = e.dev
  local pid = dev.params[dev_param_sel[e.abbr] or 1]
  if pid then
    draw_strip(dev.name, params:lookup_param(pid).name, strip_val(pid, fmt_param(pid), B.FULL))
  else
    draw_strip(dev.name, "Not built", "--", B.MED)
  end

  local c = cabinet.CAB
  for _, o in ipairs(STUDIO_DEVICES) do
    if o.group == DEV_GROUP and o.pane == e.pane then
      local focused = (o.abbr == e.abbr)
      local fk  = focused and (dev_param_sel[o.abbr] or 1) or nil
      local hix = (o.abbr == "HD1" and 1) or (o.abbr == "HD2" and 2) or nil
      if o.wide then
        draw_device_body(c.x, c.y, c.w, cabinet.H, o.dev, focused, fk, nil, false)
      elseif o.rack then
        local h = math.floor((c.h - 4) / 2)
        local nudge = (o.slot == 1) and 1 or 0
        draw_device_body(c.x, c.y + (o.slot - 1) * (h + 4) - nudge, c.w, h, o.dev, focused, fk, nil, true)
      else
        local x = (o.slot == 1) and c.x or (c.x + c.w - cabinet.HALF_W)
        draw_device_body(x, c.y, cabinet.HALF_W, cabinet.H, o.dev, focused, fk, hix, false)
      end
    end
  end
  screen.update()
end

function redraw()
  if initing then return end
  strip_live = false
  if gui_mode == 3 then screen.clear(); screen.update(); return end
  -- The chooser takes the whole screen; the pane beneath needn't be drawn.
  if modrack.chooser_open() then modrack.draw_chooser(); return end
  if gui_mode == 2 then
    if mod_open then draw_group1_pane() else draw_performance() end
    return
  end
  if mod_open      then draw_group1_pane();  return end
  if view_group == 1 then draw_group1_pane(); return end
  if view_group == DEV_GROUP then draw_device_pane(); return end
  if view_group == 3 then draw_pedalboard(); return end
  if view_pane[0] == 2 then draw_looper_pane(); return end
  screen.clear()
  draw_left_strip()
  if amp_kind() == "strip" then
    local abbr = STUDIO_DEVICES[studio_sel].abbr
    if abbr == "RVB" then
      chstrip.draw_tank(params:get("reverb_enable") == 2, dev_param_sel.RVB or 1, params:get("reverb_freeze") == 2)
    else
      chstrip.draw(not amp_is_bypassed(), abbr == "AMP" and (dev_param_sel.AMP or 1) or nil)
    end
    screen.update()
    return
  end
  local neutral = amp_kind() == "nam"
  cabinet.draw_grillcloth(params:get("cab_mode"), cab_sel_id() == "mic_position", params:get("mic_position") - 1, neutral)
  cabinet.draw_panel(sel, params:get("signal_input") == 2, amp_is_bypassed(), neutral and AMP_NAM_KNOBS or nil)
  cabinet.draw_cabinet(neutral)
  screen.update()
end

local function is_tune_active()
  if mod_open then return false end
  if gui_mode == 1 then return STUDIO_DEVICES[studio_sel].abbr == "TUN" end
  if gui_mode == 2 then return PERF_DEVICES[perf_sel].abbr    == "TUN" end
  return false
end

refresh_tune = function()
  tune.set_active(is_tune_active())
  if not initing then engine.mute(params:get("tune_mute") == 2 and 1 or 0) end
end

local function set_pane(p)
  local g  = view_group
  local lo = (g == 1 and mod_open) and MOD_PANE_1 or 1
  view_pane[g] = util.clamp(p, lo, GROUP_MAX[g])
  tune.set_active(is_tune_active())
  redraw()
end

cab_sel_id = function()
  local e  = STUDIO_DEVICES[studio_sel]
  local id = e and e.dev.params[dev_param_sel[e.abbr] or 1]
  if id then return id, e.dev.name end
  return PARAMS_DEF[sel].id, PARAMS_DEF[sel].cat
end

local function cab_sync_knob(e)
  local id = e.dev.params[dev_param_sel[e.abbr] or 1]
  local d  = id and PARAM_DEF_OF[id]
  if d and d.def == PARAMS_DEF then sel = d.idx end
end

studio_apply = function()
  local e = STUDIO_DEVICES[studio_sel]
  view_group         = e.group
  view_pane[e.group] = e.pane
  if e.cab then cab_sync_knob(e) end
  tune.set_active(is_tune_active())
end

-- The rack has its own 20 Hz pulse, because LFO scopes and trigger flashes change with nobody
-- turning anything. It beats only while the rack or chooser is open and keeps still in the norns
-- menu.
local rack_beat = false
local function rack_pulse_start()
  if rack_beat then return end
  rack_beat = true
  clock.run(function()
    while mod_open or modrack.chooser_open() do
      clock.sleep(1 / 20)
      if not (_menu and _menu.mode) then redraw() end
    end
    rack_beat = false
  end)
end

-- K1 for two seconds: the rack opens the first patched source straight in the editor. If
-- nothing is patched yet, it says "Empty".
local function mod_open_toggle()
  mod_open = not mod_open
  if mod_open then
    rack_pulse_start()
    view_group   = 1
    local first  = modrack.active()[1]
    if first then modrack.show_edit() else modrack.show_empty() end
    view_pane[1] = first or math.max(view_pane[1], MOD_PANE_1)
  elseif gui_mode == 1 then
    studio_apply()
  else
    view_group = 0
  end
  tune.set_active(is_tune_active())
  redraw()
end

local function count_tick_now()
  local lvl      = 0.5 * control.amp(lfo.count.level ~= nil and lfo.count.level or params:get("count_level"))
  local length   = lfo.count.length   ~= nil and lfo.count.length        or params:get("count_length")
  local root     = lfo.count.root     ~= nil and lfo.count.root          or params:get("count_root")
  local register = lfo.count.register ~= nil and lfo.count.register      or params:get("count_register")
  if root <= 0 then return end
  local scale_idx = lfo.count.scale  ~= nil and lfo.count.scale  or params:get("count_scale")
  local play      = lfo.count.play   ~= nil and lfo.count.play   or params:get("count_scale_play")
  local kind      = lfo.count.chords ~= nil and lfo.count.chords or params:get("count_chords")
  local position  = params:get("count_position") - 1
  local base      = (register - 1) * 12 + root

  local stepping  = (scale_idx >= 2 and play >= 2)
  local degree    = 1
  if scale_idx >= 2 then
    local base_deg   = stepping and scales.play_degree(scale_idx, play, count_step) or 1
    local degree_off = (lfo.count.degree ~= nil and lfo.count.degree or params:get("count_degree")) - 1
    degree = base_deg + degree_off
  end

  for _, off in ipairs(scales.chord_tones(scale_idx, degree, kind)) do
    local p = util.clamp(base + off, 1, 108)
    engine.count_tick(lvl, p - 1 - 57, length, position)
  end

  if stepping then count_step = count_step + 1 end
  count_flash = util.time()
  if view_group == 1 and not mod_open and gui_mode == 1 and view_pane[1] <= 2 then
    redraw()
    clock.run(function() clock.sleep(0.1) redraw() end)
  end
end

local function count_clock_start()
  count_clock_gen = count_clock_gen + 1
  local my = count_clock_gen
  count_step = 0
  clock.run(function()
    if clock_running then
      clock.sync(sync.COUNT_DIV_BEATS[lfo.count.div or params:get("count_div")])
      while my == count_clock_gen do
        count_tick_now()
        clock.sync(sync.COUNT_DIV_BEATS[lfo.count.div or params:get("count_div")])
      end
    else
      while my == count_clock_gen do
        count_tick_now()
        local div = lfo.count.div or params:get("count_div")
        local bpm = params:get("count_bpm")
        clock.sleep(sync.COUNT_DIV_BEATS[div] * 60.0 / bpm)
      end
    end
  end)
end

local function count_clock_stop()
  count_clock_gen = count_clock_gen + 1
end

-- ── The mod-source strips ────────────────────────────────────
-- Sense, Walk, Trigger and LFO show one row of their insides at the bottom: E2 walks the rows
-- (skipping hidden ones), E3 turns the visible row's value, and each source only says where its
-- rows are. The fields are functions because the libraries create their tables only in init.
local mod_strip_enc = (function()
  local K = {
    env  = { prefix = "env",
             strip   = function() return env.STRIP end,
             sel     = function() return env.strip_sel end,
             advance = function(i, c, d) return env.strip_advance(i, c, d) end },
    seq  = { prefix = "seq",
             strip   = function() return seq.STRIP end,
             sel     = function() return seq_strip_sel end,
             advance = function(i, c, d) return seq.strip_advance(i, c, d) end,
             resolve = function(i, c) return seq.strip_resolve(i, c) end,
             start   = function(i) seq.start_clock(i) end },
    trig = { prefix = "trig",
             strip   = function() return trigs.STRIP end,
             sel     = function() return trigs.strip_sel end,
             advance = function(i, c, d) return trigs.strip_fn.advance(i, c, d) end,
             resolve = function(i, c) return trigs.strip_fn.resolve(i, c) end,
             start   = function(i) trigs.fn.start_clock(i) end },
    lfo  = { prefix = "lfo",
             strip   = function() return lfo.STRIP end,
             sel     = function() return lfo_strip_sel end,
             advance = function(i, c, d) return lfo.strip_advance(i, c, d) end,
             resolve = function(i, c) return lfo.strip_resolve(i, c) end,
             start   = function(i) lfo.start_clock(i) end },
  }
  return function(kind, idx, n, d)
    local k = K[kind] or K.lfo
    local sel = k.sel()
    if n == 2 then
      sel[idx] = k.advance(idx, sel[idx], d)
    elseif n == 3 then
      if k.resolve then sel[idx] = k.resolve(idx, sel[idx]) end
      local row = k.strip()[sel[idx]]
      local id  = k.prefix .. idx .. row.suf
      if row.typ == "opt" then
        local nmax = row.nmax_fn and row.nmax_fn(idx) or row.nmax
        if nmax > 0 then params:set(id, util.clamp(params:get(id) + d, 1, nmax)) end
      else
        params:delta(id, d)
      end
      if row.suf == "_sync_div" and k.start then k.start(idx) end
    end
    redraw()
  end
end)()

function enc(n, d)
  if gui_mode == 3 then return end
  if modrack.chooser_open() then modrack.chooser_enc(n, d); return end
  if mod_open and modrack.view() == "empty" then return end
  if gui_mode == 2 and not mod_open then perf_enc(n, d); return end
  if n == 1 then
    if mod_open then
      local p = modrack.neighbour(view_pane[1], d)
      if p then set_pane(p) end
    else
      studio_sel = step_visible(studio_sel, d, STUDIO_DEVICES)
      studio_apply()
      redraw()
    end
    return
  end
  if view_group == DEV_GROUP then
    local e   = STUDIO_DEVICES[studio_sel]
    local dev = e.dev
    if #dev.params > 0 then
      if n == 2 then
        dev_param_sel[e.abbr] = util.clamp((dev_param_sel[e.abbr] or 1) + util.clamp(d, -1, 1), 1, #dev.params)
      elseif n == 3 then
        edit_param(dev.params[dev_param_sel[e.abbr] or 1], d)
      end
    end
    redraw()
    return
  end
  if view_group == 1 then
    local src = RACK_PANES[view_pane[1]]
    if src.kind == "tune" then
      if n == 3 then edit_param("tune_ref", d) end
    elseif src.kind == "count" then
      if n == 2 then
        count_strip_sel = util.clamp(count_strip_sel + d, 1, #COUNT_STRIP)
        redraw()
      elseif n == 3 then
        local ms = COUNT_STRIP[count_strip_sel]
        if ms.typ == "opt" then
          params:set(ms.id, util.clamp(params:get(ms.id) + d, 1, ms.nmax))
        else
          params:delta(ms.id, d)
        end
        redraw()
      end
    else
      mod_strip_enc(src.kind, src.idx, n, d)
    end
    return
  end

  if view_group == 3 then
    if n == 2 then
      cur_pedal().psel = util.clamp(cur_pedal().psel + d, 1, #cur_pedal().params)
      redraw()
    elseif n == 3 then
      local pd = cur_pedal()
      edit_param(pd.params[pd.psel].id, d)
      redraw()
    end
    return
  end

  if view_pane[0] == 2 then
    looper_ui.enc(n, d)
    return
  end

  local e = STUDIO_DEVICES[studio_sel]
  if n == 2 then
    -- E2 selects knob by knob, as in the other panes: fast turning skips none.
    dev_param_sel[e.abbr] = util.clamp((dev_param_sel[e.abbr] or 1) + util.clamp(d, -1, 1), 1, #e.dev.params)
    cab_sync_knob(e)
    redraw()
  elseif n == 3 then
    edit_param(e.dev.params[dev_param_sel[e.abbr] or 1], d)
    redraw()
  end
end

local function long_press(key, z, fn_long, fn_short)
  if z == 1 then
    k_clock[key] = clock.run(function()
      clock.sleep(2.0)
      k_clock[key] = nil
      fn_long()
    end)
  else
    if k_clock[key] ~= nil then
      clock.cancel(k_clock[key])
      k_clock[key] = nil
      if fn_short then fn_short() end
    end
  end
end

-- ── Keys in the rack ─────────────────────────────────────────
local function mod_rack_randomize()
  local src = RACK_PANES[view_pane[1]]
  if src.kind == "lfo" or src.kind == "seq" then
    params:set(src.kind .. src.idx .. "_randomize", 1)
  end
end

-- K2 in the rack is a source's secondary function: an LFO restarts, a Sense freezes (or thaws)
-- its modulation, a Walk jumps to step 1, a Trigger fires by hand.
local function mod_rack_secondary()
  local src = RACK_PANES[view_pane[1]]
  if src.kind == "lfo" then lfo.reset(src.idx)
  elseif src.kind == "env" then params:set("env" .. src.idx .. "_freeze", 3 - params:get("env" .. src.idx .. "_freeze"))
  elseif src.kind == "seq" then seq.reset(src.idx)
  elseif src.kind == "trig" then trigs.fn.fire(src.idx) end
  redraw()
end

local function mod_rack_toggle()
  local src = RACK_PANES[view_pane[1]]
  if src.idx then
    local id = src.kind .. src.idx .. "_enable"
    params:set(id, 3 - params:get(id))
  end
end

-- K3 turns every device on and off (the looper takes its transport from it), while K2 is the
-- device's secondary. The drives leave K2 free, and Route keeps both keys silent, being a place for
-- settings.
local function toggle_param(id) params:set(id, 3 - params:get(id)) end

local K2_SHORT = {
  TPE = function() tape.toggle() end,
  BLD = function() toggle_param("bld_freeze") end,
  MSM = function() toggle_param("evp_freeze") end,
  RVB = function() toggle_param("reverb_freeze") end,
  HD1 = function() engine.hold_recapture(1) end,
  HD2 = function() engine.hold_recapture(2) end,
  TUN = function() params:set("tune_ref", 440) end,
  CAB = function() params:set("mic_position", params:get("mic_position") % #MIC_NAMES + 1) end,
  AMP = function()
    local v = params:get("amp_type") % 3 + 1
    if v == 2 and not nam.available() then v = 3 end
    params:set("amp_type", v)
  end,
}

local function device_key(dev, n, z)
  local function transport(fn)
    if dev.abbr ~= "LOP" then focus_absorb["@loop"] = true end
    fn()
  end
  if dev.abbr == "RTE" then return end
  if n == 2 and tap.DEV[dev.abbr] then
    if z == 1 then
      local prefix = tap.DEV[dev.abbr]
      -- Focus jumps to the tapped value so you can see what the tap does.
      if view_group == 3 then cur_pedal().psel = 1
      elseif dev.abbr == "CNT" then count_strip_sel = 1
      else
        local pi = 1
        for i, id in ipairs(dev.params) do if id == tap.ID[prefix] then pi = i end end
        if gui_mode == 2 then perf_param[perf_sel] = pi else dev_param_sel[dev.abbr] = pi end
      end
      tap.hit(prefix)
    end
  elseif n == 2 and dev.abbr == "CUT" then
    -- A kill switch: muted while K2 is held.
    engine.mute((z == 1 or params:get("tune_mute") == 2) and 1 or 0)
  elseif n == 2 and K2_SHORT[dev.abbr] then
    long_press("k2", z, function() end, K2_SHORT[dev.abbr])
  elseif n == 2 and dev.abbr == "LOP" then
    long_press("k2", z, function() transport(looper.undo) end, function() transport(looper.stop_clear) end)
  elseif n == 3 and dev.abbr == "LOP" then
    -- The looper steps on the press, so a take starts and ends where the finger lands.
    if z == 1 then transport(looper.step) end
  elseif n == 3 then
    long_press("k3", z, function() end, function()
      if dev.enable then toggle_param(dev.enable) end
    end)
  end
end

-- In the rack as on any device: K3 toggles the source, a short K2 is its secondary
-- (mod_rack_secondary), a held K2 re-rolls (Stepped Random, Walk). K1 leads out as it led in,
-- and on an "Empty" rack K2 does too.
local function key_group1(n, z)
  local empty = modrack.view() == "empty"
  if n == 2 then
    if empty then long_press("k2", z, function() end, mod_open_toggle)
    else long_press("k2", z, mod_rack_randomize, mod_rack_secondary) end
  elseif n == 3 and not empty then
    long_press("k3", z, function() end, mod_rack_toggle)
  end
end

-- K1 and K3 held together for two seconds open the chooser for the focused param (lib/modrack),
-- in either order, since norns passes K1 on only after a quarter second and a near-simultaneous
-- K3 often arrives first. Whoever arrives first gives up its own timer, and releasing either
-- key before two seconds fires nothing.
local k1_down, k3_down, chord_clock = false, false, nil
local function chord_cancel()
  if chord_clock then clock.cancel(chord_clock); chord_clock = nil end
end
local function chord_start()
  if k_clock.k1 then clock.cancel(k_clock.k1); k_clock.k1 = nil end
  if k_clock.k3 then clock.cancel(k_clock.k3); k_clock.k3 = nil end
  chord_cancel()
  chord_clock = clock.run(function()
    clock.sleep(2.0)
    chord_clock = nil
    local id, dev
    if gui_mode == 2 then
      id, dev = perf_pid(), PERF_DEVICES[perf_sel].name
    elseif view_group == 3 then
      local pd = cur_pedal()
      id, dev = pd.params[pd.psel].id, pd.name
    else
      id = cab_sel_id()
      dev = STUDIO_DEVICES[studio_sel].dev.name
    end
    modrack.open_chooser(id, dev)
    rack_pulse_start()
    redraw()
  end)
end

function key(n, z)
  if gui_mode == 3 then return end
  if n == 3 then k3_down = z == 1 end
  if n == 1 then
    k1_down = z == 1
    if z == 1 and k3_down and not mod_open and not modrack.chooser_open() then
      chord_start()
      return
    end
    if z == 0 then chord_cancel() end
    long_press("k1", z, mod_open_toggle)
    return
  end
  if modrack.chooser_open() then
    if z == 1 and n == 2 then modrack.chooser_close(); redraw()
    elseif z == 1 and n == 3 then modrack.chooser_confirm() end
    return
  end
  if n == 3 and k1_down and not mod_open then
    if z == 1 then chord_start() else chord_cancel() end
    return
  end
  if mod_open then key_group1(n, z); return end
  if gui_mode == 2 then
    device_key(PERF_DEVICES[perf_sel], n, z)
  else
    device_key(STUDIO_DEVICES[studio_sel].dev, n, z)
  end
end

-- After a PSET loads, pick the voice by name (older PSETs counted fixed slots: 3 = Form, 4 =
-- Excite). If the voice mod is missing the input falls back to Mono, but the name stays for the
-- next save.
local function restore_voice()
  local id, v = params:get("signal_voice"), params:get("signal_input")
  if id == "" then
    if v < 3 then return end
    id = ({ "form", "excite" })[v - 2] or ""
  end
  local want = 1
  for i, vc in ipairs(VOICES) do
    if vc.id == id then want = i + 2 end
  end
  -- counts as part of the load, so Route leaves the amp slot as the PSET stored it
  local loading = params.pset_loading
  params.pset_loading = true
  if want ~= v then params:set("signal_input", want) end
  params.pset_loading = loading
  params:set("signal_voice", id)
end

function init()
  engine.fx_attach()
  -- A PSET is a letter from the past, so princeton first lays out empty envelopes whose contents
  -- reveal its age and let older spellings be translated. The reader is handed back in cleanup(),
  -- or it would read other scripts' letters with princeton's eyes.
  local modtarget = include("lib/modtarget")
  local mod_bindings = {}   -- filled once the mod sources exist (below, before params:bang)
  params._orig_read  = params._orig_read or params.read
  params.pset_loading = false
  params.pset_epoch   = params.pset_epoch or 0
  -- Params renamed since (Waveform is Shape, Probability is Chance) keep their old spelling in older
  -- PSETs; during the read the old ids point at today's params, and saved mod targets are translated too.
  local renamed = {}
  for i = 1, lfo.NUM do renamed["lfo" .. i .. "_waveform"] = "lfo" .. i .. "_shape" end
  for i = 1, trigs.N do renamed["trig" .. i .. "_probability"] = "trig" .. i .. "_chance" end
  params.read = function(self, ...)
    params.pset_loading = true
    local aliased = {}
    for old, new in pairs(renamed) do
      if params.lookup[old] == nil and params.lookup[new] then
        params.lookup[old] = params.lookup[new]; aliased[#aliased + 1] = old
      end
    end
    local marked = params.lookup["sync_scheme"] ~= nil
    if marked then params:set("sync_scheme", 1) end
    if params.lookup["signal_voice"] then params:set("signal_voice", "") end
    modtarget.mark_unknown(mod_bindings)
    local ok, err = pcall(params._orig_read, self, ...)
    for _, old in ipairs(aliased) do params.lookup[old] = nil end
    if ok and marked and params:get("sync_scheme") < sync.SCHEME then
      sync.migrate_psets()
    end
    if marked then params:set("sync_scheme", sync.SCHEME) end
    if ok then
      modtarget.restore_from_ids(mod_bindings, renamed)
      restore_voice()
    end
    params.pset_loading = false
    params.pset_epoch = params.pset_epoch + 1
    redraw()
    if not ok then error(err) end
  end
  params:add_number("sync_scheme", "sync scheme", 1, 9, sync.SCHEME)
  params:hide("sync_scheme")
  -- The chosen voice is also stored by name in the PSET. The input list is alphabetical and
  -- shifts whenever a voice mod is added or missing.
  params:add_text("signal_voice", "signal voice", "")
  params:hide("signal_voice")
  audio.level_monitor(0)
  looper.init({
    is_clock_running = function() return clock_running end,
    get_override     = function() return lfo.sync_override end,
    is_pane_visible  = function() return view_group == 0 and view_pane[0] == 2 end,
  })
  local loop_sel = 1
  looper_ui.init({
    draw_strip      = function(cat, name, val, lv) draw_strip(cat, name, strip_val(LOOPER_DEF[loop_sel].id, val, lv)) end,
    fmt_val         = function(i) loop_sel = i; return fmt_def_val(LOOPER_DEF, i) end,
    LOOPER_DEF      = LOOPER_DEF,
    val_level       = function(id) return sync.val_level(id, clock_running) end,
    draw_state_icon = draw_looper_state_icon,
    B               = B,
    looper          = looper,
    LOOPER_PTS      = sprites.LOOPER_PTS,
    LOOPER_OX       = cabinet.CAB.x,
    LOOPER_OY       = cabinet.TOP,
    edit_param      = edit_param,
  })
  lfo.init({
    TARGET_PARAMS    = TARGET_PARAMS,
    DEVICE_NAMES     = DEVICE_NAMES,
    DEVICE_PARAMS    = DEVICE_PARAMS,
    TARGET_DEVICE_OF = TARGET_DEVICE_OF,
    is_clock_running = function() return clock_running end,
    is_initing      = function() return initing end,
    on_sync_override_change = function(target_id)
      sync.push_all(initing, clock_running, lfo.sync_override)
      if target_id == "looper_quant_div" or target_id == "looper_quant_feel" then
        looper.quant_led_restart()
      end
    end,
    get_trigs_mod    = function() return trigs.mod end,
    on_target_change = function() env.rebuild_all_target_dropdowns(); seq.rebuild_all_target_dropdowns() end,
  })
  env.init({
    TARGET_PARAMS    = TARGET_PARAMS,
    DEVICE_NAMES     = DEVICE_NAMES,
    DEVICE_PARAMS    = DEVICE_PARAMS,
    TARGET_DEVICE_OF = TARGET_DEVICE_OF,
    lfo              = lfo,
    is_initing      = function() return initing end,
    is_pane_visible_l = function() return view_group == 1 and view_pane[1] == 3 end,
    is_pane_visible_r = function() return view_group == 1 and view_pane[1] == 4 end,
    redraw_pane      = function() if not initing then redraw() end end,
    on_target_change = function() seq.rebuild_all_target_dropdowns() end,
  })
  trigs.init({
    looper           = looper,
    lfo              = lfo,
    targets          = TRIG_TARGETS,
    is_initing      = function() return initing end,
    is_clock_running = function() return clock_running end,
  })
  seq.init({
    TARGET_PARAMS    = TARGET_PARAMS,
    DEVICE_NAMES     = DEVICE_NAMES,
    DEVICE_PARAMS    = DEVICE_PARAMS,
    TARGET_DEVICE_OF = TARGET_DEVICE_OF,
    lfo              = lfo,
    is_clock_running = function() return clock_running end,
    is_initing      = function() return initing end,
    on_target_change = function()
      for i = 1, lfo.NUM do lfo.rebuild_target_dropdown(i) end
      env.rebuild_all_target_dropdowns()
    end,
    is_pane_visible  = function() return view_group == 1 and RACK_PANES[view_pane[1]].kind == "seq" end,
    redraw_pane      = function() if not initing then redraw() end end,
  })
  modrack.init({
    lfo = lfo, env = env, seq = seq, trigs = trigs, cabinet = cabinet,
    TARGET_PARAMS    = TARGET_PARAMS,
    RACK_PANES       = RACK_PANES,
    draw_strip       = draw_strip,
    fmt_value        = function(id) return fmt_param(id) end,
    redraw           = function() redraw() end,
    -- Into the rack, straight to a source's editor.
    open_source      = function(kind, idx)
      if not mod_open then mod_open_toggle() end
      modrack.show_edit()
      for p, src in ipairs(RACK_PANES) do
        if src.kind == kind and src.idx == idx then set_pane(p); break end
      end
    end,
  })
  -- re() is the quiet redraw of param actions: silent during init (initing) and while a PSET is
  -- laid out (pset_loading). The PSET reader redraws once afterwards.
  local function re() if not (initing or params.pset_loading) then redraw() end end

  -- Each device registers its params in its own setup_ function, as a group in the PARAMS menu,
  -- and each action is the wire to the engine (usually engine[id] directly, levels as factors
  -- rather than dB, options as 0-based index). The groups are hooked in further down, in the
  -- order the menu shows them.
  local function add_p_params(ped)
    for _, p in ipairs(ped.params) do
      if p.options then
        params:add_option(p.id, p.name, p.options, p.default + 1)
        params:set_action(p.id, function(v) engine[p.id](v - 1); re() end)
      else
        control.add(p.id, p.name, p.kind, p.default, function(v) engine[p.id](p.scale and v * p.scale or v); re() end, p.lo, p.hi)
      end
    end
  end

  local function sync_df_action(prefix)
    local dev_name = prefix:sub(1,1):upper() .. prefix:sub(2)
    return function(_)
      if tap.ID[prefix] then
        local div = params:get(prefix .. "_sync_div")
        if tap.last_div[prefix] and (div > 1) ~= (tap.last_div[prefix] > 1) then tap.forget(prefix) end
        tap.last_div[prefix] = div
      end
      if not initing then
        sync.push_all(initing, clock_running, lfo.sync_override)
        lfo.refresh_dropdowns_for_device(dev_name)
      end
      re()
    end
  end

  -- eng(id, conv) sends a control to the engine command of the same name, converted where the
  -- engine still thinks in its own scale (an Amount of 0..100 % for a 0..10 knob, say).
  local function eng(id, conv)
    return function(v) engine[id](conv and conv(v) or v); re() end
  end
  local function tenth(v) return v * 0.1 end

  local function add_sync_params(prefix)
    params:add_separator(prefix .. "_sep_sync", "─── Synchronization ───")
    params:add_option(prefix .. "_sync_div", "Division", sync.DIV_OPTS, sync.DIV_DEFAULT)
    params:set_action(prefix .. "_sync_div", sync_df_action(prefix))
    params:add_option(prefix .. "_sync_feel", "Feel", sync.FEEL_OPTS, 1)
    params:set_action(prefix .. "_sync_feel", sync_df_action(prefix))
    if tap.ID[prefix] then
      local function retap() if not (initing or params.pset_loading) then tap.apply(prefix) end end
      params:add_option(prefix .. "_tap_div", "Tap Division", tap.DIV_OPTS, sync.DIV_DEFAULT - 1)
      params:set_action(prefix .. "_tap_div", retap)
      params:add_option(prefix .. "_tap_feel", "Tap Feel", sync.FEEL_OPTS, 1)
      params:set_action(prefix .. "_tap_feel", retap)
      params:add_binary(prefix .. "_tap", "Tap", "trigger", 0)
      params:set_action(prefix .. "_tap", function() if not (initing or params.pset_loading) then tap.hit(prefix) end end)
    end
  end

  local function setup_pedal(idx)
    local ped = PEDALS[idx]
    local prefix = ped.name:lower()
    local has_sync = false
    for _, p in ipairs(ped.params) do
      if sync.PARAM_MAP[p.id] then has_sync = true; break end
    end
    params:add_group(ped.name:upper(), 2 + #ped.params + (has_sync and 6 or 0))
    params:add_separator(prefix .. "_sep_control", "─── Control ───")
    params:add_option(ped.enable_id, "Engage", {"Off", "On"}, 1)
    params:set_action(ped.enable_id, function(v)
      if ped.subsynth then lifecycle.set(ped.subsynth, v == 2)
      else engine[ped.bypass_cmd](2 - v) end
      re()
    end)
    add_p_params(ped)
    if has_sync then add_sync_params(prefix) end
  end

  local function setup_amp()
    nam.install()
    nam.scan()
    params:add_group("AMP", 18)
    params:add_separator("amp_sep_control", "─── Control ───")
    params:add_option("amp_enable", "Engage", {"Off", "On"}, 2)
    params:set_action("amp_enable", function(v) engine.amp_bypass(2 - v); re() end)
    params:add_option("amp_type", "Amp", {"Combo", "NAM", "Strip"}, 1)
    params:add_option("amp_model", "Model", nam.options(), 1)
    local function show(ids, on)
      for _, id in ipairs(ids) do if on then params:show(id) else params:hide(id) end end
    end
    local function amp_select()
      local kind = amp_kind()
      local on, st = kind == "nam", kind == "strip"
      nam.select(on, params:get("amp_model"))
      engine.strip_cal(chstrip.CAL)
      engine.strip_on(st and 1 or 0)
      show({"amp_model", "amp_nam_cab", "amp_mid", "amp_mid_freq"}, on)
      show({"amp_volume", "amp_bass", "amp_treble", "amp_master"}, not st)
      show({"amp_rectifier"}, kind == "int")
      show(chstrip.IDS, st)
      local ad = PERF_DEVICES[PERF_INDEX_OF.AMP]
      ad.params = st and ad.params_strip or on and ad.params_nam or ad.params_int
      ad.name = st and "Strip" or "Amp"
      dev_param_sel.AMP = util.clamp(dev_param_sel.AMP or 1, 1, #ad.params)
      perf_param[PERF_INDEX_OF.AMP] = util.clamp(perf_param[PERF_INDEX_OF.AMP] or 1, 1, #ad.params)
      if not initing and STUDIO_DEVICES[studio_sel].abbr == "AMP" then studio_apply() end
      chain_cache = nil
      if cab_refresh then cab_refresh() end
      if dev_hidden(STUDIO_DEVICES[studio_sel].abbr) then focus_studio_device("AMP") end
      if dev_hidden(PERF_DEVICES[perf_sel].abbr) then perf_sel = PERF_INDEX_OF.AMP end
      if not initing then _menu.rebuild_params() end
      re()
    end
    params:set_action("amp_type", amp_select)
    -- E3 browses the models, but loading waits until the knob rests for a quarter second. That
    -- way not every model you overshoot has to pass through memory.
    local model_clock
    params:set_action("amp_model", function()
      if initing or params.pset_loading then amp_select(); return end
      if model_clock then clock.cancel(model_clock) end
      model_clock = clock.run(function() clock.sleep(0.25); model_clock = nil; amp_select() end)
      re()
    end)
    params:add_option("amp_nam_cab", "Cab Sim", {"Auto", "On", "Off"}, 1)
    params:set_action("amp_nam_cab", amp_select)
    params:hide("amp_model")
    params:hide("amp_nam_cab")
    control.add("amp_volume", "Volume", "drive", 5, eng("amp_volume"))
    -- the combo's bass is flat a quarter of the way up, so 50 % lands there and the rest spreads above
    control.add("amp_bass", "Bass", "amount", 50, eng("amp_bass", function(v) return v <= 50 and v * 0.05 or 2.5 + (v - 50) * 0.15 end))
    control.add("amp_mid", "Mid", "amount", 50, eng("amp_mid", tenth))
    params:add_control("amp_mid_freq", "Mid Freq", control.spec("hz", 250, 4000, 750))
    params:set_action("amp_mid_freq", function(v) engine.amp_mid_freq(v); re() end)
    params:hide("amp_mid")
    params:hide("amp_mid_freq")
    control.add("amp_treble", "Treble", "amount", 50, eng("amp_treble", tenth))
    control.level("amp_master", "Master", 0, function(a) engine.amp_master(a); re() end)
    params:add_option("amp_rectifier", "Rectifier", {"Tube 5Y3", "Tube 5U4", "Silicon"}, 2)
    params:set_action("amp_rectifier", function(v) engine.amp_rectifier(v - 1); re() end)
    -- Strip: one linked set for both channels. Drive 5 is unity into the console stage and every
    -- step of one adds 2 dB, so 0 to 10 spans -10 to +10 dB.
    control.add("strip_gain", "Drive", "drive", 5, eng("strip_gain", function(v) return 10 ^ ((v - 5) / 10) end))
    control.add("strip_even", "Even Harmonics", "amount", 0, eng("strip_even", tenth))
    control.add("strip_odd", "Odd Harmonics", "amount", 50, eng("strip_odd", tenth))
    control.add("strip_lowcut", "Low Cut", "hz", 80, eng("strip_lowcut"), 20, 1000)
    control.add("strip_highcut", "High Cut", "hz", 12000, eng("strip_highcut"), 1000, 20000)
    control.level("strip_level", "Level", 0, function(a) engine.strip_level(a); re() end)
    for _, id in ipairs(chstrip.IDS) do params:hide(id) end
  end

  local function setup_tremolo()
    params:add_group("TREMOLO", 10)
    params:add_separator("tremolo_sep_control", "─── Control ───")
    params:add_option("tremolo_enable", "Engage", {"Off", "On"}, 1)
    params:set_action("tremolo_enable", function(v) engine.tremolo_intensity(v == 2 and params:get("tremolo_intensity") or 0); re() end)
    control.add("tremolo_speed", "Speed", "rate", 2.5, eng("tremolo_speed"), 0.1, 25)
    params:add_control("tremolo_intensity", "Intensity", control.spec("amount", 0, 100, 0))
    params:set_action("tremolo_intensity", function(v) if params:get("tremolo_enable") == 2 then engine.tremolo_intensity(v) end; re() end)
    add_sync_params("tremolo")
  end

  local function setup_looper()
    looper_params.setup({
      re                   = re,
      is_initing           = function() return initing end,
      group_label = "LOOP",
      on_quant_div_changed = function() lfo.refresh_dropdowns_for_device("Loop") end,
      speed_is_owned       = function() return lfo.target_owner["looper_speed"] ~= nil end,
      looper               = looper,
      embedded             = true,
    })
  end

  local function setup_reverb()
    params:add_group("princeton_reverb", "REVERB", 9)
    params:add_separator("reverb_sep_control", "─── Control ───")
    params:add_option("reverb_enable", "Engage", {"Off", "On"}, 2)
    params:set_action("reverb_enable", function(v) engine.reverb_mute(v == 2 and 0 or 1); re() end)
    control.add("reverb_amount",     "Amount",     "amount", 10,  eng("reverb_amount"))
    control.add("reverb_length",     "Length",     "s",      2.5, eng("reverb_length"), 0.5, 5)
    -- the shelves turn like tone knobs; full travel is 5 dB either way
    control.add("reverb_low_shelf",  "Low Shelf",  "amount", 0,   eng("reverb_low_shelf", function(v) return v * 0.05 end), -100, 100)
    control.add("reverb_high_shelf", "High Shelf", "amount", 0,   eng("reverb_high_shelf", function(v) return v * 0.05 end), -100, 100)
    control.add("reverb_dwell",      "Dwell",      "amount", 50,  eng("reverb_dwell", tenth))
    control.add("reverb_drip",       "Drip",       "amount", 50,  eng("reverb_drip", tenth))
    params:add_option("reverb_freeze", "Freeze", {"Off", "On"}, 1)
    params:set_action("reverb_freeze", function(v) engine.reverb_freeze(v - 1); re() end)
  end

  local CAB_MODE_ALL = {"mic_position", "cab_level"}
  local CAB_MODE_VISIBLE = {
    [1] = {},
    [2] = {mic_position=true, cab_level=true},
  }

  local function setup_cab()
    params:add_group("CAB & MIC", 4)
    params:add_separator("cab_sep_control", "─── Control ───")
    params:add_option("cab_mode", "Engage", {"Off", "On"}, 2)
    cab_refresh = function()
      local v   = params:get("cab_mode")
      local off = dev_hidden("CAB")
      engine.cab_mode((v == 2 and not off) and 1 or 0)
      if off then params:hide("cab_mode") else params:show("cab_mode") end
      for _, p in ipairs(CAB_MODE_ALL) do
        if CAB_MODE_VISIBLE[v][p] and not off then params:show(p) else params:hide(p) end
      end
      if _menu and _menu.rebuild_params and not initing then _menu.rebuild_params() end
    end
    params:set_action("cab_mode", function() cab_refresh(); re() end)
    params:add_option("mic_position", "Position", MIC_NAMES, 2)
    params:set_action("mic_position", function(v) engine.mic_position(v - 1); re() end)
    control.level("cab_level", "Level", 0, function(a) engine.cab_level(a); re() end)
  end

  local function setup_envelop()
    params:add_group("MESMERIZE", 18)
    params:add_separator("evp_sep_control", "─── Control ───")
    params:add_option("evp_enable", "Engage", {"Off", "On"}, 1)
    params:set_action("evp_enable", function(v) engine.evp_bypass(2 - v); re() end)
    params:add_option("evp_freeze", "Freeze", {"Off", "On"}, 1)
    params:set_action("evp_freeze", function(v) engine.evp_freeze(v - 1); re() end)
    params:add_option("evp_spill", "Spillover", {"Off", "On"}, 1)
    params:set_action("evp_spill", function(v) engine.evp_spill(v - 1); re() end)
    -- Size, Spread and Width reach past the room's own proportions, so 0..100 % spans the tank's range
    control.add("evp_size", "Size", "amount", 30, eng("evp_size", function(v) return 10 + v * 2.9 end))
    control.add("evp_predelay", "Pre-Delay", "ms0", 100, eng("evp_predelay"), 0, 500)
    control.add("evp_decay", "Decay", "amount", 75, eng("evp_decay"))
    control.add("evp_damping", "Damping", "amount", 5, eng("evp_damping"))
    control.add("evp_tilt", "Tilt", "amount", 0, eng("evp_tilt"), -100, 100)
    control.add("evp_mix", "Mix", "amount", 25, eng("evp_mix"))
    params:add_separator("evp_sep_space", "─── Space ───")
    control.add("evp_spread", "Spread", "amount", 50, eng("evp_spread", function(v) return v * 2 end))
    control.add("evp_diffusion", "Diffusion", "amount", 25, eng("evp_diffusion", function(v) return v * 0.95 end))
    params:add_separator("evp_sep_tone", "─── Tone & Stereo ───")
    control.add("evp_saturation", "Saturation", "amount", 0, eng("evp_saturation"))
    control.add("evp_bandwidth", "Bandwidth", "amount", 50, eng("evp_bandwidth"))
    control.add("evp_lowcut", "Low Cut", "hz", 60, eng("evp_lowcut"), 20, 1000)
    control.add("evp_width", "Width", "amount", 50, eng("evp_width", function(v) return v * 2 end))
  end

  local function setup_build()
    local function push() if not initing then sync.push_all(initing, clock_running, lfo.sync_override) end end
    params:add_group("BUILD", 19)
    params:add_separator("bld_sep_control", "─── Control ───")
    params:add_option("bld_enable", "Engage", {"Off", "On"}, 1)
    params:set_action("bld_enable", function(v) engine.bld_bypass(2 - v); re() end)
    params:add_option("bld_freeze", "Freeze", {"Off", "On"}, 1)
    params:set_action("bld_freeze", function(v) engine.bld_freeze(v - 1); re() end)
    params:add_option("bld_spill", "Spillover", {"Off", "On"}, 1)
    params:set_action("bld_spill", function(v) engine.bld_spill(v - 1); re() end)
    local ratio_opts = {}
    for i, q in ipairs(BLD_RATIOS) do ratio_opts[i] = q[1] .. ":" .. q[2] end
    params:add_option("bld_ratio", "Ratio", ratio_opts, 11)
    params:set_action("bld_ratio", function(v) bld_send_ratio(v); re() end)
    params:add_number("bld_block", "Block", 1, #BLD_BLOCKS, 10, function(p) return tostring(p:get()) end)
    local block_last = 10
    -- Time steps in twelfths of a doubling up to the block's ceiling; the grid sits in the spec, so
    -- PARAMS, the pane, lcx and MIDI all land on the same semitones.
    local function time_grid(z)
      local cs = params:lookup_param("bld_time").controlspec
      cs.step, cs.quantum, cs.fine = 1 / bld_steps(z), 1 / bld_steps(z), 1 / bld_steps(z)
    end
    params:set_action("bld_block", function(z)
      local ms = bld_ms(block_last, params:get("bld_time"))
      block_last = z
      time_grid(z)
      params:set("bld_time", bld_pos(z, math.min(ms, BLD_BLOCKS[z])))
      bld_send_block(); re()
    end)
    params:add_control("bld_time", "Time", control.spec("steps", 0, 1, 1, 1 / bld_steps(10)),
      function(p)
        local ms = bld_ms(params:get("bld_block"), p:get())
        if ms < 10 then return string.format("%.1f ms", ms) end
        if ms < 1000 then return string.format("%d ms", math.floor(ms + 0.5)) end
        return string.format("%.2f s", ms / 1000)
      end)
    params:set_action("bld_time", function() bld_send_block(); re() end)
    time_grid(10)
    control.add("bld_fb", "Feedback", "amount", 50, eng("bld_fb"))
    control.add("bld_octave", "Octave", "amount", 10, eng("bld_octave"))
    control.add("bld_smear", "Smear", "amount", 10, eng("bld_smear"))
    control.add("bld_xfeed", "Crossfeed", "amount", 5, eng("bld_xfeed"))
    control.add("bld_mix", "Mix", "amount", 25, eng("bld_mix"))
    params:add_separator("bld_sep_tone", "─── Tone & Stereo ───")
    control.add("bld_spread", "Spread", "amount", 50, eng("bld_spread"))
    control.add("bld_lowcut", "Low Cut", "hz", 40, eng("bld_lowcut"), 20, 1000)
    control.add("bld_highcut", "High Cut", "hz", 15000, eng("bld_highcut"), 1000, 20000)
    params:add_separator("bld_sep_sync", "─── Synchronization ───")
    params:add_option("bld_time_sync_div", "Division", sync.DIV_OPTS, 1)
    params:set_action("bld_time_sync_div", function(v)
      if v <= 1 or not clock_running then engine.bld_time(bld_ms(params:get("bld_block"), params:get("bld_time"))) end
      push(); re()
    end)
    params:add_option("bld_time_sync_feel", "Feel", sync.FEEL_OPTS, 1)
    params:set_action("bld_time_sync_feel", function() push(); re() end)
  end

  local function setup_tape()
    params:add_group("TAPE", 13)
    params:add_separator("tape_sep_control", "─── Control ───")
    params:add_option("tape_enable", "Engage", {"Off", "On"}, 2)
    params:set_action("tape_enable", function(v) engine.tape_bypass(2 - v); re() end)
    params:add_binary("tape_transport", "Stop/Start", "trigger", 0)
    params:set_action("tape_transport", function() if not (initing or params.pset_loading) then tape.toggle() end end)
    params:add_option("tape_speed", "Speed", {"7.5 ips", "15 ips", "30 ips"}, 2)
    params:set_action("tape_speed", function(v) engine.tape_speed(v - 1); re() end)
    control.add("tape_drive", "Drive", "drive", 5, eng("tape_drive"))
    params:add_option("tape_bias", "Bias", {"Under", "Normal", "Over"}, 2)
    params:set_action("tape_bias", function(v) engine.tape_bias(v - 1); re() end)
    control.add("tape_hiss", "Hiss", "amount", 5, eng("tape_hiss", tenth))
    control.add("tape_wow", "Wow", "amount", 25, eng("tape_wow", tenth))
    control.add("tape_mag", "Magnetism", "amount", 25, eng("tape_mag", tenth))
    params:add_separator("tape_sep_transport", "─── Stereo & Transport ───")
    control.add("tape_azimuth", "Azimuth", "amount", 25, eng("tape_azimuth", tenth))
    control.add("tape_down", "Spin Down", "s", 2.5, eng("tape_down"), 0.1, 5)
    control.add("tape_up", "Spin Up", "s", 1, eng("tape_up"), 0.1, 5)
  end

  local function setup_hold(idx)
    local p = "hold" .. idx .. "_"
    local d  = (idx == 2) and 75 or 50
    local st = (idx == 2) and 12 or -12
    params:add_group("HOLD " .. idx, 16)
    params:add_separator(p .. "sep_control", "─── Control ───")
    params:add_option(p .. "enable", "Engage", {"Off", "On"}, 1)
    params:set_action(p .. "enable", function(v) if v == 2 then engine.hold_on(idx) else engine.hold_off(idx) end; re() end)
    params:add_binary(p .. "recapture", "Recapture", "trigger", 0)
    params:set_action(p .. "recapture", function() if not (initing or params.pset_loading) then engine.hold_recapture(idx) end end)
    control.add(p .. "size", "Size", "amount", d, function(v) engine.hold_size(idx, HOLD_E.size(v)); re() end)
    control.add(p .. "density", "Density", "amount", d - 5, function(v) engine.hold_density(idx, HOLD_E.density(v)); re() end)
    control.add(p .. "spread", "Spread", "amount", d, function(v) engine.hold_spread(idx, HOLD_E.spread(v)); re() end)
    control.add(p .. "move", "Movement", "amount", 25, function(v) engine.hold_move(idx, v * 0.1); hold_move_marks(); re() end)
    params:add_control(p .. "pitch", "Pitch", control.spec("steps", -24, 24, st, 1, "st"))
    params:set_action(p .. "pitch", function(v) engine.hold_pitch(idx, v); re() end)
    params:add_control(p .. "pmix", "Pitch Mix", control.spec("amount", 0, 100, 10))
    params:set_action(p .. "pmix", function(v) engine.hold_pmix(idx, v); re() end)
    params:add_control(p .. "rev", "Reverse Mix", control.spec("amount", 0, 100, 0))
    params:set_action(p .. "rev", function(v) engine.hold_rev(idx, v); re() end)
    params:add_option(p .. "shape", "Shape", {"Smooth", "Soft", "Swell", "Pluck", "Plateau"}, 1)
    params:set_action(p .. "shape", function(v) engine.hold_shape(idx, v - 1); re() end)
    params:add_option(p .. "interp", "Resolution", {"Coarse", "Fine"}, 2)
    params:set_action(p .. "interp", function(v) engine.hold_interp(idx, (v == 2) and 4 or 2); re() end)
    params:add_control(p .. "gain", "Gain", control.spec("drive", 0, 10, 5))
    params:set_action(p .. "gain", function(v) engine.hold_gain(idx, v); re() end)
    control.level(p .. "level", "Level", 0, function(a) engine.hold_level(idx, a); re() end)
    params:add_control(p .. "rise", "Rise", control.spec("s", 0.01, 5, 0.25))
    params:set_action(p .. "rise", function(v) engine.hold_rise(idx, v); re() end)
    params:add_control(p .. "fall", "Fall", control.spec("s", 0.01, 5, 2.5))
    params:set_action(p .. "fall", function(v) engine.hold_fall(idx, v); re() end)
  end

  local function setup_gate()
    params:add_group("CUT", 9)
    params:add_separator("cut_sep_control", "─── Control ───")
    params:add_option("cut_enable", "Engage", {"Off", "On"}, 1)
    params:set_action("cut_enable", function(v) if v == 2 then engine.cut_on() else engine.cut_off() end; re() end)
    params:add_control("cut_thresh", "Threshold", control.spec("level", nil, 0, -50), function(p) return control.level_str(p:get()) end)
    params:set_action("cut_thresh", function(v) engine.cut_thresh(control.db(v)); re() end)
    control.add("cut_attack",  "Attack",  "ms", 1,   eng("cut_attack"),  0.1, 2500)
    control.add("cut_hold",    "Hold",    "ms", 20,  eng("cut_hold"),    1,   2500)
    control.add("cut_release", "Release", "ms", 100, eng("cut_release"), 1,   2500)
    params:add_control("cut_range", "Range", control.spec("level", nil, 0, -75), function(p) return control.level_str(p:get()) end)
    params:set_action("cut_range", function(v) engine.cut_range(control.db(v)); re() end)
    control.add("cut_hyst", "Margin", "steps", 0, eng("cut_hyst"), 0, 25, 0.5, "dB")
    params:add_option("cut_detect", "Detection", {"Peak", "RMS"}, 1)
    params:set_action("cut_detect", function(v) engine.cut_detect(v - 1); re() end)
  end

  local function setup_fray()
    params:add_group("FRAY", 10)
    params:add_separator("fray_sep_control", "─── Control ───")
    params:add_option("fray_enable", "Engage", {"Off", "On"}, 1)
    params:set_action("fray_enable", function(v) lifecycle.set("fray", v == 2); re() end)
    control.add("fray_drive",  "Drive",  "drive",  7.5, eng("fray_drive"))
    control.add("fray_comp",   "Comp",   "amount", 50,  eng("fray_comp", tenth))
    control.add("fray_stab",   "Stab",   "amount", 0,   eng("fray_stab", tenth))
    control.add("fray_octave", "Octave", "amount", 0,   eng("fray_octave", tenth))
    params:add_option("fray_octave_mode", "Oct Mode", {"Down", "Up", "Both"}, 2)
    params:set_action("fray_octave_mode", function(v) engine.fray_octave_mode(v - 1); re() end)
    control.add("fray_gate",   "Gate",   "amount", 0,   eng("fray_gate", tenth))
    control.add("fray_tone",   "Tone",   "amount", 100, eng("fray_tone", tenth))
    control.level("fray_volume", "Level", 0, function(a) engine.fray_volume(a); re() end)
  end

  local function setup_metro()
    params:add_group("COUNT", 15)
    params:add_separator("count_sep_control", "─── Control ───")
    params:add_option("count_enable", "Engage", {"Off", "On"}, 1)
    params:set_action("count_enable", function(v) count_active = (v == 2); if count_active then count_clock_start() else count_clock_stop() end; re() end)
    -- BPM is the tempo Count hears, the internal clock's tempo or the incoming MIDI tempo. If the
    -- MIDI clock falls silent, Count keeps counting at the last tempo alone.
    params:add_number("count_bpm", "BPM", 20, 300, 120)
    params:set_action("count_bpm", function(v)
      local internal = params.lookup["clock_source"] and params:get("clock_source") == 1
      if not (initing or params.pset_loading) and internal and params.lookup["clock_tempo"]
         and math.floor(params:get("clock_tempo") + 0.5) ~= v then
        params:set("clock_tempo", v)
      end
      if count_active and not clock_running then count_clock_start() end
      re()
    end)
    params:add_option("count_div", "Division", sync.COUNT_DIV_OPTS, 3)
    params:set_action("count_div", function(_) if count_active then count_clock_start() end end)

    params:add_separator("count_sep_voice", "─── Voice ───")
    params:add_option("count_root", "Root", scales.NOTE_NAMES, 1)
    params:set_action("count_root", function(_) lfo.count.root = nil; re() end)
    params:add_option("count_register", "Register", {"0","1","2","3","4","5","6","7"}, 4)
    params:set_action("count_register", function(_) lfo.count.register = nil; re() end)
    params:add_option("count_scale", "Scale", scales.SCALE_NAMES, 1)
    params:set_action("count_scale", function(v)
      lfo.count.scale = nil
      if v == 1 then params:hide("count_scale_play"); params:hide("count_degree")
      else            params:show("count_scale_play"); params:show("count_degree") end
      if _menu and _menu.rebuild_params then _menu.rebuild_params() end
      re()
    end)
    params:add_number("count_degree", "Scale Degree", 1, 15, 1)
    params:set_action("count_degree", function(_) lfo.count.degree = nil end)
    params:add_option("count_scale_play", "Scale Play",
      {"Off", "Forward", "Reverse", "3rds", "4ths", "5ths", "7ths", "Random"}, 1)
    params:set_action("count_scale_play", function(_) lfo.count.play = nil; count_step = 0 end)
    params:add_option("count_chords", "Chords", {"Off", "Octaves", "Power Chords", "Triads"}, 1)
    params:set_action("count_chords", function(_) lfo.count.chords = nil end)

    params:add_separator("count_sep_sound", "─── Sound ───")
    control.level("count_level", "Level", 0, function() lfo.count.level = nil; re() end)
    params:add_control("count_length", "Length", control.spec("ms", 1, 500, 50))
    params:set_action("count_length", function(_) lfo.count.length = nil end)
    params:add_option("count_position", "Position", {"Parallel", "Inline"}, 1)
  end

  local function setup_tuner()
    params:add_group("TUNE", 3)
    params:add_separator("tune_sep_control", "─── Control ───")
    params:add_option("tune_mute", "Mute", {"Off", "On"}, 1)
    params:set_action("tune_mute", function(v)
      tune.muted = (v == 2)
      engine.mute(tune.muted and 1 or 0)
      re()
    end)
    params:add_control("tune_ref", "Reference", control.spec("steps", 420, 460, 440, 1, "Hz"))
    params:set_action("tune_ref", function(v) tune.ref_hz = v; re() end)
  end

  -- Signal Flow is the patch bay: Input picks Mono, Stereo or a voice from a voice mod. Sends A
  -- and B tap at the input, after the looper or at the output to feed an fx mod.
  local function setup_signal_flow()
    params:add_group("ROUTE", 7)
    params:add_separator("signal_flow_sep_control", "─── Control ───")
    local inputs = {"Mono", "Stereo"}
    for _, vc in ipairs(VOICES) do inputs[#inputs + 1] = vc.name end
    params:add_option("signal_input", "Input", inputs, 1)
    -- Stereo and the voices want a desk channel rather than a guitar amp, so turning Route to them
    -- puts the Strip in the amp slot. Back on Mono the amp from before returns, unless the slot
    -- has changed hands meanwhile.
    local amp_before
    local function route_amp(v)
      local at = params:get("amp_type")
      if v >= 2 then
        if at ~= 3 then amp_before = at; params:set("amp_type", 3) end
      else
        if at == 3 and amp_before then params:set("amp_type", amp_before) end
        amp_before = nil
      end
    end
    params:set_action("signal_input", function(v)
      if not (initing or params.pset_loading) then route_amp(v) end
      local vc = VOICES[v - 2]
      engine.voice(vc and vc.id or "")
      if not params.pset_loading then params:set("signal_voice", vc and vc.id or "") end
      engine.signal_input(math.min(v, 3))
      synth.set_voice(vc)
      re()
    end)
    control.level("input_trim", "Input Trim", 0, function(a) engine.input_trim(a); re() end)
    params:add_option("fx_send_a_source", "Send A Source", {"Input", "Loop", "Output"}, 3)
    params:set_action("fx_send_a_source", function(v) engine.fx_send_a_source(v - 1); re() end)
    control.level("fx_send_a_level", "Send A Level", 0, function(a) engine.fx_send_a_level(a); re() end)
    params:add_option("fx_send_b_source", "Send B Source", {"Input", "Loop", "Output"}, 3)
    params:set_action("fx_send_b_source", function(v) engine.fx_send_b_source(v - 1); re() end)
    control.level("fx_send_b_level", "Send B Level", 0, function(a) engine.fx_send_b_level(a); re() end)
  end

  -- The Keys are invisible: no pane, only a menu group, active while a voice is the input. They
  -- set what lib/synth does between keyboard and voice (Hold, Retrig, Octaves, MIDI port and
  -- channel).
  local function setup_synth()
    local function form_time(p) return fmt.time(fmt.nice(p:get())) end
    local function form_hz(p) return fmt.hz(fmt.nice(p:get(), true)) end
    -- Some knobs only count in one position of another; otherwise they stay out of the menu.
    local SHOWN_WHEN = {
      { ids = { "synth_retrig_div", "synth_retrig_feel", "synth_retrig_swing", "synth_retrig_gate" },
        on = function() return params:get("synth_retrig") == 2 end },
      { ids = { "synth_reset" },
        on = function() return params:get("synth_octaves") > 1 end },
    }
    local function visibility()
      for _, g in ipairs(SHOWN_WHEN) do
        local on = g.on()
        for _, id in ipairs(g.ids) do if on then params:show(id) else params:hide(id) end end
      end
      if not initing then _menu.rebuild_params() end
    end

    -- A plain entry is 0..100 % sent as 0..1, while time, hz, db and options bring their own ranges
    -- and scaling. set(x, v) replaces the engine call and receives the sent value x and the param
    -- value v.
    local KEYS_PARAMS = {
      { sep = "keys", name = "Keys" },
      { id = "hold",     name = "Hold",         options = { "Off", "On" }, set = function(_, v) synth.set_hold(v == 2) end },
      { id = "retrig",   name = "Retrig",       options = { "Off", "On" },
        set = function(_, v) synth.set_retrig(v == 2); visibility() end },
      { id = "retrig_div",  name = "Retrig Division", options = synth.RETRIG_DIVS, default = 3,
        set = function(_, v) synth.retrig_div = v end },
      { id = "retrig_feel", name = "Retrig Feel",     options = sync.FEEL_OPTS, set = function(_, v) synth.retrig_feel = v end },
      { id = "retrig_swing", name = "Retrig Swing",   default = 50, min = 50, max = 75,
        set = function(_, v) synth.retrig_swing = (v - 50) / 50 end },
      { id = "retrig_gate", name = "Retrig Gate",     default = 50, min = 10, step = 5, set = function(g) synth.retrig_gate = g end },
      { id = "octaves",  name = "Octaves",      options = { "1", "2", "3", "4" },
        set = function(_, v) synth.set_octaves(v); visibility() end },
      { id = "reset",    name = "Octave Reset", number = { 0, 64, 0 },
        fmt = function(p) local n = p:get(); return n == 0 and "Off" or (n == 1 and "1 strike" or n .. " strikes") end,
        set = function(n) synth.reset = n end },
      { sep = "midi", name = "MIDI" },
      { id = "midi_device",  name = "MIDI Device",  options = synth.port_names(), set = function(x) synth.midi_connect(x) end },
      { id = "midi_channel", name = "MIDI Channel", options = synth.CHANNELS, set = function(_, v) synth.set_channel(v) end },
    }

    params:add_group("KEYS", #KEYS_PARAMS)
    for _, e in ipairs(KEYS_PARAMS) do
      local id = "synth_" .. (e.sep and ("sep_" .. e.sep) or e.id)
      local conv
      if e.sep then
        params:add_separator(id, "─── " .. e.name .. " ───")
      elseif e.options then
        params:add_option(id, e.name, e.options, e.default or 1)
        conv = function(v) return v - 1 end
      elseif e.number then
        params:add_number(id, e.name, e.number[1], e.number[2], e.number[3], e.fmt)
        conv = function(v) return v end
      elseif e.time then
        params:add_control(id, e.name, control.spec("ms", 1, 10000, e.time), form_time)
        conv = function(v) return v / 1000 end
      elseif e.hz then
        params:add_control(id, e.name, control.spec("hz", e.hz[1], e.hz[2], e.hz[3]), form_hz)
        conv = function(v) return v end
      elseif e.db then
        params:add_control(id, e.name, control.spec("level", nil, nil, e.db))
        params:lookup_param(id).formatter = function(p) return control.level_str(p:get()) end
        conv = control.amp
      else
        local kind = (e.unit == nil or e.unit == "%") and "amount" or "steps"
        params:add_control(id, e.name, control.spec(kind, e.min or 0, e.max or 100, e.default, e.step or 1, e.unit), e.fmt)
        conv = function(v) return v * (e.scale or 0.01) end
      end
      if conv then
        params:set_action(id, function(v)
          local x = conv(v)
          if e.set then e.set(x, v) else engine[e.cmd or id](x); re() end
        end)
      end
    end
    visibility()

    midi.add = function() params:lookup_param("synth_midi_device").options = synth.port_names() end
    midi.remove = function(dev)
      midi.add()
      if synth.port == 0 or (dev and dev.port == synth.port) then synth.all_off() end
    end
    synth.active = function() return params:get("signal_input") >= 3 end
    -- Each voice brings its own param group (e.g. FORM).
    for _, vc in ipairs(VOICES) do
      vc.add_params(function() return initing end)
      vc.on_change = re
    end
  end

  local function find_filtered_idx(map, target)
    if map then
      for fi, gi in ipairs(map) do
        if gi == target then return fi end
      end
    end
    return 1
  end

  local function ui_revert(param_id, target_idx)
    local p = params:lookup_param(param_id)
    if p and p.selected ~= target_idx then
      p.selected = target_idx
      if _menu and _menu.rebuild_params then _menu.rebuild_params() end
    end
  end

  -- The mod sources register per slot (register_lfo, register_env, register_trigger,
  -- register_seq), each with Engage, its own knobs and two target lists (device, then knob)
  -- that show only what is free and meaningful right now, with an invalid choice snapping back
  -- (ui_revert). Own knobs that currently do nothing (Rate under Sync) are hidden by the source
  -- (refresh_visibility).
  local function register_lfo(idx)
    local prefix = "lfo" .. idx

    local function refresh_visibility()
      local wf  = params:get(prefix .. "_shape")
      local div = params:get(prefix .. "_sync_div")
      if div > 1 then
        params:hide(prefix .. "_rate")
      else
        params:show(prefix .. "_rate")
      end
      if wf == 6 then
        params:hide(prefix .. "_phase")
        params:hide(prefix .. "_rate_slew")
        params:show(prefix .. "_steps"); params:show(prefix .. "_stability")
        params:show(prefix .. "_sep_trigger"); params:show(prefix .. "_randomize")
      else
        params:show(prefix .. "_phase")
        params:show(prefix .. "_rate_slew")
        params:hide(prefix .. "_steps"); params:hide(prefix .. "_stability")
        params:hide(prefix .. "_sep_trigger"); params:hide(prefix .. "_randomize")
      end
      if _menu and _menu.rebuild_params then _menu.rebuild_params() end
    end

    local function compute_intended_global()
      local dev_filtered = params:get(prefix .. "_target_device")
      local dev_idx = (lfo.target_device_filter[idx] and lfo.target_device_filter[idx][dev_filtered]) or 1
      local param_filtered = params:get(prefix .. "_target_param")
      local g = (lfo.target_param_filter[idx] and lfo.target_param_filter[idx][param_filtered]) or 1
      if g <= 1 and DEVICE_PARAMS[dev_idx] and DEVICE_PARAMS[dev_idx][1] then
        g = DEVICE_PARAMS[dev_idx][1].global_idx
      end
      return g
    end

    params:add_group("LFO " .. idx, 18)
    params:add_separator(prefix .. "_sep_control", "─── Control ───")

    params:add_option(prefix .. "_enable", "Engage", {"Off", "On"}, 1)
    params:set_action(prefix .. "_enable", function(v)
      if not initing then
        if v == 2 then
          local g = compute_intended_global()
          local own = g > 1 and lfo.target_owner[TARGET_PARAMS[g].id]
          if own and own ~= idx then
            for i = 2, #TARGET_PARAMS do
              if not lfo.target_owner[TARGET_PARAMS[i].id] then g = i; break end
            end
          end
          lfo.set_target(idx, g)
        else
          lfo.set_target(idx, lfo.last_global[idx] or 1)
        end
      end
      re()
    end)

    params:add_option(prefix .. "_shape", "Shape", lfo.SHAPES, 1)
    params:set_action(prefix .. "_shape", function(_)
      refresh_visibility()
      if not initing then
        lfo.start_clock(idx)
        lfo.refresh_dropdowns_for_device("LFO " .. idx)
        trigs.fn.refresh_dropdowns_for_lfo(idx)
      end
      re()
    end)

    params:add_control(prefix .. "_rate", "Rate", control.spec("rate", 0.1, 25, 1))
    params:set_action(prefix .. "_rate", function(_)
      lfo.mod.rate[idx] = nil
      lfo.target_base[prefix .. "_rate"] = nil
    end)

    params:add_control(prefix .. "_depth", "Depth", control.spec("amount", 0, 100, 50))
    params:set_action(prefix .. "_depth", function(_)
      lfo.mod.depth[idx] = nil
      lfo.target_base[prefix .. "_depth"] = nil
    end)

    params:add_option(prefix .. "_dir", "Direction", lfo.DIR_OPTS, 3)

    params:add_option(prefix .. "_phase", "Phase", {"0°", "90°", "180°", "270°"}, 1)
    params:set_action(prefix .. "_phase", function(_)
      lfo.mod.phase[idx] = nil
      lfo.target_base[prefix .. "_phase"] = nil
    end)

    params:add_number(prefix .. "_steps", "Steps", 1, 16, 8)
    params:set_action(prefix .. "_steps", function(v)
      lfo.mod.steps[idx] = nil
      lfo.target_base[prefix .. "_steps"] = nil
      local s = lfo.state[idx]
      if s then s.tm_register = s.tm_register & lfo.tm_register_max(v) end
    end)

    params:add_control(prefix .. "_stability", "Stability", control.spec("amount", 0, 100, 50))
    params:set_action(prefix .. "_stability", function(_)
      lfo.mod.stability[idx] = nil
      lfo.target_base[prefix .. "_stability"] = nil
    end)

    params:add_control(prefix .. "_rate_slew", "Rate Slew", control.spec("s0", 0, 5, 0))
    params:set_action(prefix .. "_rate_slew", function(_)
      lfo.mod.rate_slew[idx] = nil
      lfo.target_base[prefix .. "_rate_slew"] = nil
    end)

    params:add_separator(prefix .. "_sep_sync", "─── Synchronization ───")

    params:add_option(prefix .. "_sync_div", "Division", sync.DIV_OPTS, 1)
    params:set_action(prefix .. "_sync_div", function(_)
      lfo.mod.sync_div[idx] = nil
      lfo.target_base[prefix .. "_sync_div"] = nil
      refresh_visibility()
      if not initing then
        lfo.refresh_dropdowns_for_device("LFO " .. idx)
        lfo.start_clock(idx)
      end
    end)

    params:add_option(prefix .. "_sync_feel", "Feel", sync.FEEL_OPTS, 1)
    params:set_action(prefix .. "_sync_feel", function(_)
      lfo.mod.sync_feel[idx] = nil
      lfo.target_base[prefix .. "_sync_feel"] = nil
    end)

    params:add_separator(prefix .. "_sep_target", "─── Target ───")

    params:add_option(prefix .. "_target_device", "Target Device", {"-"}, 1)
    params:set_action(prefix .. "_target_device", function(filtered_v)
      if not initing then
        local cur_global = lfo.last_global[idx] or 1
        local cur_dev = TARGET_DEVICE_OF[cur_global] or 0
        local dmap = lfo.target_device_filter[idx]
        local cur_filtered = find_filtered_idx(dmap, cur_dev)
        if not params.pset_loading then
          if filtered_v > cur_filtered + 1 then filtered_v = cur_filtered + 1
          elseif filtered_v < cur_filtered - 1 then filtered_v = cur_filtered - 1 end
        end
        local new_dev = (dmap and dmap[filtered_v]) or 1
        if new_dev ~= cur_dev or params.pset_loading then
          lfo.rebuild_target_param_dropdown(idx, new_dev)
          local new_global = 1
          if DEVICE_PARAMS[new_dev] then
            for _, entry in ipairs(DEVICE_PARAMS[new_dev]) do
              local owner = lfo.target_owner[TARGET_PARAMS[entry.global_idx].id]
              if owner == nil or owner == idx then new_global = entry.global_idx; break end
            end
          end
          lfo.set_target(idx, new_global)
        else
          ui_revert(prefix .. "_target_device", cur_filtered)
        end
      end
      re()
    end)

    params:add_option(prefix .. "_target_param", "Target Param", {"-"}, 1)
    params:set_action(prefix .. "_target_param", function(filtered_v)
      if not initing then
        local cur_global = lfo.last_global[idx] or 1
        local pmap = lfo.target_param_filter[idx]
        local cur_filtered = find_filtered_idx(pmap, cur_global)
        if not params.pset_loading then
          if filtered_v > cur_filtered + 1 then filtered_v = cur_filtered + 1
          elseif filtered_v < cur_filtered - 1 then filtered_v = cur_filtered - 1 end
        end
        local new_global = (pmap and pmap[filtered_v]) or 1
        if new_global ~= cur_global then
          lfo.set_target(idx, new_global)
        else
          ui_revert(prefix .. "_target_param", cur_filtered)
        end
      end
      re()
    end)

    params:add_separator(prefix .. "_sep_trigger", "─── Trigger ───")

    params:add_binary(prefix .. "_randomize", "Randomize", "trigger", 0)
    params:set_action(prefix .. "_randomize", function(v)
      if v == 1 and not initing then lfo.tm_randomize(idx) end
    end)
  end

  local function register_env(idx)
    local prefix = "env" .. idx

    local function compute_intended_global()
      local dev_filtered = params:get(prefix .. "_target_device")
      local dev_idx = (env.target_device_filter[idx] and env.target_device_filter[idx][dev_filtered]) or 1
      local param_filtered = params:get(prefix .. "_target_param")
      local g = (env.target_param_filter[idx] and env.target_param_filter[idx][param_filtered]) or 1
      if g <= 1 and DEVICE_PARAMS[dev_idx] and DEVICE_PARAMS[dev_idx][1] then
        g = DEVICE_PARAMS[dev_idx][1].global_idx
      end
      return g
    end

    params:add_group("SENSE " .. idx, 9)
    params:add_separator(prefix .. "_sep_control", "─── Control ───")

    params:add_option(prefix .. "_enable", "Engage", {"Off", "On"}, 1)
    params:set_action(prefix .. "_enable", function(v)
      if not initing then
        if v == 2 then
          local g = compute_intended_global()
          local own = g > 1 and lfo.target_owner[TARGET_PARAMS[g].id]
          if own and own ~= "env_" .. idx then
            for i = 2, #TARGET_PARAMS do
              if not lfo.target_owner[TARGET_PARAMS[i].id] then g = i; break end
            end
          end
          env.set_target(idx, g)
        else
          env.set_target(idx, env.last_global[idx] or 1)
        end
        env.poll_set_active(idx, v == 2)
      end
      re()
    end)

    params:add_control(prefix .. "_depth", "Depth", control.spec("amount", 0, 100, 50))

    params:add_option(prefix .. "_dir", "Direction", env.DIR_OPTS, 1)

    -- Freeze holds the modulation where it stands. The Sense keeps listening but sends nothing
    -- new to its target until Freeze is off.
    params:add_option(prefix .. "_freeze", "Freeze", {"Off", "On"}, 1)

    params:add_control(prefix .. "_slew", "Slew", control.spec("ms", 1, 500, 50))
    params:set_action(prefix .. "_slew", function(v)
      local s = v / 1000
      engine[prefix .. "_attack"](s)
      engine[prefix .. "_release"](s)
    end)

    params:add_separator(prefix .. "_sep_target", "─── Target ───")

    params:add_option(prefix .. "_target_device", "Target Device", {"-"}, 1)
    params:set_action(prefix .. "_target_device", function(filtered_v)
      if not initing then
        local cur_global = env.last_global[idx] or 1
        local cur_dev = TARGET_DEVICE_OF[cur_global] or 0
        local dmap = env.target_device_filter[idx]
        local cur_filtered = 1
        if dmap then
          for fi, gi in ipairs(dmap) do if gi == cur_dev then cur_filtered = fi; break end end
        end
        if not params.pset_loading then
          if filtered_v > cur_filtered + 1 then filtered_v = cur_filtered + 1
          elseif filtered_v < cur_filtered - 1 then filtered_v = cur_filtered - 1 end
        end
        local new_dev = (dmap and dmap[filtered_v]) or 1
        if new_dev ~= cur_dev or params.pset_loading then
          env.rebuild_target_param_dropdown(idx, new_dev)
          local new_global = 1
          if DEVICE_PARAMS[new_dev] then
            for _, entry in ipairs(DEVICE_PARAMS[new_dev]) do
              local owner = lfo.target_owner[TARGET_PARAMS[entry.global_idx].id]
              if owner == nil or owner == "env_" .. idx then new_global = entry.global_idx; break end
            end
          end
          env.set_target(idx, new_global)
        else
          local p = params:lookup_param(prefix .. "_target_device")
          if p and p.selected ~= cur_filtered then
            p.selected = cur_filtered
            if _menu and _menu.rebuild_params then _menu.rebuild_params() end
          end
        end
      end
      re()
    end)

    params:add_option(prefix .. "_target_param", "Target Param", {"-"}, 1)
    params:set_action(prefix .. "_target_param", function(filtered_v)
      if not initing then
        local cur_global = env.last_global[idx] or 1
        local pmap = env.target_param_filter[idx]
        local cur_filtered = 1
        if pmap then
          for fi, gi in ipairs(pmap) do if gi == cur_global then cur_filtered = fi; break end end
        end
        if not params.pset_loading then
          if filtered_v > cur_filtered + 1 then filtered_v = cur_filtered + 1
          elseif filtered_v < cur_filtered - 1 then filtered_v = cur_filtered - 1 end
        end
        local new_global = (pmap and pmap[filtered_v]) or 1
        if new_global ~= cur_global then
          env.set_target(idx, new_global)
        else
          local p = params:lookup_param(prefix .. "_target_param")
          if p and p.selected ~= cur_filtered then
            p.selected = cur_filtered
            if _menu and _menu.rebuild_params then _menu.rebuild_params() end
          end
        end
      end
      re()
    end)
  end

  local function register_trigger(idx)
    local prefix = "trig" .. idx

    local function refresh_visibility()
      local div = params:get(prefix .. "_sync_div")
      if div > 1 then params:hide(prefix .. "_rate")
      else            params:show(prefix .. "_rate") end
      if _menu and _menu.rebuild_params then _menu.rebuild_params() end
    end

    local default_dev = 1
    local dev_shorts = {}
    if trigs.DEVICE_PARAMS[default_dev] then
      for _, e in ipairs(trigs.DEVICE_PARAMS[default_dev]) do
        dev_shorts[#dev_shorts + 1] = e.label
      end
    end
    if #dev_shorts == 0 then dev_shorts = {"-"} end

    params:add_group("TRIGGER " .. idx, 10)
    params:add_separator(prefix .. "_sep_control", "─── Control ───")

    params:add_option(prefix .. "_enable", "Engage", {"Off", "On"}, 1)
    params:set_action(prefix .. "_enable", function(_)
      if not initing then trigs.fn.set_enable(idx) end
      re()
    end)

    params:add_control(prefix .. "_chance", "Chance", control.spec("amount", 0, 100, 100))
    params:set_action(prefix .. "_chance", function(_)
      trigs.mod.chance[idx] = nil
      lfo.target_base[prefix .. "_chance"] = nil
      re()
    end)

    params:add_control(prefix .. "_rate", "Rate", control.spec("rate", 0.1, 25, 1))
    params:set_action(prefix .. "_rate", function(_)
      trigs.mod.rate[idx] = nil
      lfo.target_base[prefix .. "_rate"] = nil
    end)

    params:add_separator(prefix .. "_sep_sync", "─── Synchronization ───")

    params:add_option(prefix .. "_sync_div", "Division", sync.DIV_OPTS, 1)
    params:set_action(prefix .. "_sync_div", function(_)
      trigs.mod.sync_div[idx] = nil
      lfo.target_base[prefix .. "_sync_div"] = nil
      refresh_visibility()
      if not initing then
        lfo.refresh_dropdowns_for_device("Trigger " .. idx)
        trigs.fn.start_clock(idx)
      end
      re()
    end)

    params:add_option(prefix .. "_sync_feel", "Feel", sync.FEEL_OPTS, 1)
    params:set_action(prefix .. "_sync_feel", function(_)
      trigs.mod.sync_feel[idx] = nil
      lfo.target_base[prefix .. "_sync_feel"] = nil
    end)

    params:add_separator(prefix .. "_sep_target", "─── Target ───")

    params:add_option(prefix .. "_target_device", "Target Device", trigs.DEVICES, default_dev)
    params:set_action(prefix .. "_target_device", function(filtered_v)
      if not initing then
        local cur_global = trigs.last_global[idx] or 1
        local cur_dev = trigs.TARGET_DEVICE_OF[cur_global]
        if not cur_dev then
          local dev_filtered = params:get(prefix .. "_target_device")
          cur_dev = (trigs.target_device_filter[idx] and trigs.target_device_filter[idx][dev_filtered]) or 1
        end
        local dmap = trigs.target_device_filter[idx]
        local cur_filtered = find_filtered_idx(dmap, cur_dev)
        if not params.pset_loading then
          if filtered_v > cur_filtered + 1 then filtered_v = cur_filtered + 1
          elseif filtered_v < cur_filtered - 1 then filtered_v = cur_filtered - 1 end
        end
        local new_dev = (dmap and dmap[filtered_v]) or 1
        if new_dev ~= cur_dev or params.pset_loading then
          trigs.fn.rebuild_target_param_dropdown(idx, new_dev)
          local new_global = 1
          if trigs.DEVICE_PARAMS[new_dev] then
            for _, entry in ipairs(trigs.DEVICE_PARAMS[new_dev]) do
              local tid = trigs.TARGETS[entry.global_idx].id
              local owner = tid and trigs.target_owner[tid]
              if owner == nil or owner == idx then new_global = entry.global_idx; break end
            end
          end
          trigs.fn.set_target(idx, new_global)
        else
          ui_revert(prefix .. "_target_device", cur_filtered)
        end
      end
      re()
    end)

    params:add_option(prefix .. "_target_param", "Target Action", dev_shorts, 1)
    params:set_action(prefix .. "_target_param", function(filtered_v)
      if not initing then
        local cur_global = trigs.last_global[idx] or 1
        local pmap = trigs.target_param_filter[idx]
        local cur_filtered = find_filtered_idx(pmap, cur_global)
        if not params.pset_loading then
          if filtered_v > cur_filtered + 1 then filtered_v = cur_filtered + 1
          elseif filtered_v < cur_filtered - 1 then filtered_v = cur_filtered - 1 end
        end
        local new_global = (pmap and pmap[filtered_v]) or 1
        if new_global ~= cur_global then
          trigs.fn.set_target(idx, new_global)
        else
          ui_revert(prefix .. "_target_param", cur_filtered)
        end
      end
      re()
    end)
  end

  -- Two clock guards watch transport start and stop and, twice a second, the clock's source and
  -- tempo. A PSET loaded between two checks keeps its divisions rather than having them overwritten
  -- with defaults.
  local function setup_clock_watchers()
    clock.transport.start = function()
      clock_running = true
      sync.activate_defaults()
      if count_active then count_clock_start() end
      sync.push_all(initing, clock_running, lfo.sync_override)
      looper.quant_led_restart()
      redraw()
    end

    clock.transport.stop = function()
      clock_running = false
      if count_active then count_clock_start() end
      sync.push_all(initing, clock_running, lfo.sync_override)
      looper.quant_led_restart()
      redraw()
    end

    clock.run(function()
      local last_source = nil
      local last_bpm = 0
      local waking = true
      local seen_epoch = params.pset_epoch
      while true do
        clock.sleep(0.5)

        local current_source = nil
        pcall(function() current_source = params:get("clock_source") end)
        local pset_arrived = params.pset_epoch ~= seen_epoch
        seen_epoch = params.pset_epoch
        if pset_arrived then
          last_source = current_source
        elseif current_source and current_source ~= last_source then
          local default = current_source == 2 and sync.DIV_DEFAULT or 1
          params:set("tremolo_sync_div", default)
          params:set("warp_sync_div",    default)
          params:set("repeat_sync_div",  default)
          params:set("looper_quant_div", default)
          last_source = current_source
        end

        local bpm = math.floor(clock.get_tempo() + 0.5)
        if bpm ~= last_bpm then
          if last_bpm == 0 and bpm > 0 then
            clock_running = true
            -- On waking the source has already decided; only a later clock start wakes the free
            -- divisions to their defaults.
            if not (waking or pset_arrived) then sync.activate_defaults() end
            if count_active then count_clock_start() end
            looper.quant_led_restart()
          elseif bpm == 0 and last_bpm > 0 then
            clock_running = false
            if count_active then count_clock_start() end
            looper.quant_led_restart()
          end
          last_bpm = bpm
          if clock_running then sync.reconcile(clock.get_tempo()) end
          sync.push_all(initing, clock_running, lfo.sync_override)
          redraw()
        end
        -- BPM follows the clock while it runs (writing back to the tempo is then a no-op).
        if bpm >= 20 and bpm <= 300 and params:get("count_bpm") ~= bpm then
          params:set("count_bpm", bpm)
        end
        waking = false
      end
    end)
  end

  local function setup_gui()
    params:add_group("GUI", 5)
    params:add_separator("gui_sep_control", "─── Control ───")
    params:add_option("gui", "GUI", {"Studio", "Stage", "Off"}, 1)
    params:set_action("gui", function(v)
      gui_mode = v
      mod_open = false
      if v == 1 then
        studio_sel = STUDIO_INDEX_OF.AMP or 1
        studio_apply()
      elseif v == 2 then
        perf_sel = PERF_INDEX_OF.TUN or 1
      end
      if refresh_tune then refresh_tune() end
      redraw()
    end)
    params:add_option("gui_follow_focus", "Follow Focus", {"Off", "On"}, 2)
    params:add_option("gui_midi_pickup", "MIDI Pickup", {"Off", "On"}, 2)
    params:set_action("gui_midi_pickup", function(v) midimap.pickup = (v == 2) end)
    params:add_binary("gui_init", "Initialize", "trigger", 0)
    params:set_action("gui_init", function(v)
      if v ~= 1 or initing then return end
      local was_loading = params.pset_loading
      params.pset_loading = true
      for i = 1, params.count do
        local p = params.params[i]
        local t = p.t
        if t == params.tNUMBER or t == params.tOPTION then
          params:set(i, p.default)
        elseif t == params.tCONTROL or t == params.tTAPER then
          params:set(i, (p.controlspec and p.controlspec.default) or p.default)
        end
      end
      params.pset_loading = was_loading
      re()
    end)
  end

  -- ── Registering params ───────────────────────────────────────
  params:add_separator("princeton_header", "─── PRINCETON ───")
  setup_gui()
  setup_signal_flow()
  setup_synth()
  setup_tuner()
  setup_metro()
  setup_gate()
  setup_fray()
  for i = 1, #PEDALS do setup_pedal(i) end
  setup_amp()
  setup_tremolo()
  setup_hold(1)
  setup_hold(2)
  setup_looper()
  setup_reverb()
  setup_cab()
  setup_tape()
  setup_build()
  setup_envelop()
  local function register_seq(idx)
    local prefix = "seq" .. idx

    local function refresh_visibility()
      local div = params:get(prefix .. "_sync_div")
      local n   = params:get(prefix .. "_steps")
      if div > 1 then params:hide(prefix .. "_rate") else params:show(prefix .. "_rate") end
      for k = 1, seq.MAX_STEPS do
        if k <= n then params:show(prefix .. "_step_" .. k) else params:hide(prefix .. "_step_" .. k) end
      end
      if _menu and _menu.rebuild_params then _menu.rebuild_params() end
    end

    local function compute_intended_global()
      local dev_filtered = params:get(prefix .. "_target_device")
      local dev_idx = (seq.target_device_filter[idx] and seq.target_device_filter[idx][dev_filtered]) or 1
      local param_filtered = params:get(prefix .. "_target_param")
      local g = (seq.target_param_filter[idx] and seq.target_param_filter[idx][param_filtered]) or 1
      if g <= 1 and DEVICE_PARAMS[dev_idx] and DEVICE_PARAMS[dev_idx][1] then
        g = DEVICE_PARAMS[dev_idx][1].global_idx
      end
      return g
    end

    params:add_group("WALK " .. idx, 29)
    params:add_separator(prefix .. "_sep_control", "─── Control ───")

    params:add_option(prefix .. "_enable", "Engage", {"Off", "On"}, 1)
    params:set_action(prefix .. "_enable", function(v)
      if not initing then
        if v == 2 then
          local g = compute_intended_global()
          local own = g > 1 and lfo.target_owner[TARGET_PARAMS[g].id]
          if own and own ~= "seq_" .. idx then
            for i = 2, #TARGET_PARAMS do
              if not lfo.target_owner[TARGET_PARAMS[i].id] then g = i; break end
            end
          end
          seq.set_target(idx, g)
        else
          seq.set_target(idx, seq.last_global[idx] or 1)
        end
      end
      re()
    end)

    params:add_number(prefix .. "_steps", "Steps", 2, 16, 16)
    params:set_action(prefix .. "_steps", function(v)
      seq.mod.steps[idx] = nil
      lfo.target_base[prefix .. "_steps"] = nil
      local s = seq.state[idx]
      if s and s.step_pos > v then s.step_pos = ((s.step_pos - 1) % v) + 1 end
      refresh_visibility()
      re()
    end)

    for k = 1, seq.MAX_STEPS do
      params:add_control(prefix .. "_step_" .. k, "Step " .. k, control.spec("amount", -100, 100, 0))
    end

    params:add_control(prefix .. "_rate", "Rate", control.spec("rate", 0.1, 25, 1))
    params:set_action(prefix .. "_rate", function(_)
      seq.mod.rate[idx] = nil
      lfo.target_base[prefix .. "_rate"] = nil
    end)

    params:add_control(prefix .. "_rate_slew", "Rate Slew", control.spec("s0", 0, 5, 0))
    params:set_action(prefix .. "_rate_slew", function(_)
      seq.mod.rate_slew[idx] = nil
      lfo.target_base[prefix .. "_rate_slew"] = nil
    end)

    params:add_separator(prefix .. "_sep_sync", "─── Synchronization ───")

    params:add_option(prefix .. "_sync_div", "Division", sync.DIV_OPTS, 1)
    params:set_action(prefix .. "_sync_div", function(_)
      seq.mod.sync_div[idx] = nil
      lfo.target_base[prefix .. "_sync_div"] = nil
      refresh_visibility()
      if not initing then
        seq.refresh_dropdowns_for_device("Walk " .. idx)
        seq.start_clock(idx)
      end
    end)

    params:add_option(prefix .. "_sync_feel", "Feel", sync.FEEL_OPTS, 1)
    params:set_action(prefix .. "_sync_feel", function(_)
      seq.mod.sync_feel[idx] = nil
      lfo.target_base[prefix .. "_sync_feel"] = nil
    end)

    params:add_separator(prefix .. "_sep_target", "─── Target ───")

    params:add_option(prefix .. "_target_device", "Target Device", {"-"}, 1)
    params:set_action(prefix .. "_target_device", function(filtered_v)
      if not initing then
        local cur_global = seq.last_global[idx] or 1
        local cur_dev = TARGET_DEVICE_OF[cur_global] or 0
        local dmap = seq.target_device_filter[idx]
        local cur_filtered = find_filtered_idx(dmap, cur_dev)
        if not params.pset_loading then
          if filtered_v > cur_filtered + 1 then filtered_v = cur_filtered + 1
          elseif filtered_v < cur_filtered - 1 then filtered_v = cur_filtered - 1 end
        end
        local new_dev = (dmap and dmap[filtered_v]) or 1
        if new_dev ~= cur_dev or params.pset_loading then
          seq.rebuild_target_param_dropdown(idx, new_dev)
          local new_global = 1
          if DEVICE_PARAMS[new_dev] then
            for _, entry in ipairs(DEVICE_PARAMS[new_dev]) do
              local owner = lfo.target_owner[TARGET_PARAMS[entry.global_idx].id]
              if owner == nil or owner == "seq_" .. idx then new_global = entry.global_idx; break end
            end
          end
          seq.set_target(idx, new_global)
        else
          ui_revert(prefix .. "_target_device", cur_filtered)
        end
      end
      re()
    end)

    params:add_option(prefix .. "_target_param", "Target Param", {"-"}, 1)
    params:set_action(prefix .. "_target_param", function(filtered_v)
      if not initing then
        local cur_global = seq.last_global[idx] or 1
        local pmap = seq.target_param_filter[idx]
        local cur_filtered = find_filtered_idx(pmap, cur_global)
        if not params.pset_loading then
          if filtered_v > cur_filtered + 1 then filtered_v = cur_filtered + 1
          elseif filtered_v < cur_filtered - 1 then filtered_v = cur_filtered - 1 end
        end
        local new_global = (pmap and pmap[filtered_v]) or 1
        if new_global ~= cur_global then
          seq.set_target(idx, new_global)
        else
          ui_revert(prefix .. "_target_param", cur_filtered)
        end
      end
      re()
    end)

    params:add_separator(prefix .. "_sep_trigger", "─── Trigger ───")

    params:add_binary(prefix .. "_randomize", "Randomize", "trigger", 0)
    params:set_action(prefix .. "_randomize", function(v)
      if v == 1 and not initing then seq.randomize(idx) end
    end)
  end

  for i = 1, env.NUM do register_env(i) end
  for i = 1, lfo.NUM do register_lfo(i) end
  for i = 1, seq.NUM do register_seq(i) end
  for i = 1, trigs.N do register_trigger(i) end
  tune.init()

  local function target_active(id)
    local owner = lfo.target_owner[id]
    if owner == nil then return false end
    if type(owner) == "number" then return lfo.is_enabled(owner) end
    local n = type(owner) == "string" and owner:match("^env_(%d+)$")
    if n then return env.is_enabled(tonumber(n)) end
    local ns = type(owner) == "string" and owner:match("^seq_(%d+)$")
    return ns ~= nil and seq.is_enabled(tonumber(ns))
  end

  for _, t in ipairs(TARGET_PARAMS) do
    if t.id then
      local p = params:lookup_param(t.id)
      if p and p.action then
        local orig = p.action
        params:set_action(t.id, function(v)
          lfo.target_base[t.id] = v
          if t.id == "looper_speed" or not target_active(t.id) then orig(v) end
        end)
      end
    end
  end

  -- The mod sources name their target in the PSET by name (see lib/modtarget.lua).
  mod_bindings = { lfo.binding(), env.binding(), trigs.binding(), seq.binding() }
  modtarget.add_id_params(mod_bindings)
  fmt.apply_all()
  menu_rows.install()
  -- Mod targets take range and resolution from their param, so a range lives in one place only.
  for _, t in ipairs(TARGET_PARAMS) do
    local p  = t.id and params.lookup[t.id] and params:lookup_param(t.id)
    local cs = p and p.t == params.tCONTROL and p.controlspec
    if cs then t.mn, t.mx, t.st = cs.minval, cs.maxval, cs.fine or (cs.step > 0 and cs.step) or 0.01 end
  end
  params:bang()
  midimap.on_touch = function(id) if params:get("gui_follow_focus") == 2 then focus_param(id) end end
  midimap.init()
  local live_poll = poll.set("hold_live", function(v)
    local pk = hold_scope.peaks
    table.insert(pk, v)
    if #pk > 27 then table.remove(pk, 1) end
  end)
  live_poll.time = 1.2 / 27
  local osc_prev = osc.event
  osc.event = function(path, args, from)
    if path == "/princeton/hold_wave" then
      local w = {}
      for k = 2, #args do w[k - 1] = args[k] end
      hold_wave[args[1]] = w
      redraw()
    elseif path == "/princeton/voice_missing" then
      print("princeton: Stimme '" .. tostring(args[1]) .. "' fehlt in SuperCollider - SYSTEM > RESTART")
    elseif osc_prev then
      osc_prev(path, args, from)
    end
  end
  initing = false

  do
    local mods = {}
    for i = 1, env.NUM do mods[#mods + 1] = { idx = i, set = env.set_target } end
    for i = 1, lfo.NUM do mods[#mods + 1] = { idx = i, set = lfo.set_target } end
    for _, m in ipairs(mods) do
      m.set(m.idx, 1)
    end
  end

  env.start_polls()

  for i = 1, trigs.N do
    trigs.fn.set_target(i, trigs.last_global[i] or 1)
    trigs.fn.set_enable(i)
  end

  setup_clock_watchers()
  redraw()

  -- norns bangs its system params once the script is up, which turns the input monitor and its
  -- own reverb back on; princeton mixes the guitar and brings its own reverbs, so both go quiet.
  clock.run(function()
    clock.sleep(0.2)
    audio.level_monitor(0)
    audio.rev_off()
  end)

  clock.run(function()
    while true do
      clock.sleep(1/25)
      if _G.screenstream_active then
        local ok, d = pcall(screen.peek, 0, 0, 128, 64)
        if ok and type(d) == "string" and #d == 8192 then
          local f = io.open("/dev/shm/norns_screen.raw.tmp", "wb")
          if f then
            f:write(d)
            f:close()
            os.rename("/dev/shm/norns_screen.raw.tmp", "/dev/shm/norns_screen.raw")
          end
        end
      end
    end
  end)

  -- ── Poll guard ───────────────────────────────────────────────
  -- Every engine display costs OSC traffic and garbage-collector work, so the guard keeps a poll
  -- open only while its device is on. Build keeps its line whenever it is on, because its history
  -- keeps growing unseen.
  local hold_pad_polls = hold_polls_make()
  local evp_poll = poll.set("evp_level", function(v) evp.level = v end)
  evp_poll.time = 1 / 15
  local bld_polls, tape_polls = {}, {}
  for k, name in ipairs({ "bld_level_a", "bld_level_b" }) do
    local p = poll.set(name, function(v) bld_level_in(k, v, 1 / 30) end)
    p.time = 1 / 30
    bld_polls[k] = p
  end
  for ch, name in ipairs({ "tape_in_l", "tape_in_r", "tape_out_l", "tape_out_r" }) do
    local p = poll.set(name, function(v) tape.lvl[ch] = v end)
    p.time = 1 / 15
    tape_polls[ch] = p
  end
  local strip_polls = {}
  for ch, name in ipairs({ "strip_out_l", "strip_out_r", "strip_drive_l", "strip_drive_r" }) do
    local p = poll.set(name, function(v) chstrip.lvl[ch] = v end)
    p.time = 1 / 15
    strip_polls[ch] = p
  end
  local rev_poll = poll.set("reverb_level", function(v) chstrip.rev.level = v end)
  rev_poll.time = 1 / 15
  -- the Strip's units or the spring tank, whichever the amp slot shows right now
  local function strip_shown(abbr)
    return gui_mode == 1 and not mod_open and view_group == 0 and view_pane[0] == 1
       and amp_kind() == "strip" and STUDIO_DEVICES[studio_sel].abbr == (abbr or "AMP")
  end
  local poll_open = {}
  local function gate(list, on)
    for _, p in ipairs(list) do
      if poll_open[p] ~= on then
        poll_open[p] = on
        if on then p:start() else p:stop() end
      end
    end
  end
  local function pane_shown(k)
    return gui_mode == 1 and not mod_open and view_group == DEV_GROUP and view_pane[DEV_GROUP] == k
  end
  local live_list, evp_list = { live_poll }, { evp_poll }
  local function gate_polls()
    gate(hold_pad_polls[1], params:get("hold1_enable") == 2)
    gate(hold_pad_polls[2], params:get("hold2_enable") == 2)
    gate(live_list,  pane_shown(3))
    gate(bld_polls,  params:get("bld_enable") == 2)
    gate(tape_polls, pane_shown(4) and params:get("tape_enable") == 2)
    gate(evp_list,   pane_shown(5) and params:get("evp_enable") == 2)
    gate(strip_polls, strip_shown() and not amp_is_bypassed())
    gate({ rev_poll }, strip_shown("RVB") and params:get("reverb_enable") == 2)
  end
  gate_polls()
  clock.run(function()
    while true do
      clock.sleep(1 / 15)
      gate_polls()
      if not initing and gui_mode == 1 and not mod_open
         and view_group == DEV_GROUP and view_pane[DEV_GROUP] == 3 then
        hold_grain_tick(1)
        hold_grain_tick(2)
        redraw()
      elseif not initing and gui_mode == 1 and not mod_open
         and view_group == DEV_GROUP and view_pane[DEV_GROUP] == 4 then
        tape.tick(1 / 15)
        redraw()
      elseif not initing and gui_mode == 1 and not mod_open
         and view_group == DEV_GROUP and view_pane[DEV_GROUP] == 5 then
        evp_tick(1 / 15)
        redraw()
      elseif not initing and strip_shown() then
        redraw()
      elseif not initing and strip_shown("RVB") then
        chstrip.rev.t = chstrip.rev.t + 1 / 15
        redraw()
      elseif strip_live and not initing then
        redraw()
      end
    end
  end)

  do
    local last = {}
    clock.run(function()
      while true do
        clock.sleep(1/20)
        local fire = params:get("gui_follow_focus") == 2 and not initing and not params.pset_loading
        if not initing then hold_move_marks() end
        local changed, n_changed = nil, 0
        for _, id in ipairs(FOCUS_IDS) do
          local v = focus_value(id)
          if last[id] == nil then
            last[id] = v
          elseif v ~= last[id] then
            last[id] = v
            if focus_absorb[id] then
              focus_absorb[id] = nil
            else
              changed, n_changed = id, n_changed + 1
            end
          end
        end
        -- Only when exactly one device has moved does the view follow it.
        if fire and n_changed == 1 then focus_device(changed) end
      end
    end)
  end
end

function cleanup()
  -- Hand the PSET reader back so the next script reads with norns' own eyes again.
  if params._orig_read then
    params.read = params._orig_read
    params._orig_read, params.pset_loading, params.pset_epoch = nil, nil, nil
  end
  -- princeton muted the input monitor and the system reverb. The next script gets back what the
  -- system mixer shows.
  pcall(function() mix:lookup_param("monitor"):bang() end)
  pcall(function() params:lookup_param("reverb"):bang() end)
  menu_rows.remove()
  midimap.cleanup()
  synth.cleanup()
end
