#!/usr/bin/env lua

---------------------------------------------------------------------
-- Miscellaneous helper functions.
---------------------------------------------------------------------

-- This function returns a table key, value iterator for the object
-- `obj`. Unlike `spairs`, this iterator will return the keys in a
-- sort order, rather than in a hash table order (non-deterministic).
function spairs(obj)
  -- Retrieve all the keys and stable-sort them.
  local keys = {}
  for k,_ in pairs(obj) do
    keys[#keys+1] = k
  end
  table.sort(keys)
  -- Return an iterator.
  local i = 1
  return function()
    if keys[i] ~= nil then
      local k = keys[i]
			i = i + 1
			return k, obj[k]
    else
      return nil
    end
  end
end

-- Checks, whether the `number` is within `range`, where
-- `range` is a comma-separated list of numeric ranges,
-- such as: 1,5,16-20,32. For `range` of *, the function
-- returns always true.
local function in_range(number, range)
  if range == "*" then return true end
  for expr in range:gmatch("([^, ]+)") do
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

-- Computes a median of an array `arr`.
local function median(arr)
  table.sort(arr)
  return arr[(#arr+1)/2-(#arr+1)/2%1]
end

-- Serializes an `object` into a `file`.
function serialize(file, object)
  if type(object) == "string" then
    file:write(string.format("%q", object))
  elseif type(object) == "table" then
    file:write("{\n")
    for k,v in spairs(object) do
      file:write(" [")
      serialize(file, k)
      file:write("] = ")
      serialize(file, v)
      file:write(",\n")
    end
    file:write("}\n")
  else
    file:write(object)
  end
end

-- Deserializes an object out of a `string`.
function deserialize(string)
  return assert(load("return " .. string))()
end

---------------------------------------------------------------------
-- The debugging and logging functions.
---------------------------------------------------------------------

-- Print a debug message.
local function debug(...)
  -- io.stderr:write(table.concat({...}, ", ") .. "\n")
end

-- Print a log message.
local function log(...)
  io.stderr:write(table.concat({...}, ", "))
end

---------------------------------------------------------------------
-- The `add_track` function.
---------------------------------------------------------------------

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

---------------------------------------------------------------------
-- The `create_transition_mesh` function and helper functions.
---------------------------------------------------------------------

-- Convert a context string into a tuple of `Note_on_c` commands.
local function context_str_to_note_ons(context_str)
  -- Parse the source node context into an array of commands.
  local context = {}
  for line in context_str:gmatch('([^\n]+)') do
    if line ~= "<<Nothing>>" then
      local raw_command = {}
      for column in line:gmatch("([^, ]+)") do
        raw_command[#raw_command+1] = column
      end
      context[#context+1] = raw_command
    end
  end
  -- Drop any messages beside `Note_on_c` and fix the timing.
  local accumulator = 0
  local i = 1
  while i <= #context do
    local raw_command = context[i]
    if raw_command[2] == "Note_on_c" then
      -- Create an associative table for each command.
      context[i] = {
        delay = assert(tonumber(raw_command[1], 10)) + accumulator,
        channel = assert(tonumber(raw_command[3], 10)),
        note = assert(tonumber(raw_command[4], 10)),
        velocity = assert(tonumber(raw_command[5], 10)) }
      accumulator = 0
      i = i + 1
    else
      table.remove(context, i)
      accumulator = accumulator + assert(tonumber(raw_command[1], 10))
    end
  end
  return context
end

-- Parse a metric options string `str` and return an options object for the
-- note_on_similarity and note_ons_similarity functions.
local function parse_note_on_options(str)
  local array = {}
  local length = 0
  -- Parse the string.
  for val in str:gmatch("([^:, ]+)") do
    array[length+1] = (val and val ~= "" and val ~= "-" and val) or nil
    length = length+1
  end
  -- Construct the options table.
  local methods = {
    add = function(a,b) return a+b end,
    mul = function(a,b) return a*b end,
    min = function(a,b) return math.min(a,b) end,
    max = function(a,b) return math.max(a,b) end }
  local options = {}
  options._note_on_reduce = array[1] or "mul" -- An annotation
  options.note_on_reduce = methods[options._note_on_reduce]
  options._note_ons_reduce = array[2] or "add" -- An annotation
  options.note_ons_reduce = methods[options._note_ons_reduce]

  -- Parse a `ADD+COEFF` string stored in `array[i]` into ADD and COEFF. Store
  -- `ADD` in `options[name .. "_add"]` and `COEFF` in `options[name .. "_coeff"]`.
  local function parse_add_coeff(i, name)
    if array[i] and array[i]:match("+") then
      options[name .. "_add"] = assert(tonumber(array[i]:match("^.-+"):
        gsub("+$", "")))
      options[name .. "_coeff"] = assert(tonumber(array[i]:match("+.*$"):
        gsub("^+", "")))
    else
      options[name .. "_add"] = 0
      options[name .. "_coeff"] = (array[i] and assert(tonumber(array[i]))) or 1
    end
  end

  parse_add_coeff(3, "delay")
  parse_add_coeff(4, "channel")
  parse_add_coeff(5, "note")
  parse_add_coeff(6, "velocity")
  return options
end

-- Reduce a non-empty array `arr` using a function `f`.
local function reduce(f, arr)
  local accumulator = arr[1]
  for i = 2,#arr do
    accumulator = f(accumulator, arr[i])
  end
  return accumulator
end

-- Measure the similarity between two `Note_on_c` commands `A` and `B` based also
-- on the maximum delay time `max_delay` and the passed `options`.
local function note_on_similarity(A, B, max_delay, options)
  local delay_similarity = 1 - math.pow(A.delay - B.delay, 2) / (max_delay*max_delay)
  local channel_similarity = 0 -- The channel similarity is binary.
  if A.channel == B.channel then
    channel_similarity = 1
  end
  local note_dist = math.pow((A.note - B.note)%12, 2) -- Disregard the octaves.
  local note_similarity = 1 - (-math.abs(note_dist-(6*6))+(6*6)) / (6*6)
  local velocity_similarity = 1 - math.abs(A.velocity - B.velocity) / (127*127)
  return reduce(options.note_on_reduce, {
    options.delay_add + options.delay_coeff * delay_similarity,
    options.channel_add + options.channel_coeff * channel_similarity,
    options.note_add + options.note_coeff * note_similarity,
    options.velocity_add + options.velocity_coeff * velocity_similarity })
end

-- Measure the similarity between two same-sized `Note_on_c` command tuples `A`
-- and `B` based also on the maximum delay time `max_delay` and the passed
-- `options`.
local function note_ons_similarity(A, B, max_delay, options)
  local similarities = {}
  for i=1,#A do
    similarities[#similarities+1] = note_on_similarity(A[i], B[i], max_delay, options)
  end
  return reduce(options.note_ons_reduce, similarities) or 0
end

-- Create a random transition mesh on top of a Markov chain using the passed
-- `options` that are intended to be passed to the note_on_similarity function.
-- `progress` is a callback function for reporting the amount of work done.
local function create_transition_mesh(prob, options, progress)

  -- This function increments and reports the progress.
  local done = 0
  function increment_progress() 
      done = done + 1
      if progress then
        progress(done / (3 * prob.total * (prob.total-1)))
      end
  end

  local mesh = {}
  local max_delay=0
  -- For all spairs of Markov chain nodes, construct `Note_on_c` message arrays.
  for source_str,_ in spairs(prob) do if source_str ~= "total" then
    local source = context_str_to_note_ons(source_str)
    -- Compute the maximum delay time.
    for i=1,#source do
      if source[i].delay > max_delay then
        max_delay = source[i].delay
      end
    end
    -- Create an array of egress edges.
    mesh[source_str] = { }
    for target_str,_ in spairs(prob) do if target_str ~= "total" and target_str ~= source_str then
      increment_progress()
      local source = source
      local target = context_str_to_note_ons(target_str)
      -- Cut the left tail of the longer of the two message arrays.
      if #source ~= #target then
        local longer
        local shorter
        local cutoff = {}
        if #source > #target then
          longer = source
          shorter = target
        else
          longer = target
          shorter = source
        end
        assert(#shorter == math.min(#source, #target))
        assert(#longer == math.max(#source, #target))
        for i = #longer-#shorter+1,#longer do
          cutoff[#cutoff+1] = longer[i]
        end
        assert(#cutoff == math.min(#source, #target))
        if #source > #target then
          source = cutoff
        else
          target = cutoff
        end
        assert(#source == #target and #target == #cutoff)
      end
      assert(#source == #target)
      -- Store the two note-on command tuples.
      mesh[source_str][target_str] = { source, target }
    end end
  end end
  -- Compute the mesh from the stored `Note_on_c` command tuples and the
  -- computed maximum delay time.
  local edges = 0
  local vertices = 0
  local max = 0
  for source_str,_ in spairs(mesh) do
    vertices = vertices + 1
    -- Compute the similarity between the `Note_on_c` command tuples.
    mesh[source_str].total = 0
    for target_str,_ in spairs(mesh[source_str]) do if target_str ~= "total" then
      increment_progress()
      local tuples = mesh[source_str][target_str]
      local similarity = note_ons_similarity(tuples[1], tuples[2], max_delay, options)
      if similarity > 0 then
        mesh[source_str][target_str] = similarity
        mesh[source_str].total = mesh[source_str].total + similarity
        edges = edges + 1
      else
        increment_progress()
        mesh[source_str][target_str] = nil
      end
    end end
    max = math.max(max, mesh[source_str].total)
  end
  -- Clamp the weights to <0; 1>.
  for source_str,_ in spairs(mesh) do
    mesh[source_str].total = { type = "<0;1>", value = (max > 0 and
      mesh[source_str].total / max) or 0 }
    assert(mesh[source_str].total.value <= 1 and mesh[source_str].total.value >= 0)
    for target_str,_ in spairs(mesh[source_str]) do if target_str ~= "total" then
      increment_progress()
      mesh[source_str][target_str] = (max > 0 and mesh[source_str][target_str] / max) or 0
    end end
  end
  return mesh, vertices, edges
end

---------------------------------------------------------------------
-- The `generate_a_track` function and helper functions.
---------------------------------------------------------------------

-- Returns a random key and value out of `table` under the assumption that
-- the array contains the total key with the total weight of all table
-- entries, and the value of each table entry is its weight.
local function pick_random(table)
  local throw
  if type(table.total) == "table" and table.total.type == "<0;1>" then
    throw = math.random() * table.total.value
    assert(throw >= 0 and throw < table.total.value)
  else
    throw = math.random(table.total)
    assert(throw > 0 and throw <= table.total)
  end
  local accumulator = 0
  local lastkv
  for k,v in spairs(table) do if k ~= "total" then
    accumulator = accumulator + v
    lastkv = k,v
    if accumulator >= throw then
      return lastkv
    end
  end end
  return lastkv
end

-- Generates a random track based on the probability table `prob`, whose key
-- length is `context_len`. The track is hard-trimmed at `maxlen` to prevent
-- infinite tracks. The `damping` factor specifies the likelyhood that an
-- ordinary random step will be made instead of random transitions. If the
-- `damping` factor is less than one, the `mesh` graph will be used for
-- random transitions.
local function generate_a_track(maxlen, prob, context_len, damping, mesh)
  local context = {}
  -- Fill the left context with `<<Nothing>>`s.
  for i=1,context_len do
    context[#context+1] = "<<Nothing>>"
  end
  -- Create a track.
  local track = {}
  for i=1,maxlen do
    -- Build the context string.
    local context_str = ""
    for j=1,context_len do
      context_str = context_str .. context[j] .. "\n"
    end
    if i > 1 and damping < 1 then
      -- If we're not standing at the beginning of the track, throw the dice
      -- and decide, whether to make an ordinary step ...
      local throw = math.random()
      local acc = 0
      if throw * mesh[context_str].total.value > damping then -- ... or a random transition.
        debug("Hop from <<" .. context_str .. ">> to ")
        context_str = pick_random(mesh[context_str])
        debug("<<" .. context_str .. ">>.\n")
        context = {}
        for line in context_str:gmatch('([^\n]+)') do
          context[#context+1] = line
        end
      end
    end
    -- Randomly pick the next line.
    local line = pick_random(prob[context_str])
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

---------------------------------------------------------------------
-- The main routine.
---------------------------------------------------------------------

-- Check that we have enough parameters.
if #arg < 7 then
  os.exit(1)
end

-- Seed the random number generator.
local seed = (arg[6] == "-" and os.time()) or assert(tonumber(arg[6], 10))
math.randomseed(seed)
log("The RNG has been seeded with the value of " .. seed .. ".\n")

-- Load the songs.
local songs = { }
for i = 7,#arg do
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
  local ratio = (song.tempo / mean_tempo) * (mean_divisions / song.divisions)
  debug("Normalizing tempo: " .. song.tempo .. " -> " .. mean_tempo)
  debug("Normalizing divisions: " .. song.divisions .. " -> " .. mean_divisions)
  debug("Ratio: " .. ratio)
  for j = 1,#song.tracks do
    local track = song.tracks[j]
    for k = 1,#track do
      local line = track[k]
      local timestamp = tonumber(line:match("^%-?%d+"), 10) -- Normalize the timestamp.
      timestamp = timestamp * ratio
      timestamp = timestamp - timestamp % 1
      local new_line = line:gsub("^%-?%d+", tostring(timestamp))
      debug("Timestamp: " .. line .. " -> " .. new_line)
      track[k] = new_line
    end
  end
end

-- Try to load the markov chain and the transition mesh out of a file.
local context_len = tonumber(arg[1]) or 3
local damping = tonumber(arg[3]) or 1
local cache_filename = arg[5]
local cache_file = (cache_filename ~= "-" and io.open(cache_filename, "r")) or nil
local cache_string = (cache_file and cache_file:read("*a")) or ""
local prob, mesh, cache
if cache_string ~= "" then
  log("Loading the Markov chain out of the file " .. cache_filename .. " ...\n")
  cache = assert(deserialize(cache_string))
  prob = cache.prob
  mesh = cache.mesh
  cache_file:close()
else
  -- Create a Markov chain over the tracks.
  prob = {}
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

  -- If damping is enabled, compute a transition mesh over the Markov chain.
  mesh = { }
  if damping < 1 then
    log("Creating a random transition mesh")
    local options = parse_note_on_options(arg[4] or "-")
    -- Write out the options.
    local arr = {}
    for k,v in spairs(options) do
      if type(v) ~= "table" and type(v) ~= "function" then
        arr[#arr+1] = k:gsub("^_*", "") .. " = " .. v
      end
    end
    log(" with the options of { " .. table.concat(arr, ", ") .. " } ... (0 %)")
    -- Compute the mesh.
    local string_length = #("( %)") + 1
    local mesh_result, mesh_vertices, mesh_edges = create_transition_mesh(prob,
      options, function(progress)
        progress = progress * 100
        log("\27[" .. string_length .. "D(" .. progress .. " %)\27[K")
        string_length = #("( %)") + #tostring(progress)
      end)
    log("\27[" .. string_length .. "D(" .. mesh_edges .. " edges over " ..
      mesh_vertices .. " vertices – " .. math.ceil(mesh_edges / (mesh_vertices *
      (mesh_vertices-1)) * 100) .. "% density)\n")
    mesh = mesh_result
  end

  -- Serialize the markov chain and the mesh.
  if cache_filename ~= "-" then
    log("Storing the Markov chain into the file " .. cache_filename .. " ...\n")
    cache_file = assert(io.open(cache_filename, "w"))
    serialize(cache_file, { prob = prob, mesh = mesh })
    cache_file:close()
  end
end

-- Generate a track via a random walk.
local maxlen = tonumber(arg[2]) or 1e309
log("Making a random walk with the maximum of " .. maxlen .. " cmds and with an " ..
  ((1-damping)*100) .. "% chance of making a random transition instead of a random step ...")
local track = generate_a_track(maxlen, prob, context_len, damping, mesh)
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
