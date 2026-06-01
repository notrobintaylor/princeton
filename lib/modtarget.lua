-- princeton modtarget
--
-- Shared modulation-target ownership + filtered target dropdowns for every
-- modulator (LFO, Sense/env, Trigger). One implementation guarantees the guard
-- (a target can be owned by only one modulator) behaves identically everywhere.
--
-- Each modulator hands in a `binding` describing its target space and owner
-- table; modtarget owns the filtered device/param dropdowns, the rebuild logic
-- and set_target (claim / release). Per-modulator specifics come from binding
-- callbacks. Bindings whose targets live in the SAME owner table (LFO + Sense)
-- are rebuilt together via each other's `on_rebuilt` hook.
--
-- binding fields:
--   num                      number of instances
--   prefix(idx) -> string    param prefix, e.g. "env"..idx
--   owner                    owner table (shared or own), keyed by target id
--   tag(idx)                 owner tag, unique across a shared owner table
--   devices                  device-name list (filtered dropdown source)
--   device_params            dev -> array of { global_idx=, ... }
--   target_device_of         global -> dev index
--   targets                  global -> { id=, ... }
--   label_of(entry) -> str   param-dropdown label for a device_params entry
--   device_filter            per-idx filtered map table (modtarget writes)
--   param_filter             per-idx filtered map table (modtarget writes)
--   last_global              per-idx current global target
--   visible(global) -> bool  target visibility predicate
--   device_excluded(idx, di) -> bool  optional, hide device di for instance idx
--   enabled(idx) -> bool     instance enabled?
--   on_claim(global, idx)    optional, after claiming ownership
--   on_release(global, idx)  optional, after releasing ownership
--   on_rebuilt()             optional, after a set_target rebuild (cross + menu)

local modtarget = {}

local function owner_key(b, g)
  local t = b.targets[g]
  return t and t.id
end

-- owner_ok: target is free or already owned by this instance.
local function owner_ok(b, idx, g)
  local key   = owner_key(b, g)
  local owner = key and b.owner[key]
  return owner == nil or owner == b.tag(idx)
end

-- available: selectable in the PARAM dropdown (free AND mode-visible).
-- The DEVICE dropdown only requires a free target (owner_ok), matching the
-- original LFO/Sense behaviour: a device with a free-but-hidden param still
-- shows (its param dropdown then resolves to "-").
local function available(b, idx, g)
  return b.visible(g) and owner_ok(b, idx, g)
end

function modtarget.rebuild_param(b, idx, dev_idx)
  local p = params:lookup_param(b.prefix(idx) .. "_target_param")
  if not p then return end
  local opts, map = {}, {}
  local dps = dev_idx and b.device_params[dev_idx]
  if dps then
    for _, entry in ipairs(dps) do
      if available(b, idx, entry.global_idx) then
        opts[#opts + 1] = b.label_of(entry)
        map[#map + 1]   = entry.global_idx
      end
    end
  end
  if #opts == 0 then opts = {"-"}; map = {1} end
  b.param_filter[idx] = map
  p.options = opts
  p.count   = #opts
  local cur, nf = b.last_global[idx] or 1, 1
  for fi, gi in ipairs(map) do if gi == cur then nf = fi; break end end
  p.selected = nf
end

function modtarget.rebuild_device(b, idx)
  local p = params:lookup_param(b.prefix(idx) .. "_target_device")
  if not p then return end
  local opts, map = {}, {}
  for di = 1, #b.devices do
    if not (b.device_excluded and b.device_excluded(idx, di)) then
      local has_available = false
      local dps = b.device_params[di]
      if dps then
        for _, entry in ipairs(dps) do
          if owner_ok(b, idx, entry.global_idx) then has_available = true; break end
        end
      end
      if has_available then
        opts[#opts + 1] = b.devices[di]
        map[#map + 1]   = di
      end
    end
  end
  if #opts == 0 then opts = {"-"}; map = {1} end
  b.device_filter[idx] = map
  p.options = opts
  p.count   = #opts
  local cur_dev, nf = b.target_device_of[b.last_global[idx] or 1] or 1, 1
  for fi, di in ipairs(map) do if di == cur_dev then nf = fi; break end end
  p.selected = nf
end

function modtarget.rebuild(b, idx)
  modtarget.rebuild_device(b, idx)
  local cur_dev = b.target_device_of[b.last_global[idx] or 1]
  if not cur_dev then
    local df = params:get(b.prefix(idx) .. "_target_device")
    cur_dev  = (b.device_filter[idx] and b.device_filter[idx][df]) or 1
  end
  modtarget.rebuild_param(b, idx, cur_dev)
end

function modtarget.rebuild_all(b)
  for i = 1, b.num do modtarget.rebuild(b, i) end
end

function modtarget.set_target(b, idx, new_global)
  local prev = b.last_global[idx] or 1
  local tag  = b.tag(idx)

  if prev > 1 then
    local key = owner_key(b, prev)
    if key and b.owner[key] == tag then
      b.owner[key] = nil
      if b.on_release then b.on_release(prev, idx) end
    end
  end

  b.last_global[idx] = new_global

  -- Claim on SELECTION, not on enable: a target is reserved (and marked "(M)")
  -- as soon as a modulator points at it, so Sense and LFO can never select the
  -- same target. Whether the modulator is actually enabled is a separate gate,
  -- handled in each modulator's apply path.
  if new_global > 1 then
    local key = owner_key(b, new_global)
    if key and not b.owner[key] then
      b.owner[key] = tag
      if b.on_claim then b.on_claim(new_global, idx) end
    end
  end

  modtarget.rebuild_all(b)
  if b.on_rebuilt then b.on_rebuilt() end
end

return modtarget
