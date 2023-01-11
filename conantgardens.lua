-- Conant Gardens v0.0.1
-- Dilla time for norns
--
-- based on the work of 
-- Roger Linn, Akai,
-- Dan Charnas, and 
-- James Dewitt Yancey
--
-- E1: Select Track
-- K1: Hold for shift
-- K2: Toggle page
--
-- In Sequence View:
-- E2: Select position
-- E3: Select division
-- K3: Add / remove notes
-- -- Hold K3 to move notes
-- shift+E1: 
-- shift+E2: Track timing
-- shift+E3: Note dynamic
-- shift+K2:
-- shift+K3: Fill notes
--
-- In Sample View
-- E2: Sample start
-- E3: Sample end
-- K3: Load sample
-- shift+E1:
-- shift+E2: Start+end
-- shift+E3: Sample volume

util = require "util"
fileselect = require "fileselect"

-- pass softcut sample values to an array for display
function copy_samples(ch, start, interval, samples)
  print("rendering a single track samples for track " .. currentTrack + 1)
  for i = 1, editArea.width, 1 do
    waveform.samples[i + currentTrack * editArea.width] = samples[i]
  end
  print("done rendering waveforms")
  screenDirty = true
  waveform.isLoaded[currentTrack + 1] = true
end

--todo: add this functionality to params - ie 'save session'
function loadPattern()
  trackEvents = tab.load(_path.data.."/conantgardens/beat01.txt")
end
function savePattern()
  tab.save(trackEvents,_path.data.."/conantgardens/beat01.txt")
end

--tick along, play events
function ticker()
  while isPlaying do
    if (clockPosition > totalBeats) then clockPosition = 0 end  --loop clock
    for i, data in ipairs(trackEvents) do     --check if it's time for an event
      if (data[4] ~=nil) then --if there's an event to check
        local localTick = clockPosition - trackTiming[data[3]+1]  --offset track playhead position by track offset
        if localTick > totalBeats then localTick = 0 - trackTiming[data[3]+1]   --check we're not out of bounds
        else if localTick < 0 then localTick = totalBeats - trackTiming[data[3]+1] end
        end
        if (localTick == math.floor(totalBeats * (data[1]))) then  --finally, play an event?
          softcut.position(data[3]+1,data[3]+1) -- put the voice playhead in the right place
          softcut.level(data[3]+1,data[4])  --set dynamic level
          softcut.play(data[3]+1,1) -- play
        end
      end
    end
    if clockPosition % 16 == 0 then screenDirty = true end -- redraw screen every x ticks
    clockPosition = clockPosition + tick -- move to next clock position
    clock.sync(1/192) -- and wait
  end
end

function redraw_clock() ----- a clock that draws space
  while true do ------------- "while true do" means "do this forever"
    clock.sleep(1/15) ------- pause for a fifteenth of a second (aka 15fps)
    if screenDirty and not weLoading then ---- only if something changed
      redraw() -------------- redraw space
      screen_dirty = false -- and everything is clean again
    end
  end
end

function init()
  redraw_clock_id = clock.run(redraw_clock) --add these for other clocks so we can kill them at the end

  editArea = {width=120, height=56, border=4} -- the overall draw window size. Should not exceed 128 x 64!

  --params
  tracksAmount = 0 -- number of tracks to play
  beatsAmount = 0 -- number of beats to sequence
  totalBeats = 0 -- number of ticks for the sequencer clock
  -- start params
  params:add_separator("Conant Gardens")
  params:add_number("tracksAmount", "Number of Tracks", 1, 8, 4)
  params:set_action("tracksAmount",   function tracksAmount_update(x)
    tracksAmount = x
    editArea.trackHeight = editArea.height / tracksAmount
  end)
  params:add_number("beatsAmount", "Number of Beats", 1, 32, 8)
  params:set_action("beatsAmount", function(x)
      beatsAmount = x
      totalBeats = 192 * beatsAmount
    end)
  params:bang() -- set defaults using above params
  --end params

  currentTrack = 0
  segmentLength = 6   --start with cursor set to 8th notes:
  resolutions = {1,2,3,4,6,8,12,16,24,32,48,64,96,128,192} -- index to read from resolutions, i.e. resolutions[segmentLength]
  beatCursor = 1 -- initial x position of cursor

  trackEvents = {} -- structure: [position, length, track, dynamic, file] 
  currentDynamic = 1.0 -- initial dynamic for adding events

  --drawing stuff
  editArea.trackHeight = editArea.height / tracksAmount -- is this redunant because of params?
  heldKeys = {false, false, false} -- are we holding any keys?
  nowPosition = {-1, -1} -- for storing where the cursor is
  isPlaying = false -- are we playing right now?
  weMoving = false -- are we moving an event right now?
  weMoved = false -- did we move an event while moving the cusor?
  movingEvents = {} -- list of events we're moving right now
  weFilling = false -- are we filling an area with events?
  fillBounds = {nil, nil} -- bounds for filling: start, end
  weLoading = false -- stops the UI from being drawn when loading a file
  theClock = clock.run(ticker) -- sequencer clock
  clockPosition = 0 -- sequencer position right now. Updated by function 'ticker'
  tick = 1 -- how much to increment each tick. Guess it could be used for double time?
  trackTiming = {}  -- offset for entire track +- in 192ths
  for i=1, 8, 1 do trackTiming[i] = 0 end -- programmatically fill trackTiming
  sampleView = false -- are we looking at samples?
  softcut.event_render(copy_samples) -- what to do when we request waveform samples from softcut
  waveform = {} -- waveform information, used when loading a file
  waveform.isLoaded = {}
  waveform.samples = {}
  waveform.channels = {}
  waveform.length = {}
  waveform.rate = {}
  for i=1, 8, 1 do
    waveform.isLoaded[i] = false 
    --waveform.samples[i] = {}
    --waveform.channels[i] = 0
    --waveform.length[i] = 0
    --waveform.rate[i] = 0
  end

  file = {} --add samples: could be used to load default samples
  
  -- start softcut
  softcut.buffer_clear()
  -- read file into buffer
  -- buffer_read_mono (file, start_src, start_dst, dur, ch_src, ch_dst)
  for i=1, 8, 1 do
    --local ch, length, rate = audio.file_info(file[i])
    --local lengthInS = length * (1 / rate)
    --if lengthInS > 1 then lengthInS = 1 end
    --waveform.length[i] = lengthInS
    --load file into buffer
    --softcut.buffer_read_mono(file[i],0,i,waveform.length[i],1,1)
    print("setting up softcut voice "..i)
    -- enable voices
    softcut.enable(i,1)
    -- set voices to buffer 1
    softcut.buffer(i,1)
    -- set voices level to 1.0
    softcut.level(i,1.0)
    -- voices disable loop
    softcut.loop(i,0)
    softcut.loop_start(i,i)
    softcut.loop_end(i,i+0.99)
    softcut.position(i,i)
    -- set voices rate to 1.0 and no fade
    softcut.rate(i,1.0)
    softcut.fade_time(i,0)
    -- disable voices play
    softcut.play(i,0)
  end
  --softcut.render_buffer(1,0,4,editArea.width) -- ch, start, duration, number of samples to make
  -- end softcut
  
  screenDirty = true -- make sure we draw screen straight away

end

-- loading a file handler: sets waveform information, softcut voice settings
function load_file(file)
  if file ~= "cancel" then
    local ch, length, rate = audio.file_info(file)     --get file info
    local lengthInS = length * (1 / rate)    --get length and limit to 1s
    if lengthInS > 1 then lengthInS = 1 end
    waveform.length[currentTrack] = lengthInS
    softcut.buffer_clear_region(currentTrack+1, 1, 0, 0)    -- erase section of buffer
    --load file into buffer (file, start_source, start_destination, duration, channel_source, channel_destination, preserve, mix)
    softcut.buffer_read_mono(file, 0, currentTrack+1, lengthInS, 1, 1, 0)
    --read samples into waveformSamples (eventually) (channel, start, duration, samples)
    softcut.render_buffer(1,currentTrack+1,1,editArea.width + 1)
  end
  weLoading = false
end

--draw a bright box for each of the events in trackEvents, so you can see what you're doing!
function drawEvents()
  for i, data in ipairs(trackEvents) do -- check each event in trackEvents
    if (data[4] ~= nil and data[3] < tracksAmount) then -- if data exists, and is within tracksAmount
      -- set some local, human-readable variables
      local x = editArea.border + math.floor(editArea.width * data[1])
      local y = editArea.border + data[3] * editArea.trackHeight 
      local w = math.floor(editArea.width * data[2])
      local h = editArea.trackHeight
      local dynamic = math.floor(data[4] * 15) -- set event brightness based on note dynamic
      screen.level(dynamic)
      --check whether the current event index is being moved, and if so, MAKE IT BLACK
      for j=#movingEvents, 1, -1 do
        if movingEvents[j] == i then
          screen.level(1)
        end
      end
      screen.rect(x, y, w, h)
      screen.fill() -- draw the event
      -- plus a nice little line for the onset
      screen.level(0)
      screen.rect(x, y, 1, h)
      screen.fill()
    end
  end
end

-- add and remove events from TrackEvents, called by button handler
function addRemoveEvents()
  --set some human-readable local variables
  local barFraction = beatsAmount / 4 --how many groups of four beats do we have?
  local position = (beatCursor - 1) / (resolutions[segmentLength] * barFraction) -- how far through the edit window in bars are we?
  local length = 1 / (resolutions[segmentLength] * barFraction) -- how wide is the cursor?
  local foundOne = false -- initially, we haven't grabbed anything yet
  
  --check for clashes, and delete event
  -- trackEvents structure reminder: [position, length, track, dynamic] 
  if #trackEvents > 0 then --if we have any events at all
    for i=#trackEvents, 1, -1 do -- for each item in trackEvents
      if trackEvents[i][4] ~= nil then -- if there's a valid event at trackEvents[i]
        if currentTrack == trackEvents[i][3] then -- if the event is on the current track
        -- if the left edge of the cursor is inside the event boundaries or if the left edge of the event is inside the cursor boundaries
          if (position >= trackEvents[i][1] and position < trackEvents[i][1] + trackEvents[i][2]) or (trackEvents[i][1] >= position and trackEvents[i][1] < position + length) then
            table.remove(trackEvents[i]) -- remove the event
            foundOne = true -- raise flag for we deleted (at least) one
            screenDirty = true
          end
        end
      end
    end
  end
  if (not foundOne and not weMoving) then -- if we didn't delete and aren't moving
    table.insert(trackEvents, {position, length, currentTrack, currentDynamic}) -- insert a new event
    screenDirty = true
  end
end

-- draws the sequencer view
function drawSequencer()
  -- SQUARES etc.
  	--a dim background
  screen.level(1)
  screen.rect(editArea.border, editArea.border, editArea.width, editArea.height)
  screen.fill()
  --track select row
  screen.level(2)
  screen.rect(editArea.border, editArea.border + editArea.trackHeight * currentTrack, editArea.width, editArea.trackHeight)
  --time selection column
  screen.rect(
    editArea.border + (editArea.width / beatsAmount) * (4 / resolutions[segmentLength]) * (beatCursor - 1),
    editArea.border,
    (editArea.width / beatsAmount) * (4 / resolutions[segmentLength]),
    editArea.height)
  screen.fill()
  --crossover, where track and time selections meet
  --screen.level(6)
  --screen.rect(
  --  editArea.border + (editArea.width / beatsAmount) * (4 / resolutions[segmentLength]) * (beatCursor - 1),
  --  editArea.border + editArea.trackHeight * currentTrack,
  --  (editArea.width / beatsAmount) * (4 / resolutions[segmentLength]),
  --  editArea.trackHeight)
  --screen.fill()
  --events
  drawEvents()
  --a bright line around the selection
  if not heldKeys[1] then
    screen.level(15)
    screen.rect(
      editArea.border + (editArea.width / beatsAmount) * (4 / resolutions[segmentLength]) * (beatCursor - 1),
      editArea.border + editArea.trackHeight * currentTrack,
      (editArea.width / beatsAmount) * (4 / resolutions[segmentLength]) + 0.5,
      editArea.trackHeight + 1
    )
    screen.stroke()
  end
  --play head line, position updated by and taken from ticker(). A dim line on the edit area, plus two bright little ticks outside the area
  local playheadX = editArea.border + (clockPosition / totalBeats) * editArea.width
  screen.level(15)
  screen.move(playheadX, 0)
  screen.line(playheadX, editArea.border)
  screen.move(playheadX, editArea.border + editArea.height)
  screen.line(playheadX, 64)
  screen.stroke()
  screen.level(3)
  for i=1, tracksAmount, 1 do
    screen.move(playheadX - trackTiming[i] / 12, editArea.border + editArea.trackHeight * (i-1))
    screen.line(playheadX - trackTiming[i] / 12, editArea.border + editArea.trackHeight * (i))
  end
  screen.stroke()
  
  --guides, little dots to demarcate bar lines and track lines
  screen.level(0)
  for beat=0, beatsAmount, 1 do
    for track=0, tracksAmount, 1 do
      screen.pixel(editArea.border + beat * (editArea.width / beatsAmount), editArea.border + track * editArea.trackHeight)
    end
  end
  screen.fill()
  
  -- TEXT
  if heldKeys[1] then -- if we've got K1 held to shift
    screen.level(8)
    screen.move(0, 62) -- move to where K2 is
    if isPlaying then screen.text("stop") else screen.text("play") end
    for i=1, tracksAmount, 1 do -- draw the display for the track timing offsets
      screen.move(editArea.border - 2 + editArea.width / 2 + trackTiming[i] / 8, editArea.border + i * editArea.trackHeight -1)
      if trackTiming[i] > 0 then
        screen.text("+"..trackTiming[i])
      else screen.text(trackTiming[i]) end
      screen.move(116, 63)
      screen.text(currentDynamic)
    end
  else do -- if we're not holding K1 to shift
      -- cursor position
      screen.level(15)
      screen.move(80, 63)
      screen.text(beatCursor)      -- which beat we're on
      screen.move(98,63)
      screen.text("/")       -- a '/'
      screen.move(116, 63)
      screen.text(resolutions[segmentLength])      -- cursor length, e.g. an eighth note
      screen.move(0, 62)
      screen.text("spl")      -- swap page display for K2
      if weMoving then
        screen.move(18, 62)
        screen.text("holding")
      end
    end
  end
  screen.move(107,5)
  screen.text("trk " .. currentTrack + 1)   -- what track we on?
  
end

-- draws the sampler view
function drawSampler()
  --background
  screen.level(1)
  screen.rect(editArea.border, editArea.border, editArea.width, editArea.height)
  screen.fill()
  --waveform
  screen.level(15)
  if waveform.isLoaded[currentTrack + 1] then
    for i=1, editArea.width, 1 do
      screen.move(i+editArea.border, editArea.border  + editArea.height * 0.5 + waveform.samples[currentTrack * editArea.width + i] * editArea.height * 0.5)
      screen.line(i+editArea.border, editArea.border  + editArea.height * 0.5 + waveform.samples[currentTrack * editArea.width + i] * editArea.height * -0.5)
      screen.stroke()
    end
  else screen.move(64,34)
    screen.text_center("K3 to load sample")
  end
  -- TEXT
  -- above K3
  screen.move(20,62)
  screen.text("load")
  --  screen.fill() -- redundant??
  screen.level(15)
  --track label
  screen.move(107,5)
  screen.text("trk " .. currentTrack + 1)
  --"seq", above K2
  screen.move(0,62)
  screen.text("seq")
end

-- draw the display!
function redraw()
  screen.clear()

  -- decide which view to draw, and draw it
  if sampleView then drawSampler()
  else drawSequencer() end
  
  --a play/stop icon, to visualise play state
  screen.level(10)
  if (isPlaying == true) then
    screen.move(0,0)
    screen.line(0,4)
    screen.line(4,2)
    screen.close() -- draw a triangle
    else screen.rect(0,0,4,4) -- draw a square
    end
  end
  screen.fill()

  screen.update()
end

--takes event number, encoder number and turn amount, and moves an event. called by ...
function moveEvent(i,e,d)
  if (e == 1) then
  --move event to a different track
    local movedTrack = util.clamp(currentTrack + d, 0, tracksAmount - 1)
    trackEvents[i][3] = movedTrack
    weMoved = true
  end
  if (e == 2) then
  -- move in time
    local length = 1 / (resolutions[segmentLength] * beatsAmount / 4)
    -- TODO at some point,an algo for 'is there an event in the way'
    -- will it go out of bounds?
    if (trackEvents[i][1] + trackEvents[i][2] + d * length <= 1 and trackEvents[i][1] + d * length >= 0) then
      --offset position in time by the cursor length
      trackEvents[i][1] = trackEvents[i][1] + d * length
      weMoved = true  
    end
  end
end

-- TODO takes a start and end bounds, and fills it with notes of length = 1 / (resolutions[segmentLength] * beatsAmount / 4)
function doFill(s,e)
  print("wouldfill. start: "..s..". End: "..e)
end

function enc(e, d)
  if (heldKeys[1]) then   --SHIFTING??
    if sampleView then
      --sample view shift behaviour, currently nothing
    else if (e == 2) then -- shift behaviour in sequencer view
      trackTiming[currentTrack +1] = trackTiming[currentTrack +1] + d -- adjust track timing
      screenDirty = true
    end
    if (e == 3) then    -- test for position, adjust note dynamic
      local position = (beatCursor - 1) / (resolutions[segmentLength])
      local length = 1 / (resolutions[segmentLength])
      currentDynamic = util.clamp(currentDynamic + d/50, 0.1, 1.0)
      for i=#trackEvents, 1, -1 do
      --is event under cursor?
        if trackEvents[i][4] ~= nil then
          if currentTrack == trackEvents[i][3] then
            if (position >= trackEvents[i][1] and position < trackEvents[i][1] + trackEvents[i][2]) then
              --yes
              currentDynamic = trackEvents[i][4]
              trackEvents[i][4] = util.clamp(currentDynamic + d/10, 0.1, 1.0)
            else if (trackEvents[i][1] >= position and trackEvents[i][1] < position + length) then
              currentDynamic = trackEvents[i][4]
              trackEvents[i][4] = util.clamp(currentDynamic + d/50, 0.1, 1.0)
              end
            end
          end
        end
      end
      screenDirty = true
      end
    end
  end
  
  --if we're holding k3, move events
  if weMoving and #movingEvents > 0 then
    for i=#movingEvents, 1, -1 do
      moveEvent(movingEvents[i],e,d)
    end
    screenDirty = true
  end

  --move cursor between tracks
  if (e == 1 and not heldKeys[1]) then
    currentTrack = util.clamp(currentTrack + d, 0, tracksAmount - 1)
    screenDirty = true
  end
  
  -- move cursor in time
  if (e == 2 and not heldKeys[1]) then
    beatCursor = math.floor(util.clamp(beatCursor + d, 1, resolutions[segmentLength] * beatsAmount/4))
    screenDirty = true
  end
  
  --adjust segment Length
  if (e == 3 and not heldKeys[1] and not heldKeys[3]) then
    local beatCursorThen = (beatCursor - 1) / resolutions[segmentLength]
    segmentLength = util.clamp(segmentLength - d, 1, #resolutions)
    -- round up beatCursor
    beatCursor = math.floor(math.min(1. + beatCursorThen * resolutions[segmentLength]), resolutions[segmentLength])
    screenDirty = true
  end

end

function key(k, z)
  
  heldKeys[k] = z == 1 -- store if we're holding any keys
  
  -- check if there are events under the cursor, and if so add them to a list (movingEvents) so they can be moved when the encoder is called
  if (heldKeys[3] and not sampleView) then
    --store initial position to check that we actually move something. if we don't end up moving the cursor, we will add/remove an event
    nowPosition[1] = beatCursor
    nowPosition[2] = currentTrack

    --calculate decimal values for the cursor start/end (event positions are stored as 0-1.)
    local selectposition = (beatCursor - 1) / (resolutions[segmentLength] * (beatsAmount / 4))
    local selectlength = 1 / (resolutions[segmentLength] * (beatsAmount / 4)) - (1/192)
    if selectlength < 1/192 then selectlength = 1/192 end

    --look through all the track events to see whether each one is under the cursor, and add the event index to a table if so
    for i=#trackEvents, 1, -1 do
      if trackEvents[i][4] ~= nil then      --if the event hasn't been deleted
        local eventEnd = trackEvents[i][1] + trackEvents[i][2]        --store a friendly event end point
        if (currentTrack == trackEvents[i][3] and selectposition < eventEnd and selectposition >= trackEvents[i][1]) then --is under cursor
          weMoving = true
          table.insert(movingEvents,i) -- store the index of the event
          else if (currentTrack == trackEvents[i][3] and trackEvents[i][1] >= selectposition and trackEvents[i][1] < selectposition + selectlength) then
            weMoving = true
            table.insert(movingEvents,i)
          end
        end
      end
    end
  end

  --play/stop
  if (heldKeys[1] and k == 2 and z == 0) then
    if isPlaying then
      isPlaying = false
      clockPosition = 0
      screenDirty = true
    else
      isPlaying = true
      clock.run(ticker) -- need to call this every time? hmm
    end
  else if (k == 2 and z == 0) then 
    sampleView = not sampleView 
    screenDirty = true 
  end
  end

  -- load sample
	if sampleView and k == 3 and z == 0 then
	  weLoading = true
	  print("loading a file onto track " .. currentTrack + 1)
		fileselect.enter(_path.audio,load_file) -- starts the fileselect function, taking screen control and eventually passing a file location
	end
  
  if (k == 3 and z == 0 and not sampleView) then
    if not weMoved then addRemoveEvents() end -- a simple press of K3, we add or remove event(s) under the cursor
    weMoving = false
    if weMoved then -- when we release K3, reset the conditions for moving events:
      weMoved = false
      movingEvents = {}
    end
  end

end

function cleanup() --------------- cleanup() is automatically called on script close
  clock.cancel(redraw_clock_id) -- melt our clock via the id we noted
  -- should we melt the ticker clock too?
end
