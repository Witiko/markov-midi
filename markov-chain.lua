#!/usr/bin/env lua
-- Print a debug message.
local function debug(...)
  -- io.stderr:write(table.concat({...}, ", ") .. "\n")
end

-- Print a log message.
local function log(...)
  io.stderr:write(table.concat({...}, ", ") .. "\n")
end

-- Updates probability table `prob` using `track` as the input track and
-- `context_len` as the key length.
local function add_track(track, prob, context_len)
  local context = {}
  -- Fill the left context with `\n`s.
  for i=1,context_len do
    context[#context+1] = "\n"
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
      prob[context_str] = {}
    end
    local line = track[i] or "\n"
    prob[context_str][line] = (prob[context_str][line] or 0) + 1
    prob[context_str].total = (prob[context_str].total or 0) + 1
  end
end

-- Generates a random track based on the probability table `prob`, whose key
-- length is `context_len`. The track is hard-trimmed at `maxlen` to prevent
-- infinite tracks.
local function generate_a_track(maxlen, prob, context_len)
  local context = {}
  -- Fill the left context with `\n`s.
  for i=1,context_len do
    context[#context+1] = "\n"
  end
  -- Create a track.
  local track = {}
  for i=1,maxlen do
    -- Build the context string.
    local context_str = ""
    for j=1,context_len do
      context_str = context_str .. context[j] .. "\n"
    end
    -- Throw the dice and find the line we've hit.
    local throw = math.random(prob[context_str].total)
    local acc = 0
    local line
    for k,v in pairs(prob[context_str]) do
      if k == "total" then goto continue end
      acc = acc + v
      if acc >= throw then
        line = k
        track[#track+1] = line
        break
      end
      ::continue::
    end
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
if #arg < 3 then
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
for i = 3,#arg do
  -- Separate the filename from the track ranges.
  local filename = arg[i]
  local range = "*"
  if filename:match("^.*=") then
    range = filename:match("=[^=]*$"):gsub("^=", "")
    filename = filename:match("^.*="):gsub("=$", "")
  end
  -- Load the file contents.
  log("Loading file " .. filename .. " as song #" .. #songs+1 .. " ...")
  local file = assert(io.open(filename, "r"))
  local song = { tracks={} }
  local lines = { } -- The line buffer.
  local header_ended = false -- Are we already past the header (track 1)?
  for line in function()
    return file:read("*L")
  end do
    -- Skip the header.
    if line:find("^2, 0, Start_track\n$") then
      header_ended = true
    end
    -- Extract the tempo.
    if line:find("^1, 0, Tempo, ") then
      song.tempo = assert(tonumber(line:gsub("^1, 0, Tempo, ", ""):gsub("\n", ""), 10))
      debug("\nTempo:\n" .. song.tempo)
    end
    -- Extract the divisions.
    if line:find("^0, 0, Header, ") then
      song.divisions = assert(tonumber(line:gsub("^0, 0, Header, %d+, %d+, ", ""):gsub("\n", ""), 10))
      debug("\nDivisions:\n" .. song.divisions)
    end
    if header_ended then
      if not line:match("^%d+, %d+, Key_signature") and -- Ignore Key_signature commands,
         not line:match("^%d+, %d+, Pitch_bend_c")  and --         Pitch_bend_c commands,
         not line:match("^%d+, %d+, Control_c")    then --        and Control_c commands.
        lines[#lines+1] = line:gsub("\n", "")
      end
    end
    -- Extract the tracks starting with track 2.
    if header_ended and line:find("End_track\n$") then
      local last_timestamp = 0
      lines.track_num = assert(tonumber(line:match("^%d+"), 10))
      if not in_range(lines.track_num, range) then  -- Check, whether we want to add this track.
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
      -- Add the song number as the first line of the track, so that there is a
      -- binding between the song and the track within the Markov chain.
      table.insert(lines, 1, "Song number: " .. #songs+1)
      song.tracks[#song.tracks+1] = lines
      debug("\nTrack #" .. (#song.tracks) .. ":\n" .. table.concat(song.tracks[#song.tracks], "\n"))
      ::skip::
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
log("Normalizing tempo and divisions ...")
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
    for k = 2,#track do -- Skip the song number as the first line of the track.
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
for i = 1,#songs do
  local song = songs[i]
  for j = 1,#song.tracks do
    local track = song.tracks[j]
    log("Adding track " .. track.track_num .. " of song " .. i .. " to the Markov chain ...")
    add_track(track, prob, context_len)
  end
end

-- Generate a track via a random walk.
local maxlen = tonumber(arg[2]) or 1e309
log("Making a random walk ...")
local track = generate_a_track(maxlen, prob, context_len)

-- Assemble a song from the generated track.
local song = songs[tonumber(track[1]:gsub("^Song number: ", ""), 10)]
local song_str = "0, 0, Header, 1, 2, " .. mean_divisions .. -- Add the static header.
  "\n1, 0, Start_track\n1, 0, Tempo, " .. mean_tempo .. "\n1, 0, End_track\n"
table.remove(track, 1) -- Pop the song number as the first line of the track.
local last_timestamp = 0
for i = 1,#track do -- Reassemble the track.
  local line = track[i]
  -- Make timestamps absolute.
  local next_timestamp = tonumber(line:match("^%-?%d+"), 10)
  last_timestamp = last_timestamp + next_timestamp
  line = line:gsub("^%-?%d+", tostring(last_timestamp))
  -- Add the track number.
  line = "2, " .. line
  track[i] = line
end
song_str = song_str .. table.concat(track, "\n") .. "\n0, 0, End_of_file"

print(song_str)