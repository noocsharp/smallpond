-- parse
local em = 8

local Glyph = {
	["noteheadWhole"] = 0xE0A2,
	["noteheadHalf"] = 0xE0A3,
	["noteheadBlack"] = 0xE0A4,
	["flag8thDown"] = 0xE241,
	["flag8thUp"] = 0xE240,
	["accidentalFlat"] = 0xE260,
	["accidentalNatural"] = 0xE261,
	["accidentalSharp"] = 0xE262,
	["gClef"] = 0xE050,
	["fClef"] = 0xE062,
}

local Clef = {
	["treble"] = {
		glyph = Glyph.gClef,
		yoff = 3*em,
		defoctave = 4,
		place = function(char, octave)
			local defoctave = 4 -- TODO: how do we use the value above?
			local NOTES = "abcdefg"
			local s, _ = string.find(NOTES, char)
			return (octave - defoctave) * 7 + 2 - s
		end
	},
	["bass"] = {
		glyph = Glyph.fClef,
		yoff = em,
		defoctave = 3,
		place = function(char, octave)
			local defoctave = 3 -- TODO: how do we use the value above?
			local NOTES = "abcdefg"
			local s, _ = string.find(NOTES, char)
			return (octave - defoctave) * 7 + 4 - s
		end
	}
}

local numerals = {
	['0'] = 0xE080,
	['1'] = 0xE081,
	['2'] = 0xE082,
	['3'] = 0xE083,
	['4'] = 0xE084,
	['5'] = 0xE085,
	['6'] = 0xE086,
	['7'] = 0xE087,
	['8'] = 0xE088,
	['9'] = 0xE089
}

voice_commands = {
	staff = {
		parse = function(text, start)
			-- move past "\staff "
			start = start + 7
			local text = string.match(text, "(%a+)", start)
			return 7 + #text, {command="changestaff", name=text}
		end
	},
	clef = {
		parse = function(text, start)
			-- move past "\clef "
			start = start + 6
			if string.match(text, "^treble", start) then
				return #"\\clef treble", {command="changeclef", kind="treble"}
			elseif string.match(text, "^bass", start) then
				return #"\\clef bass", {command="changeclef", kind="bass"}
			else
				error(string.format("unknown clef %s", string.sub(text, start)))
			end
		end
	},
	time = {
		parse = function(text, start)
			-- move past "\time "
			start = start + 6
			local num, denom = string.match(text, "^(%d+)/(%d+)", start)
			if num == nil or denom == nil then
				error(string.format("bad time signature format"))
			end
			return #"\\time " + #num + #denom + 1, {command="changetime", num=num, denom=denom}
		end
	}
}

local voices = {}
local stafforder = {}

local commands = {
	voice = function (text, start)
		local parsenotecolumn = function(text, start)
			local s, e, flags, count, dot, beam = string.find(text, "^([v^]?)(%d*)(%.?)([%[%]]?)", start)
			local out = {}

			if string.find(flags, "v", 1, true) then
				out.stemdir = 1
			elseif string.find(flags, "^", 1, true) then
				out.stemdir = -1
			end

			if beam == '[' then
				out.beam = 1
			elseif beam == ']' then
				out.beam = -1
			end

			-- make sure that count is a power of 2
			if #count ~= 0 then
				assert(math.ceil(math.log(count)/math.log(2)) == math.floor(math.log(count)/math.log(2)), "note count is not a power of 2")
			end
			out.count = tonumber(count)
			out.dot = #dot == 1

			return start + e - s + 1, out
		end
		local parsenote = function(text, start)
			-- TODO: should we be more strict about accidentals and stem orientations on rests?
			local s, e, time, note, acc, shift = string.find(text, "^(%d*%.?%d*)([abcdefgs])([fns]?)([,']*)", start)
			if note then
				local out
				if note == 's' then
					out = {command='srest'}
				else
					out = {command="note", time=tonumber(time), note=note, acc=acc}
				end

				local _, down = string.gsub(shift, ',', '')
				local _, up = string.gsub(shift, "'", '')
				out.shift = up - down
				return start + e - s + 1, out
			end

			error("unknown token")
		end
		local i = start

		voice = {}
		while true do
			::start::
			i = i + #(string.match(text, "^%s*", i) or "")
			if i >= #text then return i end
			local cmd = string.match(text, "^\\(%a+)", i)
			if cmd == "end" then
				i = i + 4
				break
			end
			if cmd then
				local size, data = voice_commands[cmd].parse(text, i)
				i = i + size
				table.insert(voice, data)
				goto start
			end

			-- barline
			local s, e = string.find(text, "^|", i)
			if s then
				i = i + e - s + 1
				table.insert(voice, {command="barline"})
				goto start
			end

			-- grouping (grace or tuplet)
			local s, e, f = string.find(text, "^(%g*)%b{}", i)
			if s then
				local notes = {}
				local grace = false

				if string.find(f, 'g', 1, true) then
					grace = true
				end

				local tn, td = string.match(f, 't(%d+)/(%d+)', 1)
				assert(not not tn == not not td)
				if not tn then
					tn = 1
					td = 1
				end

				-- TODO: deal with notegroups
				i = i + #f + 1
				while i <= e - 2 do
					i = i + #(string.match(text, "^%s*", i) or "")
					if i >= #text then return i end
					i, note = parsenote(text, i)
					i, col = parsenotecolumn(text, i)
					table.insert(voice, {command="newnotegroup", count=col.count, stemdir=col.stemdir, beam=col.beam, dot=col.dot, tuplet=Q.new(td)/tn, grace=grace, notes={[1] = note}})
				end
				i = e + 1
				goto start
			end

			-- note column
			local s, e = string.find(text, "^%b<>", i)
			if s then
				i = i + 1
				local group = {command="newnotegroup", notes = {}}
				while i <= e - 1 do
					i = i + #(string.match(text, "^%s*", i) or "")
					if i >= #text then return i end
					i, out = parsenote(text, i)
					table.insert(group.notes, out)
				end
				i = e + 1
				i, out = parsenotecolumn(text, i)
				group.count = out.count
				group.stemdir = out.stemdir
				group.beam = out.beam
				group.dot = out.dot
				table.insert(voice, group)
				goto start
			end

			i, note = parsenote(text, i)
			i, col = parsenotecolumn(text, i)

			if note.command == 'srest' then
				table.insert(voice, {command='srest', count=col.count})
			else
				table.insert(voice, {command="newnotegroup", count=col.count, stemdir=col.stemdir, beam=col.beam, dot=col.dot, notes={[1] = note}})
			end
		end

		voices[#voices + 1] = voice
		return i
	end,
	layout = function (text, start)
		local i = start
		while true do
			::start::
			i = i + #(string.match(text, "^%s*", i) or "")
			if i >= #text then return i end
			local cmd = string.match(text, "^\\(%a+)", i)
			if cmd == 'end' then
				i = i + 4
				break
			end

			if cmd == 'staff' then
				i = i + 7
				local name = string.match(text, '^(%a+)', i)
				table.insert(stafforder, name)
				i = i + #name
				goto start
			end


			error('unknown token')
		end

		return i
	end
}

function parse(text)
	local i = 1

	while true do
		i = i + #(string.match(text, "^%s*", i) or "")
		if i >= #text then return nil end
		local cmd = string.match(text, "^\\(%a+)", i)
		if cmd then
			i = i + #cmd + 1
			i = commands[cmd](text, i)
		end
	end
end

f = assert(io.open("score.sp"))
parse(f:read("*a"))

local time = Q.new(0)
local octave = 0
local clef = Clef.treble
local lastnote = nil
local staff1 = {}
local points = {}
local pointindices = {}

function point(t)
	for k, v in pairs(pointindices) do
		if t == k then
			return v
		end
	end

	table.insert(points, t)
	pointindices[t] = #points
	return pointindices[t]
end

local timings = {}
local curname
local inbeam = false
local beam
local beams = {}
local beamednotes
-- first-order placement
local dispatch1 = {
	newnotegroup = function(data)
		local heads = {}
		local beamcount = math.log(data.count) / math.log(2) - 2
		local maxtime
		local lasthead
		local flipped = false
		for _, note in ipairs(data.notes) do
			octave = octave - note.shift
			local head = {acc=note.acc, y=clef.place(note.note, octave), time=note.time, flip}

			-- avoid overlapping heads by "flipping" head across stem
			if lasthead and math.abs(head.y - lasthead.y) == 1 then
				flipped = true
				if head.y % 2 == 1 then
					head.flip = true
				else
					lasthead.flip = true
				end
			end
			lasthead = head
			table.insert(heads, head)
			if note.time and not maxtime then maxtime = note.time end
			if maxtime and note.time and note.time > maxtime then maxtime = note.time end
		end

		local index = point(time)
		if flipped and maxtime then timings[index].flipped = true end

		local incr = Q.new(1) / Q.new(data.count)
		if data.dot then
			incr = 3*incr / 2
		end
		if data.tuplet then incr = incr * data.tuplet end

		local stemlen
		if data.grace then
			stemlen = 2.5
		else
			stemlen = 3.5
		end
		local note = {kind="notecolumn", stemdir=data.stemdir, stemlen=stemlen, dot=data.dot, grace=data.grace, count=incr, length=data.count, time=maxtime, heads=heads, staff=curname}
		if data.beam == 1 then
			assert(not inbeam)
			beamednotes = {}
			table.insert(beams, beamednotes)
			table.insert(beamednotes, {note=note, count=beamcount})
			if data.grace then beamednotes.grace = data.grace end
			beamednotes.maxbeams = beamcount
			note.beamgroup = beamednotes
			inbeam = true
		elseif data.beam == -1 then
			assert(inbeam)
			inbeam = false
			table.insert(beamednotes, {note=note, count=beamcount})
			beamednotes.maxbeams = math.max(beamednotes.maxbeams, beamcount)
			note.beamgroup = beamednotes
		elseif inbeam then
			beamednotes.maxbeams = math.max(beamednotes.maxbeams, beamcount)
			table.insert(beamednotes, {note=note, count=beamcount})
			note.beamgroup = beamednotes
		end

		table.insert(staff1[curname], note)

		local index = point(time)
		if note.grace then
			table.insert(timings[index].staffs[curname].pre, note)
		else
			table.insert(timings[index].staffs[curname].on, note)
			time = time + incr
		end
		lastnote = note
	end,
	changeclef = function(data)
		local class = assert(Clef[data.kind])
		local clefitem = {kind="clef", class=class}
		local index = point(time)
		timings[index].staffs[curname].clef = clefitem
		table.insert(staff1[curname], clefitem)
		clef = class
		octave = class.defoctave
	end,
	changestaff = function(data)
		if staff1[data.name] == nil then
			staff1[data.name] = {}
		end
		curname = data.name

		-- mark cross staff beams for special treatment later
		if inbeam then beamednotes.cross = true end
	end,
	changetime = function(data)
		local timesig = {kind="time", num=data.num, denom=data.denom}
		local index = point(time)
		timings[index].staffs[curname].timesig = timesig
		table.insert(staff1[curname], timesig)
	end,
	barline = function(data)
		local index = point(time)
		timings[index].barline = true
		lastnote = nil
	end,
	srest = function(data)
		table.insert(staff1[curname], {kind='srest', length=data.count, time=time})
		time = time + 1 / Q.new(data.count)
	end,
}

for _, voice in ipairs(voices) do
	time = Q.new(0)
	for _, item in ipairs(voice) do
		local index = point(time)
		if not timings[index] then timings[index] = {staffs={}} end
		if curname and not timings[index].staffs[curname] then timings[index].staffs[curname] = {pre={}, on={}, post={}} end
		assert(dispatch1[item.command])(item)
	end
end

table.sort(points)

for _, beam in pairs(beams) do
	-- check which way the stem should point on all the notes in the beam
	local ysum = 0
	for _, entry in ipairs(beam) do
		-- FIXME: note.heads[1].y is wrong
		ysum = ysum + entry.note.heads[1].y
	end

	local stemdir
	if ysum >= 0 then
		stemdir = -1
	else
		stemdir = 1
	end

	-- check that stem direction hasn't been set manually
	local unset = true
	for _, entry in ipairs(beam) do
		if entry.note.stemdir then
			unset = false
			break
		end
	end

	-- update the stem direction
	if unset then
		for _, entry in ipairs(beam) do
			entry.note.stemdir = stemdir
		end
	end
end

local staff3 = {}
local extra3 = {}

local x = 10
local lasttime = 0

for staff, _ in pairs(staff1) do
	staff3[staff] = {}
end

local staff3ify = function(timing, el, staff)
	local xdiff
	local tindex = point(timing)
	if el.kind == "notecolumn" then
		local glyphsize
		if el.grace then
			glyphsize = 24
		else
			glyphsize = 32
		end
		local rx = x
		xdiff = 10
		rx = rx + xdiff

		local glyph
		if el.length == 1 then
			glyph = Glyph["noteheadWhole"]
		elseif el.length == 2 then
			glyph = Glyph["noteheadHalf"]
		elseif el.length >= 4 then
			glyph = Glyph["noteheadBlack"]
		end

		local w, h = glyph_extents(glyph)

		local preoffset = 0

		-- TODO: increment on each accidental to reduce overlap
		for _, head in ipairs(el.heads) do
			if #head.acc then
				preoffset = 10
			end
		end

		-- offset of stem if a head is drawn on opposite side of stem
		local altoffset = 0
		if timings[tindex].flipped then
			altoffset = w - 1.2
		end

		local heightsum = 0
		local lowheight
		local highheight
		for _, head in ipairs(el.heads) do
			heightsum = heightsum + head.y
			local ry = (em*head.y) / 2 + 2*em
			if not lowheight then lowheight = ry end
			if not highheight then highheight = ry end
			if head.flip then
				table.insert(staff3[staff], {kind="glyph", size=glyphsize, glyph=glyph, x=preoffset + rx, y=ry, time={start=head.time}})
			else
				table.insert(staff3[staff], {kind="glyph", size=glyphsize, glyph=glyph, x=preoffset + altoffset + rx, y=ry, time={start=head.time}})
			end
			if el.dot then
				xdiff = xdiff + 5
				table.insert(staff3[staff], {kind="circle", r=1.5, x=preoffset + altoffset + rx + w + 5, y=ry, time={start=head.time}})
			end
			if head.acc == "s" then
				table.insert(staff3[staff], {kind="glyph", size=glyphsize, glyph=Glyph["accidentalSharp"], x=rx, y=ry, time={start=head.time}})
			elseif head.acc == "f" then
				table.insert(staff3[staff], {kind="glyph", size=glyphsize, glyph=Glyph["accidentalFlat"], x=rx, y=ry, time={start=head.time}})
			elseif head.acc == "n" then
				table.insert(staff3[staff], {kind="glyph", size=glyphsize, glyph=Glyph["accidentalNatural"], x=rx, y=ry, time={start=head.time}})
			end

			lowheight = math.min(lowheight, ry)
			highheight = math.max(highheight, ry)

			local stoptime
			if el.time then stoptime = el.time + 1 else stoptime = nil end
			-- TODO: only do this once per column
			-- leger lines
			if head.y <= -6 then
				for j = -6, head.y, -2 do
					table.insert(staff3[staff], {kind="line", t=1.2, x1=altoffset + preoffset + rx - .2*em, y1=(em * (j + 4)) / 2, x2=altoffset + preoffset + rx + w + .2*em, y2=(em * (j + 4)) / 2, time={start=el.time, stop=stoptime}})
				end
			end

			if head.y >= 6 then
				for j = 6, head.y, 2 do
					table.insert(staff3[staff], {kind="line", t=1.2, x1=altoffset + preoffset + rx - .2*em, y1=(em * (j + 4)) / 2, x2=altoffset + preoffset + rx + w + .2*em, y2=(em * (j + 4)) / 2, time={start=el.time, stop=stoptime}})
				end
			end
		end

		if not el.stemdir and el.length > 1 then
			if heightsum <= 0 then
				el.stemdir = 1
			else
				el.stemdir = -1
			end
		end

		-- stem
		local stemstoptime
		if el.stemdir then
			if el.time then stemstoptime = el.time + .25 else stemstoptime = nil end
			if el.stemdir == -1 then
				-- stem up
				-- advance width for bravura is 1.18 - .1 for stem width
				el.stemx = w + rx - 1.08 + preoffset + altoffset
				el.stemy = lowheight -.168*em - el.stemlen*em
				local stem = {kind="line", t=1, x1=el.stemx, y1=highheight - .168*em, x2=el.stemx, y2=lowheight -.168*em - el.stemlen*em, time={start=el.time, stop=stemstoptime}}
				el.stem = stem
				table.insert(staff3[staff], el.stem)
			else
				el.stemx = rx + .5 + preoffset + altoffset
				el.stemy = lowheight + el.stemlen*em
				local stem = {kind="line", t=1, x1=el.stemx, y1=lowheight + .168*em, x2=el.stemx, y2=highheight + el.stemlen*em, time={start=el.time, stop=stemstoptime}}
				el.stem = stem
				table.insert(staff3[staff], stem)
			end
		end

		-- flag
		if el.length == 8 and not el.beamgroup then
			if el.stemdir == 1 then
				local fx, fy = glyph_extents(Glyph["flag8thDown"])
				table.insert(staff3[staff], {kind="glyph", glyph=Glyph["flag8thDown"], size=glyphsize, x=altoffset + preoffset + rx, y=highheight + 3.5*em, time={start=stemstoptime}})
			else
				-- TODO: move glyph extents to a precalculated table or something
				local fx, fy = glyph_extents(Glyph["flag8thUp"])
				table.insert(staff3[staff], {kind="glyph", glyph=Glyph["flag8thUp"], size=glyphsize, x=altoffset + el.stemx - .48, y=lowheight -.168*em - 3.5*em, time={start=stemstoptime}})
				xdiff = xdiff + fx
			end
		end
		xdiff = xdiff + 100 / el.length + 10
		lasttime = el.time
	elseif el.kind == "srest" then
		xdiff = 0
	elseif el.kind == "clef" then
		table.insert(staff3[staff], {kind="glyph", glyph=el.class.glyph, x=x, y=el.class.yoff, time={start=Q.tonumber(timing), stop=Q.tonumber(timing)+1}})
		xdiff =  30
	elseif el.kind == "time" then
		-- TODO: draw multidigit time signatures properly
		table.insert(staff3[staff], {kind="glyph", glyph=numerals[el.num], x=x, y=em, time={start=Q.tonumber(timing), stop=Q.tonumber(timing)+1}})
		table.insert(staff3[staff], {kind="glyph", glyph=numerals[el.denom], x=x, y=3*em, time={start=Q.tonumber(timing), stop=Q.tonumber(timing)+1}})
		xdiff =  30
	end

	return xdiff
end

local rtimings = {}
local snappoints = {}
for _, time in ipairs(points) do
	local tindex = point(time)
	local todraw = timings[tindex].staffs

	-- clef
	local xdiff = 0
	for staff, vals in pairs(todraw) do
		if vals.clef then
			local diff = staff3ify(time, vals.clef, staff)
			if diff > xdiff then xdiff = diff end
		end
	end

	x = x + xdiff
	xdiff = 0

	-- time signature
	local xdiff = 0
	for staff, vals in pairs(todraw) do
		if vals.timesig then
			local diff = staff3ify(time, vals.timesig, staff)
			if diff > xdiff then xdiff = diff end
		end
	end

	x = x + xdiff
	xdiff = 0

	if timings[tindex].barline then
		table.insert(extra3, {kind='barline', x=x+25})
		x = x + 10
	end

	-- prebeat
	for staff, vals in pairs(todraw) do
		if #vals.pre == 0 then goto nextstaff end
		for _, el in ipairs(vals.pre) do
			local diff = staff3ify(time, el, staff)
			if el.beamref then staff3ify(time, el.beamref, staff) end
			x = x + diff
		end
		::nextstaff::
	end
	xdiff = 0

	local maxtime = 0
	-- on beat
	for staff, vals in pairs(todraw) do
		if #vals.on == 0 then goto nextstaff end
		local diff
		for _, el in ipairs(vals.on) do
			if el.time and el.time > maxtime then maxtime = el.time end
			diff = staff3ify(time, el, staff)
			if el.beamref then staff3ify(time, el.beamref, staff) end
		end
		if xdiff < diff then xdiff = diff end
		::nextstaff::
	end

	x = x + xdiff
	rtimings[maxtime] = x
	if maxtime ~= 0 then
		table.insert(snappoints, maxtime)
	end
end

-- calculate extents
local extents = {}

for _, staff in pairs(stafforder) do
	local items = staff3[staff]
	extents[staff] = {xmin=0, ymin=0, xmax=0, ymax=0}
	for i, d in ipairs(items) do
		if d.kind == "glyph" then
			local w, h = glyph_extents(d.glyph)
			if d.x - w < extents[staff].xmin then
				extents[staff].xmin = d.x - w
			elseif d.x + w > extents[staff].xmax then
				extents[staff].xmax = d.x + w
			end

			if d.y - h < extents[staff].ymin then
				extents[staff].ymin = d.y - h
			elseif d.y + h > extents[staff].ymax then
				extents[staff].ymax = d.y + h
			end
		elseif d.kind == "line" then
			if d.x1 < extents[staff].xmin then
				extents[staff].xmin = d.x1
			elseif d.x1 > extents[staff].xmax then
				extents[staff].xmax = d.x1
			end

			if d.x2 < extents[staff].xmin then
				extents[staff].xmin = d.x2
			elseif d.x2 > extents[staff].xmax then
				extents[staff].xmax = d.x2
			end

			if d.y1 < extents[staff].ymin then
				extents[staff].ymin = d.y1
			elseif d.y1 > extents[staff].ymax then
				extents[staff].ymax = d.y1
			end

			if d.y2 < extents[staff].ymin then
				extents[staff].ymin = d.y2
			elseif d.y2 > extents[staff].ymax then
				extents[staff].ymax = d.y2
			end
		elseif d.kind == "quad" then
			if d.x1 < extents[staff].xmin then
				extents[staff].xmin = d.x1
			elseif d.x1 > extents[staff].xmax then
				extents[staff].xmax = d.x1
			end

			if d.x2 < extents[staff].xmin then
				extents[staff].xmin = d.x2
			elseif d.x2 > extents[staff].xmax then
				extents[staff].xmax = d.x2
			end

			if d.y1 < extents[staff].ymin then
				extents[staff].ymin = d.y1
			elseif d.y1 > extents[staff].ymax then
				extents[staff].ymax = d.y1
			end

			if d.y2 < extents[staff].ymin then
				extents[staff].ymin = d.y2
			elseif d.y2 > extents[staff].ymax then
				extents[staff].ymax = d.y2
			end

			if d.x3 < extents[staff].xmin then
				extents[staff].xmin = d.x3
			elseif d.x3 > extents[staff].xmax then
				extents[staff].xmax = d.x3
			end

			if d.x4 < extents[staff].xmin then
				extents[staff].xmin = d.x4
			elseif d.x4 > extents[staff].xmax then
				extents[staff].xmax = d.x4
			end

			if d.y3 < extents[staff].ymin then
				extents[staff].ymin = d.y3
			elseif d.y3 > extents[staff].ymax then
				extents[staff].ymax = d.y3
			end

			if d.y4 < extents[staff].ymin then
				extents[staff].ymin = d.y4
			elseif d.y4 > extents[staff].ymax then
				extents[staff].ymax = d.y4
			end
		end
	end
end

local xmax = 0
local yoff = 0
local firstymin, lastymin
local xmin = 0
for i, staff in pairs(stafforder) do
	local extent = extents[staff]
	if xmin > extent.xmin then
		xmin = extent.xmin
	end

	if xmax < extent.xmax then
		xmax = extent.xmax
	end

	if i == 1 then
		firstymin = yoff + extent.ymin
	end

	if i == #stafforder then
		lastymin = yoff - extent.ymin
	end

	extent.yoff = yoff
	yoff = yoff + extent.ymax - extent.ymin
end

-- draw beam (and adjust stems) after all previous notes already have set values
for _, notes in ipairs(beams) do
	local beamheight, beamspace
	if notes.grace then
		beamheight = 3
		beamspace = 5
	else
		beamheight = 5
		beamspace = 7
	end
	local x0 = notes[1].note.stemx + .5
	local y0 = notes[1].note.stemy + extents[notes[1].note.staff].yoff - extents[notes[1].note.staff].ymin
	local y0s = notes[1].note.stemy
	local yn = notes[#notes].note.stemy + extents[notes[#notes].note.staff].yoff - extents[notes[#notes].note.staff].ymin

	local m = (yn - y0) / (notes[#notes].note.stemx + .5 - x0)
	if notes.cross then
		if notes[1].note.stemdir == -1 then
			notes[1].note.stem.y2 = notes[1].note.stem.y2 - beamspace * (notes.maxbeams - 1) + beamheight
		end
	end

	for i, entry in ipairs(notes) do
		if i == 1 then goto continue end
		local note = notes[i].note
		local n = entry.count
		local x1 = notes[i-1].note.stemx + .5
		local prevymin = extents[notes[i-1].note.staff].ymin
		local x2 = note.stemx + .5
		local extent = extents[note.staff]

		-- change layout parameters depending on stem up or stem down
		local first, last, inc
		if entry.note.stemdir == 1 then
			first = beamspace*(notes.maxbeams - 2)
			last = beamspace*(notes.maxbeams - n - 1)
			if extents[entry.note.staff].yoff < extents[notes[1].note.staff].yoff then
				entry.note.stem.y2 = y0 + m*(x2 - x0) + 7*(notes.maxbeams - 2) + beamheight + extents[entry.note.staff].ymin - extents[entry.note.staff].yoff
			else
				entry.note.stem.y2 = y0s + m*(x2 - x0) + 7*(notes.maxbeams - 2) + beamheight
			end
			inc = -beamspace
		else
			if extents[entry.note.staff].yoff > extents[notes[1].note.staff].yoff then
				entry.note.stem.y2 = y0 + m*(x2 - x0) + beamheight - extents[entry.note.staff].yoff + extents[entry.note.staff].ymin
			else
				entry.note.stem.y2 = y0s + m*(x2 - x0)
			end
			first = 0
			last = beamspace*(n-1)
			inc = beamspace
		end

		-- draw beams segment by segment
		for yoff=first, last, inc do
			local starttime, stoptime
			if note.time then stoptime = note.time + .25 else stoptime = nil end
			if note.time then starttime = notes[i-1].note.time + .25 else starttime = nil end
			if entry.note.stemdir ~= 1 and notes.cross then
				table.insert(extra3, {kind="beamseg", x1=x1 - 0.5 - extent.xmin, x2=x2 - extent.xmin, y1=y0 + m*(x1 - x0) + yoff, y2=y0 + m*(x2 - x0) + yoff, h=beamheight, time={start=starttime, stop=stoptime}})
			else
				table.insert(extra3, {kind="beamseg", x1=x1 - 0.5 - extent.xmin, x2=x2 - extent.xmin, y1=y0 + m*(x1 - x0) + yoff, y2=y0 + m*(x2 - x0) + yoff, h=beamheight, time={start=starttime, stop=stoptime}})
			end
		end
		::continue::
	end
end

for staff, item in ipairs(extra3) do
	if item.kind == 'barline' then
		if item.x < xmin then
			xmin = item.x
		elseif item.x > xmax then
			xmax = item.x
		end
	end
end

local lastpoint = 0
for _, point in ipairs(snappoints) do
	lastpoint = math.max(point, lastpoint)
end

-- TODO: is there a better way to do this?
snappoints[0] = snappoints[1]
local snapidx = 1
local toff_base = 0
function drawframe(time)
	if snappoints[snapidx + 1] and snappoints[snapidx] < time then
		snapidx = snapidx + 1
		toff_base = -rtimings[snappoints[snapidx - 1]] + framewidth / 2
	end
	local xdiff = rtimings[snappoints[snapidx]] - rtimings[snappoints[snapidx - 1]]
	local delta = xdiff * (time - snappoints[snapidx - 1]) / (snappoints[snapidx] - snappoints[snapidx - 1])
	local toff = toff_base - delta

	if time > lastpoint + 3 then
		return true
	end

	for _, staff in ipairs(stafforder) do
		local extent = extents[staff]
		for i, d in ipairs(staff3[staff]) do
			if not d.time.start then goto continue end
			if d.time.start < time then
				if d.kind == "glyph" then
					draw_glyph(d.size, d.glyph, toff + d.x - extent.xmin, d.y - extent.ymin + extent.yoff)
				elseif d.kind == "line" then
					local delta = (time - d.time.start) / (d.time.stop - d.time.start)
					local endx, endy
					if d.x1 < d.x2 then
						endx = math.min(d.x1 + delta*(d.x2 - d.x1), d.x2)
					else
						endx = math.max(d.x1 + delta*(d.x2 - d.x1), d.x2)
					end
					if d.y1 < d.y2 then
						endy = math.min(d.y1 + delta*(d.y2 - d.y1), d.y2)
					else
						endy = math.max(d.y1 + delta*(d.y2 - d.y1), d.y2)
					end
					draw_line(d.t, toff + d.x1 - extent.xmin, d.y1 - extent.ymin + extent.yoff, toff + endx - extent.xmin, endy - extent.ymin + extent.yoff)
				elseif d.kind == "circle" then
					draw_circle(d.r, toff + d.x - extent.xmin, d.y - extent.ymin + extent.yoff)
				elseif d.kind == "vshear" then
					local delta = (time - d.time.start) / (d.time.stop - d.time.start)
					local endx, endy
					if d.x1 < d.x2 then
						endx = math.min(d.x1 + delta*(d.x2 - d.x1), d.x2)
					else
						endx = math.max(d.x1 + delta*(d.x2 - d.x1), d.x2)
					end
					if d.y1 < d.y2 then
						endy = math.min(d.y1 + delta*(d.y2 - d.y1), d.y2)
					else
						endy = math.max(d.y1 + delta*(d.y2 - d.y1), d.y2)
					end
					draw_quad(toff + d.x1 - extent.xmin, d.y1 - extent.ymin + extent.yoff, toff + endx - extent.xmin, endy - extent.ymin + extent.yoff, toff + endx - extent.xmin, endy + d.h - extent.ymin + extent.yoff, toff + d.x1 - extent.xmin, d.y1 + d.h - extent.ymin + extent.yoff)
				elseif d.kind == "quad" then
					draw_quad(toff + d.x1 - extent.xmin, d.y1 - extent.ymin + extent.yoff, toff + d.x2 - extent.xmin, d.y2 - extent.ymin + extent.yoff, toff + d.x3 - extent.xmin, d.y3 - extent.ymin + extent.yoff, toff + d.x4 - extent.xmin, d.y4 - extent.ymin + extent.yoff)
				end
			end

			::continue::
		end

		-- draw staff
		for y=0,em*4,em do
			draw_line(1, toff + xmin, y + extent.yoff - extent.ymin, toff + xmax, y + extent.yoff - extent.ymin)
		end
	end

	-- draw barlines
	for staff, item in ipairs(extra3) do
		if item.kind == 'barline' then
			draw_line(1, toff + item.x, -firstymin, toff + item.x, lastymin + 4*em)
		elseif item.kind == "beamseg" then
			if item.time.start > time then goto continue end
			local delta = (time - item.time.start) / (item.time.stop - item.time.start)
			local endx, endy
			if item.x1 < item.x2 then
				endx = math.min(item.x1 + delta*(item.x2 - item.x1), item.x2)
			else
				endx = math.max(item.x1 + delta*(item.x2 - item.x1), item.x2)
			end
			if item.y1 < item.y2 then
				endy = math.min(item.y1 + delta*(item.y2 - item.y1), item.y2)
			else
				endy = math.max(item.y1 + delta*(item.y2 - item.y1), item.y2)
			end
			draw_quad(toff + item.x1, item.y1, toff + endx, endy, toff + endx, endy + item.h, toff + item.x1, item.y1 + item.h)
		end
		::continue::
	end

	return false
end
