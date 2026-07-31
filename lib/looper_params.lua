-- looper_params: registers every looper_* param, shared by princeton and media.
--
-- Host contract: looper_params.setup(deps) with
--   deps.re()                   -- redraw-if-not-initing
--   deps.db_to_lin(db)          -- dB -> linear gain
--   deps.is_initing()           -- init flag
--   deps.on_quant_div_changed() -- refresh mod-rack dropdowns for the Looper device
--   deps.speed_is_owned()       -- is looper_speed claimed by a mod source?
--   deps.looper                 -- the loop state-machine module
--   deps.group_label            -- display name of that group (default "LOOPER")
--   deps.embedded               -- true: wrap params in a group (princeton);
--                               --   false: register at top level (media standalone)
local sync = include("lib/sync")

local looper_params = {}

looper_params.DIR_NAMES = { "Forward", "Reverse", "Pendulum", "Random" }

local speed_steps_prev = 0

function looper_params.setup(deps)
  local re                   = deps.re
  local db_to_lin            = deps.db_to_lin
  local is_initing           = deps.is_initing
  local on_quant_div_changed = deps.on_quant_div_changed
  local speed_is_owned       = deps.speed_is_owned
  local looper               = deps.looper

  local function db_action(name)
    return function(v) engine[name](db_to_lin(v)); re() end
  end

  if deps.embedded then params:add_group(deps.group_label or "LOOPER", 26) end
  params:add_separator("looper_sep_control", "─── Control ───")
  params:add_option("looper_transport", "Step Order", {"Rec·Play·Dub", "Rec·Dub·Play"}, 1)
  params:add_option("looper_play_from", "Play From", {"Start", "Cue"}, 1)
  params:set_action("looper_play_from", function(v) engine.looper_play_from(v - 1); re() end)
  params:add_option("looper_dub_style", "Mode", {"Overdub", "Overwrite", "Sample", "Resample"}, 1)
  params:set_action("looper_dub_style", function(v) engine.looper_dub_style(v - 1); re() end)
  params:add_option("looper_direction", "Direction", looper_params.DIR_NAMES, 1)
  params:set_action("looper_direction", function(v) engine.looper_direction(v - 1); re() end)
  params:add_control("looper_dub_level", "Rec Level", controlspec.new(-40, 0, "lin", 0.5, -2.5, "dB"))
  params:set_action("looper_dub_level", db_action("looper_dub_level"))
  params:add_control("looper_level", "Play Level", controlspec.new(-40, 0, "lin", 0.5, -2.5, "dB"))
  params:set_action("looper_level", db_action("looper_level"))
  params:add_control("looper_fade_level", "Fade Level", controlspec.new(-40, 0, "lin", 0.5, -2.5, "dB"))
  params:set_action("looper_fade_level", db_action("looper_fade_level"))
  params:add{type="number", id="looper_speed", name="Speed", min=-100, max=100, default=0, formatter=function(p) return p:get() .. "%" end, action=function(v)
    if params:get("looper_speed_control") == 1 then
      local snapped
      if     v > speed_steps_prev then snapped = v > 0 and 100 or 0
      elseif v < speed_steps_prev then snapped = v < 0 and -100 or 0
      else                             snapped = speed_steps_prev end
      speed_steps_prev = snapped
      if v ~= snapped then params:set("looper_speed", snapped); return end
    else
      speed_steps_prev = v
    end
    if not speed_is_owned() then engine.looper_speed(looper.speed_value()) end
    re()
  end}
  params:add_option("looper_speed_control", "Speed Control", {"Steps","Smooth"}, 1)

  params:add_separator("looper_sep_medium", "─── Medium ───")
  params:add_option("looper_medium", "Medium", {"BBD","Cassette","CD","Chip","Tape","Vinyl"}, 4)
  params:set_action("looper_medium", function(v) engine.looper_medium(v - 1); looper.medium_changed(); re() end)
  params:add_control("looper_imprint", "Imprint", controlspec.new(0, 100, "lin", 1, 10, "%"))
  params:set_action("looper_imprint", function(v) engine.looper_imprint(v); re() end)
  params:add_control("looper_wear", "Wear", controlspec.new(0, 100, "lin", 1, 5, "%"))
  params:set_action("looper_wear", function(v) engine.looper_wear(v); re() end)
  params:add_option("looper_bbd_tone", "M: BBD Tone", {"Bright", "Dark"}, 1)
  params:set_action("looper_bbd_tone", function(v) engine.looper_bbd_tone(v - 1) end)
  params:add_control("looper_wow_cas", "M: Cassette Wow", controlspec.new(0, 100, "lin", 1, 5, "%"))
  params:set_action("looper_wow_cas", function(v) engine.looper_wow_cas(v) end)
  params:add_control("looper_cd_errors", "M: CD Errors", controlspec.new(0, 100, "lin", 1, 0, "%"))
  params:set_action("looper_cd_errors", function(v) engine.looper_cd_errors(v) end)
  params:add_control("looper_chip_crush", "M: Chip Crush", controlspec.new(0, 100, "lin", 1, 0, "%"))
  params:set_action("looper_chip_crush", function(v) engine.looper_chip_crush(v) end)
  params:add_control("looper_wow_tape", "M: Tape Wow", controlspec.new(0, 100, "lin", 1, 5, "%"))
  params:set_action("looper_wow_tape", function(v) engine.looper_wow_tape(v) end)
  params:add_control("looper_vinyl_noise", "M: Vinyl Noise", controlspec.new(0, 100, "lin", 1, 10, "%"))
  params:set_action("looper_vinyl_noise", function(v) engine.looper_vinyl_noise(v) end)

  params:add_separator("looper_sep_sync", "─── Quantization ───")
  params:add_option("looper_quant_div", "Quantize", sync.DIV_OPTS, 1)
  params:set_action("looper_quant_div", function(_)
    looper.quant_led_restart()
    if not is_initing() then on_quant_div_changed() end
    re()
  end)
  params:add_option("looper_quant_feel", "Quantize Feel", sync.FEEL_OPTS, 1)
  params:set_action("looper_quant_feel", function(_) looper.quant_led_restart(); re() end)

  params:add_separator("looper_sep_trigger", "─── Trigger ───")
  params:add_binary("looper_rec_play", "Rec/Play", "trigger", 0)
  params:set_action("looper_rec_play", function(v) if v == 1 then looper.step() end end)
  params:add_binary("looper_stop_clear", "Stop/Clear", "trigger", 0)
  params:set_action("looper_stop_clear", function(v) if v == 1 then looper.stop_clear() end end)
end

return looper_params
