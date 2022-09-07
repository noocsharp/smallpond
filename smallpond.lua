-- parse
local em = 8

local Glyph = {
	["noteheadWhole"] = 0xE0A2,
	["noteheadHalf"] = 0xE0A3,
	["noteheadBlack"] = 0xE0A4
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
staff = {}
command_dispatch = {
	newnote = function(data)
		local i = staff.clef.place(data.note)
		if data.count == 1 then
			table.insert(staff, {kind="notehead", glyph="noteheadWhole", time=time, y=(em*i) / 2})
		elseif data.count == 2 then
			local head = {kind="notehead", glyph="noteheadHalf", time=time, y=(em*i) / 2}
			table.insert(staff, head)
			table.insert(staff, {kind="stem", head=head})
		elseif data.count == 4 then
			local head = {kind="notehead", glyph="noteheadBlack", time=time, y=(em*i) / 2}
			table.insert(staff, head)
			table.insert(staff, {kind="stem", head=head})
		elseif data.count == 8 then
			table.insert(staff, {kind="notehead", glyph="noteheadBlack", time=time, y=(em*i) / 2})
		else
			error("oops")
		end
		time = time + 100 / data.count
	end,
	changeclef = function(data)
		if data.kind == "treble" then
			staff.clef = treble
			table.insert(staff, {kind="clef", class=treble, x=x, y=3*em})
		elseif data.kind == "bass" then
			staff.clef = bass
			table.insert(staff, {kind="clef", class=bass, x=x, y=em})
		end
	end,
	changetime = function(data)
		table.insert(staff, {kind="time", x=x, y=em, num=data.num, denom=data.denom})
	end,
	barline = function(data)
		table.insert(staff, {kind="barline"})
	end
}

for tok in parse(f:read("*a")) do
	local func = assert(command_dispatch[tok.command])
	func(tok)
end

-- determine staff width, the +20 is a hack, should be determined from notehead width + some padding
local yoffset = 20
local xoffset = 20
local x = 10
local lasttime = 0

for i, el in ipairs(staff) do
	if el.kind == "notehead" then
		draw_glyph(Glyph[el.glyph], xoffset + x, yoffset + el.y)
		el.x = x
		x = x + (el.time - lasttime)
		lasttime = el.time
	elseif el.kind == "stem" then
		draw_line(1, el.head.x + xoffset + 0.5, yoffset + el.head.y + .188*em, el.head.x + xoffset + 0.5, el.head.y + yoffset + 3.5*em)
	elseif el.kind == "barline" then
		x = x + 20
		draw_line(1, x + xoffset, yoffset, x + xoffset, yoffset + 4*em)
		x = x + 20
	elseif el.kind == "clef" then
		draw_glyph(el.class.glyph, xoffset + x, yoffset + el.y)
		x = x + 30
	elseif el.kind == "time" then
		-- TODO: draw multidigit time signatures properly
		draw_glyph(numerals[el.num], xoffset + x, yoffset + el.y)
		draw_glyph(numerals[el.denom], xoffset + x, yoffset + el.y + 2*em)
		x = x + 30
	end
end

-- draw staff
for y=0,em*4,em do
	draw_line(1, xoffset, y + yoffset, x + xoffset, y + yoffset)
end
