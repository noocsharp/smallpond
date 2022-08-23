-- parse
local em = 8

function placement(char)
	assert(char)
	local NOTES = "abcdefg"
	local s, _ = string.find(NOTES, char)
	return s
end

commands = {
	clef = {
		parse = function(text, start)
			-- move past "\clef "
			start = start + 6
			if string.match(text, "^treble", start) then
				return #"\\clef treble", {command="changeclef", kind="treble"}
			else
				error(string.format("unknown clef at offset %s", string.sub(text, start)))
			end
		end
	}
}

function parse(text)
	local i = 1
	return function()
		if i >= #text then return nil end
		local cmd = string.match(text, "^\\(%a+)", i)
		if cmd then
			local size, data = commands[cmd].parse(text, i)
			i = i + size
			return data
		end

		local s, e, note = string.find(text, "^%s*([abcdefg])", i)
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
		local i = placement(data.note)
		table.insert(staff, {kind="notehead", x=x, y=(em*i) / 2})
		x = x + 20
	end,
	changeclef = function(data)
		table.insert(staff, {kind="clef", x=x, y=4*em})
		x = x + 40
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
for y=0,em*5,em do
	draw_line(xoffset, y + yoffset, staff_width + xoffset, y + yoffset)
end

local noteheadBlock = 0xE0A4
local gClef = 0xE050
for i, el in ipairs(staff) do
	if el.kind == "notehead" then
		draw_glyph(noteheadBlock, xoffset + el.x, yoffset + el.y)
	elseif el.kind == "clef" then
		draw_glyph(gClef, xoffset + el.x, yoffset + el.y)
	end
end
