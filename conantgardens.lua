-- metronome v0.0.1
-- Bing, buk, buk, buk
--
-- A screen flash and
-- sound mimic a
-- metronome
--
-- K2: Start, stop
-- K3: Switch mode
--
-- In Main mode:
-- E1: Tempo
-- E2: Whole level
-- E3: Subdivion level
--
-- In Signature mode:
-- E1: Subdivision length
-- E2: Upper number
-- E3: Lower number

util = require "util"
fileselect = require "fileselect"

--tick along
function ticker()
  while isPlaying do
    if clockPosition > count.whole then -- we're on the barline
      print("bar")
      clockPosition = 0
      beatScreen = 15
    else if clockPosition % count.subBeatLength == 0 then -- we're on a subcount
      --print("subbeat")
      --play a big sound
      beatScreen = 8
    else if clockPosition % count.beatLength == 0 then -- we're on a small beat
      --print("-")
      -- play a small sound
      beatScreen = 4
    else
      --anything here?
      count.bigBeat = false
      count.smallBeat = false
    end
    end
    end
    clockPosition = clockPosition + tick -- move to next clock position
    clock.sync(1/192) -- and wait for a tick
  end
end

function redraw_clock() ----- a clock that draws space
  while true do ------------- "while true do" means "do this forever"
    clock.sleep(1/20) ------- pause for a fifteenth of a second (aka 15fps)
    if screen_dirty or isPlaying then ---- only if something changed
      redraw() -------------- redraw space
      screen_dirty = false -- and everything is clean again
    end
  end
end

function init()
  redraw_clock_id = clock.run(redraw_clock) --add these for other clocks so we can kill them at the end
  
  --variables
 -- upperNumber = 0
--  lowerNumber = 0
--  subcount = 0
  count = {}
  count.beatLength = 0
  count.subBeatLength = 0
  count.whole = 768
  count.recalculate = function()
    count.beatLength = count.whole / params:get("lowerNumber")
    count.subBeatLength = count.beatLength * params:get("subcount")
  end
  count.bigBeat = false
  count.smallBeat = false
  --end variables
  
  -- start params
  params:add_separator("Metronome")
  params:add_number("upperNumber", "Upper Number", 1, 128, 4)
  params:set_action("upperNumber", function()
    count.recalculate()
  end)
  params:add_number("lowerNumber", "Lower Number", 1, 32, 4)
  params:set_action("lowerNumber", function()
    count.recalculate()
  end)
  params:add_number("subcount", "Small Count", 1, 128, 4)
  params:set_action("subcount", function()
    count.recalculate()
  end)
  params:bang() -- set defaults using above params
  --end params

  --could use these to make the lower number start with powers of 2?
  --segmentLength = 6 -- index to read from resolutions, i.e. resolutions[segmentLength]
  --resolutions = {1,2,3,4,6,8,12,16,24,32,48,64,96,128,192}

  --drawing stuff
  beatScreen = 0 --screen level: set to 15 when the metronome pings to flash the screen
  heldKeys = {false, false, false}
  isPlaying = false -- are we playing right now?

  --main clock
  theClock = clock.run(ticker) -- sequencer clock
  clockPosition = 0 -- sequencer position right now. Updated by function 'ticker'
  tick = 1 -- how much to increment each tick. Guess it could be used for double time?

  mainView = true -- are we adjusting the tempo and levels?

  --file = {} --add samples: could be used to load bing samples
  
  screenDirty = true -- make sure we draw screen straight away

end

-- draws the view
function drawView()

  --draw black or white background
  screen.level(beatScreen)
  screen.rect(0,0,127,63)
  screen.fill()
  
  --draw white or black text
  screen.level(15 - beatScreen)
  
  --what view we in?
  screen.move(0,5)
  if mainView then screen.text("Levels")
  else screen.text("Signature") end
  
  -- could we highlight stuff depending what view we're in?
  
  --time signature, big nice text
  screen.move(64,49)
  screen.text(params:get("upperNumber"))
  screen.move(64,59)
  screen.text(params:get("lowerNumber"))
  
  screen.move(127,5)
  if mainView then
    screen.text_right("tempo: " .. clock.get_tempo()) --tempo
    else 
    screen.text_right("subcount: " .. params:get("subcount")) --subcount
  end
  
  --count
  --programmatically, draw text representing the counts in the count
  -- e.g. ONE two three FOUR five
  --etc
  screen.move(80,32)
  if isPlaying then screen.text("playing")
  else screen.text("stopped") end 
  
  screen.fill()
  
  print(beatScreen)
  if beatScreen > 0 then 
    local beatinS = (clock.get_tempo() / 60)
    local framesPerBeat = 15 / beatinS
    beatScreen = math.floor(beatScreen - (beatScreen / framesPerBeat)) end

end

-- draw the display!
function redraw()
  screen.clear()

  drawView()

  screen.update()
end

function enc(e, d)

  if e == 1 then 
    if mainView then
      --local tempoh = clock.get_tempo() + d
      params:set("clock_tempo", clock.get_tempo() + d)
    else
      local sc = params:get("subcount") + d
      params:set("subcount", sc)
    end
  end
  
  if e == 2 then
    if mainView then
    -- set big beat playback sound
    else
      params:set("upperNumber", params:get("upperNumber") + d)
      if params:get("subcount") > params:get("upperNumber") then params:set("subcount", params:get("upperNumber")) end
    end
  end
  
  if e == 3 then
    if mainView then
      --set small beat playback sound
    else 
      params:set("lowerNumber", params:get("lowerNumber") + d)
    end
  end
  
  screen_dirty = true

end

function key(k, z)
  
  if k == 2 and z == 1 then
    if isPlaying then isPlaying = false
      clockPosition = 0
    else isPlaying = true 
      clock.run(ticker) end
  end
  
  if k == 3 and z == 1 then -- togle view
    if mainView then mainView = false
    else mainView = true end
  end

  screen_dirty = true

end

function cleanup() --------------- cleanup() is automatically called on script close
  clock.cancel(redraw_clock_id) -- melt our clock via the id we noted
end
