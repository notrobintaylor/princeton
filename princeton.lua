-- princeton
--
-- Amp sim based on a combo.
-- Tuner, effects and looper.

engine.name = "Princeton"

local initing = true

local sprites = include("lib/sprites")
-- device sprites live apart: lib/sprites is shared byte-for-byte with media, and Cut,
-- Fray, EQ and Limit exist only here
local sprites_device = include("lib/sprites_device")
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
local lifecycle = include("lib/lifecycle")

-- The amp panel's eight knobs, left to right: this order IS the drawing order, because
-- cabinet.draw_panel highlights knob i for PARAMS_DEF index i. Tremolo sits ahead of Reverb
-- so the panel reads in the same order E1 walks the chain. The ninth entry, mic_position,
-- has no knob; selecting it simply leaves the panel unhighlighted.
local PARAMS_DEF = {
  { id="amp_volume",         name="Volume",    default=5.0,  min=0,    max=10, step=0.1, db=false, cat="Amp"     },
  { id="amp_bass",           name="Bass",      default=5.0,  min=0,   max=10, step=0.1, db=false, cat="Amp"     },
  { id="amp_treble",         name="Treble",    default=5.0,  min=0,   max=10, step=0.1, db=false, cat="Amp"     },
  { id="amp_master",         name="Master",    default=7.5,  min=0,   max=10, step=0.1, db=false, cat="Amp"     },
  { id="tremolo_intensity", name="Intensity", default=0,    min=0,   max=100, step=1,  db=false, unit="%", cat="Tremolo" },
  { id="tremolo_speed",     name="Speed",     default=2.5,  min=0.1, max=25, step=0.1, db=false, unit="Hz", cat="Tremolo" },
  { id="reverb_amount",     name="Amount",    default=25,   min=0,   max=100, step=1,  db=false, unit="%", cat="Reverb"  },
  { id="reverb_length",     name="Length",    default=2.5,  min=0.5, max=5.0, step=0.1, db=false, unit="s", cat="Reverb"  },
  { id="mic_position",            name="Position",     default=1,    min=0,   max=2,  step=1,   db=false, cat="Mic"     },
}
local LOOPER_DEF = {
  { id="looper_medium",     name="Medium",     default=4,   min=1,  max=6,  step=1,   db=false, cat="Loop", options={"BBD","Cassette","CD","Chip","Tape","Vinyl"} },
  { id="looper_wear",       name="Wear",       default=5,   min=0,  max=100, step=1, db=false, unit="%", cat="Loop"  },
  { id="looper_direction",  name="Direction",  default=0,   min=0,   max=3,  step=1,  db=false, cat="Loop"  },
  { id="looper_dub_level",  name="Rec Level",  default=-2.5, min=-40, max=0, step=0.5, db=true, cat="Loop"  },
  { id="looper_level",      name="Play Level", default=-2.5, min=-40, max=0, step=0.5, db=true, cat="Loop"  },
  { id="looper_fade_level", name="Fade Level", default=-2.5, min=-40, max=0, step=0.5, db=true, cat="Loop"  },
  { id="looper_speed",      name="Speed",      default=0,   min=-100, max=100, step=1, db=false, cat="Loop"  },
  { id="looper_quant_div",  name="Quantize",      default=1,   min=1, max=8, step=1, db=false, cat="Loop", options={"Off","1/1","1/2","1/4","1/8","1/16","1/32","1/64"} },
  { id="looper_quant_feel", name="Quantize Feel", default=1,   min=1, max=3, step=1, db=false, cat="Loop", options={"Note","Dotted","Triplet"} },
}
local MIC_NAMES  = { "Center", "Middle", "Edge" }
local DIR_NAMES  = looper_params.DIR_NAMES

-- Index of the highlighted knob on the cabinet's fixed nine-knob panel (PARAMS_DEF).
-- E2 walks the focused device's whole param list, which is longer than its knobs; see
-- cab_sync_knob. Never the selection itself, only what the panel draws.
local sel = 1

local function amp_is_bypassed()
  return params:get("amp_enable") == 1
end


local view_group = 0
local view_pane  = {[0]=1, [1]=1, [3]=1, [4]=1}
local gui_mode   = 1   -- 1=Studio, 2=Stage, 3=Off
local perf_sel   = 1   -- selected device in performance view
local perf_param = {}  -- per-device selected param index
local mod_open   = false  -- mod rack showing (K1 held), in either view
local studio_sel = 1      -- selected device in the studio walk (STUDIO_DEVICES index)
local focus_absorb = {}   -- params written by the script itself; Follow Focus swallows these
local dev_param_sel = {}  -- per studio device, selected index into that device's params
local studio_apply        -- forward decl; points the views at STUDIO_DEVICES[studio_sel]
-- forward decl; the param E2 points at in the cabinet view, as id + owning device name.
-- Declared here because draw_left_strip needs it long before STUDIO_DEVICES exists, and a
-- local used above its declaration silently reads a global instead (L74).
local cab_sel_id
local MOD_PANE_1 = 3      -- first mod rack pane past Tune (1) and Count (2)
local refresh_tune    -- forward decl; syncs tune.active to the current view/device
local lfo_strip_sel = {1, 1, 1, 1, 1, 1, 1, 1}
local seq_strip_sel = {1, 1}
local count_strip_sel = 1

local PEDALS = {
  {
    name       = "Push",
    display    = "Push",
    params     = {
      { id="push_gain",  name="Gain",  default=5.0, min=0, max=10, step=0.1 },
      { id="push_tone",  name="Tone",  default=5.0, min=0, max=10, step=0.1 },
      { id="push_level", name="Level", default=5.0, min=0, max=10, step=0.1 },
      { id="push_mix",   name="Mix",   default=25, min=0, max=100, step=1, unit="%" },
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
      { id="distort_gain",    name="Gain",     default=5.0, min=0, max=10, step=0.1 },
      { id="distort_tone",    name="Tone",     default=7.5, min=0, max=10, step=0.1 },
      { id="distort_level",   name="Level",    default=5.0, min=0, max=10, step=0.1 },
      { id="distort_lowcut",  name="Low Cut",  default=0, min=0, max=2, step=1, options={"Off","100 Hz","250 Hz"} },
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
      { id="warp_rate",  name="Rate",      default=2.5, min=0.1, max=25, step=0.1, unit="Hz", warp="exp" },
      { id="warp_depth", name="Depth",     default=5, min=0, max=100, step=1, unit="%" },
      { id="warp_rise",  name="Rise/Fall", default=2.5, min=0.01, max=5.0, step=0.01, unit="s", warp="exp" },
      { id="warp_mix",   name="Mix",       default=0,  min=0, max=100, step=1, unit="%" },
    },
    psel       = 1,
    bypass_cmd = "warp_bypass",
    enable_id  = "warp_enable",
  },
  {
    name       = "Repeat",
    display    = "Repeat",
    params     = {
      { id="repeat_time",           name="Time",      default=250, min=1, max=1000, step=1, unit="ms" },
      { id="repeat_feedback",       name="Feedback",  default=50, min=0, max=100, step=1, unit="%" },
      { id="repeat_level",          name="Level",     default=50, min=0, max=100, step=1, unit="%" },
      { id="repeat_characteristic", name="Color",     default=0,   min=0, max=1,  step=1, options={"Bright","Dark"} },
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
local db_to_lin = function(db) return 10 ^ (db / 20) end


-- ── Triggers ────────────────────────────────────────────────────


local TARGET_PARAMS = {
  {label="Off"},
  {label="Cut: Threshold",    id="cut_thresh",       mn=-80,  mx=0,     st=0.5,  send=function(v) engine.cut_thresh(v) end},
  {label="Cut: Attack",       id="cut_attack",       mn=0.1,  mx=2500,  st=0.1,  send=function(v) engine.cut_attack(v) end},
  {label="Cut: Hold",         id="cut_hold",         mn=1,    mx=2500,  st=1,    send=function(v) engine.cut_hold(math.floor(v)) end},
  {label="Cut: Release",      id="cut_release",      mn=1,    mx=2500,  st=1,    send=function(v) engine.cut_release(v) end},
  {label="Cut: Range",        id="cut_range",        mn=-75,  mx=0,     st=0.5,  send=function(v) engine.cut_range(v) end},
  {label="Cut: Margin",       id="cut_hyst",         mn=0,    mx=25,    st=0.5,  send=function(v) engine.cut_hyst(v) end},
  {label="Fray: Drive",       id="fray_drive",       mn=0,    mx=10,    st=0.1,  send=function(v) engine.fray_drive(v) end},
  {label="Fray: Comp",        id="fray_comp",        mn=0,    mx=10,    st=0.1,  send=function(v) engine.fray_comp(v) end},
  {label="Fray: Stab",        id="fray_stab",        mn=0,    mx=10,    st=0.1,  send=function(v) engine.fray_stab(v) end},
  {label="Fray: Octave",      id="fray_octave",      mn=0,    mx=10,    st=0.1,  send=function(v) engine.fray_octave(v) end},
  {label="Fray: Gate",        id="fray_gate",        mn=0,    mx=10,    st=0.1,  send=function(v) engine.fray_gate(v) end},
  {label="Fray: Tone",        id="fray_tone",        mn=0,    mx=10,    st=0.1,  send=function(v) engine.fray_tone(v) end},
  {label="Fray: Volume",      id="fray_volume",      mn=0,    mx=10,    st=0.1,  send=function(v) engine.fray_volume(v) end},
  {label="Push: Gain",         id="push_gain",         mn=0,    mx=10,    st=0.1,  send=function(v) engine.push_gain(v) end},
  {label="Push: Tone",         id="push_tone",         mn=0,    mx=10,    st=0.1,  send=function(v) engine.push_tone(v) end},
  {label="Push: Level",        id="push_level",        mn=0,    mx=10,    st=0.1,  send=function(v) engine.push_level(v) end},
  {label="Push: Mix",          id="push_mix",          mn=0,    mx=100,   st=1,    send=function(v) engine.push_mix(math.floor(v)) end},
  {label="Distort: Gain",      id="distort_gain",      mn=0,    mx=10,    st=0.1,  send=function(v) engine.distort_gain(v) end},
  {label="Distort: Tone",      id="distort_tone",      mn=0,    mx=10,    st=0.1,  send=function(v) engine.distort_tone(v) end},
  {label="Distort: Level",     id="distort_level",     mn=0,    mx=10,    st=0.1,  send=function(v) engine.distort_level(v) end},
  {label="Warp: Rate",         id="warp_rate",         mn=0.1,  mx=25,    st=0.1,  send=function(v) engine.warp_rate(v) end},
  {label="Warp: Depth",        id="warp_depth",        mn=0,    mx=100,   st=1,    send=function(v) engine.warp_depth(math.floor(v)) end},
  {label="Warp: Rise/Fall",    id="warp_rise",         mn=0.01, mx=5.0,   st=0.01, send=function(v) engine.warp_rise(v) end},
  {label="Warp: Mix",          id="warp_mix",          mn=0,    mx=100,   st=1,    send=function(v) engine.warp_mix(math.floor(v)) end},
  {label="Repeat: Time",       id="repeat_time",       mn=1,    mx=1000,  st=1,    send=function(v) engine.repeat_time(math.floor(v)) end},
  {label="Repeat: Feedback",   id="repeat_feedback",   mn=0,    mx=100,   st=1,    send=function(v) engine.repeat_feedback(math.floor(v)) end},
  {label="Repeat: Level",      id="repeat_level",      mn=0,    mx=100,   st=1,    send=function(v) engine.repeat_level(math.floor(v)) end},
  {label="Amp: Volume",        id="amp_volume",        mn=0,    mx=10,    st=0.1,  send=function(v) engine.amp_volume(v) end},
  {label="Amp: Bass",          id="amp_bass",          mn=0,    mx=10,    st=0.1,  send=function(v) engine.amp_bass(v) end},
  {label="Amp: Treble",        id="amp_treble",        mn=0,    mx=10,    st=0.1,  send=function(v) engine.amp_treble(v) end},
  {label="Amp: Master",        id="amp_master",        mn=0,    mx=10,    st=0.1,  send=function(v) engine.amp_master(v) end},
  {label="Tremolo: Speed",     id="tremolo_speed",     mn=0.1,  mx=25,    st=0.1,  send=function(v) engine.tremolo_speed(v) end},
  {label="Tremolo: Intensity", id="tremolo_intensity", mn=0,    mx=100,   st=1,    send=function(v) engine.tremolo_intensity(math.floor(v)) end},
  {label="Hold 1: Size", id="hold1_size", mn=0, mx=10, st=0.1, send=function(v) engine.hold_size(1, v) end},
  {label="Hold 1: Density", id="hold1_density", mn=1, mx=10, st=0.1, send=function(v) engine.hold_density(1, v) end},
  {label="Hold 1: Spread", id="hold1_spread", mn=0, mx=10, st=0.1, send=function(v) engine.hold_spread(1, v) end},
  {label="Hold 1: Pitch", id="hold1_pitch", mn=-24, mx=24, st=1, send=function(v) engine.hold_pitch(1, v) end},
  {label="Hold 1: Pitch Mix", id="hold1_pmix", mn=0, mx=100, st=1, send=function(v) engine.hold_pmix(1, v) end},
  {label="Hold 1: Reverse Mix", id="hold1_rev", mn=0, mx=100, st=1, send=function(v) engine.hold_rev(1, v) end},
  {label="Hold 1: Gain", id="hold1_gain", mn=0, mx=10, st=0.1, send=function(v) engine.hold_gain(1, v) end},
  {label="Hold 1: Level", id="hold1_level", mn=0, mx=10, st=0.1, send=function(v) engine.hold_level(1, v) end},
  {label="Hold 2: Size", id="hold2_size", mn=0, mx=10, st=0.1, send=function(v) engine.hold_size(2, v) end},
  {label="Hold 2: Density", id="hold2_density", mn=1, mx=10, st=0.1, send=function(v) engine.hold_density(2, v) end},
  {label="Hold 2: Spread", id="hold2_spread", mn=0, mx=10, st=0.1, send=function(v) engine.hold_spread(2, v) end},
  {label="Hold 2: Pitch", id="hold2_pitch", mn=-24, mx=24, st=1, send=function(v) engine.hold_pitch(2, v) end},
  {label="Hold 2: Pitch Mix", id="hold2_pmix", mn=0, mx=100, st=1, send=function(v) engine.hold_pmix(2, v) end},
  {label="Hold 2: Reverse Mix", id="hold2_rev", mn=0, mx=100, st=1, send=function(v) engine.hold_rev(2, v) end},
  {label="Hold 2: Gain", id="hold2_gain", mn=0, mx=10, st=0.1, send=function(v) engine.hold_gain(2, v) end},
  {label="Hold 2: Level", id="hold2_level", mn=0, mx=10, st=0.1, send=function(v) engine.hold_level(2, v) end},
  {label="Loop: Rec Level",  id="looper_dub_level",  mn=-40,  mx=0,     st=0.5,  send=function(v) engine.looper_dub_level(db_to_lin(v)) end},
  {label="Loop: Play Level", id="looper_level",      mn=-40,  mx=0,     st=0.5,  send=function(v) engine.looper_level(db_to_lin(v)) end},
  {label="Loop: Fade Level", id="looper_fade_level", mn=-40,  mx=0,     st=0.5,  send=function(v) engine.looper_fade_level(db_to_lin(v)) end},
  {label="Loop: Speed",      id="looper_speed",      mn=-100, mx=100,   st=1,    send=function(v)
    local ratio
    if params:get("looper_speed_control") == 1 then
      if v < 0 then ratio = 0.5 elseif v > 0 then ratio = 2.0 else ratio = 1.0 end
    else ratio = 2^(v/100) end
    engine.looper_speed(ratio)
  end},
  {label="Loop: Imprint",    id="looper_imprint",    mn=0,    mx=100,   st=1,    send=function(v) engine.looper_imprint(math.floor(v)) end},
  {label="Loop: Wear",       id="looper_wear",       mn=0,    mx=100,   st=1,    send=function(v) engine.looper_wear(math.floor(v)) end},
  {label="Loop: Cassette Wow", id="looper_wow_cas",    mn=0,    mx=100,   st=1,    send=function(v) engine.looper_wow_cas(math.floor(v)) end},
  {label="Loop: CD Errors",  id="looper_cd_errors",  mn=0,    mx=100,   st=1,    send=function(v) engine.looper_cd_errors(math.floor(v)) end},
  {label="Loop: Chip Crush", id="looper_chip_crush", mn=0,    mx=100,   st=1,    send=function(v) engine.looper_chip_crush(math.floor(v)) end},
  {label="Loop: Tape Wow",   id="looper_wow_tape",   mn=0,    mx=100,   st=1,    send=function(v) engine.looper_wow_tape(math.floor(v)) end},
  {label="Reverb: Amount",     id="reverb_amount",     mn=0,    mx=100,   st=1,    send=function(v) engine.reverb_amount(math.floor(v)) end},
  {label="Reverb: Length",     id="reverb_length",     mn=0.5,  mx=5.0,   st=0.1,  send=function(v) engine.reverb_length(v) end},
  {label="Reverb: Low Shelf",  id="reverb_low_shelf",  mn=-5,   mx=5,     st=0.5,  send=function(v) engine.reverb_low_shelf(v) end},
  {label="Reverb: High Shelf", id="reverb_high_shelf", mn=-5,   mx=5,     st=0.5,  send=function(v) engine.reverb_high_shelf(v) end},
  {label="Cab: Cab Level",     id="cab_level",         mn=-10,  mx=10,    st=0.5,  send=function(v) engine.cab_level(db_to_lin(v)) end},
  {label="EQ: Low Boost",     id="eq_low_boost",     mn=0,    mx=10,    st=0.1,  send=function(v) engine.eq_low_boost(v) end},
  {label="EQ: Low Cut",       id="eq_low_cut",       mn=0,    mx=10,    st=0.1,  send=function(v) engine.eq_low_cut(v) end},
  {label="EQ: High Boost",    id="eq_high_boost",    mn=0,    mx=10,    st=0.1,  send=function(v) engine.eq_high_boost(v) end},
  {label="EQ: High Cut",      id="eq_high_cut",      mn=0,    mx=10,    st=0.1,  send=function(v) engine.eq_high_cut(v) end},
  {label="EQ: Gain",          id="eq_gain",          mn=-20,  mx=20,    st=0.5,  send=function(v) engine.eq_gain(v) end},
  {label="Limit: Threshold",   id="limit_threshold",   mn=-40,  mx=0,     st=0.5,  send=function(v) engine.limit_threshold(db_to_lin(v)) end},
  {label="Limit: Ratio",       id="limit_ratio",       mn=2.0,  mx=20.0,  st=0.5,  send=function(v) engine.limit_ratio(v) end},
  {label="Limit: Attack",      id="limit_attack",      mn=1,    mx=100,   st=1,    send=function(v) engine.limit_attack(math.floor(v)) end},
  {label="Limit: Decay",       id="limit_decay",       mn=50,   mx=2000,  st=50,   send=function(v) engine.limit_decay(math.floor(v)) end},
  {label="Limit: Gain",        id="limit_gain",        mn=-20,  mx=20,    st=0.5,  send=function(v) engine.limit_gain(db_to_lin(v)) end},
  {label="Count: Division",    id="count_div",         mn=1,    mx=5,     st=1,    send=function(v) lfo.count.div = math.floor(v+0.5) end},
  {label="Count: Level",       id="count_level",       mn=0,    mx=10,    st=0.1,  send=function(v) lfo.count.level = v end},
  {label="Count: Length",      id="count_length",      mn=1,    mx=500,   st=1,    send=function(v) lfo.count.length = math.floor(v + 0.5) end},
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
  {label="LFO 1: Rate",        id="lfo1_rate",         mn=0.1,  mx=25,    st=0.1,  send=function(v) lfo.mod.rate[1]  = v end},
  {label="LFO 2: Rate",        id="lfo2_rate",         mn=0.1,  mx=25,    st=0.1,  send=function(v) lfo.mod.rate[2]  = v end},
  {label="LFO 3: Rate",        id="lfo3_rate",         mn=0.1,  mx=25,    st=0.1,  send=function(v) lfo.mod.rate[3]  = v end},
  {label="LFO 4: Rate",        id="lfo4_rate",         mn=0.1,  mx=25,    st=0.1,  send=function(v) lfo.mod.rate[4]  = v end},
  {label="LFO 5: Rate",        id="lfo5_rate",         mn=0.1,  mx=25,    st=0.1,  send=function(v) lfo.mod.rate[5]  = v end},
  {label="LFO 6: Rate",        id="lfo6_rate",         mn=0.1,  mx=25,    st=0.1,  send=function(v) lfo.mod.rate[6]  = v end},
  {label="LFO 7: Rate",        id="lfo7_rate",         mn=0.1,  mx=25,    st=0.1,  send=function(v) lfo.mod.rate[7]  = v end},
  {label="LFO 8: Rate",        id="lfo8_rate",         mn=0.1,  mx=25,    st=0.1,  send=function(v) lfo.mod.rate[8]  = v end},
  {label="LFO 1: Depth",       id="lfo1_depth",        mn=0,    mx=100,   st=1,    send=function(v) lfo.mod.depth[1] = v end},
  {label="LFO 2: Depth",       id="lfo2_depth",        mn=0,    mx=100,   st=1,    send=function(v) lfo.mod.depth[2] = v end},
  {label="LFO 3: Depth",       id="lfo3_depth",        mn=0,    mx=100,   st=1,    send=function(v) lfo.mod.depth[3] = v end},
  {label="LFO 4: Depth",       id="lfo4_depth",        mn=0,    mx=100,   st=1,    send=function(v) lfo.mod.depth[4] = v end},
  {label="LFO 5: Depth",       id="lfo5_depth",        mn=0,    mx=100,   st=1,    send=function(v) lfo.mod.depth[5] = v end},
  {label="LFO 6: Depth",       id="lfo6_depth",        mn=0,    mx=100,   st=1,    send=function(v) lfo.mod.depth[6] = v end},
  {label="LFO 7: Depth",       id="lfo7_depth",        mn=0,    mx=100,   st=1,    send=function(v) lfo.mod.depth[7] = v end},
  {label="LFO 8: Depth",       id="lfo8_depth",        mn=0,    mx=100,   st=1,    send=function(v) lfo.mod.depth[8] = v end},
  {label="Tremolo: Sync Div",  id="tremolo_sync_div",  mn=2,    mx=8,     st=1,    send=function(v)
    local new_v = math.floor(v+0.5)
    if lfo.sync_override["tremolo_sync_div"] ~= new_v then
      lfo.sync_override["tremolo_sync_div"] = new_v
      sync.push_all(initing, clock_running, lfo.sync_override)
    end
  end},
  {label="Tremolo: Sync Feel", id="tremolo_sync_feel", mn=1,    mx=3,     st=1,    send=function(v)
    local new_v = math.floor(v+0.5)
    if lfo.sync_override["tremolo_sync_feel"] ~= new_v then
      lfo.sync_override["tremolo_sync_feel"] = new_v
      sync.push_all(initing, clock_running, lfo.sync_override)
    end
  end},
  {label="Warp: Sync Div",     id="warp_sync_div",     mn=2,    mx=8,     st=1,    send=function(v)
    local new_v = math.floor(v+0.5)
    if lfo.sync_override["warp_sync_div"] ~= new_v then
      lfo.sync_override["warp_sync_div"] = new_v
      sync.push_all(initing, clock_running, lfo.sync_override)
    end
  end},
  {label="Warp: Sync Feel",    id="warp_sync_feel",    mn=1,    mx=3,     st=1,    send=function(v)
    local new_v = math.floor(v+0.5)
    if lfo.sync_override["warp_sync_feel"] ~= new_v then
      lfo.sync_override["warp_sync_feel"] = new_v
      sync.push_all(initing, clock_running, lfo.sync_override)
    end
  end},
  {label="Repeat: Sync Div",   id="repeat_sync_div",   mn=2,    mx=8,     st=1,    send=function(v)
    local new_v = math.floor(v+0.5)
    if lfo.sync_override["repeat_sync_div"] ~= new_v then
      lfo.sync_override["repeat_sync_div"] = new_v
      sync.push_all(initing, clock_running, lfo.sync_override)
    end
  end},
  {label="Repeat: Sync Feel",  id="repeat_sync_feel",  mn=1,    mx=3,     st=1,    send=function(v)
    local new_v = math.floor(v+0.5)
    if lfo.sync_override["repeat_sync_feel"] ~= new_v then
      lfo.sync_override["repeat_sync_feel"] = new_v
      sync.push_all(initing, clock_running, lfo.sync_override)
    end
  end},
  {label="Loop: Quantize",   id="looper_quant_div",  mn=2,    mx=8,     st=1,    send=function(v)
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
  TARGET_PARAMS[#TARGET_PARAMS+1] = {label="LFO "..i..": Stability", id="lfo"..i.."_stability", mn=0, mx=100, st=1,   send=function(v) lfo.mod.stability[i] = v end}
  TARGET_PARAMS[#TARGET_PARAMS+1] = {label="LFO "..i..": Rate Slew", id="lfo"..i.."_rate_slew", mn=0, mx=5,   st=0.1, send=function(v) lfo.mod.rate_slew[i] = v end}
  TARGET_PARAMS[#TARGET_PARAMS+1] = {label="LFO "..i..": Sync Div",  id="lfo"..i.."_sync_div",  mn=2, mx=8,   st=1,   send=function(v) lfo.mod.sync_div[i]  = math.floor(v + 0.5) end}
  TARGET_PARAMS[#TARGET_PARAMS+1] = {label="LFO "..i..": Sync Feel", id="lfo"..i.."_sync_feel", mn=1, mx=3,   st=1,   send=function(v) lfo.mod.sync_feel[i] = math.floor(v + 0.5) end}
end

for i = 1, seq.NUM do
  TARGET_PARAMS[#TARGET_PARAMS+1] = {label="Walk "..i..": Rate",      id="seq"..i.."_rate",      mn=0.1, mx=25,  st=0.1, send=function(v) seq.mod.rate[i]      = v end}
  TARGET_PARAMS[#TARGET_PARAMS+1] = {label="Walk "..i..": Steps",     id="seq"..i.."_steps",     mn=2,   mx=16,  st=1,   send=function(v) seq.mod.steps[i]     = math.floor(v + 0.5) end}
  TARGET_PARAMS[#TARGET_PARAMS+1] = {label="Walk "..i..": Rate Slew", id="seq"..i.."_rate_slew", mn=0,   mx=5,   st=0.1, send=function(v) seq.mod.rate_slew[i] = v end}
  TARGET_PARAMS[#TARGET_PARAMS+1] = {label="Walk "..i..": Sync Div",  id="seq"..i.."_sync_div",  mn=2,   mx=8,   st=1,   send=function(v) seq.mod.sync_div[i]  = math.floor(v + 0.5) end}
  TARGET_PARAMS[#TARGET_PARAMS+1] = {label="Walk "..i..": Sync Feel", id="seq"..i.."_sync_feel", mn=1,   mx=3,   st=1,   send=function(v) seq.mod.sync_feel[i] = math.floor(v + 0.5) end}
end

for i = 1, trigs.N do
  TARGET_PARAMS[#TARGET_PARAMS+1] = {label="Trigger "..i..": Rate",        id="trig"..i.."_rate",        mn=0.1, mx=25,  st=0.1, send=function(v) trigs.mod.rate[i]        = v end}
  TARGET_PARAMS[#TARGET_PARAMS+1] = {label="Trigger "..i..": Probability", id="trig"..i.."_probability", mn=0,   mx=100, st=1,   send=function(v) trigs.mod.probability[i] = v end}
end

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
  -- A trigger firing is the modulation engine acting, not the user reaching for the
  -- device, so its writes must not drag Follow Focus along (prc_t137).
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
    { label = "Hold 2: Toggle",  id = "trig_hold2_toggle",   action = toggle("hold2_enable") },
    { label = "Loop: Rec",     id = "trig_looper_rec",     action = function() focus_absorb["@loop"] = true; looper.step() end },
    { label = "Loop: Clear",   id = "trig_looper_clear",   action = function() focus_absorb["@loop"] = true; looper.force_clear() end },
    { label = "Reverb: Toggle",  id = "trig_reverb_toggle",  action = toggle("reverb_enable") },
    { label = "EQ: Toggle",      id = "trig_eq_toggle",      action = toggle("eq_enable") },
    { label = "Limit: Toggle",   id = "trig_limit_toggle",   action = toggle("limit_enable") },
  }
  for i = 1, lfo.NUM do
    t[#t + 1] = { label = "LFO " .. i .. ": Randomize", id = "trig_lfo" .. i .. "_randomize", lfo_idx = i,
                  action = function() params:set("lfo" .. i .. "_randomize", 1) end }
  end
  for i = 1, seq.NUM do
    t[#t + 1] = { label = "Walk " .. i .. ": Randomize", id = "trig_seq" .. i .. "_randomize",
                  action = function() params:set("seq" .. i .. "_randomize", 1) end }
  end
  return t
end)()

local count_active = false
local count_clock  = nil
local count_step   = 0

local k_clock = {}


local B = { DIM=0, MED=5, FULL=15 }

local GROUP_MAX = {[0]=2, [1]=18, [3]=4, [4]=3}

local COUNT_STRIP = {
  {name="Division", id="count_div",     typ="opt",  nmax=5,  fmt=function(v) return sync.COUNT_DIV_OPTS[v] end},
  {name="Root",     id="count_root",     typ="opt", nmax=12, fmt=function(v) return scales.NOTE_NAMES[v] end},
  {name="Register", id="count_register", typ="opt", nmax=8,  fmt=function(v) return tostring(v - 1) end},
  {name="Scale",    id="count_scale",    typ="opt",  nmax=8,  fmt=function(v) return scales.SCALE_NAMES[v] end},
  {name="Degree",   id="count_degree",     typ="opt", nmax=15, fmt=function(v) return tostring(v) end},
  {name="Play",     id="count_scale_play", typ="opt", nmax=8, fmt=function(v) return ({"Off","Fwd","Rev","3rds","4ths","5ths","7ths","Rnd"})[v] end},
  {name="Chords",   id="count_chords",     typ="opt", nmax=4, fmt=function(v) return ({"Off","Octaves","Power","Triads"})[v] end},
  {name="Level",    id="count_level",   typ="ctrl", step=0.1, fmt=function(v) return string.format("%.1f",v) end},
  {name="Length",   id="count_length",  typ="ctrl", step=1,  fmt=function(v) return string.format("%dms",math.floor(v)) end},
  {name="Position", id="count_position", typ="opt",  nmax=2,  fmt=function(v) return ({"Parallel","Inline"})[v] end},
}

local function fmt_unit(v, p)
  if p.unit then
    return p.step < 1 and string.format("%.1f%s", v, p.unit) or string.format("%d%s", math.floor(v), p.unit)
  end
  return string.format("%.1f", v)
end

local function fmt_def_val(def, idx)
  local p  = def[idx]
  local id = p.id
  local v  = params:get(id)
  if p.options then return p.options[v] end
  if id == "mic_position"     then return MIC_NAMES[v] end
  if id == "looper_direction" then return DIR_NAMES[v] end
  if id == "looper_speed" then
    if params:get("looper_speed_control") == 1 then
      if v < 0 then return "-100%" elseif v > 0 then return "+100%" else return "+0%" end
    else
      return string.format("%+d%%", math.floor(v))
    end
  end
  local s = sync.fmt(id, clock_running)
  if s then return s end
  if p.db   then return string.format("%.1fdB", v) end
  return fmt_unit(v, p)
end
local function fmt_val(idx) return fmt_def_val(PARAMS_DEF, idx) end

-- reverse lookup so any param id renders exactly as in its studio view
local PARAM_DEF_OF = {}
for i, e in ipairs(PARAMS_DEF) do PARAM_DEF_OF[e.id] = { def = PARAMS_DEF, idx = i } end
for i, e in ipairs(LOOPER_DEF) do PARAM_DEF_OF[e.id] = { def = LOOPER_DEF, idx = i } end
local PARAM_PED_OF = {}
for _, pd in ipairs(PEDALS) do
  for _, e in ipairs(pd.params) do PARAM_PED_OF[e.id] = e end
end

local function fmt_param(id)
  if id == "tune_ref" then return string.format("%.1f Hz", params:get(id)) end
  local d = PARAM_DEF_OF[id]
  if d then return fmt_def_val(d.def, d.idx) end
  local pe = PARAM_PED_OF[id]
  if pe then
    local s = sync.fmt(id, clock_running)
    if s then return s end
    local v = params:get(id)
    if pe.options then return pe.options[v] end
    return fmt_unit(v, pe)
  end
  return params:string(id)
end

local function snap_val(v, step)
  if step == 1 then return math.floor(v + 0.5)
  else return math.floor(v * 10 + 0.5) / 10 end
end

-- one editing path for every view: device params carry a tuned step in the DEF
-- tables; edit_param applies it (plus the sync-division redirect) so the main
-- view, pedalboard, looper pane and stage view all edit a param identically.
-- params without a DEF step (gate/limit/cab/tune) fall back to params:delta,
-- which is exactly how they behave in the PARAMS menu.
local PARAM_STEP = {}
for _, e in ipairs(PARAMS_DEF) do PARAM_STEP[e.id] = e.step end
for _, e in ipairs(LOOPER_DEF) do PARAM_STEP[e.id] = e.step end
for _, pd in ipairs(PEDALS) do
  for _, e in ipairs(pd.params) do PARAM_STEP[e.id] = e.step end
end
PARAM_STEP["tune_ref"] = 0.1   -- tune has a custom strip edit, no DEF entry

local function edit_param(id, d)
  local m = sync.PARAM_MAP[id]
  if m and params:get(m.div) > 1 then
    params:set(m.div, sync.step_div(id, params:get(m.div), d, params:get(m.feel), clock.get_tempo()))
    return
  end
  local step = PARAM_STEP[id]
  if step then
    params:set(id, snap_val(params:get(id) + d * step, step))
  else
    params:delta(id, d)
  end
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
  screen.level(B.DIM); screen.rect(0, 0, cabinet.LEFT_W, 64); screen.fill()
  screen.font_size(8); screen.font_face(0)
  screen.level(B.MED);  screen.move(cabinet.LEFT_CX,  8); screen.text_center(cat)
  -- name: multi-part names always split onto two lines (for consistency)
  local name2
  local sp = name:find(" ")
  if sp then name, name2 = name:sub(1, sp - 1), name:sub(sp + 1) end
  local vy = 26
  screen.level(B.MED); screen.move(cabinet.LEFT_CX, 17); screen.text_center(name)
  if name2 then
    screen.level(B.MED); screen.move(cabinet.LEFT_CX, 26); screen.text_center(name2)
    vy = 35
  end
  -- unify value/unit: drop decimals on percent values, then no space before the unit
  if val_str then
    val_str = val_str:gsub("(%-?%d+)%.%d+(%s*%%)", "%1%2")  -- percent steps in whole %, so no decimals
    val_str = val_str:gsub("(%d)%s+([%a%%])", "%1%2")       -- "440.0 Hz"->"440.0Hz", "50 %"->"50%"
  end
  screen.level(val_lv); screen.move(cabinet.LEFT_CX, vy); screen.text_center(val_str)
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

-- H1 | H2: enable state of the two Hold instances as a centered fifth strip line.
-- One thin vertical stroke as a compact divider. Bypass = MED, Active = FULL.
local function draw_hold_status()
  screen.font_size(8); screen.font_face(0)
  local g  = 3   -- space on each side of the divider stroke
  local w1 = screen.text_extents("H1")
  local w2 = screen.text_extents("H2")
  local left = math.floor(cabinet.LEFT_CX - (w1 + g + 1 + g + w2) / 2 + 0.5)
  local y = 44
  screen.level(params:get("hold1_enable") == 2 and B.FULL or B.MED)
  screen.move(left, y); screen.text("H1")
  screen.level(B.MED)
  -- 5 px, not 6: the caps of this font reach from baseline-5 to baseline-1, so a 6 px
  -- stroke poked one row above the letters instead of matching their height.
  screen.rect(left + w1 + g, y - 5, 1, 5); screen.fill()
  screen.level(params:get("hold2_enable") == 2 and B.FULL or B.MED)
  screen.move(left + w1 + g + 1 + g, y); screen.text("H2")
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
    screen.move(cabinet.LEFT_CX, 26); screen.text_center("Bypass")
  elseif knob then
    draw_strip(PARAMS_DEF[knob].cat, PARAMS_DEF[knob].name, fmt_val(knob), sync.val_level(id, clock_running))
  else
    -- a param of a cabinet device that the panel has no knob for: readout only
    draw_strip(devname, params:lookup_param(id).name, fmt_param(id), sync.val_level(id, clock_running))
  end

  draw_looper_state_icon()
  draw_hold_status()
end

local function draw_metro_half(ox, oy, focused)
  local cx  = ox + 16
  local lv  = focused and B.FULL or B.MED
  local bpm_str
  if clock_running then bpm_str = string.format("%.0f", clock.get_tempo())
  else bpm_str = tostring(params:get("count_bpm") or "?") end
  screen.font_size(8); screen.font_face(0)
  screen.level(count_active and lv or B.MED)
  screen.move(cx, oy + 22); screen.text_center(bpm_str)
  screen.move(cx, oy + 32); screen.text_center("BPM")
  screen.level(lv)
  screen.move(cx, oy + 56); screen.text_center("Count")
end

local function draw_label_cursor(cx, baseline, text)
  screen.font_size(8); screen.font_face(0)
  local w = screen.text_extents(text)
  local left_x = cx - math.floor(w / 2)
  screen.level(B.FULL)
  screen.rect(left_x - 2, baseline - 5, 1, 1); screen.fill()
end

local function draw_group1_pane()
  screen.clear()
  local p       = view_pane[1]
  local is_left = (p % 2) == 1
  local pair    = math.ceil(p / 2)
  local OX1     = cabinet.CAB.x
  local OX2     = cabinet.CAB.x + cabinet.CAB.w - 33
  local py      = 4

  if pair == 1 then
    tune.draw_half(OX1, py, is_left)
    draw_metro_half(OX2, py, not is_left)
    if is_left then
      draw_strip("Tune", "Reference", fmt_param("tune_ref"), B.FULL)
    else
      local ms = COUNT_STRIP[count_strip_sel]
      draw_strip("Count", ms.name, ms.fmt(params:get(ms.id)), B.FULL)
    end
  elseif pair == 2 then
    env.draw_half(OX1, py, 1, is_left)
    env.draw_half(OX2, py, 2, not is_left)
    local idx       = is_left and 1 or 2
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
  elseif pair == 7 then
    local idx       = is_left and 1 or 2
    local strip_idx = seq.strip_resolve(idx, seq_strip_sel[idx])
    local ss        = seq.STRIP[strip_idx]
    local sel_step  = ss.suf:match("^_step_(%d+)$")
    sel_step = sel_step and tonumber(sel_step) or nil
    seq.draw_half(OX1, py, 1, is_left,     is_left and sel_step or nil)
    seq.draw_half(OX2, py, 2, not is_left, (not is_left) and sel_step or nil)
    local id  = "seq" .. idx .. ss.suf
    local v1  = ss.fmt(params:get(id), idx)
    local v2  = nil
    if ss.suf == "_target_param" then
      local sp = v1:find(" ")
      if sp then v1, v2 = v1:sub(1, sp - 1), v1:sub(sp + 1) end
    end
    draw_strip("Walk " .. idx, ss.name, v1, B.FULL, v2)
  elseif pair >= 8 then
    local trig_l = (pair - 8) * 2 + 1
    local trig_r = trig_l + 1
    trigs.draw_half(OX1, py, trig_l, is_left)
    trigs.draw_half(OX2, py, trig_r, not is_left)
    local idx       = is_left and trig_l or trig_r
    local strip_idx = trigs.strip_fn.resolve(idx, trigs.strip_sel[idx])
    local ts        = trigs.STRIP[strip_idx]
    local id  = "trig" .. idx .. ts.suf
    local v1  = ts.fmt(params:get(id), idx)
    draw_strip("Trigger " .. idx, ts.name, v1, B.FULL)
  else
    local lfo_l = (pair - 3) * 2 + 1
    local lfo_r = lfo_l + 1
    lfo.draw_half(OX1, py, lfo_l, is_left)
    lfo.draw_half(OX2, py, lfo_r, not is_left)
    local idx       = is_left and lfo_l or lfo_r
    local strip_idx = lfo.strip_resolve(idx, lfo_strip_sel[idx])
    local ls        = lfo.STRIP[strip_idx]
    local id  = "lfo" .. idx .. ls.suf
    local v1  = ls.fmt(params:get(id), idx)
    local v2  = nil
    if ls.suf == "_waveform" or ls.suf == "_target_param" then
      local sp = v1:find(" ")
      if sp then v1, v2 = v1:sub(1, sp - 1), v1:sub(sp + 1) end
    end
    draw_strip("LFO " .. idx, ls.name, v1, B.FULL, v2)
  end

  local cur_cx = (is_left and OX1 or OX2) + 16
  local cur_label
  if pair == 1 then
    cur_label = is_left and "Tune" or "Count"
  elseif pair == 2 then
    cur_label = "Sense " .. (is_left and 1 or 2)
  elseif pair == 7 then
    cur_label = "Walk " .. (is_left and 1 or 2)
  elseif pair >= 8 then
    local trig_l = (pair - 8) * 2 + 1
    cur_label = "Trig " .. (is_left and trig_l or (trig_l + 1))
  else
    local lfo_l = (pair - 3) * 2 + 1
    cur_label = "LFO " .. (is_left and lfo_l or (lfo_l + 1))
  end
  draw_label_cursor(cur_cx, py + 56, cur_label)

  -- Tune and Count are signal-chain devices and show the chain status like the rest. The
  -- mod rack panes above do not: there the left strip belongs to the modulation source,
  -- and Hold and the looper are not what you are looking at.
  if p <= 2 then
    draw_looper_state_icon()
    draw_hold_status()
  end

  screen.update()
end

local function draw_pedalboard()
  screen.clear()

  local psel = cur_pedal_sel()
  local pd   = cur_pedal()
  local p    = pd.params[pd.psel]
  local v    = params:get(p.id)
  local vstr = sync.fmt(p.id, clock_running)
  if not vstr then
    if p.options then vstr = p.options[v]
    else vstr = fmt_unit(v, p) end
  end
  draw_strip(pd.name, p.name, vstr, sync.val_level(p.id, clock_running))

  -- ── Two pedals, snapped to CAB edges ────────────────────────────
  local OX1 = cabinet.CAB.x
  local OX2 = cabinet.CAB.x + cabinet.CAB.w - 33
  local py  = 4

  if view_pane[3] >= 3 then
    local fk3 = (psel == 3) and pd.psel or nil
    local fk4 = (psel == 4) and pd.psel or nil
    sprites.draw_pedal(OX1, py, PEDALS[3].name, PEDALS[3].display, params:get(PEDALS[3].enable_id) == 1, fk3)
    sprites.draw_pedal(OX2, py, PEDALS[4].name, PEDALS[4].display, params:get(PEDALS[4].enable_id) == 1, fk4)
  else
    local fk1 = (psel == 1) and pd.psel or nil
    local fk2 = (psel == 2) and pd.psel or nil
    sprites.draw_pedal(OX1, py, PEDALS[1].name, PEDALS[1].display, params:get(PEDALS[1].enable_id) == 1, fk1)
    sprites.draw_pedal(OX2, py, PEDALS[2].name, PEDALS[2].display, params:get(PEDALS[2].enable_id) == 1, fk2)
  end
  local cur_cx = ((psel % 2 == 1) and OX1 or OX2) + 16
  draw_label_cursor(cur_cx, py + 56, PEDALS[psel].display)

  -- chain status, same place as on every other device pane
  draw_looper_state_icon()
  draw_hold_status()

  screen.update()
end

local function draw_looper_pane()
  looper_ui.draw_pane()
end

-- The signal chain, in flow order. Single source of truth for the Stage view, the
-- studio device focus and Follow Focus. Fray and EQ join once they exist (t128/t129).
local PERF_DEVICES = {
  -- like a tuner pedal: the block lights up while it is engaged, i.e. while muted
  { abbr="TUN", name="Tune",     enable="tune_mute", active=function() return tune.muted end,
    params={"tune_ref"} },
  { abbr="CUT", name="Cut",       enable="cut_enable", sprite="cut",
    params={"cut_thresh","cut_attack","cut_hold","cut_release","cut_range","cut_hyst","cut_detect"} },
  { abbr="FRY", name="Fray",      enable="fray_enable", sprite="fray",
    params={"fray_drive","fray_comp","fray_stab","fray_octave","fray_octave_mode","fray_gate","fray_tone","fray_volume"} },
  { abbr="PSH", name="Push",      enable="push_enable",
    params={"push_gain","push_tone","push_level","push_mix"} },
  { abbr="DST", name="Distort",   enable="distort_enable",
    params={"distort_gain","distort_tone","distort_level","distort_lowcut"} },
  { abbr="WRP", name="Warp",      enable="warp_enable",
    params={"warp_rate","warp_depth","warp_rise","warp_mix","warp_sync_div","warp_sync_feel"} },
  { abbr="RPT", name="Repeat",    enable="repeat_enable",
    params={"repeat_time","repeat_feedback","repeat_level","repeat_characteristic","repeat_sync_div","repeat_sync_feel"} },
  { abbr="AMP", name="Amp",       enable="amp_enable",
    params={"amp_volume","amp_bass","amp_treble","amp_master"} },
  -- knobs first and in panel order, left to right, then whatever the panel has no knob for:
  -- E2 walks this list, so its order is what the highlight does on the cabinet
  { abbr="TRM", name="Tremolo",   enable="tremolo_enable",
    params={"tremolo_intensity","tremolo_speed","tremolo_sync_div","tremolo_sync_feel"} },
  { abbr="HD1", name="Hold 1",    enable="hold1_enable", parallel=true,
    params={"hold1_size","hold1_density","hold1_spread","hold1_pitch","hold1_pmix","hold1_rev","hold1_shape","hold1_interp","hold1_gain","hold1_level","hold1_rise","hold1_fall"} },
  { abbr="HD2", name="Hold 2",    enable="hold2_enable",
    params={"hold2_size","hold2_density","hold2_spread","hold2_pitch","hold2_pmix","hold2_rev","hold2_shape","hold2_interp","hold2_gain","hold2_level","hold2_rise","hold2_fall"} },
  { abbr="LOP", name="Loop",    active=function() return looper.state ~= looper.IDLE end,
    params={"looper_medium","looper_wear","looper_direction","looper_dub_level","looper_level","looper_fade_level","looper_speed","looper_quant_div","looper_quant_feel"} },
  { abbr="RVB", name="Reverb",    enable="reverb_enable",
    params={"reverb_amount","reverb_length","reverb_low_shelf","reverb_high_shelf"} },
  { abbr="CAB", name="Cab & Mic", enable="cab_mode",
    params={"mic_position","cab_level"} },
  { abbr="EQU", name="EQ",        enable="eq_enable", sprite="eq",
    params={"eq_low_freq","eq_low_boost","eq_low_cut","eq_high_freq","eq_high_bw",
            "eq_high_boost","eq_high_cut","eq_gain"} },
  { abbr="LMT", name="Limit",     enable="limit_enable", sprite="limit",
    params={"limit_threshold","limit_ratio","limit_attack","limit_decay","limit_gain"} },
}

-- MIDI-follow: reverse index param id -> {device index, param index within device}.
-- Used by the Follow-MIDI poll (init) to move the Stage focus onto whatever device a
-- norns-mapped CC last touched, without changing the current view.
local PERF_INDEX_OF = {}
for i, dev in ipairs(PERF_DEVICES) do PERF_INDEX_OF[dev.abbr] = i end

-- Follow Focus watches only the per-device engage switches. That is the one change worth
-- pulling the view to, it is unambiguous, and it keeps ordinary knob moves - which a MIDI
-- controller fires off constantly - from dragging the display around.
-- Loop has no enable param, so it is followed through a pseudo id on the transport state,
-- which MIDI reaches via looper_rec_play / looper_stop_clear. Tune engages through its own
-- Mute param.
local FOCUS_DEVICE_OF = {}   -- enable id -> device index
local FOCUS_IDS       = {}   -- the same ids in chain order, so the poll is deterministic
for di, dev in ipairs(PERF_DEVICES) do
  if dev.enable and not FOCUS_DEVICE_OF[dev.enable] then
    FOCUS_DEVICE_OF[dev.enable] = di
    FOCUS_IDS[#FOCUS_IDS + 1]   = dev.enable
  end
end
-- Tune and Loop engage outside the param system, so they get pseudo ids: the tuner's
-- mute and the looper's transport state stand in for an enable switch.
local FOCUS_LOOP = "@loop"
if PERF_INDEX_OF.LOP then
  FOCUS_DEVICE_OF[FOCUS_LOOP] = PERF_INDEX_OF.LOP
  FOCUS_IDS[#FOCUS_IDS + 1]   = FOCUS_LOOP
end
local function focus_value(id)
  if id == FOCUS_LOOP then return looper.state end
  return params:get(id)
end

-- Count is not in the signal chain, so it has no Stage tile, but it still needs a home
-- in the studio walk.
local COUNT_DEVICE = { abbr="CNT", name="Count", enable="count_enable",
  params={"count_div","count_root","count_register","count_scale","count_degree",
          "count_scale_play","count_chords","count_level","count_length","count_position"} }

-- Studio walk: E1 steps through every device in signal order, exactly as the Stage chain
-- does, with Count inserted after Tune. The panes are only the visual grouping around
-- them, so the cabinet view is entered twice: once for Amp/Tremolo and again, after Hold
-- and Loop, for Reverb and Cab. `group`/`pane` say which existing view shows the device;
-- `cab` marks the four that live on the cabinet, whose panel knobs E2 has to keep in step.
-- DEV_GROUP is the generic pane for devices that have no view of their own yet (t131).
local DEV_GROUP = 4
local STUDIO_DEVICES = {
  { abbr="TUN", group=1, pane=1 },
  { abbr="CNT", group=1, pane=2 },
  { abbr="CUT", group=DEV_GROUP, pane=1, slot=1 },
  { abbr="FRY", group=DEV_GROUP, pane=1, slot=2 },
  { abbr="PSH", group=3, pane=1 },
  { abbr="DST", group=3, pane=2 },
  { abbr="WRP", group=3, pane=3 },
  { abbr="RPT", group=3, pane=4 },
  { abbr="AMP", group=0, pane=1, cab=true },
  { abbr="TRM", group=0, pane=1, cab=true },
  { abbr="HD1", group=DEV_GROUP, pane=2, slot=1 },
  { abbr="HD2", group=DEV_GROUP, pane=2, slot=2 },
  { abbr="LOP", group=0, pane=2 },
  { abbr="RVB", group=0, pane=1, cab=true },
  { abbr="CAB", group=0, pane=1, cab=true },
  { abbr="EQU", group=DEV_GROUP, pane=3, slot=1, rack=true },
  { abbr="LMT", group=DEV_GROUP, pane=3, slot=2, rack=true },
}
for _, e in ipairs(STUDIO_DEVICES) do
  e.dev = (e.abbr == "CNT") and COUNT_DEVICE or PERF_DEVICES[PERF_INDEX_OF[e.abbr]]
end
local STUDIO_INDEX_OF = {}
for i, e in ipairs(STUDIO_DEVICES) do STUDIO_INDEX_OF[e.abbr] = i end

-- Follow Focus, studio side: move the walk onto the device that owns `id`, and where it
-- is cheap, onto the parameter itself as well.
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
  if not mod_open then redraw() end   -- reflect it where visible; never switch views
end


local function perf_active(dev)
  if dev.placeholder then return false end   -- not built yet: always reads as bypassed
  if dev.active then return dev.active() end
  return params:get(dev.enable) == 2
end
local function perf_pid()
  local dev = PERF_DEVICES[perf_sel]
  return dev.params[perf_param[perf_sel] or 1]
end

-- ── Stage chain text ──────────────────────────────────────────
-- The chain is drawn as centered, auto-wrapped lines of full device names joined by
-- ">", with "//" between the two parallel Holds. Widths are measured at draw time, so
-- the layout adapts by itself when devices are added.
local CHAIN_X       = cabinet.CAB.x
local CHAIN_W       = 128 - cabinet.CAB.x
local CHAIN_LH      = 9    -- readout line pitch, so both columns share one baseline grid
local CHAIN_Y0      = 8    -- first baseline, matching the readout's first line
local CHAIN_ARROW_W = 2    -- hand-drawn chevron, far narrower than the ">" glyph

-- small 2x3 chevron, vertically centred on the capitals
local function draw_chain_arrow(x, y)
  screen.rect(x,     y - 4, 1, 1)
  screen.rect(x + 1, y - 3, 1, 1)
  screen.rect(x,     y - 2, 1, 1)
  screen.fill()
end

-- A unit is one device, or the inseparable "Hold 1 // Hold 2" pair. Every unit but the
-- last carries a trailing ">" so a wrapped line ends on the arrow. Gaps are explicit
-- pixels rather than space glyphs, so spacing does not depend on font metrics.
local CHAIN_GAP = 3

local function chain_units()
  local units, i = {}, 1
  while i <= #PERF_DEVICES do
    if PERF_DEVICES[i].parallel and PERF_DEVICES[i + 1] then
      -- the parallel Holds are joined by a single divider stroke, as in the readout
      units[#units + 1] = { parts = { {d=i, pre=0}, {div=true, pre=CHAIN_GAP}, {d=i+1, pre=CHAIN_GAP} } }
      i = i + 2
    else
      units[#units + 1] = { parts = { {d=i, pre=0} } }
      i = i + 1
    end
  end
  for k, u in ipairs(units) do
    if k < #units then u.parts[#u.parts + 1] = { arrow = true, pre = CHAIN_GAP } end
  end
  return units
end

-- Fixed line layout: the chain is hand-set, not wrapped automatically. Each number is
-- how many blocks sit on that line, in chain order, with the parallel Holds counting as
-- one block:
--     TUN > CUT
--     FRY > PSH > DST
--     WRP > RPT > AMP
--     TRM > HD1 | HD2
--     LOP > RVB > CAB
--     EQU > LMT
-- Adding or removing a device means updating this list.
local CHAIN_ROWS = { 2, 3, 3, 2, 3, 2 }

local function chain_span(units, i, j)
  local w = 0
  for k = i, j do w = w + units[k].w + ((k > i) and CHAIN_GAP or 0) end
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
        p.w = CHAIN_ARROW_W
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
    lines[#lines + 1] = ln
  end
  for _, count in ipairs(CHAIN_ROWS) do
    if i > #units then break end
    local j = math.min(i + count - 1, #units)
    emit(i, j)
    i = j + 1
  end
  if i <= #units then emit(i, #units) end   -- CHAIN_ROWS out of date: park the rest
  chain_cache = lines
  return lines
end

local function draw_chain()
  local lines = chain_layout()
  screen.font_size(8); screen.font_face(0)
  local y0 = CHAIN_Y0   -- share the readout's baseline grid exactly
  for li, ln in ipairs(lines) do
    local x = math.floor(CHAIN_X + (CHAIN_W - ln.w) / 2 + 0.5)
    local y = y0 + (li - 1) * CHAIN_LH
    for ui, u in ipairs(ln.units) do
      if ui > 1 then x = x + CHAIN_GAP end
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
          -- selection marker: same 1px cursor the studio panes use
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
  -- left: studio-style readout for the selected device
  local dev = PERF_DEVICES[perf_sel]
  if dev.abbr == "LOP" then
    local li = perf_param[perf_sel] or 1
    local lp = LOOPER_DEF[li]
    draw_strip(lp.cat, lp.name, fmt_def_val(LOOPER_DEF, li), sync.val_level(lp.id, clock_running))
  elseif dev.abbr == "TUN" then
    -- Stage tuner: the Reference value is not useful here, so the upper strip area
    -- shows the live note/octave/arrow instead. H1/H2 (y44) and the looper icon (y55)
    -- stay in place like on every other device.
    local cx  = cabinet.LEFT_CX
    local tlv = tune.muted and B.FULL or B.MED   -- bright while engaged, as in the chain
    screen.font_size(8); screen.font_face(0)
    screen.level(B.MED); screen.move(cx, 8); screen.text_center("Tune")
    screen.font_size(16); screen.level(tlv)
    screen.move(cx, 27); screen.text_center(tune.note)
    screen.font_size(8)
    if tune.note ~= "--" then
      screen.level(tlv)
      screen.move(cx + 11, 17); screen.text(tostring(tune.octave))
      tune.draw_arrow(cx, 32, tune.arrow)
    end
  else
    local pid = perf_pid()
    if pid then
      draw_strip(dev.name, params:lookup_param(pid).name, fmt_param(pid), B.FULL)
    else
      draw_strip(dev.name, "Not built", "--", B.MED)
    end
  end
  draw_looper_state_icon()
  draw_hold_status()
  -- right: the signal chain as centered, auto-wrapped text
  draw_chain()
  screen.update()
end

local function perf_enc(n, d)
  if n == 1 then
    perf_sel = util.clamp(perf_sel + d, 1, #PERF_DEVICES)
  elseif n == 2 then
    local dev = PERF_DEVICES[perf_sel]
    if #dev.params > 0 then
      perf_param[perf_sel] = util.clamp((perf_param[perf_sel] or 1) + d, 1, #dev.params)
    end
  elseif n == 3 then
    local pid = perf_pid()
    if pid then edit_param(pid, d) end
  end
  if refresh_tune then refresh_tune() end
  redraw()
end

-- ── Hold grain view ──────────────────────────────────────────────
-- Hold gets no pedal sprite. Twelve knob caps would not fit 33 pixels legibly, and which
-- parameter is selected is already spelled out in the readout, so the caps would be pure
-- decoration. Instead the frame shows what the device is actually doing: grains drifting
-- through the frozen buffer. It is driven by the parameters, not by the engine - the grain
-- events happen in SuperCollider and would need their own polls to reach Lua - so read it
-- as an indicator of the settings, not as a scope.
local GRAIN_MAX = 20
local hold_grains = { {}, {} }

local function hold_grain_tick(idx)
  local p  = "hold" .. idx .. "_"
  if params:get(p .. "enable") ~= 2 then hold_grains[idx] = {}; return end
  local g       = hold_grains[idx]
  local density = params:get(p .. "density")
  local size    = params:get(p .. "size")
  local spread  = params:get(p .. "spread") * 0.1
  local pitch   = params:get(p .. "pitch")
  local rev     = params:get(p .. "rev") * 0.01
  local level   = params:get(p .. "level")
  local want    = util.clamp(math.floor(3 + density * 1.6), 1, GRAIN_MAX)
  -- Pitch places the band vertically: up is up. Spread widens it into a cloud.
  local mid  = 23 - (pitch / 24) * 16
  local band = 2 + spread * 18

  for i = #g, 1, -1 do
    local q = g[i]
    q.age = q.age + 1
    q.x   = q.x + q.vx
    if q.age > q.ttl or q.x < 1 or q.x > 30 then table.remove(g, i) end
  end
  while #g < want do
    local back = math.random() < rev
    g[#g + 1] = {
      x   = back and (24 + math.random() * 6) or (2 + math.random() * 6),
      y   = util.clamp(mid + (math.random() - 0.5) * band, 2, 43),
      vx  = (back and -1 or 1) * (0.4 + size * 0.12),
      age = 0,
      ttl = math.floor(8 + size * 2.5),
      hot = math.random() < (level / 10),
    }
  end
end

local function draw_hold_grains(x, y, idx, focused)
  screen.line_width(1)
  screen.level(focused and B.FULL or B.MED)
  screen.rect(x, y, 33, 47); screen.stroke()
  if params:get("hold" .. idx .. "_enable") ~= 2 then return end
  -- A grain is a short trail: longer Size, longer streak. Drawn grouped by brightness,
  -- because screen.level applies to the whole path up to the next fill - setting it per
  -- grain and filling once at the end would give every grain the last grain's level.
  for _, hot in ipairs({ false, true }) do
    screen.level(hot and B.FULL or B.MED)
    local any = false
    for _, q in ipairs(hold_grains[idx]) do
      if q.hot == hot then
        local len  = math.max(1, math.floor(math.abs(q.vx) * 3))
        local step = (q.vx > 0) and 1 or -1
        for k = 0, len - 1 do
          local gx = math.floor(q.x) - (k * step)
          if gx >= 1 and gx <= 31 then
            screen.rect(x + gx, y + math.floor(q.y), 1, 1)
            any = true
          end
        end
      end
    end
    if any then screen.fill() end
  end
end

-- One body per device: a real sprite where we have one, the grain frame for Hold, and a
-- plain labelled box for whatever is still waiting on artwork (EQ and Limit, t131).
local function draw_device_body(x, y, w, h, dev, focused, focus_knob, idx, rack)
  if dev.sprite then
    -- pedals sit one pixel higher than their slot, matching draw_pedal, and carry their
    -- name below; the rack units are placed by the caller and carry no caption, there being
    -- no room for one between two stacked 26px faceplates.
    sprites_device.draw(dev.sprite, x, rack and y or (y - 1), perf_active(dev), focus_knob)
    if not rack then
      screen.font_size(8); screen.font_face(0)
      screen.level(perf_active(dev) and B.FULL or B.MED)
      screen.move(x + 16, y + 56); screen.text_center(dev.name)
    end
    return
  end
  if idx then
    draw_hold_grains(x, y, idx, focused)
    screen.font_size(8); screen.font_face(0)
    screen.level(perf_active(dev) and B.FULL or B.MED)
    screen.move(x + 16, y + 56); screen.text_center(dev.name)
    return
  end
  screen.line_width(1)
  screen.level(focused and B.FULL or B.MED)
  screen.rect(x, y, w, h); screen.stroke()
  screen.font_size(8); screen.font_face(0)
  screen.level(perf_active(dev) and B.FULL or B.MED)
  screen.move(x + w / 2, y + math.floor(h / 2) + 3); screen.text_center(dev.abbr)
end

local function draw_device_pane()
  screen.clear()
  local e   = STUDIO_DEVICES[studio_sel]
  local dev = e.dev
  local pid = dev.params[dev_param_sel[e.abbr] or 1]
  if pid then
    draw_strip(dev.name, params:lookup_param(pid).name, fmt_param(pid), B.FULL)
  else
    draw_strip(dev.name, "Not built", "--", B.MED)
  end
  draw_looper_state_icon()
  draw_hold_status()

  local c = cabinet.CAB
  for _, o in ipairs(STUDIO_DEVICES) do
    if o.group == DEV_GROUP and o.pane == e.pane then
      local focused = (o.abbr == e.abbr)
      -- only the focused device shows a bright cap, and only on its selected param
      local fk  = focused and (dev_param_sel[o.abbr] or 1) or nil
      local hix = (o.abbr == "HD1" and 1) or (o.abbr == "HD2" and 2) or nil
      if o.rack then                              -- stacked 19" units, full width
        local h = math.floor((c.h - 4) / 2)
        -- Only the upper unit was nudged, by two rows, so its top edge sits where the eye
        -- expects a device to start. Limit keeps the position it had, which widens the gap
        -- between the two faceplates from 4 to 6 px.
        local nudge = (o.slot == 1) and 2 or 0
        draw_device_body(c.x, c.y + (o.slot - 1) * (h + 4) - nudge, c.w, h, o.dev, focused, fk, nil, true)
      else                                        -- two pedals, snapped to the edges
        local x = (o.slot == 1) and c.x or (c.x + c.w - 33)
        draw_device_body(x, 4, 33, 47, o.dev, focused, fk, hix, false)
        -- same focus marker the pedalboard and the mod rack use: a pixel left of the caption
        if focused then draw_label_cursor(x + 16, 4 + 56, o.dev.name) end
      end
    end
  end
  screen.update()
end

function redraw()
  if initing then return end
  if gui_mode == 3 then screen.clear(); screen.update(); return end
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
  cabinet.draw_grillcloth(params:get("cab_mode"), cab_sel_id() == "mic_position", params:get("mic_position") - 1)
  cabinet.draw_panel(sel, params:get("signal_input") == 2, amp_is_bypassed())
  cabinet.draw_cabinet()
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
  local lo = (g == 1 and mod_open) and MOD_PANE_1 or 1   -- no Tune/Count from Stage
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

-- The cabinet's panel has nine fixed knobs, but its four devices own more params than that:
-- Tremolo's Sync and Feel, Reverb's two shelves and Cab Level have no knob to turn. E2 walks
-- the full list all the same - they were reachable in Stage and in PARAMS but nowhere in the
-- studio - and this keeps the drawn panel in step: it moves the highlight whenever the
-- selected param does have a knob, and leaves it on the device's last one when it does not.
local function cab_sync_knob(e)
  local id = e.dev.params[dev_param_sel[e.abbr] or 1]
  local d  = id and PARAM_DEF_OF[id]
  if d and d.def == PARAMS_DEF then sel = d.idx end
end

-- Point the views at whatever device the studio walk currently selects.
studio_apply = function()
  local e = STUDIO_DEVICES[studio_sel]
  view_group         = e.group
  view_pane[e.group] = e.pane
  -- enter on the device's own first param (its leftmost knob), or where you left it
  if e.cab then cab_sync_knob(e) end
  tune.set_active(is_tune_active())
end

-- Hold K1 to open the mod rack, hold again to return. Works in both views.
local function mod_open_toggle()
  mod_open = not mod_open
  if mod_open then
    view_group   = 1
    view_pane[1] = math.max(view_pane[1], MOD_PANE_1)
  elseif gui_mode == 1 then
    studio_apply()          -- back to whatever device the walk is on
  else
    view_group = 0
  end
  tune.set_active(is_tune_active())
  redraw()
end

local function count_tick_now()
  local level    = lfo.count.level    ~= nil and lfo.count.level / 10.0 or params:get("count_level") / 10.0
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
    engine.count_tick(level, p - 1 - 57, length, position)
  end

  if stepping then count_step = count_step + 1 end
end

local function count_clock_start()
  if count_clock then clock.cancel(count_clock) end
  count_step = 0
  count_clock = clock.run(function()
    if clock_running then
      clock.sync(sync.COUNT_DIV_BEATS[lfo.count.div or params:get("count_div")])
      while true do
        count_tick_now()
        clock.sync(sync.COUNT_DIV_BEATS[lfo.count.div or params:get("count_div")])
      end
    else
      while true do
        count_tick_now()
        local div = lfo.count.div or params:get("count_div")
        local bpm = tonumber(params:get("count_bpm")) or 120
        clock.sleep(sync.COUNT_DIV_BEATS[div] * 60.0 / bpm)
      end
    end
  end)
end

local function count_clock_stop()
  if count_clock then clock.cancel(count_clock); count_clock = nil end
end

function enc(n, d)
  if gui_mode == 3 then return end
  -- in Stage the mod rack borrows the regular group-1 handling below
  if gui_mode == 2 and not mod_open then perf_enc(n, d); return end
  -- E1 walks the signal chain; inside the mod rack it walks that rack's panes instead
  if n == 1 then
    if mod_open then
      set_pane(view_pane[1] + d)
    else
      studio_sel = util.clamp(studio_sel + d, 1, #STUDIO_DEVICES)
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
        dev_param_sel[e.abbr] = util.clamp((dev_param_sel[e.abbr] or 1) + d, 1, #dev.params)
      elseif n == 3 then
        edit_param(dev.params[dev_param_sel[e.abbr] or 1], d)
      end
    end
    redraw()
    return
  end
  if view_group == 1 then
    local p = view_pane[1]
    if p == 1 then
      if n == 3 then edit_param("tune_ref", d) end
    elseif p == 2 then
      if n == 2 then
        count_strip_sel = util.clamp(count_strip_sel + d, 1, #COUNT_STRIP)
        redraw()
      elseif n == 3 then
        local ms = COUNT_STRIP[count_strip_sel]
        if ms.typ == "opt" then
          params:set(ms.id, util.clamp(params:get(ms.id) + d, 1, ms.nmax))
        else
          params:set(ms.id, snap_val(params:get(ms.id) + d * ms.step, ms.step))
        end
        redraw()
      end
    elseif p == 3 or p == 4 then
      local idx = (p == 3) and 1 or 2
      if n == 2 then
        env.strip_sel[idx] = env.strip_advance(idx, env.strip_sel[idx], d)
        redraw()
      elseif n == 3 then
        local es  = env.STRIP[env.strip_sel[idx]]
        local id  = "env" .. idx .. es.suf
        if es.typ == "opt" then
          local nmax = es.nmax_fn and es.nmax_fn(idx) or es.nmax
          if nmax > 0 then
            params:set(id, util.clamp(params:get(id) + d, 1, nmax))
          end
        else
          params:set(id, snap_val(params:get(id) + d * es.step, es.step))
        end
        redraw()
      end
    elseif p == 13 or p == 14 then
      local idx = (p == 13) and 1 or 2
      if n == 2 then
        seq_strip_sel[idx] = seq.strip_advance(idx, seq_strip_sel[idx], d)
        redraw()
      elseif n == 3 then
        local ss  = seq.STRIP[seq.strip_resolve(idx, seq_strip_sel[idx])]
        local id  = "seq" .. idx .. ss.suf
        if ss.typ == "opt" then
          local nmax = ss.nmax_fn and ss.nmax_fn(idx) or ss.nmax
          if nmax > 0 then
            params:set(id, util.clamp(params:get(id) + d, 1, nmax))
          end
        else
          params:set(id, snap_val(params:get(id) + d * ss.step, ss.step))
        end
        if ss.suf == "_sync_div" then seq.start_clock(idx) end
        redraw()
      end
    elseif p >= 15 then
      local is_left = (p % 2) == 1
      local pair    = math.ceil(p / 2)
      local idx     = (pair - 8) * 2 + (is_left and 1 or 2)
      if n == 2 then
        trigs.strip_sel[idx] = trigs.strip_fn.advance(idx, trigs.strip_sel[idx], d)
        redraw()
      elseif n == 3 then
        local ts  = trigs.STRIP[trigs.strip_sel[idx]]
        local id  = "trig" .. idx .. ts.suf
        if ts.typ == "opt" then
          local nmax = ts.nmax_fn and ts.nmax_fn(idx) or ts.nmax
          if nmax > 0 then
            params:set(id, util.clamp(params:get(id) + d, 1, nmax))
          end
        else
          params:set(id, snap_val(params:get(id) + d * ts.step, ts.step))
        end
        if ts.suf == "_sync_div" then trigs.fn.start_clock(idx) end
        redraw()
      end
    else
      local is_left = (p % 2) == 1
      local pair    = math.ceil(p / 2)
      local idx     = (pair - 3) * 2 + (is_left and 1 or 2)
      if n == 2 then
        lfo_strip_sel[idx] = lfo.strip_advance(idx, lfo_strip_sel[idx], d)
        redraw()
      elseif n == 3 then
        local ls  = lfo.STRIP[lfo_strip_sel[idx]]
        local id  = "lfo" .. idx .. ls.suf
        if ls.typ == "opt" then
          local nmax = ls.nmax_fn and ls.nmax_fn(idx) or ls.nmax
          if nmax > 0 then
            params:set(id, util.clamp(params:get(id) + d, 1, nmax))
          end
        else
          params:set(id, snap_val(params:get(id) + d * ls.step, ls.step))
        end
        if ls.suf == "_sync_div" then lfo.start_clock(idx) end
        redraw()
      end
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

  -- the cabinet holds four devices; E2 stays inside the focused one's params, knob or not
  local e = STUDIO_DEVICES[studio_sel]
  if n == 2 then
    dev_param_sel[e.abbr] = util.clamp((dev_param_sel[e.abbr] or 1) + d, 1, #e.dev.params)
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

-- ── Mod rack key actions ──────────────────────────────────────
-- Shared by the Studio mod rack and the Stage overlay, so both behave identically.
local function mod_rack_lfo_idx(p)
  local is_left = (p % 2) == 1
  local pair    = math.ceil(p / 2)
  return (pair - 3) * 2 + (is_left and 1 or 2)
end

local function mod_rack_trig_idx(p)
  local is_left = (p % 2) == 1
  local pair    = math.ceil(p / 2)
  return (pair - 8) * 2 + (is_left and 1 or 2)
end

local function mod_rack_randomize()
  local p = view_pane[1]
  if p >= 5 and p <= 12 then
    params:set("lfo" .. mod_rack_lfo_idx(p) .. "_randomize", 1)
  elseif p == 13 or p == 14 then
    params:set("seq" .. ((p == 13) and 1 or 2) .. "_randomize", 1)
  end
end

local function mod_rack_toggle()
  local p = view_pane[1]
  local function flip(id) params:set(id, 3 - params:get(id)) end
  if p == 3 or p == 4 then           flip("env" .. ((p == 3) and 1 or 2) .. "_enable")
  elseif p >= 5 and p <= 12 then     flip("lfo" .. mod_rack_lfo_idx(p) .. "_enable")
  elseif p == 13 or p == 14 then     flip("seq" .. ((p == 13) and 1 or 2) .. "_enable")
  elseif p >= 15 then                flip("trig" .. mod_rack_trig_idx(p) .. "_enable")
  end
end

-- Amp and Loop keep the looper transport on K2/K3, so it stays reachable from the
-- default focus; every other device toggles itself on K3.
local function is_transport_dev(dev)
  return dev.abbr == "LOP" or dev.abbr == "AMP"
end

-- K2/K3 for the focused device, shared by the Stage chain and the studio walk. The
-- 2-second holds are gone: only K1 still has one, for the mod rack.
local function device_key(dev, n, z)
  -- Amp carries the transport so the looper stays reachable from the default view; that
  -- shortcut must not then yank the focus over to Loop and undo the point of it.
  local function transport(fn)
    if dev.abbr ~= "LOP" then focus_absorb["@loop"] = true end
    fn()
  end
  if n == 2 then
    long_press("k2", z, function() end, function()
      if is_transport_dev(dev) then transport(looper.stop_clear) end
    end)
  elseif n == 3 then
    long_press("k3", z, function() end, function()
      if is_transport_dev(dev) then
        transport(looper.step)
      elseif dev.enable then
        params:set(dev.enable, 3 - params:get(dev.enable))
      end
    end)
  end
end

-- mod rack K2/K3, used whenever the rack is open in either view
local function key_group1(n, z)
  if n == 2 then
    long_press("k2", z, function() end, mod_rack_randomize)
  elseif n == 3 then
    long_press("k3", z, function() end, mod_rack_toggle)
  end
end

function key(n, z)
  if gui_mode == 3 then return end
  if n == 1 then
    long_press("k1", z, mod_open_toggle)   -- the only remaining 2-second hold
    return
  end
  if mod_open then key_group1(n, z); return end
  if gui_mode == 2 then
    device_key(PERF_DEVICES[perf_sel], n, z)
  else
    device_key(STUDIO_DEVICES[studio_sel].dev, n, z)
  end
end


function init()
  if not params._orig_read then
    params._orig_read = params.read
    params.pset_loading = false
    params.read = function(self, ...)
      params.pset_loading = true
      local ok, err = pcall(params._orig_read, self, ...)
      params.pset_loading = false
      if not ok then error(err) end
    end
  end
  audio.level_monitor(0)
  looper.init({
    is_clock_running = function() return clock_running end,
    get_override     = function() return lfo.sync_override end,
    is_pane_visible  = function() return view_group == 0 and view_pane[0] == 2 end,
  })
  looper_ui.init({
    draw_strip      = draw_strip,
    fmt_val         = function(i) return fmt_def_val(LOOPER_DEF, i) end,
    LOOPER_DEF      = LOOPER_DEF,
    val_level       = function(id) return sync.val_level(id, clock_running) end,
    draw_state_icon = draw_looper_state_icon,
    draw_overlay    = draw_hold_status,
    B               = B,
    looper          = looper,
    LOOPER_PTS      = sprites.LOOPER_PTS,
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
    is_pane_visible  = function() return view_group == 1 and (view_pane[1] == 13 or view_pane[1] == 14) end,
    redraw_pane      = function() if not initing then redraw() end end,
  })
  local function re() if not initing then redraw() end end

  local function add_p_params(ped)
    for _, p in ipairs(ped.params) do
      if p.options then
        params:add_option(p.id, p.name, p.options, p.default + 1)
        params:set_action(p.id, function(v) engine[p.id](v - 1); re() end)
      else
        params:add_control(p.id, p.name, controlspec.new(p.min, p.max, p.warp or "lin", p.step, p.default, p.unit or ""))
        params:set_action(p.id, function(v) engine[p.id](p.step == 1 and math.floor(v) or v); re() end)
      end
    end
  end

  local function sync_df_action(prefix)
    local dev_name = prefix:sub(1,1):upper() .. prefix:sub(2)
    return function(_)
      if not initing then
        sync.push_all(initing, clock_running, lfo.sync_override)
        lfo.refresh_dropdowns_for_device(dev_name)
      end
      re()
    end
  end

  local function db_action(name)
    return function(v) engine[name](db_to_lin(v)); re() end
  end

  local function add_engine_ctrl(id, name, mn, mx, warp, step, default, unit)
    params:add_control(id, name, controlspec.new(mn, mx, warp, step, default, unit or ""))
    params:set_action(id, function(v) engine[id](v); re() end)
  end

  local function add_sync_params(prefix)
    params:add_separator(prefix .. "_sep_sync", "─── Synchronization ───")
    params:add_option(prefix .. "_sync_div", "Sync", sync.DIV_OPTS, 4)
    params:set_action(prefix .. "_sync_div", sync_df_action(prefix))
    params:add_option(prefix .. "_sync_feel", "Sync Feel", sync.FEEL_OPTS, 1)
    params:set_action(prefix .. "_sync_feel", sync_df_action(prefix))
  end

  local function setup_pedal(idx)
    local ped = PEDALS[idx]
    local prefix = ped.name:lower()
    local has_sync = false
    for _, p in ipairs(ped.params) do
      if sync.PARAM_MAP[p.id] then has_sync = true; break end
    end
    params:add_group(ped.name:upper(), 6 + (has_sync and 3 or 0))
    params:add_separator(prefix .. "_sep_control", "─── Control ───")
    params:add_option(ped.enable_id, "Engage", {"Bypass", "Active"}, 1)
    params:set_action(ped.enable_id, function(v)
      if ped.subsynth then lifecycle.set(ped.subsynth, v == 2)
      else engine[ped.bypass_cmd](2 - v) end
      re()
    end)
    add_p_params(ped)
    if has_sync then add_sync_params(prefix) end
  end

  local function setup_amp()
    params:add_group("AMP", 6)
    params:add_separator("amp_sep_control", "─── Control ───")
    params:add_option("amp_enable", "Engage", {"Bypass", "Active"}, 2)
    params:set_action("amp_enable", function(v) engine.amp_bypass(2 - v); re() end)
    add_engine_ctrl("amp_volume", "Volume", 0, 10, "lin", 0.1, 5.0)
    add_engine_ctrl("amp_bass",   "Bass",   0, 10, "lin", 0.1, 5.0)
    add_engine_ctrl("amp_treble", "Treble", 0, 10, "lin", 0.1, 5.0)
    add_engine_ctrl("amp_master", "Master", 0, 10, "lin", 0.1, 7.5)
  end

  local function setup_tremolo()
    params:add_group("TREMOLO", 7)
    params:add_separator("tremolo_sep_control", "─── Control ───")
    params:add_option("tremolo_enable", "Engage", {"Bypass", "Active"}, 2)
    params:set_action("tremolo_enable", function(v) engine.tremolo_intensity(v == 2 and params:get("tremolo_intensity") or 0); re() end)
    add_engine_ctrl("tremolo_speed", "Speed", 0.1, 25, "exp", 0, 2.5, "Hz")
    params:add_control("tremolo_intensity", "Intensity", controlspec.new(0, 100, "lin", 1, 0, "%"))
    params:set_action("tremolo_intensity", function(v) if params:get("tremolo_enable") == 2 then engine.tremolo_intensity(v) end; re() end)
    add_sync_params("tremolo")
  end

  local function setup_looper()
    looper_params.setup({
      re                   = re,
      db_to_lin            = db_to_lin,
      is_initing           = function() return initing end,
      group_label = "LOOP",
      on_quant_div_changed = function() lfo.refresh_dropdowns_for_device("Loop") end,
      speed_is_owned       = function() return lfo.target_owner["looper_speed"] ~= nil end,
      looper               = looper,
      embedded             = true,
    })
  end

  local function setup_reverb()
    params:add_group("SPRING REVERB", 6)
    params:add_separator("reverb_sep_control", "─── Control ───")
    params:add_option("reverb_enable", "Engage", {"Bypass", "Active"}, 2)
    params:set_action("reverb_enable", function(v) engine.reverb_mute(v == 2 and 0 or 1); re() end)
    add_engine_ctrl("reverb_amount",     "Amount",     0,   100, "lin", 1,   25,  "%")
    add_engine_ctrl("reverb_length",     "Length",     0.5, 5.0, "lin", 0.1, 2.5, "s")
    add_engine_ctrl("reverb_low_shelf",  "Low Shelf", -5,   5,   "lin", 0.5, 0,   "dB")
    add_engine_ctrl("reverb_high_shelf", "High Shelf",-5,   5,   "lin", 0.5, 0,   "dB")
  end

  local CAB_MODE_ALL = {"mic_position", "cab_level"}
  local CAB_MODE_VISIBLE = {
    [1] = {},
    [2] = {mic_position=true, cab_level=true},
  }

  local function setup_cab()
    params:add_group("CAB & MIC", 4)
    params:add_separator("cab_sep_control", "─── Control ───")
    params:add_option("cab_mode", "Mode", {"Bypass", "Cab & Mic Sim"}, 2)
    params:set_action("cab_mode", function(v)
      engine.cab_mode(v - 1)
      for _, p in ipairs(CAB_MODE_ALL) do
        if CAB_MODE_VISIBLE[v][p] then params:show(p) else params:hide(p) end
      end
      if _menu and _menu.rebuild_params then _menu.rebuild_params() end
      re()
    end)
    params:add_option("mic_position", "Mic Position", MIC_NAMES, 2)
    params:set_action("mic_position", function(v) engine.mic_position(v - 1); re() end)
    params:add_control("cab_level", "Cab Level", controlspec.new(-10, 10, "lin", 0.5, 0, "dB"))
    params:set_action("cab_level", db_action("cab_level"))
  end

  local function setup_eq()
    params:add_group("EQ", 10)
    params:add_separator("eq_sep_control", "─── Control ───")
    params:add_option("eq_enable", "Engage", {"Bypass", "Active"}, 1)
    params:set_action("eq_enable", function(v) engine.eq_bypass(2 - v); re() end)
    params:add_option("eq_low_freq", "Low Freq", {"100 Hz", "140 Hz", "200 Hz", "300 Hz"}, 2)
    params:set_action("eq_low_freq", function(v) engine.eq_low_freq(v - 1); re() end)
    -- 0..10 maps straight onto the filter's dB argument, so the number is already decibels
    add_engine_ctrl("eq_low_boost", "Low Boost", 0, 10, "lin", 0.1, 0, "dB")
    add_engine_ctrl("eq_low_cut",   "Low Cut",   0, 10, "lin", 0.1, 0, "dB")
    params:add_option("eq_high_freq", "High Freq",
      {"1 kHz", "1.5 kHz", "2 kHz", "3 kHz", "4 kHz", "5 kHz"}, 4)
    params:set_action("eq_high_freq", function(v) engine.eq_high_freq(v - 1); re() end)
    params:add_option("eq_high_bw", "Bandwidth", {"Sharp", "Broad"}, 1)
    params:set_action("eq_high_bw", function(v) engine.eq_high_bw(v - 1); re() end)
    add_engine_ctrl("eq_high_boost", "High Boost", 0, 10, "lin", 0.1, 0, "dB")
    add_engine_ctrl("eq_high_cut",   "High Cut",   0, 10, "lin", 0.1, 0, "dB")
    params:add_control("eq_gain", "Gain", controlspec.new(-20, 20, "lin", 0.5, 0, "dB"))
    params:set_action("eq_gain", function(v) engine.eq_gain(v); re() end)
  end

  local function setup_limit()
    params:add_group("LIMIT", 7)
    params:add_separator("limit_sep_control", "─── Control ───")
    params:add_option("limit_enable", "Engage", {"Bypass", "Active"}, 1)
    params:set_action("limit_enable", function(v) engine.limit_bypass(2 - v); re() end)
    params:add_control("limit_threshold", "Threshold", controlspec.new(-40, 0, "lin", 0.5, -10, "dB"))
    params:set_action("limit_threshold", db_action("limit_threshold"))
    add_engine_ctrl("limit_ratio",  "Ratio",  2.0, 20.0, "lin", 0.5, 4.0, ": 1")
    add_engine_ctrl("limit_attack", "Attack", 1,   100,  "lin", 1,   10,  "ms")
    add_engine_ctrl("limit_decay",  "Decay",  50,  2000, "lin", 50,  50,  "ms")
    params:add_control("limit_gain", "Gain", controlspec.new(-20, 20, "lin", 0.5, 0, "dB"))
    params:set_action("limit_gain", db_action("limit_gain"))
  end

  local function setup_hold(idx)
    local p = "hold" .. idx .. "_"
    local d  = (idx == 2) and 7.5 or 5   -- Hold 2 startet laenger/dichter/breiter
    local st = (idx == 2) and 12 or -12  -- Hold 1 an octave down, Hold 2 an octave up
    params:add_group("HOLD " .. idx, 14)
    params:add_separator(p .. "sep_control", "─── Control ───")
    params:add_option(p .. "enable", "Engage", {"Bypass", "Active"}, 1)
    params:set_action(p .. "enable", function(v) if v == 2 then engine.hold_on(idx) else engine.hold_off(idx) end; re() end)
    params:add_control(p .. "size", "Size", controlspec.new(0, 10, "lin", 0.1, d))
    params:set_action(p .. "size", function(v) engine.hold_size(idx, v); re() end)
    params:add_control(p .. "density", "Density", controlspec.new(1, 10, "lin", 0.1, d))
    params:set_action(p .. "density", function(v) engine.hold_density(idx, v); re() end)
    params:add_control(p .. "spread", "Spread", controlspec.new(0, 10, "lin", 0.1, d))
    params:set_action(p .. "spread", function(v) engine.hold_spread(idx, v); re() end)
    params:add_control(p .. "pitch", "Pitch", controlspec.new(-24, 24, "lin", 1, st, "st"))
    params:set_action(p .. "pitch", function(v) engine.hold_pitch(idx, v); re() end)
    params:add_control(p .. "pmix", "Pitch Mix", controlspec.new(0, 100, "lin", 1, 10, "%"))
    params:set_action(p .. "pmix", function(v) engine.hold_pmix(idx, v); re() end)
    params:add_control(p .. "rev", "Reverse Mix", controlspec.new(0, 100, "lin", 1, 0, "%"))
    params:set_action(p .. "rev", function(v) engine.hold_rev(idx, v); re() end)
    params:add_option(p .. "shape", "Shape", {"Smooth", "Soft", "Swell", "Pluck", "Plateau"}, 1)
    params:set_action(p .. "shape", function(v) engine.hold_shape(idx, v - 1); re() end)
    params:add_option(p .. "interp", "Resolution", {"Coarse", "Fine"}, 2)
    params:set_action(p .. "interp", function(v) engine.hold_interp(idx, (v == 2) and 4 or 2); re() end)
    params:add_control(p .. "gain", "Gain", controlspec.new(0, 10, "lin", 0.1, 5))
    params:set_action(p .. "gain", function(v) engine.hold_gain(idx, v); re() end)
    params:add_control(p .. "level", "Level", controlspec.new(0, 10, "lin", 0.1, 5))
    params:set_action(p .. "level", function(v) engine.hold_level(idx, v); re() end)
    params:add_control(p .. "rise", "Rise", controlspec.new(0.01, 5.0, "exp", 0.01, 0.25, "s"))
    params:set_action(p .. "rise", function(v) engine.hold_rise(idx, v); re() end)
    params:add_control(p .. "fall", "Fall", controlspec.new(0.01, 5.0, "exp", 0.01, 2.5, "s"))
    params:set_action(p .. "fall", function(v) engine.hold_fall(idx, v); re() end)
  end

  local function setup_gate()
    params:add_group("CUT", 9)
    params:add_separator("cut_sep_control", "─── Control ───")
    params:add_option("cut_enable", "Engage", {"Bypass", "Active"}, 1)
    params:set_action("cut_enable", function(v) if v == 2 then engine.cut_on() else engine.cut_off() end; re() end)
    params:add_control("cut_thresh", "Threshold", controlspec.new(-80, 0, "lin", 0.5, -50, "dB"))
    params:set_action("cut_thresh", function(v) engine.cut_thresh(v); re() end)
    add_engine_ctrl("cut_attack",  "Attack",  0.1, 2500, "exp", 0, 1,   "ms")
    add_engine_ctrl("cut_hold",    "Hold",    1,   2500, "exp", 0, 20,  "ms")
    add_engine_ctrl("cut_release", "Release", 1,   2500, "exp", 0, 100, "ms")
    params:add_control("cut_range", "Range", controlspec.new(-75, 0, "lin", 0.5, -75, "dB"))
    params:set_action("cut_range", function(v) engine.cut_range(v); re() end)
    add_engine_ctrl("cut_hyst", "Margin", 0, 25, "lin", 0.5, 0, "dB")
    params:add_option("cut_detect", "Detection", {"Peak", "RMS"}, 1)
    params:set_action("cut_detect", function(v) engine.cut_detect(v - 1); re() end)
  end

  local function setup_fray()
    params:add_group("FRAY", 10)
    params:add_separator("fray_sep_control", "─── Control ───")
    params:add_option("fray_enable", "Engage", {"Bypass", "Active"}, 1)
    params:set_action("fray_enable", function(v) lifecycle.set("fray", v == 2); re() end)
    add_engine_ctrl("fray_drive",  "Drive",  0, 10, "lin", 0.1, 5)
    add_engine_ctrl("fray_comp",   "Comp",   0, 10, "lin", 0.1, 5)
    add_engine_ctrl("fray_stab",   "Stab",   0, 10, "lin", 0.1, 0)
    add_engine_ctrl("fray_octave", "Octave", 0, 10, "lin", 0.1, 0)
    params:add_option("fray_octave_mode", "Oct Mode", {"Down", "Up", "Both"}, 2)
    params:set_action("fray_octave_mode", function(v) engine.fray_octave_mode(v - 1); re() end)
    add_engine_ctrl("fray_gate",   "Gate",   0, 10, "lin", 0.1, 0)
    add_engine_ctrl("fray_tone",   "Tone",   0, 10, "lin", 0.1, 10)
    add_engine_ctrl("fray_volume", "Volume", 0, 10, "lin", 0.1, 5)
  end

  local function setup_metro()
    params:add_group("COUNT", 15)
    params:add_separator("count_sep_control", "─── Control ───")
    params:add_option("count_enable", "Engage", {"Off", "On"}, 1)
    params:set_action("count_enable", function(v) count_active = (v == 2); if count_active then count_clock_start() else count_clock_stop() end; re() end)
    params:add_text("count_bpm", "BPM", "120")
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
      {"Off", "Forward", "Reverse", "Interval (Thirds)", "Interval (Fourths)", "Interval (Fifths)", "Interval (Sevenths)", "Random"}, 1)
    params:set_action("count_scale_play", function(_) lfo.count.play = nil; count_step = 0 end)
    params:add_option("count_chords", "Chords", {"Off", "Octaves", "Power Chords", "Triads"}, 1)
    params:set_action("count_chords", function(_) lfo.count.chords = nil end)

    params:add_separator("count_sep_sound", "─── Sound ───")
    params:add_control("count_level", "Level", controlspec.new(0, 10, "lin", 0.1, 5.0, ""))
    params:set_action("count_level", function(_) lfo.count.level = nil; re() end)
    params:add_control("count_length", "Length", controlspec.new(1, 500, "lin", 1, 50, "ms"))
    params:set_action("count_length", function(_) lfo.count.length = nil end)
    params:add_option("count_position", "Position", {"Parallel", "Inline"}, 1)
  end

  local function setup_tuner()
    params:add_group("TUNE", 3)
    params:add_separator("tune_sep_control", "─── Control ───")
    params:add_option("tune_mute", "Engage", {"Bypass", "Active"}, 1)
    params:set_action("tune_mute", function(v)
      tune.muted = (v == 2)
      engine.mute(tune.muted and 1 or 0)
      re()
    end)
    params:add_control("tune_ref", "Reference", controlspec.new(420, 460, "lin", 0.1, 440.0, "Hz"))
    params:set_action("tune_ref", function(v) tune.ref_hz = v; re() end)
  end

  local function setup_signal_flow()
    params:add_group("SIGNAL FLOW", 7)
    params:add_separator("signal_flow_sep_control", "─── Control ───")
    params:add_option("signal_input", "Input", {"Mono", "Stereo"}, 1)
    params:set_action("signal_input", function(v) engine.signal_input(v); re() end)
    params:add_control("input_trim", "Input Trim", controlspec.new(-75, 10, "lin", 0.5, 0, "dB"))
    params:set_action("input_trim", db_action("input_trim"))
    params:add_option("fx_send_a_source", "Send A Source", {"Input", "Loop", "Output"}, 3)
    params:set_action("fx_send_a_source", function(v) engine.fx_send_a_source(v - 1); re() end)
    params:add_control("fx_send_a_level", "Send A Level", controlspec.new(-60, 10, "lin", 0.5, 0, "dB"))
    params:set_action("fx_send_a_level", db_action("fx_send_a_level"))
    params:add_option("fx_send_b_source", "Send B Source", {"Input", "Loop", "Output"}, 3)
    params:set_action("fx_send_b_source", function(v) engine.fx_send_b_source(v - 1); re() end)
    params:add_control("fx_send_b_level", "Send B Level", controlspec.new(-60, 10, "lin", 0.5, 0, "dB"))
    params:set_action("fx_send_b_level", db_action("fx_send_b_level"))
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

  local function register_lfo(idx)
    local prefix = "lfo" .. idx

    local function refresh_visibility()
      local wf  = params:get(prefix .. "_waveform")
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

    params:add_group("MOD LFO " .. idx, 18)
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

    params:add_option(prefix .. "_waveform", "Waveform", lfo.WAVEFORMS, 1)
    params:set_action(prefix .. "_waveform", function(_)
      refresh_visibility()
      if not initing then
        lfo.start_clock(idx)
        lfo.refresh_dropdowns_for_device("LFO " .. idx)
        trigs.fn.refresh_dropdowns_for_lfo(idx)
      end
      re()
    end)

    params:add_control(prefix .. "_rate", "Rate", controlspec.new(0.1, 25, "exp", 0.1, 1.0, "Hz"))
    params:set_action(prefix .. "_rate", function(_)
      lfo.mod.rate[idx] = nil
      lfo.target_base[prefix .. "_rate"] = nil
    end)

    params:add_control(prefix .. "_depth", "Depth", controlspec.new(0, 100, "lin", 1, 50, "%"))
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

    params:add_control(prefix .. "_stability", "Stability", controlspec.new(0, 100, "lin", 1, 50, "%"))
    params:set_action(prefix .. "_stability", function(_)
      lfo.mod.stability[idx] = nil
      lfo.target_base[prefix .. "_stability"] = nil
    end)

    params:add_control(prefix .. "_rate_slew", "Rate Slew", controlspec.new(0, 5, "lin", 0.1, 0, "s"))
    params:set_action(prefix .. "_rate_slew", function(_)
      lfo.mod.rate_slew[idx] = nil
      lfo.target_base[prefix .. "_rate_slew"] = nil
    end)

    params:add_separator(prefix .. "_sep_sync", "─── Synchronization ───")

    params:add_option(prefix .. "_sync_div", "Sync", sync.DIV_OPTS, 1)
    params:set_action(prefix .. "_sync_div", function(_)
      lfo.mod.sync_div[idx] = nil
      lfo.target_base[prefix .. "_sync_div"] = nil
      refresh_visibility()
      if not initing then
        lfo.refresh_dropdowns_for_device("LFO " .. idx)
        lfo.start_clock(idx)
      end
    end)

    params:add_option(prefix .. "_sync_feel", "Sync Feel", sync.FEEL_OPTS, 1)
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

    params:add_group("MOD SENSE " .. idx, 8)
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

    params:add_control(prefix .. "_depth", "Depth", controlspec.new(0, 100, "lin", 1, 50, "%"))

    params:add_option(prefix .. "_dir", "Direction", env.DIR_OPTS, 1)

    params:add_control(prefix .. "_slew", "Slew", controlspec.new(1, 500, "lin", 1, 50, "ms"))
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

    params:add_group("MOD TRIGGER " .. idx, 10)
    params:add_separator(prefix .. "_sep_control", "─── Control ───")

    params:add_option(prefix .. "_enable", "Engage", {"Off", "On"}, 1)
    params:set_action(prefix .. "_enable", function(_)
      if not initing then trigs.fn.set_enable(idx) end
      re()
    end)

    params:add_control(prefix .. "_probability", "Probability", controlspec.new(0, 100, "lin", 1, 100, "%"))
    params:set_action(prefix .. "_probability", function(_)
      trigs.mod.probability[idx] = nil
      lfo.target_base[prefix .. "_probability"] = nil
      re()
    end)

    params:add_control(prefix .. "_rate", "Rate", controlspec.new(0.1, 25, "exp", 0.1, 1.0, "Hz"))
    params:set_action(prefix .. "_rate", function(_)
      trigs.mod.rate[idx] = nil
      lfo.target_base[prefix .. "_rate"] = nil
    end)

    params:add_separator(prefix .. "_sep_sync", "─── Synchronization ───")

    params:add_option(prefix .. "_sync_div", "Sync", sync.DIV_OPTS, 1)
    params:set_action(prefix .. "_sync_div", function(_)
      refresh_visibility()
      if not initing then trigs.fn.start_clock(idx) end
      re()
    end)

    params:add_option(prefix .. "_sync_feel", "Sync Feel", sync.FEEL_OPTS, 1)

    params:add_separator(prefix .. "_sep_target", "─── Target ───")

    params:add_option(prefix .. "_target_device", "Device", trigs.DEVICES, default_dev)
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

    params:add_option(prefix .. "_target_param", "Target", dev_shorts, 1)
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


  local function setup_clock_watchers()
    clock.run(function()
      clock.sleep(1.0)
      params:set("tremolo_sync_div", 1)
      params:set("warp_sync_div", 1)
      params:set("repeat_sync_div", 1)
      params:set("looper_quant_div", 1)
    end)

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
      while true do
        clock.sleep(0.5)

        local current_source = nil
        pcall(function() current_source = params:get("clock_source") end)
        if current_source and current_source ~= last_source then
          local default = current_source == 2 and 4 or 1
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
            sync.activate_defaults()
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
        if bpm > 0 and params:get("count_bpm") ~= tostring(bpm) then
          params:set("count_bpm", tostring(bpm))
        end
      end
    end)
  end

  local function setup_gui()
    params:add_group("GUI", 4)
    params:add_separator("gui_sep_control", "─── Control ───")
    params:add_option("gui", "GUI", {"Studio", "Stage", "Off"}, 1)
    params:set_action("gui", function(v)
      gui_mode = v
      mod_open = false         -- the mod rack never carries across a view switch
      if v == 1 then           -- Studio opens on the amp
        studio_sel = STUDIO_INDEX_OF.AMP or 1
        studio_apply()         -- sets the panel knob from the device's selected param
      elseif v == 2 then       -- Stage opens on the tuner
        perf_sel = PERF_INDEX_OF.TUN or 1
      end
      if refresh_tune then refresh_tune() end
      redraw()
    end)
    params:add_option("gui_follow_focus", "Follow Focus", {"Off", "On"}, 2)
    params:add_binary("gui_init", "Initialize", "trigger", 0)
    params:set_action("gui_init", function(v)
      if v ~= 1 or initing then return end
      -- mirror PSET-load: bypass the L35 +/-1 clamp so target dropdowns
      -- (LFO/Sense/Trigger/Walk) actually jump back to their default, not by one step.
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

  -- ── Param registration ───────────────────────────────────────
  params:add_separator("princeton_header", "─── PRINCETON ───")
  setup_gui()
  setup_signal_flow()
  -- from here the groups follow the signal chain, same order as the E1 walk
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
  setup_eq()
  setup_limit()
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

    params:add_group("MOD WALK " .. idx, 29)
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
      params:add_control(prefix .. "_step_" .. k, "Step " .. k, controlspec.new(-100, 100, "lin", 1, 0, "%"))
    end

    params:add_control(prefix .. "_rate", "Rate", controlspec.new(0.1, 25, "exp", 0.1, 1.0, "Hz"))
    params:set_action(prefix .. "_rate", function(_)
      seq.mod.rate[idx] = nil
      lfo.target_base[prefix .. "_rate"] = nil
    end)

    params:add_control(prefix .. "_rate_slew", "Rate Slew", controlspec.new(0, 5, "lin", 0.1, 0, "s"))
    params:set_action(prefix .. "_rate_slew", function(_)
      seq.mod.rate_slew[idx] = nil
      lfo.target_base[prefix .. "_rate_slew"] = nil
    end)

    params:add_separator(prefix .. "_sep_sync", "─── Synchronization ───")

    params:add_option(prefix .. "_sync_div", "Sync", sync.DIV_OPTS, 1)
    params:set_action(prefix .. "_sync_div", function(_)
      seq.mod.sync_div[idx] = nil
      lfo.target_base[prefix .. "_sync_div"] = nil
      refresh_visibility()
      if not initing then
        seq.refresh_dropdowns_for_device("Walk " .. idx)
        seq.start_clock(idx)
      end
    end)

    params:add_option(prefix .. "_sync_feel", "Sync Feel", sync.FEEL_OPTS, 1)
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

  params:bang()
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

  clock.run(function()
    clock.sleep(0.2)
    audio.level_monitor(0)
  end)

  clock.run(function()
    while true do
      clock.sleep(1/25)
      if _G.screenstream_active then
        redraw()
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

  -- Grain animation: only while the Hold pane is actually on screen, so it costs nothing
  -- anywhere else. Same idea as the Walk pane's moving playhead.
  clock.run(function()
    while true do
      clock.sleep(1 / 15)
      if not initing and gui_mode == 1 and not mod_open
         and view_group == DEV_GROUP and view_pane[DEV_GROUP] == 2 then
        hold_grain_tick(1)
        hold_grain_tick(2)
        redraw()
      end
    end
  end)

  -- Follow Focus: poll the engage switches; when one flips, focus that device in both
  -- views (background only, never a view switch). Only the user's own hand should move
  -- the focus, so three sources are filtered out:
  --   * modulation - LFO/Sense/Walk send to the engine directly and never write a param
  --   * triggers   - they mark their write in focus_absorb before flipping it
  --   * PSET loads - guarded below, and last[] is kept current even while off, so
  --                  switching Follow Focus on never fires on a change from before
  -- If several devices flip within one tick there is no single intent, so nothing moves.
  do
    local last = {}
    clock.run(function()
      while true do
        clock.sleep(1/20)
        local fire = params:get("gui_follow_focus") == 2 and not initing and not params.pset_loading
        local changed = {}
        for _, id in ipairs(FOCUS_IDS) do
          local v = focus_value(id)
          if last[id] == nil then
            last[id] = v
          elseif v ~= last[id] then
            last[id] = v
            if focus_absorb[id] then
              focus_absorb[id] = nil      -- a trigger wrote this, not the user
            else
              changed[#changed + 1] = id
            end
          end
        end
        if fire and #changed == 1 then focus_device(changed[1]) end
      end
    end)
  end
end
