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

commands = {
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

function parse(text)
	local i = 1
	return function()
		i = i + #(string.match(text, "^%s*", i) or "")
		if i >= #text then return nil end
		local cmd = string.match(text, "^\\(%a+)", i)
		if cmd then
			local size, data = commands[cmd].parse(text, i)
			i = i + size
			return data
		end

		local s, e = string.find(text, "^|", i)
		if s then
			i = i + e - s + 1
			return {command="barline"}
		end

		local s, e = string.find(text, "^'", i)
		if s then
			i = i + e - s + 1
			return {command="changeoctave", count=-(e - s + 1)}
		end

		local s, e = string.find(text, "^,", i)
		if s then
			i = i + e - s + 1
			return {command="changeoctave", count=e - s + 1}
		end

		local s, e, note, acc, flags, count = string.find(text, "^([abcdefg])([fns]?)([v^]?)([1248]?)", i)
		if note then
			i = i + e - s + 1
			local out = {command="newnote", note=note, acc=acc, count=tonumber(count)}
			if string.find(flags, "v", 1, true) then
				out.stemdir = 1
			elseif string.find(flags, "^", 1, true) then
				out.stemdir = -1
			end
			return out
		end


		error("unknown token")
	end
end

f = assert(io.open("score.sp"))

local time = 0 -- time in increments of denom
local octave = 0
local clef = Clef.treble
local lastnote = nil
-- first-order placement
first_order = {}
abstract_dispatch = {
	newnote = function(data)
		local i = clef.place(data.note, octave)
		local beamed = false
		if data.count == 8 and (time % .25 == 0 or lastnote.beamed) then
			beamed = true
			-- TODO: should we be emitting a beam here?
		end
		local note = {kind="note", acc=data.acc, beamed=beamed, stemdir=data.stemdir, stemlen=3.5, length=data.count, time=time, sy=i}
		table.insert(first_order, note)
		lastnote = note
		time = time + 1 / data.count
	end,
	changeclef = function(data)
		local class = assert(Clef[data.kind])
		table.insert(first_order, {kind="clef", class=class})
		clef = class
		octave = class.defoctave
	end,
	changetime = function(data)
		table.insert(first_order, {kind="time", num=data.num, denom=data.denom})
	end,
	barline = function(data)
		table.insert(first_order, {kind="barline"})
		lastnote = nil
	end,
	changeoctave = function(data)
		octave = octave + data.count
	end
}

for tok in parse(f:read("*a")) do
	assert(abstract_dispatch[tok.command])(tok)
end

-- second-order placement
local staff = {}
local tobeam = {}

for i, el in ipairs(first_order) do
	if el.kind == 'note' and el.beamed then
		tobeam[#tobeam + 1] = el
	else
		if #tobeam > 1 then
			-- check which way the stem should point on all the notes in the beam
			local ysum = 0
			for _, note in ipairs(tobeam) do
				ysum = ysum + note.sy
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
			table.insert(staff, {kind='beam', first=tobeam[1], last=tobeam[#tobeam]})
		elseif #tobeam == 1 then
			tobeam[1].beamed = false
			table.insert(staff, tobeam[1])
		end
		tobeam = {}
		table.insert(staff, el)
	end
end

drawables = {}

-- starting yoffset at 20 is a hack
local yoffset = 20
local xoffset = 20
local x = 10
local lasttime = 0

for i, el in ipairs(staff) do
	if el.kind == "note" then
		local rx = xoffset + x
		local ry = yoffset + (em*el.sy) / 2 + 2*em
		if el.acc == "s" then
			table.insert(drawables, {kind="glyph", glyph=Glyph["accidentalSharp"], x=rx, y=ry})
		elseif el.acc == "f" then
			table.insert(drawables, {kind="glyph", glyph=Glyph["accidentalFlat"], x=rx, y=ry})
		elseif el.acc == "n" then
			table.insert(drawables, {kind="glyph", glyph=Glyph["accidentalNatural"], x=rx, y=ry})
		end

		rx = rx + 10

		local glyph
		if el.length == 1 then
			glyph = Glyph["noteheadWhole"]
		elseif el.length == 2 then
			glyph = Glyph["noteheadHalf"]
		elseif el.length == 4 then
			glyph = Glyph["noteheadBlack"]
		elseif el.length == 8 then
			glyph = Glyph["noteheadBlack"]
		end

		local w, h = glyph_extents(glyph)
		-- leger lines
		if el.sy <= -6 then
			for j = -6, el.sy, -2 do
				table.insert(drawables, {kind="line", t=1.2, x1=rx - .2*em, y1=yoffset + (em * j) / 2, x2=rx + w + .2*em, y2=yoffset + (em * j) / 2})
			end
		end

		if el.sy >= 6 then
			for j = 6, el.sy, 2 do
				table.insert(drawables, {kind="line", t=1.2, x1=rx - .2*em, y1=yoffset + (em * j) / 2, x2=rx + w + .2*em, y2=yoffset + (em * j) / 2})
			end
		end

		table.insert(drawables, {kind="glyph", glyph=glyph, x=rx, y=ry})

		if not el.stemdir and el.length > 1 then
			if el.sy <= 0 then
				el.stemdir = -1
			else
				el.stemdir = 1
			end
		end

		-- stem
		if el.stemdir then
			if el.stemdir == -1 then
				-- stem up
				el.stemx = w + rx - .5
				el.stemy = ry -.168*em - el.stemlen*em
				table.insert(drawables, {kind="line", t=1, x1=w + rx - .5, y1=ry - .168*em, x2=w + rx - .5, y2=ry -.168*em - el.stemlen*em})
			else
				el.stemx = rx - .5
				el.stemy = ry + el.stemlen*em
				table.insert(drawables, {kind="line", t=1, x1=rx + 0.5, y1=ry + .168*em, x2=rx + 0.5, y2=ry + el.stemlen*em})
			end
		end

		if el.length == 8 and not el.beamed then
			if el.stemdir == 1 then
				table.insert(drawables, {kind="glyph", glyph=Glyph["flag8thDown"], x=rx, y=ry + 3.5*em})
			else
				-- TODO: move glyph extents to a precalculated table or something
				local fx, fy = glyph_extents(Glyph["flag8thUp"])
				table.insert(drawables, {kind="glyph", glyph=Glyph["flag8thUp"], x=w + rx - 1, y=ry -.168*em - 3.5*em})
				x = x + fx
			end
		end
		x = x + 100 / el.length + 10
		lasttime = el.time
	elseif el.kind == "beam" then
				table.insert(drawables, {kind="quad", x1=el.first.stemx - 0.5, y1=el.first.stemy, x2=el.last.stemx, y2=el.last.stemy, x4=el.first.stemx - 0.5, y4=el.first.stemy + 5, x3=el.last.stemx, y3=el.last.stemy + 5})
	elseif el.kind == "barline" then
		x = x + 20
		table.insert(drawables, {kind="line", t=1, x1=x + xoffset, y1=yoffset, x2=x + xoffset, y2 = yoffset + 4*em})
		x = x + 20
	elseif el.kind == "clef" then
		table.insert(drawables, {kind="glyph", glyph=el.class.glyph, x=xoffset + x, y=yoffset + el.class.yoff})
		x = x + 30
	elseif el.kind == "time" then
		-- TODO: draw multidigit time signatures properly
		table.insert(drawables, {kind="glyph", glyph=numerals[el.num], x=xoffset + x, y=yoffset + em})
		table.insert(drawables, {kind="glyph", glyph=numerals[el.denom], x=xoffset + x, y=yoffset + 3*em})
		x = x + 30
	end
end

-- calculate extents
local xmin = 0
local ymin = 0
local xmax = 0
local ymax = 0
for i, d in ipairs(drawables) do
	if d.kind == "glyph" then
		-- TODO
		local w, h = glyph_extents(glyph)
	elseif d.kind == "line" then
		if d.x1 < xmin then
			xmin = d.x1
		elseif d.x1 > xmax then
			xmax = d.x1
		end

		if d.x2 < xmin then
			xmin = d.x2
		elseif d.x2 > xmax then
			xmax = d.x2
		end

		if d.y1 < ymin then
			ymin = d.y1
		elseif d.y1 > ymax then
			ymax = d.y1
		end

		if d.y2 < ymin then
			ymin = d.y2
		elseif d.y2 > ymax then
			ymax = d.y2
		end
	elseif d.kind == "quad" then
		if d.x1 < xmin then
			xmin = d.x1
		elseif d.x1 > xmax then
			xmax = d.x1
		end

		if d.x2 < xmin then
			xmin = d.x2
		elseif d.x2 > xmax then
			xmax = d.x2
		end

		if d.y1 < ymin then
			ymin = d.y1
		elseif d.y1 > ymax then
			ymax = d.y1
		end

		if d.y2 < ymin then
			ymin = d.y2
		elseif d.y2 > ymax then
			ymax = d.y2
		end

		if d.x3 < xmin then
			xmin = d.x3
		elseif d.x3 > xmax then
			xmax = d.x3
		end

		if d.x4 < xmin then
			xmin = d.x4
		elseif d.x4 > xmax then
			xmax = d.x4
		end

		if d.y3 < ymin then
			ymin = d.y3
		elseif d.y3 > ymax then
			ymax = d.y3
		end

		if d.y4 < ymin then
			ymin = d.y4
		elseif d.y4 > ymax then
			ymax = d.y4
		end
	end
end

create_surface(xmax - xmin, ymax - ymin)

for i, d in ipairs(drawables) do
	if d.kind == "glyph" then
		draw_glyph(d.glyph, d.x - xmin, d.y - ymin)
	elseif d.kind == "line" then
		draw_line(d.t, d.x1 - xmin, d.y1 - ymin, d.x2 - xmin, d.y2 - ymin)
	elseif d.kind == "quad" then
		draw_quad(d.t, d.x1 - xmin, d.y1 - ymin, d.x2 - xmin, d.y2 - ymin, d.x3 - xmin, d.y3 - ymin, d.x4 - xmin, d.y4 - ymin)
	end
end

-- draw staff
for y=0,em*4,em do
	draw_line(1, xoffset - xmin, y + yoffset - ymin, x + xoffset - xmin, y + yoffset - ymin)
end
