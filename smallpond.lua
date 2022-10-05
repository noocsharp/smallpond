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
		local parsenote = function(text, start)
			-- TODO: should we be more strict about accidentals and stem orientations on rests?
			local s, e, note, acc, flags, shift, count = string.find(text, "^([abcdefgs])([fns]?)([v^]?)([,']*)(%d*)", start)
			if note then
				-- make sure that count is a power of 2
				if #count ~= 0 then
					assert(math.ceil(math.log(count)/math.log(2)) == math.floor(math.log(count)/math.log(2)), "note count is not a power of 2")
				end
				local out
				if note == 's' then
					out = {command='srest', count=tonumber(count)}
				else
					out = {command="note", note=note, acc=acc, count=tonumber(count)}
				end
				if string.find(flags, "v", 1, true) then
					out.stemdir = 1
				elseif string.find(flags, "^", 1, true) then
					out.stemdir = -1
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

			local s, e, count = string.find(text, "^%b<>(%d+)", i)
			if s then
				i = i + 1
				local group = {command="newnotegroup", notes = {}}
				while i <= e - 1 - #count do
					i = i + #(string.match(text, "^%s*", i) or "")
					if i >= #text then return i end
					i, out = parsenote(text, i)
					table.insert(group.notes, out)
				end
				i = e + 1
				group.count = tonumber(count)
				table.insert(voice, group)
				goto start
			end

			i, out = parsenote(text, i)

			if out.command == 'srest' then
				table.insert(voice, out)
			else
				table.insert(voice, {command="newnotegroup", count=out.count, notes={[1] = out}})
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
local curname
-- first-order placement
abstract_dispatch = {
	newnotegroup = function(data)
		local heads = {}
		local beamed
		local beamcount
		if data.count >= 8 and (time % (1 / data.count) == 0 or (lastnote and lastnote.beamed)) then
			beamed = true
			beamcount = math.log(data.count) / math.log(2) - 2
			-- TODO: should we be emitting a beam here?
		end
		for _, note in ipairs(data.notes) do
			octave = octave - note.shift
			table.insert(heads, {acc=note.acc, stemdir=note.stemdir, y=clef.place(note.note, octave)})
		end
		local note = {kind="notecolumn", beamed=beamed, beamcount=beamcount, stemlen=3.5, length=data.count, time=time, heads=heads}
		table.insert(staff1[curname], note)
		lastnote = note
		time = time + 1 / data.count
	end,
	changeclef = function(data)
		local class = assert(Clef[data.kind])
		table.insert(staff1[curname], {kind="clef", class=class})
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
		table.insert(staff1[curname], {kind="time", num=data.num, denom=data.denom})
	end,
	barline = function(data)
		table.insert(staff1[curname], {kind="barline"})
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
		assert(abstract_dispatch[item.command])(item)
	end
end

-- second-order placement
local staff2 = {}

function trybeam(staff, tobeam, beampattern)
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
		table.insert(staff, {kind='beam', notes=tobeam, pattern=beampattern})
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
		if el.kind == 'notecolumn' and el.beamed then
			tobeam[#tobeam + 1] = el
			beampattern[#beampattern + 1] = el.beamcount
		else
			trybeam(staff2[name], tobeam, beampattern)
			table.insert(staff2[name], el)
			tobeam = {}
			beampattern = {}
		end
	end
	trybeam(staff2[name], tobeam, beampattern)
	tobeam = {}
	beampattern = {}
end

local staffindex = {}
local staff3 = {}

local x = 10
local lasttime = 0

for staff, _ in pairs(staff2) do
	staffindex[staff] = 1
	staff3[staff] = {}
end

while true do
	local todraw = {}
	-- draw untimed elements before timed elements
	-- we assume that staff2 contains lists sorted by time
	local lowesttime
	local timed = true
	local empty = true
	for name, i in pairs(staffindex) do
		if not staff2[name][i] then
			goto continue
		end

		if timed then
			if staff2[name][i].time then
				if not lowesttime then
					lowesttime = staff2[name][i].time
				end

				if lowesttime > staff2[name][i].time then
					lowesttime = staff2[name][i].time
					todraw = {[1] = {staff=name, i=i}}
					print("inserted first timed element", staff2[name][i].kind, staff2[name][i].time, name)
					goto continue
				end

				if lowesttime < staff2[name][i].time then
					goto continue
				end

				empty = false
				table.insert(todraw, {staff=name, i=i})
				print("inserted timed element", staff2[name][i].kind, staff2[name][i].time, name)
			else
				todraw = {}
				table.insert(todraw, {staff=name, i=i})
				timed = false
				empty = false
				print("inserted first untimed element", staff2[name][i].kind, name)
			end
		else
			if not staff2[name][i].time then
				table.insert(todraw, {staff=name, i=i, xdiff=0})
				print("inserted untimed element", staff2[name][i].kind, name)
			end
		end

		::continue::
	end

	if empty then break end

	local xdiffs = {}
	for _, pair in ipairs(todraw) do
		local staff = pair.staff
		el = staff2[staff][pair.i]
		if el.kind == "notecolumn" then
			local rx = x
			local xdiff = 10
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
					table.insert(staff3[staff], {kind="line", t=1, x1=el.stemx, y1=highheight - .168*em, x2=el.stemx, y2=lowheight -.168*em - el.stemlen*em})
				else
					el.stemx = rx + .5 + preoffset
					el.stemy = lowheight + el.stemlen*em
					table.insert(staff3[staff], {kind="line", t=1, x1=el.stemx, y1=lowheight + .168*em, x2=el.stemx, y2=lowheight + el.stemlen*em})
				end
			end

			if el.length == 8 and not el.beamed then
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
			xdiffs[staff] = xdiff
			lasttime = el.time
		elseif el.kind == "srest" then
			xdiffs[staff] = 0
		elseif el.kind == "beam" then
			local m = (el.notes[#el.notes-1].stemy - el.notes[1].stemy) / (el.notes[#el.notes-1].stemx - el.notes[1].stemx)
			for i, n in ipairs(el.pattern) do
				if i == 1 then goto continue end
				for yoff=0, 7*(n-1), 7 do
					table.insert(staff3[staff], {kind="quad", x1=el.notes[i-1].stemx - 0.5, y1=el.notes[i-1].stemy + yoff, x2=el.notes[i].stemx, y2=el.notes[i].stemy + yoff, x3=el.notes[i].stemx, y3=el.notes[i].stemy + 5 + yoff, x4=el.notes[i-1].stemx - 0.5, y4=el.notes[i-1].stemy + 5 + yoff})
				end
				::continue::
			end
		elseif el.kind == "barline" then
			xdiffs[staff] = 20
			table.insert(staff3[staff], {kind="line", t=1, x1=x + xdiffs[staff], y1=0, x2=x + xdiffs[staff], y2 = 0 + 4*em})
			xdiffs[staff] = xdiffs[staff] + 20
		elseif el.kind == "clef" then
			table.insert(staff3[staff], {kind="glyph", glyph=el.class.glyph, x=x, y=el.class.yoff})
			xdiffs[staff] =  30
		elseif el.kind == "time" then
			-- TODO: draw multidigit time signatures properly
			table.insert(staff3[staff], {kind="glyph", glyph=numerals[el.num], x=x, y=em})
			table.insert(staff3[staff], {kind="glyph", glyph=numerals[el.denom], x=x, y=3*em})
			xdiffs[staff] =  30
		end

		staffindex[staff] = staffindex[staff] + 1
	end

	local maxdiff = 0
	for _, xd in pairs(xdiffs) do
		maxdiff = math.max(maxdiff, xd)
	end

	x = x + maxdiff
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
local xmin = 0
for _, staff in pairs(stafforder) do
	local extent = extents[staff]
	if xmin > extent.xmin then
		xmin = extent.xmin
	end

	if xmax < extent.xmax then
		xmax = extent.xmax
	end

	extent.yoff = yoff
	yoff = yoff + extent.ymax - extent.ymin
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
