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
			local s, e, flags, count, beam = string.find(text, "^([v^]?)(%d*)([%[%]]?)", start)
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

			return start + e - s + 1, out
		end
		local parsenote = function(text, start)
			-- TODO: should we be more strict about accidentals and stem orientations on rests?
			local s, e, note, acc, shift = string.find(text, "^([abcdefgs])([fns]?)([,']*)", start)
			if note then
				local out
				if note == 's' then
					out = {command='srest', count=tonumber(count)}
				else
					out = {command="note", note=note, acc=acc, count=tonumber(count)}
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

			local s, e = string.find(text, "^|", i)
			if s then
				i = i + e - s + 1
				table.insert(voice, {command="barline"})
				goto start
			end

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
				table.insert(voice, group)
				goto start
			end

			i, note = parsenote(text, i)
			i, col = parsenotecolumn(text, i)

			if note.command == 'srest' then
				table.insert(voice, {command='srest', count=col.count})
			else
				table.insert(voice, {command="newnotegroup", count=col.count, stemdir=col.stemdir, beam=col.beam, notes={[1] = note}})
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

local time = 0 -- time in increments of denom
local octave = 0
local clef = Clef.treble
local lastnote = nil
local staff1 = {}
local points = {}
local pointthere = {}
local timings = {}
local curname
local inbeam = 0
-- first-order placement
local dispatch1 = {
	newnotegroup = function(data)
		local heads = {}
		local beamcount = math.log(data.count) / math.log(2) - 2
		for _, note in ipairs(data.notes) do
			octave = octave - note.shift
			table.insert(heads, {acc=note.acc, y=clef.place(note.note, octave)})
		end

		local note = {kind="notecolumn", beamcount=beamcount, stemdir=data.stemdir, stemlen=3.5, length=data.count, time=time, heads=heads}
		if data.beam == 1 then
			assert(inbeam == 0)
			inbeam = 1
			note.beamed = inbeam
		elseif data.beam == -1 then
			assert(inbeam == 1)
			inbeam = 0
			note.beamed = -1
		else
			note.beamed = inbeam
		end
		table.insert(staff1[curname], note)
		table.insert(timings[time].staffs[curname].on, note)
		lastnote = note
		time = time + 1 / data.count
	end,
	changeclef = function(data)
		local class = assert(Clef[data.kind])
		local clefitem = {kind="clef", class=class}
		timings[time].staffs[curname].clef = clefitem
		table.insert(staff1[curname], clefitem)
		clef = class
		octave = class.defoctave
	end,
	changestaff = function(data)
		if staff1[data.name] == nil then
			staff1[data.name] = {}
		end
		curname = data.name
	end,
	changetime = function(data)
		local timesig = {kind="time", num=data.num, denom=data.denom}
		timings[time].staffs[curname].timesig = timesig
		table.insert(staff1[curname], timesig)
	end,
	barline = function(data)
		table.insert(staff1[curname], {kind="barline"})
		timings[time].barline = true
		lastnote = nil
	end,
	srest = function(data)
		table.insert(staff1[curname], {kind='srest', length=data.count, time=time})
		time = time + 1 / data.count
	end
}

for _, voice in ipairs(voices) do
	time = 0
	for _, item in ipairs(voice) do
		if not pointthere[time] then
			pointthere[time] = true
			table.insert(points, time)
			timings[time] = {staffs={}}
		end
		if curname and not timings[time].staffs[curname] then timings[time].staffs[curname] = {pre={}, on={}, post={}} end
		assert(dispatch1[item.command])(item)
	end
end

table.sort(points)

-- second-order placement
local staff2 = {}

function trybeam(staffname, tobeam, beampattern)
	local staff = staff2[staffname]
	if #tobeam > 1 then
		-- check which way the stem should point on all the notes in the beam
		local ysum = 0
		for _, note in ipairs(tobeam) do
			-- FIXME: note.heads[1].y is wrong
			ysum = ysum + note.heads[1].y
		end

		local stemdir
		if ysum >= 0 then
			stemdir = -1
		else
			stemdir = 1
		end

		-- update the stem direction
		for _, note in ipairs(tobeam) do
			note.stemdir = stemdir
			table.insert(staff, note)
		end
		local beam = {kind='beam', notes=tobeam, pattern=beampattern, stemdir=stemdir, maxbeams=math.max(table.unpack(beampattern))}
		table.insert(staff, beam)
		tobeam[#tobeam].beamref = beam
	elseif #tobeam == 1 then
		tobeam[1].beamed = false
		table.insert(staff, tobeam[1])
	end
end

for name, staff in pairs(staff1) do
	staff2[name] = {}
	local tobeam = {}
	local beampattern = {}
	for i, el in ipairs(staff) do
		if el.kind == 'notecolumn' then
			if el.beamed == 1 then
				tobeam[#tobeam + 1] = el
				beampattern[#beampattern + 1] = el.beamcount
			elseif el.beamed == -1 then
				tobeam[#tobeam + 1] = el
				beampattern[#beampattern + 1] = el.beamcount
				trybeam(name, tobeam, beampattern)
				tobeam = {}
				beampattern = {}
			else
				table.insert(staff2[name], el)
			end
		else
			table.insert(staff2[name], el)
		end
	end
	trybeam(name, tobeam, beampattern)
	tobeam = {}
	beampattern = {}
end

local staff3 = {}
local extra3 = {}

local x = 10
local lasttime = 0

for staff, _ in pairs(staff2) do
	staff3[staff] = {}
end

local staff3ify = function(el, staff)
	local xdiff
	if el.kind == "notecolumn" then
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
		for _, head in ipairs(el.heads) do
			if #head.acc then
				preoffset = 10
			end
		end

		local heightsum = 0
		local lowheight
		local highheight
		for _, head in ipairs(el.heads) do
			heightsum = heightsum + head.y
			local ry = (em*head.y) / 2 + 2*em
			if not lowheight then lowheight = ry end
			if not highheight then highheight = ry end
			table.insert(staff3[staff], {kind="glyph", glyph=glyph, x=preoffset + rx, y=ry})
			if head.acc == "s" then
				table.insert(staff3[staff], {kind="glyph", glyph=Glyph["accidentalSharp"], x=rx, y=ry})
			elseif head.acc == "f" then
				table.insert(staff3[staff], {kind="glyph", glyph=Glyph["accidentalFlat"], x=rx, y=ry})
			elseif head.acc == "n" then
				table.insert(staff3[staff], {kind="glyph", glyph=Glyph["accidentalNatural"], x=rx, y=ry})
			end

			lowheight = math.min(lowheight, ry)
			highheight = math.max(highheight, ry)

			-- TODO: only do this once per column
			-- leger lines
			if head.y <= -6 then
				for j = -6, head.y, -2 do
					table.insert(staff3[staff], {kind="line", t=1.2, x1=preoffset + rx - .2*em, y1=(em * (j + 4)) / 2, x2=preoffset + rx + w + .2*em, y2=(em * (j + 4)) / 2})
				end
			end

			if head.y >= 6 then
				for j = 6, head.y, 2 do
					table.insert(staff3[staff], {kind="line", t=1.2, x1=preoffset + rx - .2*em, y1=(em * (j + 4)) / 2, x2=preoffset + rx + w + .2*em, y2=(em * (j + 4)) / 2})
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
		if el.stemdir then
			if el.stemdir == -1 then
				-- stem up
				-- advance width for bravura is 1.18 - .1 for stem width
				el.stemx = w + rx - 1.08 + preoffset
				el.stemy = lowheight -.168*em - el.stemlen*em
				local stem = {kind="line", t=1, x1=el.stemx, y1=highheight - .168*em, x2=el.stemx, y2=lowheight -.168*em - el.stemlen*em}
				el.stem = stem
				table.insert(staff3[staff], el.stem)
			else
				el.stemx = rx + .5 + preoffset
				el.stemy = lowheight + el.stemlen*em
				local stem = {kind="line", t=1, x1=el.stemx, y1=lowheight + .168*em, x2=el.stemx, y2=lowheight + el.stemlen*em}
				el.stem = stem
				table.insert(staff3[staff], stem)
			end
		end

		if el.length == 8 and el.beamed == 0 then
			if el.stemdir == 1 then
				table.insert(staff3[staff], {kind="glyph", glyph=Glyph["flag8thDown"], x=preoffset + rx, y=lowheight + 3.5*em})
			else
				-- TODO: move glyph extents to a precalculated table or something
				local fx, fy = glyph_extents(Glyph["flag8thUp"])
				table.insert(staff3[staff], {kind="glyph", glyph=Glyph["flag8thUp"], x=el.stemx - .48, y=lowheight -.168*em - 3.5*em})
				xdiff = xdiff + fx
			end
		end
		xdiff = xdiff + 100 / el.length + 10
		lasttime = el.time
	elseif el.kind == "srest" then
		xdiff = 0
	elseif el.kind == "beam" then
		local m = (el.notes[#el.notes].stemy - el.notes[1].stemy) / (el.notes[#el.notes].stemx - el.notes[1].stemx)
		local x0 = el.notes[1].stemx
		local y0 = el.notes[1].stemy
		if el.stemdir == 1 then
			el.notes[1].stem.y2 = y0 + 7*(el.maxbeams - 2) + 5
		end
		for i, n in ipairs(el.pattern) do
			if i == 1 then goto continue end
			local x1 = el.notes[i-1].stemx
			local x2 = el.notes[i].stemx

			local first, last, inc
			if el.stemdir == 1 then
				first = 7*(el.maxbeams - 2)
				last = 7*(el.maxbeams - n - 1)
				el.notes[i].stem.y2 = y0 + m*(x2 - x0) + 7*(el.maxbeams - 2) + 5
				inc = -7
			else
				el.notes[i].stem.y2 = y0 + m*(x2 - x0)
				first = 0
				last = 7*(n-1)
				inc = 7
			end
			for yoff=first, last, inc do
				table.insert(staff3[staff], {kind="quad", x1=x1 - 0.5, y1=y0 + m*(x1 - x0) + yoff, x2=x2, y2=y0 + m*(x2 - x0) + yoff, x3=x2, y3=y0 + m*(x2 - x0) + 5 + yoff, x4=x1 - 0.5, y4=y0 + m*(x1 - x0) + 5 + yoff})
			end
			::continue::
		end
	elseif el.kind == "clef" then
		table.insert(staff3[staff], {kind="glyph", glyph=el.class.glyph, x=x, y=el.class.yoff})
		xdiff =  30
	elseif el.kind == "time" then
		-- TODO: draw multidigit time signatures properly
		table.insert(staff3[staff], {kind="glyph", glyph=numerals[el.num], x=x, y=em})
		table.insert(staff3[staff], {kind="glyph", glyph=numerals[el.denom], x=x, y=3*em})
		xdiff =  30
	end

	return xdiff
end

for _, time in ipairs(points) do
	local todraw = timings[time].staffs

	-- clef
	local xdiff = 0
	for staff, vals in pairs(todraw) do
		if vals.clef then
				local diff = staff3ify(vals.clef, staff)
				if diff > xdiff then xdiff = diff end
		end
	end

	x = x + xdiff
	xdiff = 0

	-- time signature
	local xdiff = 0
	for staff, vals in pairs(todraw) do
		if vals.timesig then
				local diff = staff3ify(vals.timesig, staff)
				if diff > xdiff then xdiff = diff end
		end
	end

	x = x + xdiff
	xdiff = 0

	if timings[time].barline then
		table.insert(extra3, {kind='barline', x=x+25})
		x = x + 10
	end

	for staff, vals in pairs(todraw) do
		if #vals.on == 0 then goto nextstaff end
		local diff
		for _, el in ipairs(vals.on) do
			diff = staff3ify(el, staff)
			if el.beamref then staff3ify(el.beamref, staff) end
		end
		if xdiff < diff then xdiff = diff end
		::nextstaff::
	end

	x = x + xdiff
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

for staff, item in ipairs(extra3) do
	if item.kind == 'barline' then
		if item.x < xmin then
			xmin = item.x
		elseif item.x > xmax then
			xmax = item.x
		end
	end
end

create_surface(xmax - xmin, yoff)

for _, staff in ipairs(stafforder) do
	local extent = extents[staff]
	for i, d in ipairs(staff3[staff]) do
		if d.kind == "glyph" then
			draw_glyph(d.glyph, d.x - extent.xmin, d.y - extent.ymin + extent.yoff)
		elseif d.kind == "line" then
			draw_line(d.t, d.x1 - extent.xmin, d.y1 - extent.ymin + extent.yoff, d.x2 - extent.xmin, d.y2 - extent.ymin + extent.yoff)
		elseif d.kind == "quad" then
			draw_quad(d.t, d.x1 - extent.xmin, d.y1 - extent.ymin + extent.yoff, d.x2 - extent.xmin, d.y2 - extent.ymin + extent.yoff, d.x3 - extent.xmin, d.y3 - extent.ymin + extent.yoff, d.x4 - extent.xmin, d.y4 - extent.ymin + extent.yoff)
		end
	end

	-- draw staff
	for y=0,em*4,em do
		draw_line(1, xmin, y + extent.yoff - extent.ymin, xmax, y + extent.yoff - extent.ymin)
	end
end

-- draw barlines
for staff, item in ipairs(extra3) do
	if item.kind == 'barline' then
		draw_line(1, item.x, -firstymin, item.x, lastymin + 4*em)
	end
end
