local sync           = include("lib/sync")
local modtarget      = include("lib/modtarget")
local sprites_looper = include("lib/sprites_looper")

local seq = {}

local MED  = 5
local FULL = 15

seq.NUM       = 2
seq.MAX_STEPS = 16

local NUM_SEQS  = seq.NUM
local MAX_STEPS = seq.MAX_STEPS

seq.mod = {
  rate        = {},
  rate_slewed = {},
  steps       = {},
  rate_slew   = {},
  sync_div    = {},
  sync_feel   = {},
}

seq.state                = {}
seq.clocks               = {}
seq.last_global          = {}
seq.target_device_filter = {}
seq.target_param_filter  = {}

local TARGET_PARAMS, DEVICE_NAMES, DEVICE_PARAMS, TARGET_DEVICE_OF
local lfo, is_clock_running, is_initing, on_target_change
local is_pane_visible, redraw_pane
local binding

local OWN_PREFIX = "seq_"
local function owner_tag(idx) return OWN_PREFIX .. idx end

function seq.is_sync_active(idx) return params:get("seq"..idx.."_sync_div") > 1 end
function seq.is_enabled(idx)     return params:get("seq"..idx.."_enable")   == 2 end

-- ── Strip ────────────────────────────────────────────────────
seq.STRIP = {
  {name="Steps",    suf="_steps",  typ="ctrl", step=1, fmt=function(v,i) return tostring(math.floor(v)) end},
}
for k = 1, MAX_STEPS do
  local kk = k
  seq.STRIP[#seq.STRIP+1] = {name="Step "..kk, suf="_step_"..kk, typ="ctrl", step=1,
    fmt=function(v,i) return string.format("%d%%", math.floor(v)) end,
    visible_when=function(idx) return params:get("seq"..idx.."_steps") >= kk end}
end
do
  local after = {
    {name="Rate",      suf="_rate",      typ="ctrl", step=0.1, fmt=function(v,i) return string.format("%.1fHz",v) end,
     visible_when=function(idx) return not seq.is_sync_active(idx) end},
    {name="Sync",      suf="_sync_div",  typ="opt",  nmax=8, fmt=function(v,i) return sync.DIV_OPTS[v] end},
    {name="Sync Feel", suf="_sync_feel", typ="opt",  nmax=3, fmt=function(v,i) return sync.FEEL_OPTS[v] end,
     visible_when=function(idx) return seq.is_sync_active(idx) end},
    {name="Rate Slew", suf="_rate_slew", typ="ctrl", step=0.1, fmt=function(v,i) return string.format("%.1fs",v) end},
    {name="Device",    suf="_target_device", typ="opt", nmax_fn=function(i) return #(seq.target_device_filter[i] or {}) end,
     fmt=function(v,i)
       local dmap = seq.target_device_filter[i]
       local di   = dmap and dmap[v]
       if di == 0 then return "-" end
       return (di and DEVICE_NAMES[di]) or "?"
     end},
    {name="Parameter", suf="_target_param", typ="opt", nmax_fn=function(i) return #(seq.target_param_filter[i] or {}) end,
     fmt=function(v,i)
       local pmap = seq.target_param_filter[i]
       local gi   = pmap and pmap[v]
       if gi and gi > 1 and TARGET_PARAMS[gi] then return TARGET_PARAMS[gi].label:match(": (.+)$") or TARGET_PARAMS[gi].label end
       return "-"
     end},
  }
  for _, e in ipairs(after) do seq.STRIP[#seq.STRIP+1] = e end
end

function seq.strip_visible(idx, strip_i)
  local entry = seq.STRIP[strip_i]
  return entry and (not entry.visible_when or entry.visible_when(idx))
end

function seq.strip_resolve(idx, current)
  if seq.strip_visible(idx, current) then return current end
  for i = current + 1, #seq.STRIP do
    if seq.strip_visible(idx, i) then return i end
  end
  for i = current - 1, 1, -1 do
    if seq.strip_visible(idx, i) then return i end
  end
  return current
end

function seq.strip_advance(idx, current, d)
  if d == 0 then return current end
  local step = d > 0 and 1 or -1
  local next_idx = current + step
  while next_idx >= 1 and next_idx <= #seq.STRIP do
    if seq.strip_visible(idx, next_idx) then return next_idx end
    next_idx = next_idx + step
  end
  return current
end

-- ── Modulation ───────────────────────────────────────────────
local function seq_g(field, idx)
  return seq.mod[field][idx] or params:get("seq"..idx.."_"..field)
end

local function target_visible(target_id)
  if target_id == "tremolo_sync_div" or target_id == "tremolo_sync_feel" then return params:get("tremolo_sync_div") > 1 end
  if target_id == "warp_sync_div"    or target_id == "warp_sync_feel"    then return params:get("warp_sync_div")    > 1 end
  if target_id == "repeat_sync_div"  or target_id == "repeat_sync_feel"  then return params:get("repeat_sync_div")  > 1 end
  if target_id == "looper_quant_div" or target_id == "looper_quant_feel" then return params:get("looper_quant_div") > 1 end
  local n, suf = target_id:match("^lfo(%d+)_(.+)$")
  if n then
    local target_lfo    = tonumber(n)
    local target_wf     = params:get("lfo"..target_lfo.."_waveform")
    local target_synced = params:get("lfo"..target_lfo.."_sync_div") > 1
    if suf == "rate"      then return not target_synced end
    if suf == "phase" or suf == "rate_slew"  then return target_wf ~= 6 end
    if suf == "steps" or suf == "stability"  then return target_wf == 6 end
    if suf == "sync_div" or suf == "sync_feel" then return target_synced end
  end
  local ns, sufs = target_id:match("^seq(%d+)_(.+)$")
  if ns then
    local target_synced = params:get("seq"..tonumber(ns).."_sync_div") > 1
    if sufs == "rate"     then return not target_synced end
    if sufs == "sync_div" or sufs == "sync_feel" then return target_synced end
  end
  return true
end

function seq.rebuild_target_param_dropdown(idx, dev_idx)
  modtarget.rebuild_param(binding, idx, dev_idx)
end

function seq.rebuild_target_dropdown(idx)
  modtarget.rebuild(binding, idx)
end

function seq.rebuild_all_target_dropdowns()
  modtarget.rebuild_all(binding)
end

local function apply_to_target(idx)
  if is_initing() then return end
  if params:get("seq"..idx.."_enable") ~= 2 then return end
  local target_idx = seq.last_global[idx] or 1
  if target_idx == 1 then return end
  local t = TARGET_PARAMS[target_idx]
  if not t or not t.id or not t.send then return end
  if lfo.target_owner[t.id] ~= owner_tag(idx) then return end

  local base = lfo.target_base[t.id]
  if base == nil then base = params:get(t.id) end

  local s  = seq.state[idx]
  local sv = params:get("seq"..idx.."_step_"..s.step_pos) / 100
  if sv < -1 then sv = -1 elseif sv > 1 then sv = 1 end

  -- 0% = base (no modulation), +100% = target max, -100% = target min
  local off
  if sv >= 0 then off = sv * (t.mx - base)
  else            off = sv * (base - t.mn)
  end

  local val = util.clamp(base + off, t.mn, t.mx)
  val = math.floor(val / t.st + 0.5) * t.st
  t.send(val)
end

function seq.set_target(idx, new_global_idx)
  modtarget.set_target(binding, idx, new_global_idx)
  seq.start_clock(idx)
end

function seq.refresh_dropdowns_for_device(dev_name)
  for other = 1, NUM_SEQS do
    local g = seq.last_global[other] or 1
    if g > 1 then
      local cur_dev = TARGET_DEVICE_OF[g]
      if cur_dev and DEVICE_NAMES[cur_dev] == dev_name then
        seq.rebuild_target_param_dropdown(other, cur_dev)
        local f = seq.target_param_filter[other]
        local present = false
        if f then
          for _, gi in ipairs(f) do if gi == g then present = true; break end end
        end
        if not present then seq.set_target(other, (f and f[1]) or 1) end
      end
    end
  end
end

function seq.start_clock(idx)
  if seq.clocks[idx] then clock.cancel(seq.clocks[idx]); seq.clocks[idx] = nil end
  if is_initing() then return end
  if params:get("seq"..idx.."_enable") ~= 2 then return end
  local target_idx = seq.last_global[idx] or 1
  if target_idx == 1 then return end
  local t = TARGET_PARAMS[target_idx]
  if not t or not t.id or lfo.target_owner[t.id] ~= owner_tag(idx) then return end

  seq.state[idx].step_pos = 1
  seq.mod.rate_slewed[idx] = nil
  apply_to_target(idx)

  seq.clocks[idx] = clock.run(function()
    while true do
      local cur_target = seq.last_global[idx] or 1
      if cur_target == 1 then break end

      local sync_div_opt = seq_g("sync_div", idx)
      if sync_div_opt > 1 and is_clock_running() then
        local beats = sync.DIV_BEATS[sync_div_opt] * sync.FEEL_MULT[seq_g("sync_feel", idx)]
        clock.sync(beats)
      else
        local target_rate = seq.mod.rate[idx] ~= nil and seq.mod.rate[idx] or params:get("seq"..idx.."_rate")
        local slew = seq_g("rate_slew", idx)
        local rate
        if slew > 0 and seq.mod.rate[idx] ~= nil then
          if seq.mod.rate_slewed[idx] == nil then seq.mod.rate_slewed[idx] = target_rate end
          local dt_step = 1 / math.max(0.05, seq.mod.rate_slewed[idx])
          local coeff = math.min(1, dt_step / slew)
          seq.mod.rate_slewed[idx] = seq.mod.rate_slewed[idx] + (target_rate - seq.mod.rate_slewed[idx]) * coeff
          rate = seq.mod.rate_slewed[idx]
        else
          seq.mod.rate_slewed[idx] = nil
          rate = target_rate
        end
        clock.sleep(1 / math.max(0.05, rate))
      end

      local s = seq.state[idx]
      local nsteps = seq_g("steps", idx)
      if nsteps < 1 then nsteps = 1 end
      s.step_pos = (s.step_pos % nsteps) + 1
      apply_to_target(idx)
      if is_pane_visible and is_pane_visible() and redraw_pane then redraw_pane() end
    end
    seq.clocks[idx] = nil
  end)
end

function seq.randomize(idx)
  local n = params:get("seq"..idx.."_steps")
  for k = 1, n do
    params:set("seq"..idx.."_step_"..k, math.random(-100, 100))
  end
  apply_to_target(idx)
end

-- ── Draw (looper-style knob grid: playhead + edit cursor) ────
-- Reuse the looper pane's knob sprite (5x5), normalised to a stamp.
local KNOB = (function()
  local raw = sprites_looper.LOOPER_PTS.knob[1]
  local minx, miny = 999, 999
  for _, q in ipairs(raw) do
    if q[1] < minx then minx = q[1] end
    if q[2] < miny then miny = q[2] end
  end
  local st = {}
  for _, q in ipairs(raw) do st[#st + 1] = { q[1] - minx, q[2] - miny } end
  return st
end)()

local H_PITCH, V_PITCH = 8, 11

local function blit_knob(kx, ky, lv)
  screen.level(lv)
  for _, q in ipairs(KNOB) do screen.rect(kx + q[1], ky + q[2], 1, 1) end
  screen.fill()
end

function seq.draw_half(ox, oy, idx, focused, sel_step)
  local enabled = seq.is_enabled(idx)
  local n       = params:get("seq"..idx.."_steps")
  local cur     = seq.state[idx] and seq.state[idx].step_pos or 1

  -- fixed 4x4 layout: knob positions never move; unused steps (k > n) are
  -- simply not drawn, so adding/removing steps keeps every knob in place.
  local cols   = 4
  local grid_w = 3 * H_PITCH + 5
  local grid_h = 3 * V_PITCH + 5
  local x0     = ox + math.floor((33 - grid_w) / 2)
  local y0     = oy + math.floor((50 - grid_h) / 2) + 2

  for k = 1, n do
    local kx = x0 + ((k - 1) % cols) * H_PITCH
    local ky = y0 + math.floor((k - 1) / cols) * V_PITCH
    blit_knob(kx, ky, (enabled and k == cur) and FULL or MED)
    if sel_step == k then
      screen.level(FULL)
      screen.rect(kx - 1, ky - 1, 1, 1); screen.fill()
    end
  end

  screen.font_size(8); screen.font_face(0)
  screen.level(enabled and FULL or MED)
  screen.move(ox + 16, oy + 56); screen.text_center("Walk " .. idx)
end

function seq.init(deps)
  TARGET_PARAMS    = deps.TARGET_PARAMS
  DEVICE_NAMES     = deps.DEVICE_NAMES
  DEVICE_PARAMS    = deps.DEVICE_PARAMS
  TARGET_DEVICE_OF = deps.TARGET_DEVICE_OF
  lfo              = deps.lfo
  is_clock_running = deps.is_clock_running
  is_initing       = deps.is_initing
  on_target_change = deps.on_target_change
  is_pane_visible  = deps.is_pane_visible
  redraw_pane      = deps.redraw_pane

  for i = 1, NUM_SEQS do
    seq.state[i] = { step_pos = 1 }
    seq.last_global[i] = 1
    seq.target_device_filter[i] = {}
    for di = 1, #DEVICE_NAMES do seq.target_device_filter[i][di] = di end
    seq.target_param_filter[i] = {}
    if DEVICE_PARAMS[1] then
      for j, e in ipairs(DEVICE_PARAMS[1]) do seq.target_param_filter[i][j] = e.global_idx end
    end
  end

  binding = {
    num              = NUM_SEQS,
    none_option      = true,
    prefix           = function(i) return "seq" .. i end,
    owner            = lfo.target_owner,
    tag              = owner_tag,
    devices          = DEVICE_NAMES,
    device_params    = DEVICE_PARAMS,
    target_device_of = TARGET_DEVICE_OF,
    targets          = TARGET_PARAMS,
    label_of         = function(e) return e.short end,
    device_filter    = seq.target_device_filter,
    param_filter     = seq.target_param_filter,
    last_global      = seq.last_global,
    visible          = function(g) local t = TARGET_PARAMS[g]; return t ~= nil and target_visible(t.id) end,
    device_excluded  = function(idx, di) return DEVICE_NAMES[di] == "Walk " .. idx end,
    enabled          = seq.is_enabled,
    on_claim         = function(g)
      local id = TARGET_PARAMS[g].id
      lfo.target_base[id] = params:get(id)
      lfo.mark_modulated(id)
    end,
    on_release       = function(g)
      local t = TARGET_PARAMS[g]
      lfo.unmark_modulated(t.id)
      local base = lfo.target_base[t.id]
      if base == nil then base = params:get(t.id) end
      if t.send then t.send(base) end
    end,
    on_rebuilt       = function()
      if on_target_change then on_target_change() end
      if _menu and _menu.rebuild_params then _menu.rebuild_params() end
    end,
  }
end

return seq
