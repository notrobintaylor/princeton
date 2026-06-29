local scales = {}

scales.NOTE_NAMES  = {"C","C#","D","D#","E","F","F#","G","G#","A","A#","B"}
scales.SCALE_NAMES = {"Off","Chromatic","Major","Minor","Dorian","Pent Maj","Pent Min","Blues"}

local INTERVALS = {
  {0},
  {0,1,2,3,4,5,6,7,8,9,10,11},
  {0,2,4,5,7,9,11},
  {0,2,3,5,7,8,10},
  {0,2,3,5,7,9,10},
  {0,2,4,7,9},
  {0,3,5,7,10},
  {0,3,5,6,7,10},
}

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

function scales.degree_semitones(scale_idx, degree)
  local iv = INTERVALS[scale_idx]
  local n  = #iv
  local d0 = degree - 1
  return math.floor(d0 / n) * 12 + iv[d0 % n + 1]
end

function scales.chord_tones(scale_idx, degree, kind)
  local r = scales.degree_semitones(scale_idx, degree)
  if kind == 2 then return {r, r + 12} end
  local third, fifth
  if scale_idx >= 2 then
    third = scales.degree_semitones(scale_idx, degree + 2)
    fifth = scales.degree_semitones(scale_idx, degree + 4)
  else
    third, fifth = r + 4, r + 7
  end
  if kind == 3 then return {r, fifth} end
  if kind == 4 then return {r, third, fifth} end
  return {r}
end

local PLAY_K = { 2, 3, 4, 6 }
function scales.play_degree(scale_idx, play, step)
  local n = #INTERVALS[scale_idx]
  if play == 2 then return (step % (n + 1)) + 1 end
  if play == 3 then return (n + 1) - (step % (n + 1)) end
  if play == 8 then return math.random(1, n) end
  local k     = PLAY_K[play - 3]
  local cycle = math.floor((2 * n) / k) + 1
  return (step % cycle) * k + 1
end

return scales
