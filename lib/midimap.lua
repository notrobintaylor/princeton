-- midimap engages a MIDI control only once it has caught the parameter's value, so a knob parked
-- elsewhere can't make it jump. Whoever turns holds focus, and a second control takes over only
-- after the first has rested a quarter second.
local midimap = {
  pickup   = true,
  on_touch = nil,
}

local HOLD    = 0.25
local CATCH   = 2 / 127

local orig
local owner, owner_t = nil, 0
local picked, last_in, expect = {}, {}, {}

local function norm_value(id)
  local p = params:lookup_param(id)
  local t = params:t(id)
  if t == params.tCONTROL or t == params.tTAPER then return params:get_raw(id) end
  if t == params.tOPTION then return (params:get(id) - 1) / math.max(1, #p.options - 1) end
  if t == params.tNUMBER then return (params:get(id) - p.min) / math.max(1, p.max - p.min) end
  return nil
end

local function incoming(d, v)
  local s = util.clamp(v, d.in_lo, d.in_hi)
  s = util.linlin(d.in_lo, d.in_hi, d.out_lo, d.out_hi, s)
  return util.linlin(d.out_lo, d.out_hi, 0, 1, s)
end

local function touch(id)
  local now  = util.time()
  local idle = now - owner_t > HOLD
  if midimap.on_touch and (owner == id or owner == nil or idle) then
    if owner ~= id or idle then midimap.on_touch(id) end
    owner = id
  end
  if owner == id then owner_t = now end
end

local function caught(id, d, v)
  local cur = norm_value(id)
  if not midimap.pickup or d.accum or cur == nil then return true end
  if expect[id] and math.abs(expect[id] - cur) > CATCH then picked[id] = false end
  local new = incoming(d, v)
  if not picked[id] then
    local prev = last_in[id]
    last_in[id] = new
    if math.abs(new - cur) <= CATCH or (prev and (prev - cur) * (new - cur) <= 0) then
      picked[id] = true
    else
      return false
    end
  end
  return true
end

local function handler(data, dev)
  local ch, cc, v = data[1] - 175, data[2], data[3]
  local pm = norns.pmap
  if ch > 0 and ch < 17 and not (_menu and _menu.mode) and pm.rev[dev] and pm.rev[dev][ch] then
    local id = pm.rev[dev][ch][cc]
    local d  = id and pm.data[id]
    if d then
      if not caught(id, d, v) then return end
      touch(id)
      orig(data, dev)
      expect[id] = norm_value(id)
      return
    end
  end
  orig(data, dev)
end

function midimap.init()
  if orig then return end
  orig = norns.menu_midi_event
  norns.menu_midi_event = handler
end

function midimap.cleanup()
  if orig then norns.menu_midi_event = orig end
  orig = nil
end

return midimap
