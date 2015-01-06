local M = {}

local cstyle = require "dmd.cstyle"
local icons = require "dmd.icons"
local dsnippets = require "dmd.snippets"
local snippets = _G.snippets
local keys = _G.keys

-- Used for dscanner/ctags symbol finder
local lineDict = {}

-- Used for DCD call tips
local calltips = {}
local currentCalltip = 1

M.PATH_TO_DCD_SERVER = "dcd-client"
M.PATH_TO_DCD_CLIENT = "dcd-client"
M.PATH_TO_DSCANNER = "dscanner"

textadept.editing.comment_string.dmd = '//'
textadept.run.compile_commands.dmd = 'dmd -c -o- %(filename)'
textadept.run.error_patterns.dmd = {
	pattern = '^(.-)%((%d+)%): (.+)$',
	filename = 1, line = 2, message = 3
}

local function registerImages()
	buffer:register_image(1, icons.FIELD)
	buffer:register_image(2, icons.FUNCTION)
	buffer:register_image(3, icons.PACKAGE)
	buffer:register_image(4, icons.MODULE)
	buffer:register_image(5, icons.KEYWORD)
	buffer:register_image(6, icons.CLASS)
	buffer:register_image(7, icons.UNION)
	buffer:register_image(8, icons.STRUCT)
	buffer:register_image(9, icons.INTERFACE)
	buffer:register_image(10, icons.ENUM)
	buffer:register_image(11, icons.ALIAS)
	buffer:register_image(12, icons.TEMPLATE)
end

local function showCompletionList(r)
	registerImages()
	local setting = buffer.auto_c_choose_single
	buffer.auto_c_choose_single = false;
	buffer.auto_c_max_width = 0
	local completions = {}
	for symbol, kind in r:gmatch("([^%s]+)\t(%a)\n") do
		completion = symbol
		if kind == "k" then
			completion = completion .. "?5"
		elseif kind == "v" then
			completion = completion .. "?1"
		elseif kind == "e" then
			completion = completion .. "?10"
		elseif kind == "s" then
			completion = completion .. "?8"
		elseif kind == "g" then
			completion = completion .. "?10"
		elseif kind == "u" then
			completion = completion .. "?7"
		elseif kind == "m" then
			completion = completion .. "?1"
		elseif kind == "c" then
			completion = completion .. "?6"
		elseif kind == "i" then
			completion = completion .. "?9"
		elseif kind == "f" then
			completion = completion .. "?2"
		elseif kind == "M" then
			completion = completion .. "?4"
		elseif kind == "P" then
			completion = completion .. "?3"
		elseif kind == "l" then
			completion = completion .. "?11"
		elseif kind == "t" or kind == "T" then
			completion = completion .. "?12"
		end
		completions[#completions + 1] = completion
	end
	table.sort(completions, function(a, b) return string.upper(a) < string.upper(b) end)
	local charactersEntered = buffer.current_pos - buffer:word_start_position(buffer.current_pos)
	local prevChar = buffer.char_at[buffer.current_pos - 1]
	if prevChar == string.byte('.')
			or prevChar == string.byte(':')
			or prevChar == string.byte(' ')
			or prevChar == string.byte('\t')
			or prevChar == string.byte('(')
			or prevChar == string.byte('[') then
		charactersEntered = 0
	end
	buffer:auto_c_show(charactersEntered, table.concat(completions, " "))
	--buffer.auto_c_fill_ups = "(.["
	buffer.auto_c_choose_single = setting
end

local function showCurrentCallTip()
	local tip = calltips[currentCalltip]
	buffer:call_tip_show(buffer:word_start_position(buffer.current_pos),
		string.format("%d of %d\1\2\n%s", currentCalltip, #calltips,
			calltips[currentCalltip]:gsub("(%f[\\])\\n", "%1\n")
			:gsub("\\\\n", "\\n")))
end

local function showCalltips(calltip)
	currentCalltip = 1
	calltips = {}
	for tip in calltip:gmatch("(.-)\n") do
		if tip ~= "calltips" then
			table.insert(calltips, tip)
		end
	end
	if (#calltips > 0) then
		showCurrentCallTip()
	end
end

local function cycleCalltips(delta)
	if not buffer:call_tip_active() then
		return false
	end
	if delta > 0 then
		currentCalltip = math.max(math.min(#calltips, currentCalltip + 1), 1)
	else
		currentCalltip = math.min(math.max(1, currentCalltip - 1), #calltips)
	end
	showCurrentCallTip()
end

local function runDCDClient(args)
	local command = M.PATH_TO_DCD_CLIENT .. " " .. args .. " -c" .. buffer.current_pos
	local p = spawn(command)
	p:write(buffer:get_text():sub(1, buffer.length))
	p:close()
	return p:read("*a")
end

local function showDoc()
	local r = runDCDClient("-d")
	if r ~= "\n" then
		showCalltips(r)
	end
end

local function gotoDeclaration()
	local r = runDCDClient("-l")
	if r ~= "Not found\n" then
		path, position = r:match("^(.-)\t(%d+)")
		if (path ~= nil and position ~= nil) then
			if (path ~= "stdin") then
				io.open_file(path)
			end
			buffer:goto_pos(tonumber(position))
			buffer:vertical_centre_caret()
			buffer:word_right_end_extend()
		end
	end
end

local function expandContext(meta)
	local patterns = {"struct:(%w+)", "class:([%w_]+)", "template:([%w_]+)",
		"interface:([%w_]+)", "union:([%w_]+)", "function:([%w_]+)"}
	if meta == nil or meta == "" then return "" end
	for item in meta:gmatch("%w+:[%w%d_]+") do
		for _, pattern in ipairs(patterns) do
			local result = item:match(pattern)
			if result ~= nil then return result end
		end
	end
	return ""
end

-- Expands ctags type abbreviations to full words
local function expandCtagsType(tagType)
    if tagType == "g" then return "enum"
    elseif tagType == "e" then return ""
    elseif tagType == "v" then return "variable"
    elseif tagType == "i" then return "interface"
    elseif tagType == "c" then return "class"
    elseif tagType == "s" then return "struct"
    elseif tagType == "f" then return "function"
    elseif tagType == "u" then return "union"
    elseif tagType == "T" then return "template"
	else return "" end
end

local function onSymbolListSelection(list, item)
	list:close()
	buffer:goto_line(item[4] - 1)
	buffer:vertical_centre_caret()
end

-- Uses dscanner's --ctags option to create a symbol index for the contents of
-- the buffer. Automatically uses Textadept's normal dialogs or textredux lists.
local function symbolIndex()
	local fileName = os.tmpname()
	local tmpFile = io.open(fileName, "w")
	tmpFile:write(buffer:get_text():sub(1, buffer.length))
	tmpFile:flush()
	tmpFile:close()
	local command = M.PATH_TO_DSCANNER .. " --ctags " .. fileName
	local p = spawn(command)
	local r = p:read("*a")
	os.remove(fileName)
	local symbolList = {}
	local i = 0

	for line in r:gmatch("(.-)\n") do
		if not line:match("^!") then
			local name, file, lineNumber, tagType, meta = line:match(
				"([~%w_]+)\t([%w/_ ]+)\t(%d+);\"\t(%w)\t?(.*)")
			if package.loaded['textredux'] then
				table.insert(symbolList, {name, expandCtagsType(tagType), expandContext(meta), lineNumber})
			else
				table.insert(symbolList, name)
				table.insert(symbolList, expandCtagsType(tagType))
				table.insert(symbolList, expandContext(meta))
				table.insert(symbolList, lineNumber)
			end
			lineDict[i + 1] = tonumber(lineNumber - 1)
			i = i + 1
		end
	end

	local headers = {"Name", "Kind", "Context", "Line"}

	if package.loaded['textredux'] then
		local reduxlist = require 'textredux.core.list'
		local reduxstyle = require 'textredux.core.style'
		local list = reduxlist.new('Go to symbol')
		list.items = symbolList
		list.on_selection = onSymbolListSelection
		list.headers = headers
		list.column_styles = { reduxstyle.variable, reduxstyle.keyword, reduxstyle.class, reduxstyle.number }
		list:show()
	else
		local button, i = ui.dialogs.filteredlist{
			title = "Go to symbol",
			columns = headers,
			items = symbolList
		}
		if i ~= nil then
			buffer:goto_line(lineDict[i])
			buffer:vertical_centre_caret()
		end
	end
end

local function autocomplete()
	registerImages()
	local r = runDCDClient("")
	if r ~= "\n" then
		if r:match("^identifiers.*") then
			showCompletionList(r)
		else
			showCalltips(r)
		end
	end
	if not buffer:auto_c_active() then
		textadept.editing.autocomplete("word")
	end
end

-- Autocomplete handler. Launches DCD on '(', '.', or ':' character insertion
events.connect(events.CHAR_ADDED, function(ch)
	if buffer:get_lexer() ~= "dmd" or ch > 255 then return end
	if string.char(ch) == '(' or string.char(ch) == '.' or string.char(ch) == ':' then
		autocomplete(ch)
	end
end)

-- Run dscanner's static analysis after saves and print the warnings and errors
-- reported to the buffer as annotations
events.connect(events.FILE_AFTER_SAVE, function()
	if buffer:get_lexer() ~= "dmd" then return end
	buffer:annotation_clear_all()
	local command = M.PATH_TO_DSCANNER .. " --styleCheck 2>&1 " .. buffer.filename
	local p = io.popen(command)
	for line in p:lines() do
		lineNumber, column, level, message = string.match(line, "^.-%((%d+):(%d+)%)%[(%w+)%]: (.+)$")
		if lineNumber == nil then return end
		local l = tonumber(lineNumber) - 1
		if l >= 0 then
			local c = tonumber(column)
			if level == "error" then
				buffer.annotation_style[l] = 8
			elseif buffer.annotation_style[l] ~= 8 then
				buffer.annotation_style[l] = 2
			end

			local t = buffer.annotation_text[l]
			if #t > 0 then
				buffer.annotation_text[l] = buffer.annotation_text[l] .. "\n" .. message
			else
				buffer.annotation_text[l] = message
			end
		end
	end
end)

-- Handler for clicks on the up and down arrow on function call tips
events.connect(events.CALL_TIP_CLICK, function(arrow)
	if buffer:get_lexer() ~= "dmd" then return end
	if arrow == 1 then
		cycleCalltips(-1)
	elseif arrow == 2 then
		cycleCalltips(1)
	end
end)

-- Spawn the dcd-server
M.serverProcess = spawn(M.PATH_TO_DCD_SERVER)

-- Set an event handler that shuts down the DCD server, but only if this module
-- successfully started it. Do nothing if somebody else owns the server instance
events.connect(events.QUIT, function()
	if (M.serverProcess:status() == running) then
		spawn("dcd-client", {"--shutdown"})
		if (M.serverProcess:status() == "running") then M.serverProcess:kill() end
	end
end)

-- Key bindings
keys.dmd = {
	[keys.LANGUAGE_MODULE_PREFIX] = {
		m = { io.open_file,
		(_USERHOME..'/modules/dmd/init.lua'):iconv('UTF-8', _CHARSET) },
	},
	['a\n'] = {cstyle.newline},
	['s\n'] = {cstyle.newline_semicolon},
	['c;'] = {cstyle.endline_semicolon},
	['}'] = {cstyle.match_brace_indent},
	['c{'] = {cstyle.openBraceMagic, true},
	['\n'] = {cstyle.enter_key_pressed},
	['c\n'] = {autocomplete},
	['cH'] = {showDoc},
	['down'] = {cycleCalltips, 1},
	['up'] = {cycleCalltips, -1},
	['cG'] = {gotoDeclaration},
	['cM'] = {symbolIndex},
}

-- Snippets
if type(snippets) == 'table' then
	snippets.dmd = dsnippets.snippets
end

function M.set_buffer_properties()
end

return M
