local scales    = include("lib/scales")
local lifecycle = include("lib/lifecycle")

local tuner = {
  active  = false,
  muted   = false,
  ref_hz  = 440.0,
  note    = "--",
  octave  = 0,
  cents   = 0,
  arrow   = 0,
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
local last_arrow     = 0

local function round_sym(x)
  if x >= 0 then return math.floor(x + 0.5)
  else return -math.floor(-x + 0.5) end
end

local function freq_to_note(freq)
  if freq < 20 then return "--", 0, 0 end
  local semitones = 69 + 12 * math.log(freq / 440.0) / math.log(2)
  local nearest   = round_sym(semitones)
  local cents     = round_sym((semitones - nearest) * 100)
  local name      = scales.NOTE_NAMES[nearest % 12 + 1]
  local octave    = math.floor(nearest / 12) - 1
  return name, octave, cents
end

local function cents_to_ref(freq, ref)
  if freq < 20 or ref < 20 then return 0 end
  local semitones = 12 * math.log(freq / ref) / math.log(2)
  local nearest   = round_sym(semitones)
  local cents     = round_sym((semitones - nearest) * 100)
  return cents
end

function tuner.init()
  pitch_poll = poll.set("tuner_pitch", function(freq)
    if not tuner.active then return end
    if freq and freq > 30 then
      lost_count = 0
      local note, oct, _ = freq_to_note(freq)
      local c = cents_to_ref(freq, tuner.ref_hz)

      cents_smooth = cents_smooth * 0.75 + c * 0.25
      tuner.cents = round_sym(cents_smooth)

      local abs = math.abs(tuner.cents)
      if abs < 5 then
        tuner.arrow = 0
      elseif abs > 8 then
        tuner.arrow = tuner.cents < 0 and -1 or 1
      end

      if note == note_candidate and oct == oct_candidate then
        note_hold = note_hold + 1
        if note_hold >= HOLD_FRAMES then
          tuner.note   = note_candidate
          tuner.octave = oct_candidate
        end
      else
        note_candidate = note
        oct_candidate  = oct
        note_hold      = 1
      end
    else
      lost_count = lost_count + 1
      if lost_count >= LOST_FRAMES then
        tuner.note     = "--"
        tuner.octave   = 0
        tuner.cents    = 0
        tuner.arrow    = 0
        cents_smooth   = 0
        note_candidate = "--"
        oct_candidate  = 0
        note_hold      = 0
      end
    end
    if tuner.note ~= last_note or tuner.octave ~= last_oct or tuner.arrow ~= last_arrow then
      last_note  = tuner.note
      last_oct   = tuner.octave
      last_arrow = tuner.arrow
      redraw()
    end
  end)
  pitch_poll.time = 0.055
end

function tuner.set_active(b)
  if tuner.active == b then return end
  tuner.active = b
  if b then
    tuner.muted    = false
    tuner.note     = "--"
    tuner.octave   = 0
    tuner.cents    = 0
    tuner.arrow    = 0
    cents_smooth   = 0
    note_candidate = "--"
    oct_candidate  = 0
    note_hold      = 0
    lost_count     = 0
    last_note      = "--"
    last_oct       = 0
    last_arrow     = 0
    engine.mute(0)
    lifecycle.spawn("tuner")
    if pitch_poll then pitch_poll:start() end
  else
    if pitch_poll then pitch_poll:stop() end
    lifecycle.free("tuner")
    engine.mute(0)
  end
end

-- tuning indicator: centered dot when in tune, otherwise a pixel-symmetric
-- triangle that points inward toward the centre (built from columns so the
-- left/right arrows are exact mirrors and each is vertically symmetric)
function tuner.draw_arrow(cx, y, arrow)
  y = y - 1   -- sit one pixel higher
  if arrow == 0 then
    screen.circle(cx, y, 2); screen.fill()
    return
  end
  local s = arrow < 0 and -1 or 1
  for i = 0, 5 do
    local hh = math.floor(3 * (5 - i) / 5 + 0.5)
    local x  = cx + s * (9 - i)
    screen.move(x, y - hh); screen.line(x, y + hh); screen.stroke()
  end
end

function tuner.draw_half(ox, oy, focused)
  local cx  = ox + 16
  local lv  = focused and FULL or MED
  local tlv = tuner.muted and MED or lv
  screen.font_size(16); screen.font_face(0)
  screen.level(tlv)
  screen.move(cx, oy + 28); screen.text_center(tuner.note)
  screen.font_size(8)
  if tuner.note ~= "--" then
    screen.level(lv)
    screen.move(cx + 11, oy + 16); screen.text(tostring(tuner.octave))
    tuner.draw_arrow(cx, oy + 42, tuner.arrow)
  end
  screen.level(lv)
  screen.move(cx, oy + 56); screen.text_center("Tuner")
end

return tuner
