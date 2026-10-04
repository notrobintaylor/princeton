local sync = include("lib/sync")

local looper = {}

looper.IDLE = 0
looper.REC  = 1
looper.DUB  = 2
looper.PLAY = 3
looper.STOP = 4
local IDLE, REC, DUB, PLAY, STOP = 0, 1, 2, 3, 4

local LOOP_SR  = 48000
local LOOP_MAX = LOOP_SR * 60

local SETTINGS = {
  "wear", "bbd_tone", "wow_cas",
  "cd_errors", "chip_crush", "wow_tape", "vinyl_noise",
  "level", "dub_level", "fade_level",
  "direction", "speed", "play_from", "dub_style"
}

local function cname(base, idx)
  if idx == 1 then return base end
  local head, rest = base:match("^([^_]+)(_.*)$")
  return head .. idx .. rest
end

function looper.new(deps, into)
  local L = into or {}
  local idx = deps.idx or 1

  L.IDLE, L.REC, L.DUB, L.PLAY, L.STOP = IDLE, REC, DUB, PLAY, STOP
  L.state         = IDLE
  L.frames        = 0
  L.quant_led_lit = false
  L.idx           = idx

  local prefix = (idx == 1) and "looper_" or ("looper" .. idx .. "_")
  local function P(name) return prefix .. name end
  local function E(base) return engine[cname(base, idx)] end

  L.pid = P
  L.cmd = E

  local is_clock_running = deps.is_clock_running or function() return true end
  local get_override     = deps.get_override     or function() return {} end
  local is_pane_visible  = deps.is_pane_visible  or function() return false end

  local rec_start         = 0
  local quant_pending     = false
  local epoch             = 0
  local following         = false
  local sample_retrig_val = 0
  local sample_gen   = 0
  local led_gen      = 0
  local led_off_gen  = 0
  local rec_auto_gen = 0
  local rec_auto_start
  local engine_active = false

  L.on_transition = nil
  local function notify(st)
    if L.on_transition and not following then L.on_transition(st) end
  end

  function L.speed_value()
    if params:get(P("speed_control")) == 1 then
      local v = params:get(P("speed"))
      if v < 0 then return 0.5 elseif v > 0 then return 2.0 else return 1.0 end
    else
      local pct = params:get(P("speed"))
      return 2 ^ (pct / 100)
    end
  end

  local function ensure_active()
    if not engine_active then
      E("looper_on")()
      for _, name in ipairs(SETTINGS) do params:lookup_param(P(name)):bang() end
      engine_active = true
    end
  end

  local function deactivate()
    if engine_active then
      E("looper_off")()
      engine_active = false
    end
  end

  local function clear_to_idle()
    sample_gen = sample_gen + 1
    epoch = epoch + 1
    quant_pending = false
    L.state  = IDLE
    L.frames = 0
    E("imprint_off")()
    E("loop_clear")()
    deactivate()
    redraw()
    notify(IDLE)
  end

  local function set_engine(st)
    ensure_active()
    local imprinting = (st == REC or st == DUB)
    if imprinting then E("imprint_on")() end
    E("loop_rec") (st == REC  and 1 or 0)
    E("loop_dub") (st == DUB  and 1 or 0)
    E("loop_play")((st == PLAY or st == DUB) and 1 or 0)
    if not imprinting then E("imprint_off")() end
  end

  local function commit_frames()
    local elapsed = util.time() - rec_start
    L.frames = math.max(math.min(math.floor(elapsed * LOOP_SR * L.speed_value()), LOOP_MAX), 2)
    E("loop_frames")(L.frames)
  end

  local function transition_to(st)
    rec_auto_gen = rec_auto_gen + 1
    L.state = st
    if st == REC then notify("prepare") end
    set_engine(st)
    notify(st)
    if st == REC then rec_auto_start() end
    redraw()
  end

  rec_auto_start = function()
    local duration = LOOP_MAX / LOOP_SR / L.speed_value()
    rec_auto_gen = rec_auto_gen + 1
    local my = rec_auto_gen
    clock.run(function()
      clock.sleep(duration)
      if my ~= rec_auto_gen then return end
      if L.state == REC then
        L.frames = LOOP_MAX
        E("loop_frames")(L.frames)
        if params:get(P("dub_style")) == 3 then
          transition_to(STOP)
        else
          transition_to(params:get(P("transport")) == 2 and DUB or PLAY)
        end
      end
    end)
  end

  local function sample_oneshot_start()
    sample_gen = sample_gen + 1
    local my = sample_gen
    local passes   = params:get(P("direction")) == 3 and 2 or 1
    local duration = L.frames / LOOP_SR / L.speed_value() * passes
    clock.run(function()
      clock.sleep(duration)
      if my ~= sample_gen then return end
      if L.state == PLAY and params:get(P("dub_style")) == 3 then
        transition_to(STOP)
      end
    end)
  end

  local function quant_beats()
    local override = get_override()
    local div_opt  = override[P("quant_div")] or params:get(P("quant_div"))
    if div_opt <= 1 then return nil end
    local feel_opt = override[P("quant_feel")] or params:get(P("quant_feel"))
    return sync.DIV_BEATS[div_opt] * sync.FEEL_MULT[feel_opt]
  end

  local function quantize_then(fn)
    local beats = is_clock_running() and quant_beats() or nil
    if not beats then fn(); return end
    local my, done = epoch, false
    local function once()
      if done then return end
      done = true
      if my ~= epoch then return end
      fn()
    end
    local wait = beats * 60 / clock.get_tempo()
    clock.run(function() clock.sync(beats); once() end)
    clock.run(function() clock.sleep(wait + math.max(1.0, wait * 0.25)); once() end)
  end

  local function quant_led_pulse_now()
    L.quant_led_lit = true
    led_off_gen = led_off_gen + 1
    local my = led_off_gen
    if is_pane_visible() then redraw() end
    clock.run(function()
      clock.sleep(0.08)
      if my ~= led_off_gen then return end
      L.quant_led_lit = false
      if is_pane_visible() then redraw() end
    end)
  end

  function L.quant_led_restart()
    led_gen     = led_gen + 1
    led_off_gen = led_off_gen + 1
    L.quant_led_lit = false
    if not is_clock_running() then return end
    local beats = quant_beats()
    if not beats then return end
    local my = led_gen
    clock.run(function()
      while true do
        clock.sync(beats)
        if my ~= led_gen then return end
        quant_led_pulse_now()
      end
    end)
  end

  function L.step()
    if L.state == IDLE then
      if quant_pending then return end
      quant_pending = true
      quantize_then(function()
        quant_pending = false
        E("loop_frames")(LOOP_MAX)
        rec_start = util.time()
        transition_to(REC)
      end)
      redraw()
    elseif L.state == REC then
      if quant_pending then return end
      quant_pending = true
      quantize_then(function()
        quant_pending = false
        commit_frames()
        if params:get(P("dub_style")) == 3 then
          transition_to(STOP)
        else
          transition_to(params:get(P("transport")) == 2 and DUB or PLAY)
        end
      end)
    elseif L.state == PLAY then
      if params:get(P("dub_style")) == 3 then
        sample_retrig_val = 1 - sample_retrig_val
        E("loop_sample_retrig")(sample_retrig_val)
        sample_oneshot_start()
        redraw()
      else
        transition_to(DUB)
      end
    elseif L.state == DUB then
      quantize_then(function()
        transition_to(PLAY)
      end)
    elseif L.state == STOP then
      if params:get(P("dub_style")) == 3 then
        L.state = PLAY
        set_engine(PLAY)
        if params:get(P("play_from")) == 2 then
          sample_retrig_val = 1 - sample_retrig_val
          E("loop_sample_retrig")(sample_retrig_val)
        end
        sample_oneshot_start()
        redraw()
      else
        if quant_pending then return end
        quant_pending = true
        quantize_then(function()
          quant_pending = false
          transition_to(PLAY)
        end)
        redraw()
      end
    end
  end

  function L.stop_clear()
    if L.state == IDLE then
      epoch = epoch + 1
      quant_pending = false
      return
    elseif L.state == REC then
      clear_to_idle()
    elseif L.state == DUB then
      quantize_then(function()
        transition_to(STOP)
      end)
    elseif L.state == STOP then
      clear_to_idle()
    elseif L.state ~= IDLE then
      sample_gen = sample_gen + 1
      quantize_then(function()
        transition_to(STOP)
      end)
    end
  end

  function L.follow(st)
    if st == "prepare" then ensure_active() return end
    if st == L.state then return end
    following = true
    if st == IDLE then
      if L.state ~= IDLE then clear_to_idle() end
    elseif st == REC then
      if L.state ~= IDLE then clear_to_idle() end
      E("loop_frames")(LOOP_MAX)
      rec_start = util.time()
      transition_to(REC)
    else
      if L.state == REC then commit_frames() end
      if L.frames > 0 then transition_to(st) end
    end
    following = false
  end

  function L.force_clear()
    if L.state == IDLE then return end
    clear_to_idle()
  end

  function L.medium_changed()
    if L.state == IDLE then return end
    clear_to_idle()
  end

  return L
end

function looper.init(deps)
  return looper.new(deps, looper)
end

return looper
