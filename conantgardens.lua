-- Conant Gardens v0.0.1
-- Dilla time for norns
--
-- based on the work of 
-- Roger Linn, Akai,
-- Dan Charnas, and 
-- James Dewitt Yancey
--
-- E1: Select Track
-- E2: Select Position
-- E3: Select Division
--
-- K1: Hold for shift
-- K2: Change page
-- K3: Add / remove notes
-- - Hold K3 to move notes
--
-- shift+E1:
-- shift+E2: track timing
-- shift+E3: note dynamic
--
-- shift+K2:
-- shift+K3:

util = require "util"
fileselect = require "fileselect"

function init ()
  --inits
  currentTrack = 0
  segmentLength = 2
  beatCursor = 1
  -- structure: [position, length, track, dynamic] 
  trackEvents = {}
  currentDynamic = 1.0
  isPlaying = false
  editArea = {width=120, height=56, border=4}
  tracksAmount = 4
  editArea.trackHeight = editArea.height / tracksAmount
  resolutions = {1,2,3,4,6,8,12,16,24,32,48,64,96,128,192}
  heldKeys = {false, false, false}
  nowPosition = {-1, -1}
  weMoving = false
  theClock = clock.run(ticker)
  clockPosition = 0
  tick = 1
  -- offset for entire track +- in 192ths
  trackTiming = {0,0,0,0}
  sampleView = false
  
  --add a samples
  file = {}
  file[1] = _path.dust.."audio/common/purpDrums/Kick.wav"
  file[2] = _path.dust.."audio/common/808/808-SD.wav"
  file[3] = _path.dust.."audio/common/808/808-CH.wav"
  file[4] = _path.dust.."audio/common/808/808-CP.wav"

    -- clear buffer
  softcut.buffer_clear()
  -- read file into buffer
  -- buffer_read_mono (file, start_src, start_dst, dur, ch_src, ch_dst)
  for i=0,3,1 do
    softcut.buffer_read_mono(file[i+1],0,i,-1,1,1)
    -- enable voice 1
    softcut.enable(i,1)
    -- set voice 1 to buffer 1
    softcut.buffer(i,1)
    -- set voice 1 level to 1.0
    softcut.level(i,1.0)
    -- voice 1 disable loop
    softcut.loop(i,0)
    softcut.loop_start(i,i)
    softcut.loop_end(i,i+0.2)
    -- set voice 1 rate to 1.0
    softcut.rate(i,1.0)
    -- enable voice 1 play
    softcut.play(i,0)
  end
  
  
  for i = 1, 3 do
--    norns.encoders.set_sens(i, 16)
--    counters:reset_enc(i)
  end
  
  -- ready!
  redraw()
end

--tick along, play events
function ticker()
  while isPlaying do
    --loop clock
    if (clockPosition > 768) then clockPosition = 0 end
    --check if it's time for an event
    for i, data in ipairs(trackEvents) do
      if (data[1] ~= nil and data[2] ~= nil and data[3] ~= nil and data[4] ~=nil) then
        --offset by track offset
        local localTick = clockPosition - trackTiming[data[3]+1]
        --check we're not out of bounds
        if localTick > 768 then localTick = 0 + trackTiming[data[3]+1]
        else if localTick < 0 then localTick = 768 + trackTiming[data[3]+1] end 
        end
        --finally, play an event?
        if (localTick == math.floor(768 * (data[1]))) then
          softcut.position(data[3],data[3])
          --set dynamic level
          softcut.level(data[3],data[4])
          softcut.play(data[3],1)
        end
      end
    end
    --limit redraw
    --change this to not be tied to tempo!
    if (math.floor(clockPosition % 24) == 0) then redraw() end
    --tick
    clockPosition = clockPosition + tick
    --wait
    clock.sync(1/192)
  end
end

function callback(file) 
  print(file)  
end

function drawEvents()
--draws a bright box for each of the events in trackEvents, so you can see what you're doing!
  for i, data in ipairs(trackEvents) do
    if (data[1] ~= nil and data[2] ~= nil and data[3] ~= nil and data[4] ~= nil) then
      local x = editArea.border + math.floor(0.5 + editArea.width * data[1])
      local y = editArea.border + data[3] * editArea.trackHeight 
      local w = math.floor(0.5 + editArea.width * data[2])
      local h = editArea.trackHeight
      local dynamic = math.floor(data[4] * 15)
      screen.level(dynamic)
      screen.rect(x, y, w, h)
      screen.fill() 
      -- plus a nice little line for the onset
      screen.level(0)
      screen.rect(x, y, 1, h)
      screen.fill()
    end
  end
end

function drawSequencer()
  -- squares... 
  --a dim background
  screen.level(1)
  --  screen.rect(editArea.border, editArea.border, editArea.width, editArea.height)
  --  screen.fill()
  --dither
  --  screen.level(0)
  for i=0, editArea.height - 1, 1 do
    for j=0, editArea.width - 1, 2 do
      screen.pixel(j + 4 + (i%2),i + 4)
    end
  end
  screen.fill()
  --track sel
  screen.level(4)
--  screen.rect(editArea.border, editArea.border + editArea.trackHeight * currentTrack, editArea.width, editArea.trackHeight)
  for i=editArea.border + editArea.trackHeight * currentTrack, editArea.border + editArea.trackHeight + editArea.trackHeight * currentTrack - 1, 1 do
    for j=4, editArea.width + editArea.border - 1, 2 do
      screen.pixel(j + i%2, i)
    end
  end
  --time select
--  screen.rect(editArea.border + ((beatCursor - 1) * (editArea.width / resolutions[segmentLength])), editArea.border, math.max(editArea.width / resolutions[segmentLength],1), editArea.height)
  for i=editArea.border, editArea.border + editArea.height - 1, 1 do
    for j=editArea.border + ((beatCursor - 1) * (editArea.width / resolutions[segmentLength])), editArea.border + ((beatCursor - 1) * (editArea.width / resolutions[segmentLength])) + editArea.width / resolutions[segmentLength] - 1, 2 do
      screen.pixel(j + i%2, i)
    end
  end
  screen.fill()
  --crossover, where track and time selections meet
  screen.level(6)
--  screen.rect(editArea.border + ((beatCursor - 1) * (editArea.width / resolutions[segmentLength])), editArea.border + editArea.trackHeight * currentTrack, math.max(editArea.width / resolutions[segmentLength],1), editArea.trackHeight)
  for i=editArea.border + editArea.trackHeight * currentTrack, editArea.border + editArea.trackHeight * currentTrack + editArea.trackHeight - 1 do
    for j=editArea.border + ((beatCursor - 1) * (editArea.width / resolutions[segmentLength])), editArea.border + ((beatCursor - 1) * (editArea.width / resolutions[segmentLength])) + editArea.width / resolutions[segmentLength] - 1, 2 do
      screen.pixel(j + i%2, i)
    end
  end
  screen.fill()
  --events
  drawEvents()
  --play head line, position updated by and taken from ticker() 
  screen.level(0)
  screen.rect(editArea.border + (clockPosition / 768) * editArea.width, editArea.border, 1, editArea.height)
  screen.fill()
  
  --guides, little dots to demarcate bar lines and track lines
  screen.level(0)
  for beat=0, 3, 1 do
    for track=0, tracksAmount, 1 do
      screen.pixel(editArea.border + beat * (editArea.width / 4), editArea.border + track * editArea.trackHeight)
    end
  end
  screen.fill()
  
  --a play/stop icon, to visualise play state
  screen.level(10)
  if (isPlaying == true) then
    screen.move(0,60)
    screen.line(0,64)
    screen.line(4,62)
    screen.close()
    else screen.rect(0,60,4,4)
  end
  screen.fill()
  
  -- text labels
  --what track
  screen.move(107,5)
  screen.text("trk " .. currentTrack + 1)
  --shifting?
  if heldKeys[1] then
    screen.level(8)
    for i=1, tracksAmount, 1 do
      screen.move(editArea.border - 2 + editArea.width / 2, editArea.border + i * editArea.trackHeight - 4)
      screen.text(trackTiming[i])
      screen.move(116, 63)
      screen.text(currentDynamic)
    end
    else do
      --position
      screen.level(15)
      screen.move(80, 63)
      screen.text(beatCursor)
      -- divison
      screen.move(98,63)
      screen.text("/")
      --length
      screen.move(116, 63)
      screen.text(resolutions[segmentLength])
    end
  end
end

function drawSampler()
  screen.level(15)
  screen.move(107,5)
  screen.text("trk " .. currentTrack + 1)
end

function redraw()
  screen.clear()
  
  if sampleView then drawSampler()
  else drawSequencer() end

  screen.update()
end

function moveEvent(i,e,d)
--takes event number, encoder num and turn amount, and moves events
    if (e == 1) then
    --move event to a different track
      trackEvents[i][3] = util.clamp(currentTrack + d, 0, tracksAmount - 1)
    end
    if (e == 2) then
    -- move in time
      local length = 1 / (resolutions[segmentLength])
      --at some point,an algo for 'is there an event in the way'
      -- will it go out of bounds?
      if (trackEvents[i][1] + trackEvents[i][2] + d * length <= 1 and trackEvents[i][1] + d * length >= 0) then
        trackEvents[i][1] = trackEvents[i][1] + d * length
      end
    end
end

function enc(e, d)
  --SHIFTED
  if (heldKeys[1]) then
    if (e == 2) then
      trackTiming[currentTrack +1] = trackTiming[currentTrack +1] + d
    end
    if (e == 3) then
      -- test for position, adjust note dynamic
      local position = (beatCursor - 1) / (resolutions[segmentLength])
      local length = 1 / (resolutions[segmentLength])
      currentDynamic = util.clamp(currentDynamic + d/50, 0.1, 1.0)
      for i=#trackEvents, 1, -1 do
      --is event under cursor?
        if (position >= trackEvents[i][1] and position < trackEvents[i][1] + trackEvents[i][2] and currentTrack == trackEvents[i][3]) then
          --yes
          currentDynamic = trackEvents[i][4]
          trackEvents[i][4] = util.clamp(currentDynamic + d/50, 0.1, 1.0)
        else if (trackEvents[i][1] >= position and trackEvents[i][1] < position + length and currentTrack == trackEvents[i][3]) then
          currentDynamic = trackEvents[i][4]
          trackEvents[i][4] = util.clamp(currentDynamic + d/50, 0.1, 1.0)
        end
        end
      end
    end
  end
  
  --if we're holding k3 to move
  if (heldKeys[3] == true) then
    weMoving = true
    local position = (beatCursor - 1) / (resolutions[segmentLength])
    local length = 1 / (resolutions[segmentLength])
    for i=#trackEvents, 1, -1 do
      --is event under cursor?
      if (position >= trackEvents[i][1] and position < trackEvents[i][1] + trackEvents[i][2] and currentTrack == trackEvents[i][3]) then
        --yes
        moveEvent(i,e,d)
        else if (trackEvents[i][1] >= position and trackEvents[i][1] < position + length and currentTrack == trackEvents[i][3]) then
          moveEvent(i,e,d)
        end
      end
    end
  end

  --track select
  if (e == 1 and not heldKeys[1]) then
    currentTrack = util.clamp(currentTrack + d, 0, tracksAmount - 1)
  end
  
  --cursor
  if (e == 2 and not heldKeys[1]) then
    beatCursor = util.clamp(beatCursor + d, 1, resolutions[segmentLength])
  end
  
  --segment Length
  if (e == 3 and not heldKeys[1] and not heldKeys[3]) then
    local beatCursorThen = (beatCursor - 1) / resolutions[segmentLength]
    
    segmentLength = util.clamp(segmentLength + d, 1, #resolutions)

    -- round up beatCursor
    beatCursor = math.floor(math.min(1. + beatCursorThen * resolutions[segmentLength]), resolutions[segmentLength])
  end
  
  redraw()
end

function key(k, z)
  
  heldKeys[k] = z == 1
  if (k == 3 and z == 1 and not sampleView) then
    nowPosition[1] = beatCursor
    nowPosition[2] = currentTrack
  end

  --play/stop
  if (heldKeys[1] and k == 2 and z == 0) then
    if (isPlaying) then
      isPlaying = false
      clockPosition = 0
    else
      isPlaying = true
      clock.run(ticker)
    end
  else if (k == 2 and z == 0) then sampleView = not sampleView end
  end
  
  --add and remove events
  if (k == 3 and z == 0 and nowPosition[1] == beatCursor and nowPosition[2] == currentTrack and not sampleView) then
    local position = (beatCursor - 1) / (resolutions[segmentLength])
    local length = 1 / (resolutions[segmentLength])
    local track = currentTrack
    local foundOne = 0
    
    --check for clashes, and delete event
    if (#trackEvents > 0 and trackEvents[1][1] ~= nil) then
      for i=#trackEvents, 1, -1 do
        if (position >= trackEvents[i][1] and position < trackEvents[i][1] + trackEvents[i][2] and currentTrack == trackEvents[i][3] and not weMoving) then
          table.remove(trackEvents[i])
          foundOne = 1
          else if (trackEvents[i][1] >= position and trackEvents[i][1] < position + length and currentTrack == trackEvents[i][3] and not weMoving) then
            table.remove(trackEvents[i])
            foundOne = 1
          end
        end
      end
    end
    if (foundOne == 0 and not weMoving) then
      table.insert(trackEvents, {position, length, track, currentDynamic}) 
    end
    weMoving = false
  end
  
  if (k == 3 and z == 0 and sampleView) then
    fs.enter(dust, callback)
  end

  redraw()
end
