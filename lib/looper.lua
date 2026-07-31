-- looper: host-agnostic loop state machine, shared by princeton and media.
--
-- Host contract:
--   looper.init(deps) with
--     deps.is_clock_running() -> bool   -- is the Norns clock running?
--     deps.get_override()     -> table  -- mod-source overrides for looper_quant_div/feel ({} if none)
--     deps.is_pane_visible()  -> bool   -- is the looper pane on screen? (gates quant-LED redraws)
--   Globals the host must provide:
--     params   -- every looper_* param registered, ids identical across hosts (see LOOP_SETTINGS)
--     engine   -- looper command set: looper_on/off, loop_rec/dub/play/clear/frames/sample_retrig, imprint_on/off
--     redraw() -- the script's redraw entry point
--     clock, util (Norns built-ins), lib/sync (shared module)
local sync = include("lib/sync")

local looper = {}

looper.IDLE = 0
looper.REC  = 1
looper.DUB  = 2
looper.PLAY = 3
looper.STOP = 4
local IDLE, REC, DUB, PLAY, STOP = 0, 1, 2, 3, 4

looper.state          = IDLE
looper.frames         = 0
looper.quant_led_lit  = false

local LOOP_SR  = 48000
local LOOP_MAX = LOOP_SR * 60

local rec_start         = 0
local quant_pending     = false
local sample_retrig_val = 0
local sample_done_clock = nil
local quant_led_clock     = nil
local quant_led_off_clock = nil
local rec_auto_clock      = nil
local rec_auto_start                    -- forward decl; defined just after transition_to

local is_clock_running = function() return true end
local get_override     = function() return {} end
local is_pane_visible  = function() return false end

function looper.init(deps)
  is_clock_running = deps.is_clock_running
  get_override     = deps.get_override
  is_pane_visible  = deps.is_pane_visible
end

function looper.speed_value()
  if params:get("looper_speed_control") == 1 then
    local v = params:get("looper_speed")
    if v < 0 then return 0.5 elseif v > 0 then return 2.0 else return 1.0 end
  else
    local pct = params:get("looper_speed")
    return 2 ^ (pct / 100)
  end
end

local LOOP_SETTINGS = {
  "looper_wear", "looper_bbd_tone", "looper_wow_cas",
  "looper_cd_errors", "looper_chip_crush", "looper_wow_tape", "looper_vinyl_noise",
  "looper_level", "looper_dub_level", "looper_fade_level",
  "looper_direction", "looper_speed", "looper_play_from", "looper_dub_style"
}
local engine_active = false

local function looper_ensure_active()
  if not engine_active then
    engine.looper_on()
    for _, id in ipairs(LOOP_SETTINGS) do params:lookup_param(id):bang() end
    engine_active = true
  end
end

local function looper_deactivate()
  if engine_active then
    engine.looper_off()
    engine_active = false
  end
end

local function clear_to_idle()
  if sample_done_clock then clock.cancel(sample_done_clock); sample_done_clock = nil end
  quant_pending = false
  looper.state  = IDLE
  looper.frames = 0
  engine.imprint_off()
  engine.loop_clear()
  looper_deactivate()
  redraw()
end

local function set_engine(st)
  looper_ensure_active()
  -- The imprint synth is the recorder's source, read over a private bus, and SuperCollider
  -- does not clear private buses. So it has to exist BEFORE recording starts, or the first
  -- blocks of every take carry the last block of the previous one, written at buffer
  -- position 0 - precisely at the seam. Switching it off has to wait until after recording
  -- has stopped, for the same reason at the other edge.
  local imprinting = (st == REC or st == DUB)
  if imprinting then engine.imprint_on() end
  engine.loop_rec (st == REC  and 1 or 0)
  engine.loop_dub (st == DUB  and 1 or 0)
  engine.loop_play((st == PLAY or st == DUB) and 1 or 0)
  if not imprinting then engine.imprint_off() end
end

local function transition_to(st)
  if rec_auto_clock then clock.cancel(rec_auto_clock); rec_auto_clock = nil end
  looper.state = st
  set_engine(st)
  if st == REC then rec_auto_start() end
  redraw()
end

-- Auto-commit the initial recording when it reaches the maximum loop length: stop
-- recording and advance to Play/Dub (or Stop in Sample mode), exactly like a manual
-- K2/K3 at that instant. Without this the record buffer wraps and silently overwrites
-- a long take with itself. Cancelled by transition_to whenever REC is left first.
rec_auto_start = function()
  local speed_mult = looper.speed_value()
  local duration   = LOOP_MAX / LOOP_SR / speed_mult
  rec_auto_clock = clock.run(function()
    clock.sleep(duration)
    rec_auto_clock = nil
    if looper.state == REC then
      looper.frames = LOOP_MAX
      engine.loop_frames(looper.frames)
      if params:get("looper_dub_style") == 3 then
        transition_to(STOP)
      else
        local nxt = params:get("looper_transport") == 2 and DUB or PLAY
        transition_to(nxt)
      end
    end
  end)
end

local function sample_oneshot_start()
  if sample_done_clock then clock.cancel(sample_done_clock) end
  local speed_mult = looper.speed_value()
  local passes     = params:get("looper_direction") == 3 and 2 or 1
  local duration   = looper.frames / LOOP_SR / speed_mult * passes
  sample_done_clock = clock.run(function()
    clock.sleep(duration)
    if looper.state == PLAY and params:get("looper_dub_style") == 3 then
      transition_to(STOP)
    end
    sample_done_clock = nil
  end)
end

local function quantize_then(fn)
  local override = get_override()
  local div_opt = override["looper_quant_div"] or params:get("looper_quant_div")
  if not is_clock_running() or div_opt <= 1 then fn(); return end
  local feel_opt = override["looper_quant_feel"] or params:get("looper_quant_feel")
  local beats = sync.DIV_BEATS[div_opt] * sync.FEEL_MULT[feel_opt]
  clock.run(function()
    clock.sync(beats)
    fn()
  end)
end

local function quant_led_pulse_now()
  looper.quant_led_lit = true
  if quant_led_off_clock then clock.cancel(quant_led_off_clock); quant_led_off_clock = nil end
  if is_pane_visible() then redraw() end
  quant_led_off_clock = clock.run(function()
    clock.sleep(0.08)
    looper.quant_led_lit = false
    quant_led_off_clock = nil
    if is_pane_visible() then redraw() end
  end)
end

function looper.quant_led_restart()
  if quant_led_clock     then clock.cancel(quant_led_clock);     quant_led_clock     = nil end
  if quant_led_off_clock then clock.cancel(quant_led_off_clock); quant_led_off_clock = nil end
  looper.quant_led_lit = false
  if not is_clock_running() then return end
  local override = get_override()
  local div_opt = override["looper_quant_div"] or params:get("looper_quant_div")
  if div_opt <= 1 then return end
  local feel_opt = override["looper_quant_feel"] or params:get("looper_quant_feel")
  local beats = sync.DIV_BEATS[div_opt] * sync.FEEL_MULT[feel_opt]
  quant_led_clock = clock.run(function()
    while true do
      clock.sync(beats)
      quant_led_pulse_now()
    end
  end)
end

function looper.step()
  if looper.state == IDLE then
    if quant_pending then return end
    quant_pending = true
    quantize_then(function()
      if not quant_pending then return end
      quant_pending = false
      engine.loop_frames(LOOP_MAX)
      rec_start = util.time()
      transition_to(REC)
    end)
    redraw()
  elseif looper.state == REC then
    if quant_pending then return end
    quant_pending = true
    quantize_then(function()
      quant_pending = false
      local elapsed    = util.time() - rec_start
      local speed_mult = looper.speed_value()
      looper.frames = math.max(math.min(math.floor(elapsed * LOOP_SR * speed_mult), LOOP_MAX), 2)
      engine.loop_frames(looper.frames)
      if params:get("looper_dub_style") == 3 then
        transition_to(STOP)
      else
        local nxt = params:get("looper_transport") == 2 and DUB or PLAY
        transition_to(nxt)
      end
    end)
  elseif looper.state == PLAY then
    if params:get("looper_dub_style") == 3 then
      sample_retrig_val = 1 - sample_retrig_val
      engine.loop_sample_retrig(sample_retrig_val)
      sample_oneshot_start()
      redraw()
    else
      transition_to(DUB)
    end
  elseif looper.state == DUB then
    quantize_then(function()
      transition_to(PLAY)
    end)
  elseif looper.state == STOP then
    if params:get("looper_dub_style") == 3 then
      looper.state = PLAY
      set_engine(PLAY)
      if params:get("looper_play_from") == 2 then
        sample_retrig_val = 1 - sample_retrig_val
        engine.loop_sample_retrig(sample_retrig_val)
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

function looper.stop_clear()
  if looper.state == IDLE then
    quant_pending = false
    return
  elseif looper.state == REC then
    clear_to_idle()
  elseif looper.state == DUB then
    quantize_then(function()
      transition_to(STOP)
    end)
  elseif looper.state == STOP then
    clear_to_idle()
  elseif looper.state ~= IDLE then
    if sample_done_clock then clock.cancel(sample_done_clock); sample_done_clock = nil end
    quantize_then(function()
      transition_to(STOP)
    end)
  end
end

function looper.force_clear()
  if looper.state == IDLE then return end
  clear_to_idle()
end

function looper.medium_changed()
  if looper.state == IDLE then return end
  clear_to_idle()
end

return looper
