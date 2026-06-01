-- princeton scales
--
-- Note names, scale intervals, and pitch quantization for the metro and tuner.

local scales = {}

scales.NOTE_NAMES  = {"C","C#","D","D#","E","F","F#","G","G#","A","A#","B"}
scales.SCALE_NAMES = {"Chromatic","Major","Minor","Dorian","Pent Maj","Pent Min","Blues"}

local INTERVALS = {
  {0,1,2,3,4,5,6,7,8,9,10,11},
  {0,2,4,5,7,9,11},
  {0,2,3,5,7,8,10},
  {0,2,3,5,7,9,10},
  {0,2,4,7,9},
  {0,3,5,7,10},
  {0,3,5,6,7,10},
}

function scales.quantize(pitch_idx, root, scale_idx)
  if scale_idx == 1 then return pitch_idx end
  local intervals = INTERVALS[scale_idx]
  local best, best_dist = pitch_idx, 97
  for oct = 0, 7 do
    for _, iv in ipairs(intervals) do
      local p = oct * 12 + (root + iv) % 12 + 1
      if p >= 1 and p <= 96 then
        local d = math.abs(pitch_idx - p)
        if d < best_dist then best_dist = d; best = p end
      end
    end
  end
  return best
end

function scales.quantize_root(root_idx, tonic, scale_idx)
  if scale_idx == 1 then return root_idx end
  local intervals = INTERVALS[scale_idx]
  local best, best_dist = root_idx, 13
  for _, iv in ipairs(intervals) do
    local p = (tonic + iv) % 12 + 1
    local d = math.abs(root_idx - p)
    if d < best_dist then best_dist = d; best = p end
  end
  return best
end

scales.METRO_PITCH_NAMES = (function()
  local t = {}
  for oct = 0, 7 do
    for _, n in ipairs(scales.NOTE_NAMES) do
      t[#t + 1] = n .. oct
    end
  end
  return t
end)()

return scales
