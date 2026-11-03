local sync  = include("lib/sync")
local control = include("lib/control")

-- looper_params: the controls each looper built by looper.new gets in the PARAMS menu:
-- transport, level, speed, the medium and its quirks, quantize and three
-- mappable triggers. A host script can restrict the media (deps.media); the list then shows
-- only those, while the engine still gets their fixed numbers (to_engine).
local looper_params = {}

looper_params.DIR_NAMES = { "Forward", "Reverse", "Pendulum", "Random" }

local MEDIA_ALL = { "BBD", "Cassette", "CD", "Chip", "Tape", "Vinyl" }

function looper_params.setup(deps)
  local speed_steps_prev = 0
  local re                   = deps.re
  local is_initing           = deps.is_initing
  local on_quant_div_changed = deps.on_quant_div_changed
  local speed_is_owned       = deps.speed_is_owned
  local looper               = deps.looper
  local P                    = looper.pid
  local E                    = looper.cmd

  local function level_add(suffix, name)
    control.level(P(suffix), name, -2.5, function(a) E("looper_" .. suffix)(a); re() end)
  end

  -- ── Media selection ────────────────────────────────────────────
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

  if deps.embedded then params:add_group(deps.group_label or "LOOPER", 30) end
  params:add_separator(P("sep_control"), "─── Control ───")
  params:add_option(P("transport"), "Step Order", {"Rec·Play·Dub", "Rec·Dub·Play"}, 1)
  params:add_option(P("play_from"), "Play From", {"Start", "Cue"}, 1)
  params:set_action(P("play_from"), function(v) E("looper_play_from")(v - 1); re() end)
  params:add_option(P("dub_style"), "Mode", {"Overdub", "Overwrite", "Sample", "Resample"}, 1)
  params:set_action(P("dub_style"), function(v) E("looper_dub_style")(v - 1); re() end)
  params:add_option(P("direction"), "Direction", looper_params.DIR_NAMES, 1)
  params:set_action(P("direction"), function(v) E("looper_direction")(v - 1); re() end)
  level_add("dub_level", "Rec Level")
  level_add("level", "Play Level")
  level_add("fade_level", "Fade Level")
  params:add_control(P("speed"), "Speed", control.spec("amount", -100, 100, 0))
  params:set_action(P("speed"), function(v)
    -- in Steps, Speed knows only half, normal and double: any move snaps to the next stage in
    -- its direction
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
  end)
  params:add_option(P("speed_control"), "Speed Mode", {"Octaves","Free"}, 1)

  params:add_separator(P("sep_medium"), "─── Medium ───")
  params:add_option(P("medium"), "Medium", labels, medium_default)
  params:set_action(P("medium"), function(v)
    E("looper_medium")(to_engine[v]); looper.medium_changed(); re()
  end)
  params:add_control(P("imprint"), "Imprint", control.spec("amount", 0, 100, 10))
  params:set_action(P("imprint"), function(v) E("looper_imprint")(v); re() end)
  params:add_control(P("wear"), "Wear", control.spec("amount", 0, 100, 5))
  params:set_action(P("wear"), function(v) E("looper_wear")(v); re() end)
  params:add_option(P("bbd_tone"), "BBD Tone", {"Bright", "Dark"}, 1)
  params:set_action(P("bbd_tone"), function(v) E("looper_bbd_tone")(v - 1) end)
  params:add_control(P("wow_cas"), "Cassette Wow", control.spec("amount", 0, 100, 5))
  params:set_action(P("wow_cas"), function(v) E("looper_wow_cas")(v) end)
  params:add_control(P("cd_errors"), "CD Errors", control.spec("amount", 0, 100, 0))
  params:set_action(P("cd_errors"), function(v) E("looper_cd_errors")(v) end)
  params:add_control(P("chip_crush"), "Chip Crush", control.spec("amount", 0, 100, 0))
  params:set_action(P("chip_crush"), function(v) E("looper_chip_crush")(v) end)
  params:add_control(P("wow_tape"), "Tape Wow", control.spec("amount", 0, 100, 5))
  params:set_action(P("wow_tape"), function(v) E("looper_wow_tape")(v) end)
  params:add_control(P("vinyl_noise"), "Vinyl Noise", control.spec("amount", 0, 100, 10))
  params:set_action(P("vinyl_noise"), function(v) E("looper_vinyl_noise")(v) end)

  params:add_separator(P("sep_sync"), "─── Quantization ───")
  params:add_option(P("quant_div"), "Quantize Division", sync.DIV_OPTS, 1)
  params:set_action(P("quant_div"), function(_)
    looper.quant_led_restart()
    if not is_initing() then on_quant_div_changed() end
    re()
  end)
  params:add_option(P("quant_feel"), "Quantize Feel", sync.FEEL_OPTS, 1)
  params:set_action(P("quant_feel"), function(_) looper.quant_led_restart(); re() end)

  params:add_separator(P("sep_trigger"), "─── Trigger ───")
  -- trigger params also fire when init or a PSET sets them; there they should do nothing
  local function fired()
    return not (is_initing() or params.pset_loading)
  end
  params:add_binary(P("rec_play"), "Rec/Play", "trigger", 0)
  params:set_action(P("rec_play"), function() if fired() then looper.step() end end)
  params:add_binary(P("stop_clear"), "Stop/Clear", "trigger", 0)
  params:set_action(P("stop_clear"), function() if fired() then looper.stop_clear() end end)
  params:add_binary(P("undo"), "Undo", "trigger", 0)
  params:set_action(P("undo"), function() if fired() then looper.undo() end end)
  params:add_binary(P("record"), "Rec", "trigger", 0)
  params:set_action(P("record"), function() if fired() then looper.record() end end)
  params:add_binary(P("play"), "Play", "trigger", 0)
  params:set_action(P("play"), function() if fired() then looper.play() end end)
  -- Read-only mirror of the transport (0 empty, 1 rec, 2 dub, 3 play, 4 stop) for controllers.
  params:add_number(P("state"), "State", 0, 4, 0)
  params:hide(P("state"))
  params:set_save(P("state"), false)
end

return looper_params
