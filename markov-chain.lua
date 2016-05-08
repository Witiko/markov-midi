#!/usr/bin/env lua
-- Print a debug message.
local function debug(...)
  -- io.stderr:write(table.concat({...}, ", ") .. "\n")
end

-- Print a log message.
local function log(...)
  io.stderr:write(table.concat({...}, ", "))
end

-- Updates probability table `prob` using `track` as the input track and
-- `context_len` as the key length. `weight` is the weight of the new
-- edges added into the Markov chain.
local function add_track(track, prob, context_len, weight)
  local context = {}
  -- Fill the left context with `<<Nothing>>`s.
  for i=1,context_len do
    context[#context+1] = "<<Nothing>>"
  end
  -- Append the rest of `track` to the left context.
  for i=1,#track do
    context[#context+1] = track[i]
  end
  -- Iterate over the `song`.
  for i=1,#track+1 do
    -- Built the context string.
    local context_str = ""
    for j=i,i+context_len-1 do
      context_str = context_str .. context[j] .. "\n"
    end
    -- Update the `table`.
    if prob[context_str] == nil then
      prob.total = (prob.total or 0) + 1
      prob[context_str] = {}
    end
    local line = track[i] or "\n"
    prob[context_str][line] = (prob[context_str][line] or 0) + weight
    prob[context_str].total = (prob[context_str].total or 0) + weight
  end
end

-- Returns a random key and value out of `table` containing `nr_of_keys` keys,
-- while skipping any elements that are accepted by the `skip_predicate`.
-- Each element k,v has weight `weight(k, v)`.
local function pick_random(table, nr_of_keys, skip_predicate, weight)
  local throw = math.random(nr_of_keys)
  local acc = 0
  for k,v in pairs(table) do
    if skip_predicate(k,v) then goto skip end
    acc = acc + weight(k,v)
    if acc >= throw then
      return k,v
    end
    ::skip::
  end
end

-- Generates a random track based on the probability table `prob`, whose key
-- length is `context_len`. The track is hard-trimmed at `maxlen` to prevent
-- infinite tracks. The `damping` factor specifies the likelyhood that an
-- ordinary random step will be made instead of a teleportation.
local function generate_a_track(maxlen, prob, context_len, damping)
  local context = {}
  -- Fill the left context with `<<Nothing>>`s.
  for i=1,context_len do
    context[#context+1] = "<<Nothing>>"
  end
  -- Create a track.
  local track = {}
  for i=1,maxlen do
    if i > 1 then
      -- If we're not standing at the beginning of the track, throw the dice
      -- and decide, whether to make an ordinary step ...
      local throw = math.random()
      local acc = 0
      if throw > damping then -- ... or teleport to a random node.
        context_str = pick_random(prob, prob.total, function(k)
          return k == "total"
        end, function() return 1 end)
        context = {}
        for line in context_str:gmatch('([^\n]+)') do
          context[#context+1] = line
        end
      end
    end
    -- Build the context string.
    local context_str = ""
    for j=1,context_len do
      context_str = context_str .. context[j] .. "\n"
    end
    -- Randomly pick the next line.
    local line = pick_random(prob[context_str], prob[context_str].total,
      function(k) return k == "total" end, function(_,v) return v end)
    track[#track+1] = line
    -- If we've hit `\n`, then remove the newline and end prematurely.
    if track[#track] == "\n" then
      table.remove(track) -- Pop the `\n` from the end of the track.
      break
    end
    -- Shift the context.
    table.remove(context, 1)
    context[#context+1] = line
  end
  -- If we were cut prematurely, add the End_track line.
  if not track[#track]:match("End_track$") then
    track[#track+1] = "0, End_track"
  end
  -- Return the track.
  return track
end

-- Check that we have enough parameters.
if #arg < 4 then
  os.exit(1)
end

-- Checks, whether the `number` is within `range`, where
-- `range` is a comma-separated list of numeric ranges,
-- such as: 1,5,16-20,32. For `range` of *, the function
-- returns always true.
local function in_range(number, range)
  if range == "*" then return true end
  for expr in string.gmatch(range, "([^,]+)") do
    if expr:match("-") then -- Handle a range expression.
      local left = assert(tonumber(expr:match("^.*-"):gsub("-", ""), 10))
      local right = assert(tonumber(expr:match("-.*$"):gsub("-", ""), 10))
      local min = math.min(left, right)
      local max = math.max(left, right)
      if min <= number and number <= max then
        return true
      end
    else -- Handle an atomic number.
      local atom = assert(tonumber(expr, 10))
      if atom == number then
        return true
      end
    end
  end
  return false
end

-- Load the songs.
local songs = { }
for i = 4,#arg do
  -- Separate the filename from the track ranges and the weight coefficient.
  local filename = arg[i]
  local range = "*"
  local weight = 1
  if filename:match("^.*=") then
    range = filename:match("=[^=]*$"):gsub("^=", "")
    filename = filename:match("^.*="):gsub("=$", "")
  end
  if filename:match("~.*$") then
    weight = assert(tonumber(filename:match("^[^~]*~"):gsub("~$", ""), 10))
    filename = filename:match("~.*$"):gsub("^~", "")
  end
  -- Load the file contents.
  log("Loading file " .. filename .. " as song #" .. #songs+1 .. " ...\n")
  local file = assert(io.open(filename, "r"))
  local song = { tracks={}, weight=weight }
  local lines = { } -- The line buffer.
  local contains_notes = false -- Does the track contain any notes?
  for line in function()
    return file:read("*L")
  end do
    -- Check, whether the track contains notes.
    if line:find("^%d+, %d+, Note_on_c") or line:find("^%d+, %d+, Note_off_c") then
      contains_notes = true
    end
    -- Extract the tempo.
    if line:find("^%d+, 0, Tempo, ") then
      song.tempo = assert(tonumber(line:gsub("^%d+, 0, Tempo, ", ""):gsub("\n", ""), 10))
      debug("\nTempo:\n" .. song.tempo)
    end
    -- Extract the divisions.
    if line:find("^0, 0, Header, ") then
      song.divisions = assert(tonumber(line:gsub("^0, 0, Header, %d+, %d+, ", ""):gsub("\n", ""), 10))
      debug("\nDivisions:\n" .. song.divisions)
    end
    -- Record each line containing whitelisted commands:
    if line:match("^%d+, %d+, Note_on_c") or -- note presses
       line:match("^%d+, %d+, Note_off_c") or -- note releases
       line:match("^%d+, %d+, Program_c") or -- program changes
       line:match("^%d+, %d+, Start_track") or -- track start
       line:match("^%d+, %d+, End_track") then -- track end
      lines[#lines+1] = line:gsub("\n", "")
    end
    -- Extract the tracks containing notes.
    if line:find("End_track\n$") then
      local last_timestamp = 0
      if not contains_notes then goto skip end -- Check, whether this track contains notes.
      lines.track_num = assert(tonumber(line:match("^%d+"), 10))
      if not in_range(lines.track_num, range) then  -- Check, whether the user wants to add this track.
        goto skip
      end
      for i = 1,#lines do -- Normalize the track.
        local line = lines[i]
        -- Strip the track number.
        line = line:gsub("^%d+, ", "")
        -- Make timestamps relative.
        local next_timestamp = assert(tonumber(line:match("^%d+"), 10))
        line = line:gsub("^%d+", tostring(next_timestamp - last_timestamp))
        last_timestamp = next_timestamp
        lines[i] = line
      end
      song.tracks[#song.tracks+1] = lines
      debug("\nTrack #" .. (#song.tracks) .. ":\n" .. table.concat(song.tracks[#song.tracks], "\n"))
      ::skip::
      contains_notes = false
      lines = { }
    end
  end
  songs[#songs+1] = song
  assert(file:close())
end

-- Computes a median of an array.
local function median(arr)
  table.sort(arr)
  return arr[(#arr+1)/2-(#arr+1)/2%1]
end

-- Normalize the tempo.
log("Normalizing tempo and divisions ...\n")
local tempos = { }
local divisions = { }
for i = 1,#songs do
  tempos[#tempos+1] = songs[i].tempo
  divisions[#divisions+1] = songs[i].divisions
end
local mean_tempo = median(tempos)
local mean_divisions = median(divisions)
for i = 1,#songs do -- Normalize the songs.
  local song = songs[i]
  local ratio = (mean_tempo / song.tempo) * (mean_divisions / song.divisions)
  debug("Normalizing tempo: " .. song.tempo .. " -> " .. mean_tempo)
  debug("Normalizing divisions: " .. song.divisions .. " -> " .. mean_divisions)
  debug("Ratio: " .. ratio)
  for j = 1,#song.tracks do
    local track = song.tracks[j]
    for k = 1,#track do
      local line = track[k]
      local timestamp = tonumber(line:match("^%-?%d+"), 10) -- Normalize the timestamp.
      timestamp = timestamp / ratio
      timestamp = timestamp - timestamp % 1
      local new_line = line:gsub("^%-?%d+", tostring(timestamp))
      debug("Timestamp: " .. line .. " -> " .. new_line)
      track[k] = new_line
    end
  end
end

-- Create a Markov chain over the tracks.
local prob = {}
local context_len = tonumber(arg[1]) or 3
log("Creating a Markov chain with the left context of " .. context_len .. " cmds ...\n")
for i = 1,#songs do
  local song = songs[i]
  local weight = song.weight
  if weight > 0 then -- Add a track only if it has positive weight.
    for j = 1,#song.tracks do
      local track = song.tracks[j]
      log("Adding track #" .. track.track_num .. " of song #" .. i ..
        " (" .. #track .. " cmds) to the Markov chain with weight " .. weight .. " ...\n")
      add_track(track, prob, context_len, weight)
    end
  end
end

-- Generate a track via a random walk.
local maxlen = tonumber(arg[2]) or 1e309
local damping = tonumber(arg[3]) or 1
log("Making a random walk with the maximum of " .. maxlen .. " cmds ...")
local track = generate_a_track(maxlen, prob, context_len, damping)
log(" (" .. #track .. " cmds)\n")

-- Assemble a song from the generated track.
local song_str = "0, 0, Header, 1, 2, " .. mean_divisions .. -- Add the static header.
  "\n1, 0, Start_track\n1, 0, Tempo, " .. mean_tempo .. "\n1, 0, End_track"
local last_timestamp = 0
for i = 1,#track do -- Reassemble the track.
  local line = track[i]
  local next_timestamp
  if (i > 1 and line:match("%d+, Start_track")) or      -- Skip late `Start_track` messages,
     (i < #track and line:match("%d+, End_track")) then -- and early `End_track` messages.
      goto skip end
  -- Make timestamps absolute.
  next_timestamp = tonumber(line:match("^%-?%d+"), 10)
  last_timestamp = last_timestamp + next_timestamp
  line = line:gsub("^%-?%d+", tostring(last_timestamp))
  -- Add the track number.
  line = "2, " .. line
  song_str = song_str .. "\n" .. line
  ::skip::
end
song_str = song_str .. "\n0, 0, End_of_file"

print(song_str)
