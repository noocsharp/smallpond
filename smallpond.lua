-- parse
local em = 8

local Glyph = {
	["noteheadWhole"] = 0xE0A2,
	["noteheadHalf"] = 0xE0A3,
	["noteheadBlack"] = 0xE0A4,
	["flag8thDown"] = 0xE241,
}

local gClef = 0xE050
local fClef = 0xE062
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

local treble = {
	glyph = gClef,
	yoff = 3*em,
	place = function(char)
		local NOTES = "abcdefg"
		local s, _ = string.find(NOTES, char)
		return 6 - s
	end
}

local bass = {
	glyph = fClef,
	yoff = em,
	place = function(char)
		local NOTES = "abcdefg"
		local s, _ = string.find(NOTES, char)
		return 8 - s
	end
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

		local s, e, note, count = string.find(text, "^([abcdefg])([1248]?)", i)
		if note then
			i = i + e - s + 1
			return {command="newnote", note=note, count=tonumber(count)}
		end

		local s, e = string.find(text, "^|", i)
		if s then
			i = i + e - s + 1
			return {command="barline"}
		end

		error("unknown token")
	end
end

f = assert(io.open("score.sp"))

local time = 0 -- time in increments of denom
-- abstract placement
staff = {}
abstract_dispatch = {
	newnote = function(data)
		local i = staff.clef.place(data.note)
		table.insert(staff, {kind="note", length=data.count, time=time, sy=i})
		time = time + 1 / data.count
	end,
	changeclef = function(data)
		if data.kind == "treble" then
			staff.clef = treble
			table.insert(staff, {kind="clef", class=treble, yoff=3*em})
		elseif data.kind == "bass" then
			staff.clef = bass
			table.insert(staff, {kind="clef", class=bass, yoff=em})
		end
	end,
	changetime = function(data)
		table.insert(staff, {kind="time", num=data.num, denom=data.denom})
	end,
	barline = function(data)
		table.insert(staff, {kind="barline"})
	end
}

for tok in parse(f:read("*a")) do
	local func = assert(abstract_dispatch[tok.command])
	func(tok)
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
		local ry = yoffset + (em*el.sy) / 2
		local glyph
		if el.length == 1 then
			glyph = Glyph["noteheadWhole"]
		elseif el.length == 2 then
			glyph = Glyph["noteheadHalf"]
		elseif el.length == 4 then
			glyph = Glyph["noteheadBlack"]
		elseif el.length == 8 then
			glyph = Glyph["noteheadBlack"]
			table.insert(drawables, {kind="glyph", glyph=Glyph["flag8thDown"], x=rx, y=ry + 3.5*em})
		end
		table.insert(drawables, {kind="glyph", glyph=glyph, x=rx, y=ry})
		if el.length > 1 then
			table.insert(drawables, {kind="line", t=1, x1=rx + 0.5, y1=ry + .188*em, x2=rx + 0.5, y2=ry + 3.5*em})
		end
		x = x + 100 / el.length
		lasttime = el.time
	elseif el.kind == "barline" then
		x = x + 20
		table.insert(drawables, {kind="line", t=1, x1=x + xoffset, y1=yoffset, x2=x + xoffset, y2 = yoffset + 4*em})
		x = x + 20
	elseif el.kind == "clef" then
		table.insert(drawables, {kind="glyph", glyph=el.class.glyph, x=xoffset + x, y=yoffset + el.yoff})
		x = x + 30
	elseif el.kind == "time" then
		-- TODO: draw multidigit time signatures properly
		table.insert(drawables, {kind="glyph", glyph=numerals[el.num], x=xoffset + x, y=yoffset + em})
		table.insert(drawables, {kind="glyph", glyph=numerals[el.denom], x=xoffset + x, y=yoffset + 3*em})
		x = x + 30
	end
end

for i, d in ipairs(drawables) do
	if d.kind == "glyph" then
		draw_glyph(d.glyph, d.x, d.y)
	elseif d.kind == "line" then
		draw_line(d.t, d.x1, d.y1, d.x2, d.y2)
	end
end

-- draw staff
for y=0,em*4,em do
	draw_line(1, xoffset, y + yoffset, x + xoffset, y + yoffset)
end
