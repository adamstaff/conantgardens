-- Conant Gardens v0.0.1
-- Dilla time for norns
--
-- based on the work of 
-- Roger Linn, Akai,
-- Dan Charnas, and 
-- James Dewitt Yancey
--
-- K1: Hold for shift
-- K2: Toggle page
--
-- In Sequence View:
-- E1: Select Track
-- E2: Select position
-- E3: Select division
-- K3: Add / remove notes
-- -- Hold K3 to move notes
-- shift+E1: Change tempo
-- shift+E2: Track timing
-- shift+E3: Note dynamic
-- shift+K2: Play/Stop
-- shift+K3: Fill notes
--
-- In Sample View
-- E1: Select track
-- E2: Sample start
-- E3: Sample end
-- K3: Load sample
-- shift+E1: Sample volume
-- shift+E2: S.Start fine
-- shift+E3: S.End fine
-- shift+K2: Play/Stop
-- shift+K3: Play sample

util = require "util"
fileselect = require "fileselect"

function init_params()
  params:add_separator('Conant Gardens')
  params:add_number('tracksAmount', 'number of tracks', 1, 6, 4)
  params:set_action('tracksAmount', tracksAmount_update)
  params:add_number('beatsAmount', 'number of beats', 1, 16, 8)
  params:set_action('beatsAmount', function(x) beatsAmount = x
    totalTicks = 192*x end )
  params:add_group('track_volumes', 'track volumes', 6)
  for i=1, 6, 1 do
    params:add_number('trackVolume_'..i, 'track volume '..i, -96,6,0, function(param) return param:get() .."dB" end)
  end
  params:add_group('track_pans', 'track pans', 6)
  for i=1, 6, 1 do
    params:add_number('trackPan_'..i, 'track pan '..i, -1.0,1.0,0.0, function(param) return param:get() end)
    params:set_action('trackPan_'..i, function(x) softcut.pan(i,x) end)
  end
  params:add_group('track_rates', 'track rates', 6)
  for i=1, 6, 1 do
    params:add_number('trackRate_'..i, 'track rate '..i, -10.0,10.0,1.0, function(param) return param:get() .."x" end)
    params:set_action('trackRate_'..i, function(x) softcut.rate(i,x) end)
  end
  params:add_group('track_timings', 'track timings', 6)
  for i=1, 6, 1 do
    params:add_number('trackTiming_'..i, 'track timing '..i)
  end
  params:add_group('track_samples', 'track samples', 6)
  -- sample file locations
  for i=1, 6, 1 do
    local file = "cancel"
    params:add{
      type = "file",
      id = "sample_"..i,
      name = "sample "..i,
      path = _path.audio,
      action = function(file)
        if not weIniting then
          weLoading = true
          load_file(file, i)
        end
      end
    }
  end
  params:add_group('sample_starts_ends', 'sample starts/ends', 12)
  -- sample start/end points
  for i=1, 6, 1 do
  	params:add_number('sampStart_'..i, 'sample '..i..' start', 0.0,10.0,0.0)
  	params:set_action('sampStart_'.. i, function(x) softcut.loop_start(i, (i-1) * softcutSampleLength + x) end)
  	params:add_number('sampEnd_'..i, 'sample '..i..' end',0.0,10.1,1.0)
	  params:set_action('sampEnd_'.. i, function(x) softcut.loop_end(i, (i-1) * softcutSampleLength + x) end)
  end

  -- here, we set our PSET callbacks for save / load:
  params.action_write = function(filename,name,number)
    os.execute("mkdir -p "..norns.state.data.."/"..number.."/")
    tab.save(trackEvents,norns.state.data.."/"..number.."/notes.data")
    print("finished writing '"..filename.."'", number)
  end
  params.action_read = function(filename,silent,number)
    note_data = tab.load(norns.state.data.."/"..number.."/notes.data")
    trackEvents = note_data -- send this restored table to the sequins
    print("finished reading '"..filename.."'", number)
    -- reload waveforms
    for i=1, tracksAmount, 1 do
      redraw_sample(i)
    end
  end 
  params.action_delete = function(filename,name,number)
    norns.system_cmd("rm -r "..norns.state.data.."/"..number.."/")
    print("finished deleting '"..filename, number)
  end
  params:bang()
end

function init()
  weLoading = false
  weIniting = true
  currentTrack = 1
  redraw_clock_id = clock.run(redraw_clock)
  music_clock_id = clock.run(ticker)
  editArea = {width=120, height=56, border=4}
  softcutSampleLength = 10
  init_params()
  --global x and y - tracks and beats to sequence:
  editArea.trackHeight = editArea.height / params:get('tracksAmount')
  totalTicks = 192 * params:get('beatsAmount')
  trackEvents = {}
  --cursor stuff
  segmentLength = 6
  resolutions = {1,2,3,4,6,8,12,16,24,32,48,64,96,128,192}
  beatCursor = 1
  currentDynamic = 1.0
  heldKeys = {false, false, false}
  nowPosition = {-1, -1}
  isPlaying = false
  weMoving = false
  weMoved = false
  movingEvents = {}
  weFilling = false
  weFilled = false
  sampleView = false
  softcut.event_render(copy_samples)
  waveform = {}
  waveform.isLoaded = {false, false, false, false, false, false, false, false}
  waveform.samples = {}
  waveform.channels = {}
  waveform.length = {}
  waveform.rate = {}
  
  --add samples
  file = {}
  
  -- clear buffer
  softcut.buffer_clear()
  for i=1, 6, 1 do
    -- enable voices
    softcut.enable(i,1)
    -- set voices to buffer 1
    softcut.buffer(i,1)
    -- set voices level to 1.0
    softcut.level(i,1.0)
    softcut.level_slew_time(i,0)
    softcut.pan(i,0)
    -- voices disable loop
    softcut.loop(i,0)
    softcut.loop_start(i, (i - 1) * softcutSampleLength)
    softcut.loop_end(i, i * softcutSampleLength)
    softcut.position(i,i - 1)
    -- set voices rate to 1.0 and no fade
    softcut.rate(i, params:get('trackRate_'..i))
    softcut.fade_time(i,0)
    -- disable voices play
    softcut.play(i,0)
  end

	--clock stuff
  clockPosition = 0
  tick = 1

  weIniting = false
  screenDirty = true
end

function copy_samples(ch, start, length, samples)
  start = math.floor(start / 10) + 1
  for i = 1, editArea.width, 1 do
    waveform.samples[i + start * editArea.width] = samples[i]
  end
  waveform.isLoaded[start] = true
  screenDirty = true
end

function redraw_sample(track)
  if track then
    softcut.render_buffer(1, (track-1)*10 + params:get('sampStart_'..track), params:get('sampEnd_'..track) - params:get('sampStart_'..track), editArea.width + 1)
  end
end

function load_file(file,track)
  if file and file ~= "cancel" then
    if not track then track = currentTrack end
    --get file info
    local ch, length, rate = audio.file_info(file)
    --get length and limit to 1s
    local lengthInS = length * (1 / rate)
    if lengthInS > softcutSampleLength then lengthInS = softcutSampleLength end
    --set start/end play positions
    params:set('sampStart_'..track, 0)
    params:set('sampEnd_'..track, lengthInS)
    if waveform then
      waveform.length[track-1] = lengthInS
    end
    -- erase section of buffer -- required?
    softcut.buffer_clear_region((track - 1) * softcutSampleLength, softcutSampleLength, 0, 0)
    --load file into buffer (file, start_source, start_destination, duration, channel_source, channel_destination, preserve, mix)
    softcut.buffer_read_mono(file, 0, (track - 1) * softcutSampleLength, lengthInS, 1, 1, 0)
    --read samples into waveformSamples (channel)
    redraw_sample(track)
    --update param
    params:set("sample_"..track,file,0)
  end
  weLoading = false
end

function play(track, level)
  if not level then level = 1.0 end
  --todo add option for MIDI here --
	-- put the softcut playhead in position (voice, position)
	softcut.position(track, (track - 1) * softcutSampleLength + params:get('sampStart_'.. track))
  --set dynamic level
  softcut.level(track, level * 10^(params:get('trackVolume_'..track) / 20))
	-- play from position to softcut.loop_end
  softcut.play(track, 1)
end

function ticker()
  while true do
    if isPlaying then
      --loop clock
      if (clockPosition > totalTicks) then clockPosition = 0 end
      --check if it's time for an event
      local barsAmount = beatsAmount / 4
      for i, data in ipairs(trackEvents) do
        --if there's an event to check
        if (data[4] ~=nil) then
          --offset track playhead position by track offset
          local localTick = clockPosition - params:get('trackTiming_'..data[3])
          --check we're not out of bounds
          if localTick > totalTicks then localTick = 0 - params:get('trackTiming_'..data[3])
          else if localTick < 0 then localTick = totalTicks - params:get('trackTiming_'..data[3]) end
          end
          --finally, play an event?
          if (localTick == math.floor(totalTicks * (data[1]) / barsAmount)) and data[3] <= tracksAmount then
  	        play(data[3], data[4])
          end
        end
      end
      --tick
      clockPosition = clockPosition + tick
      --wait
      if clockPosition % 4 == 0 then screenDirty = true end
    end
  clock.sync(1/192)
  end
end

function tracksAmount_update(new)
	tracksAmount = new
	editArea.trackHeight = editArea.height / tracksAmount
end

function addRemoveEvents()
  -- generate local values:
  local barFraction = beatsAmount / 4
  -- the left edge of the cursor
  local position = (beatCursor - 1) / (resolutions[segmentLength] * barFraction) * barFraction
  -- the length of the cursor
  local length = 1 / (resolutions[segmentLength] * barFraction) * barFraction
  local track = currentTrack
  local foundOne = 0
  
  --check for clashes, and delete event
  -- structure: [position, length, track, dynamic] 
  if #trackEvents > 0 then
    for i=#trackEvents, 1, -1 do
	  -- check if the start of the cursor is inside the event
      if (trackEvents[i][4] ~= nil and position >= trackEvents[i][1] and position < trackEvents[i][1] + trackEvents[i][2] and currentTrack == trackEvents[i][3]) then
        table.remove(trackEvents[i])
        foundOne = 1
        -- check if the end of the cursor is inside the event
        else if (trackEvents[i][4] ~= nil and trackEvents[i][1] >= position and trackEvents[i][1] < position + length and currentTrack == trackEvents[i][3]) then
          table.remove(trackEvents[i])
          foundOne = 1
        end
      end
    end
    screenDirty = true
  end
  --actually add a note
  if (foundOne == 0 and not weMoving) then
    table.insert(trackEvents, {position, length, track, currentDynamic})
    screenDirty = true
  end
end

function drawEvents()
  local barsAmount = beatsAmount / 4
--draws a bright box for each of the events in trackEvents, so you can see what you're doing!
  for i, data in ipairs(trackEvents) do
    -- check there's a note, and it's not on too high a track
    if (data[4] ~= nil and data[3] <= tracksAmount) then
      local x = editArea.border + util.round(editArea.width * (data[1] / barsAmount), 1)
      local y = editArea.border + (data[3] - 1) * editArea.trackHeight 
      local w = math.floor((editArea.width * data[2]) / barsAmount)
      local h = editArea.trackHeight
      local dynamic = math.floor(data[4] * 15)
      screen.level(dynamic)
      --check whether the current event index is being moved, and if so, MAKE IT BLACK
      for j=#movingEvents, 1, -1 do
        if movingEvents[j] == i then
          screen.level(1)
        end
      end
      --draw the event
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
  screen.rect(editArea.border, editArea.border, editArea.width, editArea.height)
  screen.fill()
  --track sel
  screen.level(2)
  screen.rect(editArea.border, editArea.border + editArea.trackHeight * (currentTrack - 1), editArea.width, editArea.trackHeight)
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
    editArea.border + editArea.trackHeight * (currentTrack - 1),
    (editArea.width / beatsAmount) * (4 / resolutions[segmentLength]),
    editArea.trackHeight)
  screen.fill()
  --events
  drawEvents()
  --a bright line around the selection
  if not heldKeys[1] then
    screen.level(15)
    local leftEdge = editArea.border + (editArea.width / beatsAmount) * (4 / resolutions[segmentLength]) * (beatCursor - 1)
    local width = (editArea.width / beatsAmount) * (4 / resolutions[segmentLength]) + 0.5
    if weFilling then
      leftEdge = editArea.border + (editArea.width / beatsAmount) * (4 / resolutions[segmentLength]) * (nowPosition[1] - 1)
	    width = ((editArea.width / beatsAmount) * (4 / resolutions[segmentLength])) * (1 + beatCursor - nowPosition[1])
    	if nowPosition[1] > beatCursor then
    	  width = ((editArea.width / beatsAmount) * (4 / resolutions[segmentLength])) * (1 + fillStart - beatCursor)
    		leftEdge = editArea.border + (editArea.width / beatsAmount) * (4 / resolutions[segmentLength]) * (beatCursor - 1)
    	end
    end
    screen.rect(
      leftEdge,
      editArea.border + editArea.trackHeight * (currentTrack - 1),
      width,
      editArea.trackHeight + 1
    )
    screen.stroke()
  end
  screen.aa(0)
  --play head line, position updated by and taken from ticker() 
  local playheadX = editArea.border + util.round((clockPosition / totalTicks) * editArea.width, 1)
  screen.level(15)
  screen.move(playheadX, 0)
  screen.line(playheadX, editArea.border)
  screen.move(playheadX, editArea.border + editArea.height)
  screen.line(playheadX, 64)
  screen.stroke()
  screen.level(3)
  for i=1, tracksAmount, 1 do
    screen.move(playheadX - params:get('trackTiming_'..i) / 12, editArea.border + editArea.trackHeight * (i-1))
    screen.line(playheadX - params:get('trackTiming_'..i) / 12, editArea.border + editArea.trackHeight * (i))
  end
  screen.stroke()
  screen.aa(0)
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
    screen.level(15)
    screen.move(0, 62)
    if isPlaying then screen.text("stop") else screen.text("play") end
    screen.level(0)
    for i=1, tracksAmount, 1 do
      screen.move(editArea.border - 2 + editArea.width / 2 + params:get('trackTiming_'..i) / 4, editArea.border + i * editArea.trackHeight -1)
      if params:get('trackTiming_'..i) > 0 then
        screen.text("+"..params:get('trackTiming_'..i))
      else screen.text(params:get('trackTiming_'..i)) end
    end
    screen.level(15)
    screen.move(116, 63)
    screen.text(currentDynamic)
    screen.move(127,5)
    local tempo = params:get("clock_tempo")
    screen.text_right(tempo.."bpm")
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
      if weFilling then
        screen.move(18, 62)
        screen.text("filling")
      end
      --what track
      screen.move(127,5)
      screen.text_right("trk " .. currentTrack)
    end
  end
end

function drawSampler()
	--background
	screen.level(1)
	screen.rect(editArea.border, editArea.border, editArea.width, editArea.height)
	screen.fill()
	--waveform
	screen.level(15)
	if waveform.isLoaded[currentTrack] then
  	for i=1, editArea.width - 1, 1 do
  	  screen.move(i+editArea.border, editArea.border  + editArea.height * 0.5 + waveform.samples[(currentTrack) * editArea.width + i] * editArea.height * 0.5)
	    screen.line(i+editArea.border, editArea.border  + editArea.height * 0.5 + waveform.samples[(currentTrack) * editArea.width + i] * editArea.height * -0.5)
	    screen.stroke()
  	end
	else
	   screen.move(64,34)
	   screen.text_center("K3 to load sample")
	end
	screen.fill()
	
	-- text labels
  screen.level(15)
	--track label
  screen.move(107,5)
  screen.text("trk " .. currentTrack)
  if heldKeys[1] then
    -- db
    screen.move(127,62)
    screen.text_right(params:get('trackVolume_'..currentTrack)..'dB')
    screen.move(64,62)
    screen.text_center(util.round(params:get('trackRate_'..currentTrack), 0.01)..'x')
    screen.move(0,62)
    screen.text(util.round(params:get('trackPan_'..currentTrack), 0.01))
  else
    --"seq"
    screen.move(0,62)
    screen.text("seq")
    screen.move(20,62)
  	screen.text("load") 
  end
end

function redraw()
  screen.clear()
  
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
  screen.fill()

  screen.update()

end

function redraw_clock() ----- a clock that draws space
  while true do ------------- "while true do" means "do this forever"
    clock.sleep(1/60) ------- pause for a fifteenth of a second (aka 15fps)
    if screenDirty and not weLoading then ---- only if something changed
      redraw() -------------- redraw space
      screenDirty = false -- and everything is clean again
    end
  end
end

function moveEvent(i,e,d)
--takes event number, encoder number and turn amount, and moves events
  if (e == 1) then
  --move event to a different track
    local movedTrack = util.clamp(currentTrack + d, 1, tracksAmount)
    trackEvents[i][3] = movedTrack
    weMoved = true
  end
  if (e == 2) then
    local barsAmount = beatsAmount / 4
  -- move in time
    local length = 1 / (resolutions[segmentLength] * beatsAmount / 4)
    local nudgeamount = d * length * barsAmount
    --TODO at some point, an algo for 'is there an event in the way'
    -- if so, nudgeamount = 0
    -- will it go out of bounds?
    if (trackEvents[i][1] + trackEvents[i][2] + nudgeamount <= barsAmount and trackEvents[i][1] + nudgeamount >= 0) then
      --offset position in time by the cursor length
      trackEvents[i][1] = trackEvents[i][1] + nudgeamount
      weMoved = true
    end
  end
end

function doFill(s,e)
  local barsAmount = beatsAmount / 4
  if s>e then
    local tempS = s
    s = e
    e = tempS
  end
  s=s-1
  e=e-1
  lengthD = 1 / (resolutions[segmentLength] * barsAmount)
  for i = s, e, 1 do
    table.insert(trackEvents, {lengthD * barsAmount * i, lengthD, currentTrack, currentDynamic})
  end
  screenDirty = true
end

function enc(e, d)
  --SHIFTING??
  if (heldKeys[1]) then
    if sampleView then
      --sample view shift behaviour
      if e == 1 then
      	params:set('trackPan_'..currentTrack, params:get('trackPan_'..currentTrack) + d/100)
      end
      if e == 2 then
        params:set('trackRate_'..currentTrack, params:get('trackRate_'..currentTrack) + d / 100)
      end
      if e == 3 then
        params:set('trackVolume_'..currentTrack, params:get('trackVolume_'..currentTrack) + d)
      end
    else
      -- sequence view shift behaviour
      if e == 1 then
        params:set("clock_tempo", params:get("clock_tempo") + d)
      end
      if (e == 2) then
        params:set('trackTiming_'..currentTrack, params:get('trackTiming_'..currentTrack) + d)
      end
      if (e == 3) then
        -- test for position, adjust note dynamic
        local position = ((beatCursor - 1) / (resolutions[segmentLength] * beatsAmount / 4)) * beatsAmount / 4
        local length = 1 / (resolutions[segmentLength])
        currentDynamic = util.clamp(currentDynamic + d/50, 0.1, 1.0)
        for i=#trackEvents, 1, -1 do
        --is event under cursor?
          if trackEvents[i][4] ~= nil then
            local eventEnd = trackEvents[i][1] + trackEvents[i][2]
            if (currentTrack == trackEvents[i][3] and position < eventEnd and position >= trackEvents[i][1]) 
            or (currentTrack == trackEvents[i][3] and trackEvents[i][1] >= position and trackEvents[i][1] < position + length) then
                currentDynamic = trackEvents[i][4]
                trackEvents[i][4] = util.clamp(currentDynamic + d/50, 0.1, 1.0)
            end
          end
        end
      end
    end
  end
  
  --if we're holding k3 to move
  if (weMoving and #movingEvents > 0) then
    for i=#movingEvents, 1, -1 do
      moveEvent(movingEvents[i],e,d)
    end
  end

  --track select
  if (e == 1 and not heldKeys[1]) then
    currentTrack = util.clamp(currentTrack + d, 1, tracksAmount)
  end
  
  --cursor
  if (e == 2 and not heldKeys[1]) then
    if sampleView then
      params:set('sampStart_'..currentTrack, params:get('sampStart_'..currentTrack) + (d/1000))
      redraw_sample(currentTrack) 
    else
      beatCursor = math.floor(util.clamp(beatCursor + d, 1, resolutions[segmentLength] * beatsAmount/4))
    end
    if weFilling then
      weFilled = true
    end
  end
  
  --segment Length
  if (e == 3 and not heldKeys[1] and not heldKeys[3]) then
    if sampleView then
      params:set('sampEnd_'.. currentTrack, params:get('sampEnd_'.. currentTrack) + (d/1000))
      redraw_sample(currentTrack)
    else
    local beatCursorThen = (beatCursor - 1) / resolutions[segmentLength]
    segmentLength = util.clamp(segmentLength - d, 1, #resolutions)

    -- round up beatCursor
    beatCursor = math.floor(math.min(1. + beatCursorThen * resolutions[segmentLength]), resolutions[segmentLength])
    end
  end

  screenDirty = true

end

function key(k, z)
  
  heldKeys[k] = z == 1
  
  -- holding k3 to move events
  if (heldKeys[3] and not sampleView) then
    --store initial position to check that we actually move something. Because if we don't, we'll add/remove an event
    nowPosition[1] = beatCursor
    nowPosition[2] = currentTrack
    local barsAmount = beatsAmount / 4

    --store decimal values for the cursor start/end (event positions are stored decimally)
    local selectposition = ((beatCursor - 1) / (resolutions[segmentLength] * barsAmount)) * barsAmount
    local selectlength = barsAmount / (resolutions[segmentLength] * barsAmount) - (1/192)
    if selectlength < 1/192 then selectlength = 1/192 end

    --look through all the track events to see whether each one is under the cursor, and add the event index to a table if so
    for i=#trackEvents, 1, -1 do
      --if the event hasn't been deleted
      if trackEvents[i][4] ~= nil then
        --store a friendly event end point
        local eventEnd = trackEvents[i][1] + trackEvents[i][2]
        if (currentTrack == trackEvents[i][3] and selectposition < eventEnd and selectposition >= trackEvents[i][1]) or (currentTrack == trackEvents[i][3] and trackEvents[i][1] >= selectposition and trackEvents[i][1] < selectposition + selectlength) then
          weMoving = true
          table.insert(movingEvents,i)
        end
      end
    end
    if not weMoving then
      weFilling = true
      fillStart = nowPosition[1]
    end
  end

  --play/stop
  if (heldKeys[1] and k == 2 and z == 0) then
    if (isPlaying) then
      isPlaying = false
      clockPosition = 0
    else
      isPlaying = true
    end
    else if (k == 2 and z == 0) then 
      sampleView = not sampleView 
    end
  end

  -- load sample
	if sampleView and k == 3 and z == 0 and not heldKeys[1] then
	  weLoading = true
		fileselect.enter(_path.audio,load_file)
	end
	
	if sampleView and k==3 and z==1 and heldKeys[1] then
	  play(currentTrack)
	end
  
  --release K3
  if (k == 3 and z == 0 and not sampleView) then
    if not weMoved then addRemoveEvents() end
    if weFilled and weFilling then 
      doFill(nowPosition[1], beatCursor)
    else
      movingEvents = {}
    end
    weMoving = false
    weMoved = false
    weFilling = false
    weFilled = false
  end
  
  screenDirty = true

end

function cleanup() --------------- cleanup() is automatically called on script close
  clock.cancel(redraw_clock_id) -- melt our clocks via the ids we noted
  clock.cancel(music_clock_id)
end
