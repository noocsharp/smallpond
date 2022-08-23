-- parse
local em = 8

local noteheadBlock = 0xE0A4
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
	place = function(char)
		local NOTES = "abcdefg"
		local s, _ = string.find(NOTES, char)
		return 6 - s
	end
}

local bass = {
	glyph = fClef,
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

		local s, e, note = string.find(text, "^([abcdefg])", i)
		if note then
			i = i + e - s + 1
			return {command="newnote", note=note}
		end

		error("unknown token")
	end
end

f = assert(io.open("score.sp"))

local x = 10
staff = {}
command_dispatch = {
	newnote = function(data)
		local i = staff.clef.place(data.note)
		table.insert(staff, {kind="notehead", x=x, y=(em*i) / 2})
		x = x + 20
	end,
	changeclef = function(data)
		if data.kind == "treble" then
			staff.clef = treble
			table.insert(staff, {kind="clef", class=treble, x=x, y=3*em})
		elseif data.kind == "bass" then
			staff.clef = bass
			table.insert(staff, {kind="clef", class=bass, x=x, y=em})
		end
		x = x + 40
	end,
	changetime = function(data)
		table.insert(staff, {kind="time", x=x, y=em, num=data.num, denom=data.denom})
		x = x + 30
	end
}

for tok in parse(f:read("*a")) do
	local func = assert(command_dispatch[tok.command])
	func(tok)
end

-- determine staff width, the +20 is a hack, should be determined from notehead width + some padding
local staff_width = staff[#staff].x + 20
local yoffset = 20
local xoffset = 20

-- draw staff
for y=0,em*4,em do
	draw_line(xoffset, y + yoffset, staff_width + xoffset, y + yoffset)
end

for i, el in ipairs(staff) do
	if el.kind == "notehead" then
		draw_glyph(noteheadBlock, xoffset + el.x, yoffset + el.y)
	elseif el.kind == "clef" then
		draw_glyph(el.class.glyph, xoffset + el.x, yoffset + el.y)
	elseif el.kind == "time" then
		-- TODO: draw multidigit time signatures properly
		draw_glyph(numerals[el.num], xoffset + el.x, yoffset + el.y)
		draw_glyph(numerals[el.denom], xoffset + el.x, yoffset + el.y + 2*em)
	end
end
