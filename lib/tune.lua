local scales    = include("lib/scales")
local lifecycle = include("lib/lifecycle")

local tune = {
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

function tune.init()
  pitch_poll = poll.set("tune_pitch", function(freq)
    if not tune.active then return end
    if freq and freq > 30 then
      lost_count = 0
      local note, oct, _ = freq_to_note(freq)
      local c = cents_to_ref(freq, tune.ref_hz)

      cents_smooth = cents_smooth * 0.75 + c * 0.25
      tune.cents = round_sym(cents_smooth)

      local abs = math.abs(tune.cents)
      if abs < 5 then
        tune.arrow = 0
      elseif abs > 8 then
        tune.arrow = tune.cents < 0 and -1 or 1
      end

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
        tune.arrow    = 0
        cents_smooth   = 0
        note_candidate = "--"
        oct_candidate  = 0
        note_hold      = 0
      end
    end
    if tune.note ~= last_note or tune.octave ~= last_oct or tune.arrow ~= last_arrow then
      last_note  = tune.note
      last_oct   = tune.octave
      last_arrow = tune.arrow
      redraw()
    end
  end)
  pitch_poll.time = 0.055
end

-- Mute is owned by the tune_mute param (host side), not by this view: it stays put when
-- the tuner is left, so a MIDI-mapped mute behaves like a footswitch.
function tune.set_active(b)
  if tune.active == b then return end
  tune.active = b
  if b then
    tune.note     = "--"
    tune.octave   = 0
    tune.cents    = 0
    tune.arrow    = 0
    cents_smooth   = 0
    note_candidate = "--"
    oct_candidate  = 0
    note_hold      = 0
    lost_count     = 0
    last_note      = "--"
    last_oct       = 0
    last_arrow     = 0
    lifecycle.spawn("tune")
    if pitch_poll then pitch_poll:start() end
  else
    if pitch_poll then pitch_poll:stop() end
    lifecycle.free("tune")
  end
end

-- tuning indicator: centered dot when in tune, otherwise a pixel-symmetric
-- triangle that points inward toward the centre (built from columns so the
-- left/right arrows are exact mirrors and each is vertically symmetric)
function tune.draw_arrow(cx, y, arrow)
  y = y - 1   -- sit one pixel higher
  if arrow == 0 then
    -- drawn from rows rather than screen.circle, which rasterises lopsided at this
    -- radius; this way the dot is exactly symmetric about cx and y like the arrows
    screen.rect(cx - 1, y - 2, 3, 1)
    screen.rect(cx - 2, y - 1, 5, 3)
    screen.rect(cx - 1, y + 2, 3, 1)
    screen.fill()
    return
  end
  local s = arrow < 0 and -1 or 1
  for i = 0, 5 do
    local hh = math.floor(3 * (5 - i) / 5 + 0.5)
    local x  = cx + s * (9 - i)
    screen.move(x, y - hh); screen.line(x, y + hh); screen.stroke()
  end
end

function tune.draw_half(ox, oy, focused)
  local cx  = ox + 16
  local lv  = focused and FULL or MED
  local tlv = tune.muted and FULL or MED   -- note carries the mute state, label the focus
  screen.font_size(16); screen.font_face(0)
  screen.level(tlv)
  screen.move(cx, oy + 28); screen.text_center(tune.note)
  screen.font_size(8)
  if tune.note ~= "--" then
    screen.level(lv)
    screen.move(cx + 11, oy + 16); screen.text(tostring(tune.octave))
    tune.draw_arrow(cx, oy + 42, tune.arrow)
  end
  screen.level(lv)
  screen.move(cx, oy + 56); screen.text_center("Tune")
end

return tune
