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

function copy_samples(ch, start, interval, samples)
  print("rendering a single track samples for track " .. currentTrack + 1)
  for i = 1, editArea.width, 1 do
    waveform.samples[i + currentTrack * editArea.width] = samples[i]
  end
  print("done rendering waveforms")
  screenDirty = true
  waveform.isLoaded[currentTrack + 1] = true
end

function init_params()
  params:add_separator('Conant Gardens')
  params:add_number('tracksAmount', 'Number of Tracks', 1, 8, 4)
  params:set_action('tracksAmount', tracksAmount_update)
  params:add_number('beatsAmount', 'Number of Beats', 1, 16, 8)
  params:set_action('beatsAmount', function(x) beatsAmount = x
    totalBeats = 192*beatsAmount end )
  params:add_group('track_timings', 'track timings', 8)
  for i=1, 8, 1 do
    params:add_number('trackTiming_'..i, 'track timing '..i)
--[[    params:set_action('trackTiming_'..i, function(x)
        trackTiming[i] = x
      end
    )]]
  end
  params:add_group('track_samples', 'track samples', 8)
  for i=1, 8, 1 do
    currentTrack = i-1
    local file = "cancel"
    params:add{
      type = "file",
      id = "sample_"..i,
      name = "sample "..i,
      path = _path.audio,
      action = function(file) 
        weLoading = true
	      print("loading a file onto track " .. currentTrack + 1)
        load_file(file)
      end
    }
  end
  -- here, we set our PSET callbacks for save / load:
  params.action_write = function(filename,name,number)
    os.execute("mkdir -p "..norns.state.data.."/"..number.."/")
    tab.save(trackEvents,norns.state.data.."/"..number.."/notes.data")
    print("finished writing '"..filename.."'", number)
  end
  params.action_read = function(filename,silent,number)
    trackEvents = note_data -- send this restored table to the sequins
    note_data = tab.load(norns.state.data.."/"..number.."/notes.data")
    noteEvents = note_data -- send this restored table to the sequins
    print("finished reading '"..filename.."'", number)
  end
  params.action_delete = function(filename,name,number)
    norns.system_cmd("rm -r "..norns.state.data.."/"..number.."/")
    print("finished deleting '"..filename, number)
  end
  params:bang()
end

function loadPattern()
  trackEvents = tab.load(_path.data.."/conantgardens/beat01.txt")
end

function savePattern()
  tab.save(trackEvents,_path.data.."/conantgardens/beat01.txt")
end


--tick along, play events
function ticker()
  while isPlaying do
    --loop clock
    if (clockPosition > totalBeats) then clockPosition = 0 end
    --check if it's time for an event
    for i, data in ipairs(trackEvents) do
      --if there's an event to check
      if (data[4] ~=nil) then
        --offset track playhead position by track offset
        local localTick = clockPosition - trackTiming[data[3]+1]
        --check we're not out of bounds
        if localTick > totalBeats then localTick = 0 - trackTiming[data[3]+1]
        else if localTick < 0 then localTick = totalBeats - trackTiming[data[3]+1] end
        end
        --finally, play an event?
        if (localTick == math.floor(totalBeats * (data[1]))) then
          softcut.position(data[3]+1,data[3]+1)
          --set dynamic level
          softcut.level(data[3]+1,data[4])
          softcut.play(data[3]+1,1)
        end
      end
    end
    --tick
    clockPosition = clockPosition + tick
    --wait
    clock.sync(1/192)
    if clockPosition % 16 == 0 then screenDirty = true end
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

function sleeper()
  clock.sleep(1)
  weIniting = false
end

function init()
  --weIniting = true
  weLoading = false
  --inits
  redraw_clock_id = clock.run(redraw_clock)
  editArea = {width=120, height=56, border=4}
  --global x and y - tracks and beats to sequence:
  --todo make params
  tracksAmount = 8
  function tracksAmount_update(new)
    tracksAmount = new
    editArea.trackHeight = editArea.height / tracksAmount
  end
  beatsAmount = 8
  totalBeats = 192 * beatsAmount
  --params
  init_params()
  --end params
  currentTrack = 0
  --start with cursor set to 8th notes:
  segmentLength = 6
  resolutions = {1,2,3,4,6,8,12,16,24,32,48,64,96,128,192}
  beatCursor = 1
  -- structure: [position, length, track, dynamic] 
  trackEvents = {}
  currentDynamic = 1.0
  --drawing stuff
  editArea.trackHeight = editArea.height / tracksAmount
  heldKeys = {false, false, false}
  nowPosition = {-1, -1}
  isPlaying = false
  weMoving = false
  weMoved = false
  movingEvents = {}
  weFilling = false
  fillStart = nil
  fillEnd = nil
  theClock = clock.run(ticker)
  clockPosition = 0
  tick = 1
  -- offset for entire track +- in 192ths
  trackTiming = {}
  for i=1, 8, 1 do trackTiming[i] = 0 end
  sampleView = false
  softcut.event_render(copy_samples)
  waveform = {}
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
  
  --add samples
  file = {}
  
  -- clear buffer
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

  -- ch, start, duration, number of samples to make
  --softcut.render_buffer(1,0,4,editArea.width)

  currentTrack = 0
  
  screenDirty = true

end

function load_file(file,track)
  if file ~= "cancel" then
    print("loading a file on track "..currentTrack+1 ..": "..file)
    --get file info
    local ch, length, rate = audio.file_info(file)
    --get length and limit to 1s
    local lengthInS = length * (1 / rate)
    if lengthInS > 1 then lengthInS = 1 end
    if waveform then
      waveform.length[currentTrack] = lengthInS
    end
    -- erase section of buffer
    softcut.buffer_clear_region(currentTrack+1, 1, 0, 0)
    --load file into buffer (file, start_source, start_destination, duration, channel_source, channel_destination, preserve, mix)
    softcut.buffer_read_mono(file, 0, currentTrack+1, lengthInS, 1, 1, 0)
    --read samples into waveformSamples (eventually) (channel, start, duration, samples)
    softcut.render_buffer(1,currentTrack+1,1,editArea.width + 1)
    --update param
    params:set("sample_"..currentTrack+1,file,0)
  end
  weLoading = false
end

function drawEvents()
--draws a bright box for each of the events in trackEvents, so you can see what you're doing!
  for i, data in ipairs(trackEvents) do
    if (data[4] ~= nil and data[3] < tracksAmount) then
      local x = editArea.border + math.floor(editArea.width * data[1])
      local y = editArea.border + data[3] * editArea.trackHeight 
      local w = math.floor(editArea.width * data[2])
      local h = editArea.trackHeight
      local dynamic = math.floor(data[4] * 15)
      screen.level(dynamic)
      --check whether the current event index is being moved, and if so, MAKE IT BLACK
      for j=#movingEvents, 1, -1 do
        if movingEvents[j] == i then
          screen.level(1)
        end
      end
      screen.rect(x, y, w, h)
      screen.fill() 
      -- plus a nice little line for the onset
      screen.level(0)
      screen.rect(x, y, 1, h)
      screen.fill()
    end
  end
end

function addRemoveEvents()
  local barFraction = beatsAmount / 4
  local position = (beatCursor - 1) / (resolutions[segmentLength] * barFraction)
  local length = 1 / (resolutions[segmentLength] * barFraction)
  local track = currentTrack
  local foundOne = 0
  
  --check for clashes, and delete event
  -- structure: [position, length, track, dynamic] 
  if #trackEvents > 0 then
    for i=#trackEvents, 1, -1 do
      if (trackEvents[i][4] ~= nil and position >= trackEvents[i][1] and position < trackEvents[i][1] + trackEvents[i][2] and currentTrack == trackEvents[i][3]) then
        table.remove(trackEvents[i])
        foundOne = 1
        else if (trackEvents[i][4] ~= nil and trackEvents[i][1] >= position and trackEvents[i][1] < position + length and currentTrack == trackEvents[i][3]) then
          table.remove(trackEvents[i])
          foundOne = 1
        end
      end
    end
    screenDirty = true
  end
  if (foundOne == 0 and not weMoving) then
    table.insert(trackEvents, {position, length, track, currentDynamic})
    screenDirty = true
  end
end

function drawSequencer()
  -- squares... 
  --a dim background
  screen.level(1)
  screen.rect(editArea.border, editArea.border, editArea.width, editArea.height)
  screen.fill()
  --track sel
  screen.level(2)
  screen.rect(editArea.border, editArea.border + editArea.trackHeight * currentTrack, editArea.width, editArea.trackHeight)
  --time select
  screen.rect(
    editArea.border + (editArea.width / beatsAmount) * (4 / resolutions[segmentLength]) * (beatCursor - 1),
    editArea.border,
    (editArea.width / beatsAmount) * (4 / resolutions[segmentLength]),
    editArea.height)
  screen.fill()
  --crossover, where track and time selections meet
  screen.level(6)
  screen.rect(
    editArea.border + (editArea.width / beatsAmount) * (4 / resolutions[segmentLength]) * (beatCursor - 1),
    editArea.border + editArea.trackHeight * currentTrack,
    (editArea.width / beatsAmount) * (4 / resolutions[segmentLength]),
    editArea.trackHeight)
  screen.fill()
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
  --play head line, position updated by and taken from ticker() 
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
  
  --shifting?
  if heldKeys[1] then
    screen.level(8)
    screen.move(0, 62)
    if isPlaying then screen.text("stop") else screen.text("play") end
    for i=1, tracksAmount, 1 do
      screen.move(editArea.border - 2 + editArea.width / 2 + trackTiming[i] / 8, editArea.border + i * editArea.trackHeight -1)
      if trackTiming[i] > 0 then
        screen.text("+"..trackTiming[i])
      else screen.text(trackTiming[i]) end
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
      -- swap page
      screen.move(0, 62)
      screen.text("spl")
      if weMoving then
        screen.move(18, 62)
        screen.text("holding")
      end
    end
  end

  --what track
  screen.move(107,5)
  screen.text("trk " .. currentTrack + 1)
  
end

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
	else
	   screen.move(64,34)
	   screen.text_center("K3 to load sample")
	end
	screen.move(20,62)
	screen.text("load")
	screen.fill()
	
	-- text labels
  screen.level(15)
	--track label
  screen.move(107,5)
  screen.text("trk " .. currentTrack + 1)
  --"seq"
  screen.move(0,62)
  screen.text("seq")
end

function redraw()
  screen.clear()
  
  if weIniting then
    --wait for proper render
    --clock position to hold?
    screen.clear()
    screen.move(64, 34)
    screen.text_center("loading...")
    clock.run(sleeper)
  else
  
  if sampleView then drawSampler()
  else drawSequencer() end
  
  --a play/stop icon, to visualise play state
  screen.level(10)
  if (isPlaying == true) then
    screen.move(0,0)
    screen.line(0,4)
    screen.line(4,2)
    screen.close()
    else screen.rect(0,0,4,4)
  end
  --else end
  end
  screen.fill()

  screen.update()

end

function moveEvent(i,e,d)
--takes event number, encoder number and turn amount, and moves events
  if (e == 1) then
  --move event to a different track
    local movedTrack = util.clamp(currentTrack + d, 0, tracksAmount - 1)
    trackEvents[i][3] = movedTrack
    weMoved = true
  end
  if (e == 2) then
  -- move in time
    local length = 1 / (resolutions[segmentLength] * beatsAmount / 4)
    --at some point,an algo for 'is there an event in the way'
    -- will it go out of bounds?
    if (trackEvents[i][1] + trackEvents[i][2] + d * length <= 1 and trackEvents[i][1] + d * length >= 0) then
      --offset position in time by the cursor length
      trackEvents[i][1] = trackEvents[i][1] + d * length
      weMoved = true  
    end
  end
end

function doFill(s,e)
  print("wouldfill. start: "..s..". End: "..e)
end

function enc(e, d)
  --SHIFTING??
  if (heldKeys[1]) then
    if sampleView then
      --sample view shift behaviour
    else
      if (e == 2) then
        trackTiming[currentTrack +1] = trackTiming[currentTrack +1] + d
        screenDirty = true
      end
      if (e == 3) then
        -- test for position, adjust note dynamic
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
  
  --if we're holding k3 to move
  if weMoving and #movingEvents > 0 then
    for i=#movingEvents, 1, -1 do
      moveEvent(movingEvents[i],e,d)
    end
    screenDirty = true
  end

  --track select
  if (e == 1 and not heldKeys[1]) then
    currentTrack = util.clamp(currentTrack + d, 0, tracksAmount - 1)
    screenDirty = true
  end
  
  --cursor
  if (e == 2 and not heldKeys[1]) then
    beatCursor = math.floor(util.clamp(beatCursor + d, 1, resolutions[segmentLength] * beatsAmount/4))
    screenDirty = true
  end
  
  --segment Length
  if (e == 3 and not heldKeys[1] and not heldKeys[3]) then
    local beatCursorThen = (beatCursor - 1) / resolutions[segmentLength]
    
    segmentLength = util.clamp(segmentLength - d, 1, #resolutions)

    -- round up beatCursor
    beatCursor = math.floor(math.min(1. + beatCursorThen * resolutions[segmentLength]), resolutions[segmentLength])
    screenDirty = true
  end
  
  --if sampleView or not isPlaying then
    --screenDirty = true
  --end

  --screenDirty = true

end

function key(k, z)
  
  heldKeys[k] = z == 1
  
  -- holding k3 to move events
  if (heldKeys[3] and not sampleView) then
    --store initial position to check that we actually move something. Because if we don't, we'll add/remove an event
    nowPosition[1] = beatCursor
    nowPosition[2] = currentTrack

    --store decimal values for the cursor start/end (event positions are stored decimally)
    local selectposition = (beatCursor - 1) / (resolutions[segmentLength] * (beatsAmount / 4))
    local selectlength = 1 / (resolutions[segmentLength] * (beatsAmount / 4)) - (1/192)
    if selectlength < 1/192 then selectlength = 1/192 end

    --look through all the track events to see whether each one is under the cursor, and add the event index to a table if so
    for i=#trackEvents, 1, -1 do
      --if the event hasn't been deleted
      if trackEvents[i][4] ~= nil then
        --store a friendly event end point
        local eventEnd = trackEvents[i][1] + trackEvents[i][2]
        if (currentTrack == trackEvents[i][3] and selectposition < eventEnd and selectposition >= trackEvents[i][1]) then
          --yes
          weMoving = true
          table.insert(movingEvents,i)
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
    if (isPlaying) then
      isPlaying = false
      clockPosition = 0
      screenDirty = true
    else
      isPlaying = true
      clock.run(ticker)
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
		fileselect.enter(_path.audio,load_file)
	end
  
  if (k == 3 and z == 0 and not sampleView) then
    if not weMoved then addRemoveEvents() end
    weMoving = false
    if weMoved then 
      weMoved = false
      movingEvents = {}
    end
  end

end

function cleanup() --------------- cleanup() is automatically called on script close
  clock.cancel(redraw_clock_id) -- melt our clock vie the id we noted
end
