local scales    = include("lib/scales")
local lifecycle = include("lib/lifecycle")
local cabinet   = include("lib/cabinet")

-- tune is a strobe tuner that accepts a note only after three identical reports, so a decaying tone
-- doesn't flicker between neighbours. The strobe drifts faster the further off you are and stands
-- still within two cents.
local tune = {
  active  = false,
  muted   = false,
  ref_hz  = 440.0,
  note    = "--",
  octave  = 0,
  cents   = 0,
  phase   = 0,
}

local MED  = 5
local FULL = 15

local HOLD_FRAMES = 3
local LOST_FRAMES = 27

local cents_smooth   = 0
local note_candidate = "--"
local oct_candidate  = 0
local note_hold      = 0
local lost_count     = 0
local pitch_poll     = nil

local last_note      = "--"
local last_oct       = 0
local last_t         = 0

local STROBE_W      = 13
local STROBE_PERIOD = 6
local STROBE_SPEED  = 1.0
local IN_TUNE       = 2

local function round_sym(x)
  if x >= 0 then return math.floor(x + 0.5)
  else return -math.floor(-x + 0.5) end
end

local function freq_to_note(freq)
  if freq < 20 then return "--", 0, 0 end
  local semitones = 69 + 12 * math.log(freq / tune.ref_hz) / math.log(2)
  local nearest   = round_sym(semitones)
  local cents     = round_sym((semitones - nearest) * 100)
  local name      = scales.NOTE_NAMES[nearest % 12 + 1]
  local octave    = math.floor(nearest / 12) - 1
  return name, octave, cents
end

function tune.init()
  pitch_poll = poll.set("tune_pitch", function(freq)
    if not tune.active then return end
    if freq and freq > 30 then
      lost_count = 0
      local note, oct, _ = freq_to_note(freq)
      local c = 1200 * math.log(freq / tune.ref_hz, 2)
      c = c - 100 * round_sym(c / 100)

      cents_smooth = cents_smooth * 0.75 + c * 0.25
      tune.cents = cents_smooth

      if note == note_candidate and oct == oct_candidate then
        note_hold = note_hold + 1
        if note_hold >= HOLD_FRAMES then
          tune.note   = note_candidate
          tune.octave = oct_candidate
        end
      else
        note_candidate = note
        oct_candidate  = oct
        note_hold      = 1
      end
    else
      lost_count = lost_count + 1
      if lost_count >= LOST_FRAMES then
        tune.note     = "--"
        tune.octave   = 0
        tune.cents    = 0
        cents_smooth   = 0
        note_candidate = "--"
        oct_candidate  = 0
        note_hold      = 0
      end
    end
    local now = util.time()
    local dt  = math.min(now - last_t, 0.2)
    last_t = now
    tune.phase = (tune.phase - cents_smooth * STROBE_SPEED * dt) % STROBE_PERIOD
    if tune.note ~= "--" or tune.note ~= last_note or tune.octave ~= last_oct then
      last_note = tune.note
      last_oct  = tune.octave
      redraw()
    end
  end)
  pitch_poll.time = 0.055
end

function tune.set_active(b)
  if tune.active == b then return end
  tune.active = b
  if b then
    tune.note     = "--"
    tune.octave   = 0
    tune.cents    = 0
    tune.phase    = 0
    cents_smooth   = 0
    note_candidate = "--"
    oct_candidate  = 0
    note_hold      = 0
    lost_count     = 0
    last_note      = "--"
    last_oct       = 0
    last_t         = util.time()
    lifecycle.spawn("tune")
    if pitch_poll then pitch_poll:start() end
  else
    if pitch_poll then pitch_poll:stop() end
    lifecycle.free("tune")
  end
end

function tune.draw_strobe(cx, y, focused)
  local top     = focused and 13 or 4
  local in_tune = math.abs(tune.cents) < IN_TUNE
  for dx = -STROBE_W, STROBE_W do
    local v = 0.5 + 0.5 * math.cos(2 * math.pi * (dx - tune.phase) / STROBE_PERIOD)
    screen.level(math.floor(2 + (top - 2) * v + 0.5))
    screen.rect(cx + dx, y - 4, 1, 7); screen.fill()
  end
  screen.level(in_tune and FULL or MED)
  screen.rect(cx, y - 7, 1, 2); screen.fill()
end

local PLAY = {
  "110.1...010.101",
  "101.1...101.101",
  "110.1...111..1.",
  "100.1...101..1.",
  "100.111.101..1.",
}

local function draw_play(cx, y0, lv)
  screen.level(lv)
  for r, row in ipairs(PLAY) do
    for k = 1, #row do
      if row:sub(k, k) == "1" then screen.rect(cx - 8 + k, y0 + r - 1, 1, 1) end
    end
  end
  screen.fill()
end

local function strobe_band(x0, x1, y0, rows, top)
  local low = math.abs(tune.cents) < IN_TUNE and 3 or 2
  for x = x0, x1 do
    local v = 0.5 + 0.5 * math.cos(2 * math.pi * (x - tune.phase) / STROBE_PERIOD)
    screen.level(math.floor(low + (top - low) * v + 0.5))
    screen.rect(x, y0, 1, rows); screen.fill()
  end
end

-- Tune stands in a 37 x 60 px box like any half device: the window with note and strobe on top,
-- the in-tune lamp in the middle, the footswitch below. The param strip carries the name; the
-- bright frame shows that Tune has focus.
function tune.draw_half(ox, oy, focused)
  oy = oy - 1
  local cx      = ox + math.floor(cabinet.HALF_W / 2)
  local lv      = focused and FULL or MED
  local has     = tune.note ~= "--"
  local in_tune = has and math.abs(tune.cents) < IN_TUNE
  cabinet.frame(ox, oy, cabinet.HALF_W, cabinet.H, lv)
  screen.level(1); screen.rect(ox + 4, oy + 5, 29, 27); screen.fill()
  screen.level(4)
  screen.rect(ox + 4, oy + 4, 29, 1); screen.rect(ox + 4, oy + 32, 29, 1)
  screen.rect(ox + 3, oy + 5, 1, 27); screen.rect(ox + 33, oy + 5, 1, 27); screen.fill()
  screen.font_size(16); screen.font_face(0)
  if has then
    local letter = tune.note:sub(1, 1)
    local w  = screen.text_extents(letter)
    local gx = cx - math.floor((w + 9) / 2)
    local dx = gx + w + 4
    screen.level((tune.muted or in_tune) and FULL or 9)
    screen.move(gx + w / 2, oy + 20); screen.text_center(letter)
    screen.font_size(8)
    screen.level(9)
    screen.move(dx + 2, oy + 14); screen.text_center(tostring(tune.octave))
    if tune.note:find("#") then
      screen.rect(dx + 1, oy + 16, 1, 5); screen.rect(dx + 3, oy + 16, 1, 5)
      screen.rect(dx, oy + 17, 5, 1); screen.rect(dx, oy + 19, 5, 1); screen.fill()
    end
  else
    draw_play(cx, oy + 13, 7)
  end
  if has then
    strobe_band(ox + 5, ox + 31, oy + 27, 4, focused and 13 or 6)
  else
    screen.level(2); screen.rect(ox + 5, oy + 27, 27, 4); screen.fill()
  end
  if has then
    screen.level(in_tune and FULL or MED)
    screen.rect(cx, oy + 24, 1, 2); screen.fill()
  end
  screen.level(in_tune and FULL or 3)
  screen.rect(cx - 1, oy + 40, 3, 2); screen.fill()
  screen.level(5)
  screen.rect(cx - 5, oy + 50, 11, 1); screen.rect(cx - 5, oy + 56, 11, 1)
  screen.rect(cx - 6, oy + 51, 1, 5); screen.rect(cx + 6, oy + 51, 1, 5); screen.fill()
  screen.level(8); screen.rect(cx - 5, oy + 51, 11, 2); screen.fill()
  screen.level(3); screen.rect(cx - 5, oy + 54, 11, 2); screen.fill()
  screen.font_size(8)
end

return tune
