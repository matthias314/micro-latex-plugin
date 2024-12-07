-- micro editor plugin for LaTeX support

errors = import("errors")

micro = import("micro")
config = import("micro/config")
buffer = import("micro/buffer")
action = import("micro/action")
shell = import("micro/shell")
util = import("micro/util")

function findfirst(v, x)
    for i = 1, #v do
        if v[i] == x then return i end
    end
    return nil
end

function concat(v, sep)
    local s = ""
    for i = 1, #v do
        s = s..v[i]
        s = i == #v and s or s.."|"
    end
    return s
end

function sort_unique(l)
    table.sort(l)
    for i = #l-1, 1, -1 do
        if l[i] == l[i+1] then
            table.remove(l, i+1)
        end
    end
end

function replace_suffix(s, oldsuffix, newsuffix)
    if string.sub(s, -#oldsuffix-1, -1) == "."..oldsuffix then
        return string.sub(s, 1, -#oldsuffix-1)..newsuffix
    end
end

function get_loc(v, i)
-- if i is nil, then v is a Cursor
-- otherwise v is a list of buffer.Loc's and i is the desired position
    local loc = i and v[i] or v.Loc
    return buffer.Loc(loc.X, loc.Y)
end

function get_string(buf, loc1, loc2)
    return util.String(buf:Substr(loc1, loc2))
end

function set_bufpane_active(bp)
    local tab = bp:Tab()
    local pane = tab:GetPane(bp:ID())
    tab:SetActive(pane)
end

function get_env(buf, down, loc)
    if not loc then
        local cur = buf:GetActiveCursor()
        loc = get_loc(cur)
    end
	local level = 0, match, found
    while level >= 0 do
        local loc1 = down and loc or buf:Start()
        local loc2 = down and buf:End() or loc
        match, found = buf:FindNextSubmatch("(?-i)\\\\(begin|end){([[:alpha:]]*\\*?)}", loc1, loc2, loc, down)
        if not found then return end
    	local be = get_string(buf, get_loc(match, 3), get_loc(match, 4))
    	level = level + (down and 1 or -1)*(be == "begin" and 1 or -1)
        loc = get_loc(match, down and 2 or 1)
    end
    local loc1, loc2 = get_loc(match, 5), get_loc(match, 6)
    return get_string(buf, loc1, loc2), loc1, loc2
end

function insert_env(bp, env)
    curs = bp.Buf:GetCursors()
    for i = 1, #curs do
        bp.Cursor = curs[i]
        local cur = bp.Cursor
        local sel
        if cur:HasSelection() then
            local loc1 = get_loc(cur.CurSelection, 1)
            local loc2 = get_loc(cur.CurSelection, 2)
            sel = get_string(bp.Buf, loc1, loc2)
            cur:DeleteSelection()
        end
        bp:Insert("\\begin{"..env.."}")
        bp:InsertNewline()
        bp:Insert("\\end{"..env.."}")
        bp:CursorUp()
        bp:EndOfLine()
        bp:InsertNewline()
        if sel then
            local loc1 = get_loc(cur)
            bp:Insert(sel)
            local loc2 = get_loc(cur)
            bp.Cursor:SetSelectionStart(loc1)
            bp.Cursor:SetSelectionEnd(loc2)
            bp:IndentSelection()
            bp.Cursor:ResetSelection()
            -- TODO: better indentation?
            --[=[
            if string.sub(sel, -1, -1) == "\n" then
                bp:InsertTab()
            end
            ]=]
        else
            bp:InsertTab()
        end
    end
end

--[[
function insert_env(bp, env)
    curs = bp.Buf:GetCursors()
    for i = 1, #curs do
        bp.Cursor = curs[i]
        local cur = bp.Cursor
        local loc1, loc2
        if cur:HasSelection() then        
            loc1 = get_loc(cur.CurSelection, 1)
            bp:IndentSelection()
            loc2 = get_loc(cur.CurSelection, 2)
            bp.Cursor:ResetSelection()
        else
            loc1 = buffer.Loc(cur.Loc.X, cur.Loc.Y)
            bp:InsertTab()
            loc2 = buffer.Loc(cur.Loc.X, cur.Loc.Y)
        end
        bp:InsertNewline()
        -- bp:Insert("@")
        -- local loc2 = buffer.Loc(cur.Loc.X, cur.Loc.Y)
        bp:OutdentLine()
        bp:Insert("\\end{"..env.."}")
        bp:GotoLoc(loc1)
        bp:Insert("\\begin{"..env.."}")
        bp:InsertNewline()        
        bp:GotoLoc(buffer.Loc(loc2.X, loc2.Y+1))
        bp:Insert("@")
        -- micro.TermMessage(loc2, cur.Loc)
        -- bp:CursorUp()
        -- bp:EndOfLine()        
    end
end
--]]

function completer(tags)
    return function(buf)
        local raw = buf:GetArg()
        local input = ""
        for i = 1, #raw do
            if string.sub(raw, i, i) == "{" then
                input = string.sub(raw, i+1, -1)
            end
        end
        local completions, suggestions = {}, {}
        for _, tag in ipairs(tags) do
            if string.sub(tag, 1, #input) == input then
                table.insert(suggestions, tag)
                table.insert(completions, string.sub(tag, #input+1, -1))
            end
        end
        return completions, suggestions
    end
end

function findall_tags(buf, macro)
    local tags = {}
    local matches = buf:FindAllSubmatch("(?-i)\\\\"..macro.."{([^} ]+)}", buf:Start(), buf:End())
    for i = 1, #matches do
        local match = matches[i]
        local loc1, loc2 = get_loc(match, 3), get_loc(match, 4)
        local j = findfirst(buf:LineBytes(loc1.Y), 37) -- string.char(37) == "%"
        if not j or j > loc1.X then
            -- we are probably not inside a comment
	        local tag = get_string(buf, loc1, loc2)
            table.insert(tags, tag)
        end
    end
    sort_unique(tags)
    return tags
end

function change_env_end(buf, loc, newenv)
    local _, loc1, loc2 = get_env(buf, true, loc)
    buf:Remove(loc1, loc2)
    buf:Insert(loc1, newenv)
end

function insert_bibtags(tags, bibfile)
    local buf, err = buffer.NewBufferFromFile(bibfile)
    if err then
        return err
    elseif buf:LinesNum() == 1 then
        return errors.New("file empty or non-existing")
    end
    local matches = buf:FindAllSubmatch("^@[[:alnum:]]+{([^\"#%'(),={}]+),", buf:Start(), buf:End())
    for i = 1, #matches do
        local match = matches[i]
	    local tag = get_string(buf, get_loc(match, 3), get_loc(match, 4))
        table.insert(tags, tag)
    end
    buf:Close()
end

function preAutocomplete(bp)
    local buf = bp.Buf
    if buf:FileType() ~= "tex" or buf.HasSuggestions then return true end

    local loc = get_loc(bp.Cursor)
    local match, found = buf:FindNextSubmatch("(?-i)\\\\([[:alpha:]]*)(?:\\[[^]]*\\])?{([^} ]*)", buffer.Loc(0, loc.Y), loc, loc, false)
    if not found then return true end
    local macro = get_string(buf, get_loc(match, 3), get_loc(match, 4))
    if get_loc(match, 2) ~= get_loc(match, 6) then return true end

    local tags
    if macro == "begin" then
        tags = findall_tags(buf, "end")
    elseif findfirst(config.GetGlobalOption("latex.refmacros"), macro) then
        tags = findall_tags(buf, "label")
    elseif findfirst(config.GetGlobalOption("latex.citemacros"), macro) then
        local bibre = "(?:"..concat(config.GetGlobalOption("latex.bibmacros"), "|")..")"
        local bibs = findall_tags(buf, bibre)
        if #bibs == 0 then
            tags = findall_tags(buf, "bibitem")
        else
            tags = {}
            for i = 1, #bibs do
                err = insert_bibtags(tags, bibs[i])
                if err then
                    micro.InfoBar():Error("Error reading bib file "..bibs[i]..": "..err:Error())
                    return false
                end
            end
            sort_unique(tags)
        end
    end

    -- TODO: this is a hack
	buf.Completions, buf.Suggestions = completer(tags)(buf)
	buf.CurSuggestion = -1
	buf.HasSuggestions = true

    if macro == "begin" and #buf.Suggestions ~= 0 then
        change_env_end(buf, loc, suggestions[1])
    end

	return true
end

function on_cycle_autocomplete(bp)
    local buf = bp.Buf
    if buf:FileType() == "tex" then
        local loc = get_loc(bp.Cursor)
        local match, found = buf:FindNextSubmatch("(?-i)\\\\([[:alpha:]]*)(?:\\[[^]]*\\])?{", buffer.Loc(0, loc.Y), loc, loc, false)
        if not found then return false end
        local tag = get_string(buf, get_loc(match, 3), get_loc(match, 4))
        if tag == "begin" then
            local input = buf.Suggestions[buf.CurSuggestion+1]
            change_env_end(buf, loc, input)
            buf.HasSuggestions = true
        end
    end
    return true
end

function onAutocomplete(bp)
    return on_cycle_autocomplete(bp)
end

function onCycleAutocompleteBack(bp)
    return on_cycle_autocomplete(bp)
end

function insert_env_prompt(bp)
    micro.InfoBar():Prompt("Environment: ", "", "Latex/Environment", nil,
        function(env, cancel)
            if not cancel then insert_env(bp, env) end
        end)
end

function change_env(bp, env)
    local buf = bp.Buf
    local env1, loc11, loc12 = get_env(buf, false)
    local env2, loc21, loc22 = get_env(buf, true)
    if not env1 then
        micro.InfoBar():Error("Malformed environment: no '\\begin' found")
    elseif not env2 then
        micro.InfoBar():Error("Malformed environment: no '\\end{", env1, "}' found")
    elseif env1 ~= env2 then
        micro.InfoBar():Error("Unbalanced environment: '",
            env1, "' (line ", loc12.Y+1, ") ended by '", env2, "' (line ", loc22.Y+1, ")")
    else
        bp.Buf:Replace(loc11, loc12, env)
        bp.Buf:Replace(loc21, loc22, env)
    end
end

function change_env_prompt(bp)
    local buf = bp.Buf
    local env1, loc11, loc12 = get_env(buf, false)
    local env2, loc21, loc22 = get_env(buf, true)
    if not env1 then
        micro.InfoBar():Error("Malformed environment: no '\\begin' found")
    elseif not env2 then
        micro.InfoBar():Error("Malformed environment: no '\\end{", env1, "}' found")
    elseif env1 ~= env2 then
        micro.InfoBar():Error("Unbalanced environment: '",
            env1, "' (line ", loc12.Y+1, ") ended by '", env2, "' (line ", loc22.Y+1, ")")
    else
        micro.InfoBar():Prompt("Environment: ", env1, "Latex/Environment", nil,
            function(env, cancel)
                if not cancel then
                    bp.Buf:Replace(loc11, loc12, env)
                    bp.Buf:Replace(loc21, loc22, env)
                end
            end)
    end
end

function log(bp)
    if logbp then
        return logbp
    elseif logbuf then
        logbp = bp:HSplitBuf(logbuf)
        return logbp
    else
        micro.InfoBar():Error("No latexmk log available")
    end
end

function compile(bp)
    bp:Save()
    local buf = bp.Buf
    local path = buf.Path
    -- micro.InfoBar():Message("Compiling ", path, " ...")
    -- micro.InfoBar():Display()  -- TODO: does this do anything?
    local mode = buf.Settings["latex.mode"]
    local output, err = shell.ExecCommand("latexmk", "-cd", "-"..mode, path)
    if logbuf then
        logbuf.EventHandler:Remove(logbuf:Start(), logbuf:End())
    else
        logbuf = buffer.NewLogBuffer("", "Log-Latexmk")
    end
    logbuf.EventHandler:Insert(logbuf:End(), output)
    if err then
        micro.InfoBar():Error("Error compiling ", path)
        logbp = log(bp)
        local match, found = logbuf:FindNext("(?-i)^! Emergency stop", logbuf:Start(), logbuf:End(), logbuf:End(), false, true)
        if found then
            local loc = get_loc(match, 1)
            logbp:GotoLoc(loc)
            logbp:Center()
            local match, found = logbuf:FindNextSubmatch("(?-i)^l\.(\\d+)", loc, logbuf:End(), loc, true)
            if found then
                local line = get_string(logbuf, get_loc(match, 3), get_loc(match, 4))
                bp:GotoLoc(buffer.Loc(0, line-1))
                bp:Center()
            end
        end
        set_bufpane_active(bp)
    else
        if logbp then
            logbp:Quit()
            logbp = nil -- TODO: why is this necessary?
        end
        micro.InfoBar():Message("Compiled ", path)
    end
end

function view(bp)
    local buf = bp.Buf
    local mode = buf.Settings["latex.mode"]
    if buf:FileType() ~= "tex" then
        micro.InfoBar():Error("Not a TeX file")
        return
    elseif string.find(mode, "pdf") == 1 then
        path = replace_suffix(buf.Path, "tex", "pdf")
        prog = config.GetGlobalOption("latex.pdfviewer")
    elseif mode == "ps" then
        path = replace_suffix(buf.Path, "tex", "ps")
        prog = config.GetGlobalOption("latex.psviewer")
    elseif string.find(mode, "dvi") == 1 then
        path = replace_suffix(buf.Path, "tex", "dvi")
        prog = config.GetGlobalOption("latex.dviviewer")
    end
    if path then
        shell.JobSpawn(prog, {path}, nil, nil, nil)
    else
        micro.InfoBar():Error("File name not supported")
    end
end

function onBufferOpen(buf)
    if buf:FileType() == "tex" then
        buf.Settings["autoclose.pairs"] = {"()", "{}", "[]", "$$"}
    end
    return true
end

function onQuit(bp)
    if bp.Buf == logbuf then
        logbp = nil
    end
end

function preRune(bp, r)
    local buf = bp.Buf
    if buf:FileType() ~= "tex" then return true end
    local cur = get_loc(bp.Cursor)
    if r == "\""  and config.GetGlobalOption("latex.smartquotes") then
        local rune = cur.X == 0 and " " or util.RuneAt(buf:Line(cur.Y), cur.X-1)
        if rune == "\\" then
            return true
        elseif string.find(" \t~(", rune, 1, true) then
            bp:Insert("``")
        else
            bp:Insert("''")
        end
        return false
    elseif cur.X >= 1 and util.RuneAt(buf:Line(cur.Y), cur.X-1) == "\\" then
        if r == "$" then
            bp:Insert(r)
            return false
        end
        autoclosePairs = buf.Settings["autoclose.pairs"]
        for i = 1, #autoclosePairs do
            if r == util.RuneAt(autoclosePairs[i], 0) then
                bp:Insert(r.."\\"..util.RuneAt(autoclosePairs[i], 1))
                bp:CursorLeft()
                bp:CursorLeft()
                return false
            end
        end
        return true
    end
end

function onRune(bp, r)
    local buf = bp.Buf
    if buf:FileType() ~= "tex" then return true end
    if config.GetGlobalOption("latex.smartbraces") and (r == "^" or r == "_") then
        bp:Insert("{}")
        bp:CursorLeft()
    end
    return false
end

-- global options: access with config.GetGlobalOption("plugin.option")
config.RegisterGlobalOption("latex", "smartbraces", true)
config.RegisterGlobalOption("latex", "smartquotes", true)
config.RegisterGlobalOption("latex", "keymod", "Alt")
config.RegisterGlobalOption("latex", "refmacros", {"ref", "eqref", "cref", "Cref"})
-- \cref and \Cref are from cleveref
config.RegisterGlobalOption("latex", "citemacros", {"cite", "textcite", "parencite"})
config.RegisterGlobalOption("latex", "bibmacros", {"addbibresource", "addglobalbib", "addsectionbib", "bibliography"})
-- \textcite and \parencite are from biblatex
config.RegisterGlobalOption("latex", "dviviewer", "xdvi")
config.RegisterGlobalOption("latex", "psviewer", nil)
config.RegisterGlobalOption("latex", "pdfviewer", nil)

-- buffer-local options: access with bp.Buf.Settings["plugin.option"]
config.RegisterCommonOption("latex", "mode", "pdf")

keys = {
    ["a"] = "\\alpha",
    ["b"] = "\\beta",
    ["c"] = "\\chi", -- or "h"?
    ["d"] = "\\delta",
    ["e"] = "\\epsilon",
    ["f"] = "\\phi",
    ["g"] = "\\gamma",
    ["h"] = "\\eta", -- ?
    ["i"] = "\\iota",
    ["j"] = "\\theta", -- ?
    ["k"] = "\\kappa",
    ["l"] = "\\lambda",
    ["m"] = "\\mu",
    ["n"] = "\\nu",
    ["o"] = "\\omega",
    ["p"] = "\\pi",
    ["r"] = "\\rho",
    ["s"] = "\\sigma",
    ["t"] = "\\tau",
    ["w"] = "\\psi", -- ?
    ["x"] = "\\xi",
    ["y"] = "\\upsilon",
    ["z"] = "\\zeta",
    ["C"] = "\\Chi",
    ["D"] = "\\Delta",
    ["F"] = "\\Phi",
    ["G"] = "\\Gamma",
    ["J"] = "\\Theta",
    ["L"] = "\\Lambda",
    ["O"] = "\\Omega",
    ["P"] = "\\Pi",
    ["S"] = "\\Sigma",
    ["W"] = "\\Psi",
    ["X"] = "\\Xi",
    ["Y"] = "\\Upsilon",

    ["+"] = "\\oplus",
    ["-"] = "\\ominus",
    ["*"] = "\\otimes",
}

function init()
    local mod = config.GetGlobalOption("latex.keymod")
    for key, val in pairs(keys) do
        key = string.sub(mod, 1, 1) ~= "<" and key or "<"..key..">"
        config.TryBindKey(mod..key, "command:insert '"..val.."'", false)
    end

    config.MakeCommand("latex_insert_env", function(bp, args)
            for i = 1, #args do
                insert_env(bp, args[i])
            end
        end, completer(envs))
    config.MakeCommand("latex_change_env", function(bp, args)
            if #args == 1 then
                change_env(bp, args[1])
            else
                micro.InfoBar():Error("Wrong number of arguments")
            end
        end, nil)
    config.MakeCommand("latex_compile", function(bp, args) compile(bp) end, nil)
    config.MakeCommand("latex_log", function(bp, args) log(bp) end, nil)
    config.MakeCommand("latex_view", function(bp, args) view(bp) end, nil)
end
