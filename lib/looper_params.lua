local sync = include("lib/sync")

local looper_params = {}

looper_params.DIR_NAMES = { "Forward", "Reverse", "Pendulum", "Random" }

local MEDIA_ALL = { "BBD", "Cassette", "CD", "Chip", "Tape", "Vinyl" }

function looper_params.setup(deps)
  local speed_steps_prev = 0
  local re                   = deps.re
  local db_to_lin            = deps.db_to_lin
  local is_initing           = deps.is_initing
  local on_quant_div_changed = deps.on_quant_div_changed
  local speed_is_owned       = deps.speed_is_owned
  local looper               = deps.looper
  local P                    = looper.pid
  local E                    = looper.cmd

  local function db_action(suffix)
    return function(v) E("looper_" .. suffix)(db_to_lin(v)); re() end
  end

  -- ── medium subset ────────────────────────────────────────────
  local labels, to_engine = {}, {}
  for _, want in ipairs(deps.media or MEDIA_ALL) do
    for i, name in ipairs(MEDIA_ALL) do
      if name == want then
        labels[#labels + 1]    = name
        to_engine[#labels]     = i - 1
      end
    end
  end
  local medium_default = 1
  for i, name in ipairs(labels) do
    if name == (deps.medium_default or "Chip") then medium_default = i end
  end

  if deps.embedded then params:add_group(deps.group_label or "LOOPER", 26) end
  params:add_separator(P("sep_control"), "─── Control ───")
  params:add_option(P("transport"), "Step Order", {"Rec·Play·Dub", "Rec·Dub·Play"}, 1)
  params:add_option(P("play_from"), "Play From", {"Start", "Cue"}, 1)
  params:set_action(P("play_from"), function(v) E("looper_play_from")(v - 1); re() end)
  params:add_option(P("dub_style"), "Mode", {"Overdub", "Overwrite", "Sample", "Resample"}, 1)
  params:set_action(P("dub_style"), function(v) E("looper_dub_style")(v - 1); re() end)
  params:add_option(P("direction"), "Direction", looper_params.DIR_NAMES, 1)
  params:set_action(P("direction"), function(v) E("looper_direction")(v - 1); re() end)
  params:add_control(P("dub_level"), "Rec Level", controlspec.new(-40, 0, "lin", 0.5, -2.5, "dB"))
  params:set_action(P("dub_level"), db_action("dub_level"))
  params:add_control(P("level"), "Play Level", controlspec.new(-40, 0, "lin", 0.5, -2.5, "dB"))
  params:set_action(P("level"), db_action("level"))
  params:add_control(P("fade_level"), "Fade Level", controlspec.new(-40, 0, "lin", 0.5, -2.5, "dB"))
  params:set_action(P("fade_level"), db_action("fade_level"))
  params:add{type="number", id=P("speed"), name="Speed", min=-100, max=100, default=0, formatter=function(p) return p:get() .. "%" end, action=function(v)
    if params:get(P("speed_control")) == 1 then
      local snapped
      if     v > speed_steps_prev then snapped = v > 0 and 100 or 0
      elseif v < speed_steps_prev then snapped = v < 0 and -100 or 0
      else                             snapped = speed_steps_prev end
      speed_steps_prev = snapped
      if v ~= snapped then params:set(P("speed"), snapped); return end
    else
      speed_steps_prev = v
    end
    if not speed_is_owned() then E("looper_speed")(looper.speed_value()) end
    re()
  end}
  params:add_option(P("speed_control"), "Speed Control", {"Steps","Smooth"}, 1)

  params:add_separator(P("sep_medium"), "─── Medium ───")
  params:add_option(P("medium"), "Medium", labels, medium_default)
  params:set_action(P("medium"), function(v)
    E("looper_medium")(to_engine[v]); looper.medium_changed(); re()
  end)
  params:add_control(P("imprint"), "Imprint", controlspec.new(0, 100, "lin", 1, 10, "%"))
  params:set_action(P("imprint"), function(v) E("looper_imprint")(v); re() end)
  params:add_control(P("wear"), "Wear", controlspec.new(0, 100, "lin", 1, 5, "%"))
  params:set_action(P("wear"), function(v) E("looper_wear")(v); re() end)
  params:add_option(P("bbd_tone"), "M: BBD Tone", {"Bright", "Dark"}, 1)
  params:set_action(P("bbd_tone"), function(v) E("looper_bbd_tone")(v - 1) end)
  params:add_control(P("wow_cas"), "M: Cassette Wow", controlspec.new(0, 100, "lin", 1, 5, "%"))
  params:set_action(P("wow_cas"), function(v) E("looper_wow_cas")(v) end)
  params:add_control(P("cd_errors"), "M: CD Errors", controlspec.new(0, 100, "lin", 1, 0, "%"))
  params:set_action(P("cd_errors"), function(v) E("looper_cd_errors")(v) end)
  params:add_control(P("chip_crush"), "M: Chip Crush", controlspec.new(0, 100, "lin", 1, 0, "%"))
  params:set_action(P("chip_crush"), function(v) E("looper_chip_crush")(v) end)
  params:add_control(P("wow_tape"), "M: Tape Wow", controlspec.new(0, 100, "lin", 1, 5, "%"))
  params:set_action(P("wow_tape"), function(v) E("looper_wow_tape")(v) end)
  params:add_control(P("vinyl_noise"), "M: Vinyl Noise", controlspec.new(0, 100, "lin", 1, 10, "%"))
  params:set_action(P("vinyl_noise"), function(v) E("looper_vinyl_noise")(v) end)

  params:add_separator(P("sep_sync"), "─── Quantization ───")
  params:add_option(P("quant_div"), "Quantize", sync.DIV_OPTS, 1)
  params:set_action(P("quant_div"), function(_)
    looper.quant_led_restart()
    if not is_initing() then on_quant_div_changed() end
    re()
  end)
  params:add_option(P("quant_feel"), "Quantize Feel", sync.FEEL_OPTS, 1)
  params:set_action(P("quant_feel"), function(_) looper.quant_led_restart(); re() end)

  params:add_separator(P("sep_trigger"), "─── Trigger ───")
  local function fired()
    return not (is_initing() or params.pset_loading)
  end
  params:add_binary(P("rec_play"), "Rec/Play", "trigger", 0)
  params:set_action(P("rec_play"), function() if fired() then looper.step() end end)
  params:add_binary(P("stop_clear"), "Stop/Clear", "trigger", 0)
  params:set_action(P("stop_clear"), function() if fired() then looper.stop_clear() end end)
end

return looper_params
