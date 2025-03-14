-- micro editor plugin for LaTeX support

--[[ from https://pkg.go.dev/layeh.com/gopher-luar#New
Pointer values can be compared for equality. The pointed to value can be
changed using the pow operator (pointer = pointer ^ value). A pointer can
be dereferenced using the unary minus operator (value = -pointer).

Calling an array, slice or map returns an iterator over the elements,
analogous to ipairs and pairs.
--]]

errors = import("errors")
filepath = import("path/filepath")

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

function getAbsPath(buf, file)
    return filepath.IsAbs(file) and file or filepath.Join(filepath.Dir(buf.AbsPath), file)
end

function get_string(buf, loc1, loc2)
    return util.String(buf:Substr(loc1, loc2))
end

function set_bufpane_active(bp)
    local tab = bp:Tab()
    local pane = tab:GetPane(bp:ID())
    tab:SetActive(pane)
end

function insert_brackets(bp, left, right)
    local curs = bp.Buf:GetCursors()
    for _, cur in curs() do
        bp.Cursor = cur
        bp:Insert(left)
        local x = bp.Cursor.X
        bp:Insert(right)
        for _ = 1, bp.Cursor.X-x do
            bp.Cursor:Left()
        end
    end
end

rgrp_env = buffer.NewRegexpGroup("\\\\(begin|end){([[:alpha:]]*\\*?)}")

function get_env(buf, down, loc)
    if not loc then
        loc = -buf:GetActiveCursor().Loc
    end
    local level = 0, match
    while level >= 0 do
        if down then
            match = buf:FindDownSubmatch(rgrp_env, loc, buf:End())
        else
            match = buf:FindUpSubmatch(rgrp_env, buf:Start(), loc)
        end
        if not match then return end
        local be = get_string(buf, -match[3], -match[4])
        level = level + (down and 1 or -1)*(be == "begin" and 1 or -1)
        loc = -match[down and 2 or 1]
    end
    local loc1, loc2 = -match[5], -match[6]
    return get_string(buf, loc1, loc2), loc1, loc2
end

function insert_env(bp, env)
    local curs = bp.Buf:GetCursors()
    for _, cur in curs() do
        bp.Cursor = cur
        local sel
        if cur:HasSelection() then
            sel = get_string(bp.Buf, -cur.CurSelection[1], -cur.CurSelection[2])
            cur:DeleteSelection()
        end
        bp:Insert("\\begin{"..env.."}")
        bp:InsertNewline()
        bp:Insert("\\end{"..env.."}")
        bp:CursorUp()
        bp:EndOfLine()
        bp:InsertNewline()
        if sel then
            local loc1 = -cur.Loc
            bp:Insert(sel)
            local loc2 = -cur.Loc
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
    local curs = bp.Buf:GetCursors()
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

function completer(tags, r)
    return function(buf)
        local raw = buf:GetArg()
        local input = ""
        for i = 1, #raw do
            if string.sub(raw, i, i) == r then
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

function findall_submatch(buf, regexp)
    local curloc = -buf:GetActiveCursor().Loc
    local submatches = {}
    buf:FindAllSubmatchFunc(regexp, buf:Start(), buf:End(), function(match)
        local loc0, loc1, loc2 = -match[2], -match[3], -match[4]
        -- local j = findfirst(buf:LineBytes(loc1.Y), 37) -- string.char(37) == "%"
        if (loc0 ~= curloc) then -- and (not j or j > loc1.X) then
            -- we are probably not inside a comment
            local submatch = get_string(buf, loc1, loc2)
            table.insert(submatches, submatch)
        end
    end)
    sort_unique(submatches)
    return submatches
end

function findall_macros(buf)
    local regexp = "\\\\([[:alpha:]]+)"
    return findall_submatch(buf, regexp)
end

function findall_tags(buf, macro)
    local regexp = "\\\\"..macro.."{([^} ]+)}"
    return findall_submatch(buf, regexp)
end

function change_env_end(buf, loc, newenv)
    local env, loc1, loc2 = get_env(buf, true, loc)
    if not env then return end
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
    buf:FindAllSubmatchFunc("^@[[:alnum:]]+{([^\"#%'(),={}]+),", buf:Start(), buf:End(), function(match)
        local tag = get_string(buf, -match[3], -match[4])
        table.insert(tags, tag)
    end)
    buf:Close()
end

rgrp_macro_arg = buffer.NewRegexpGroup("\\\\([[:alpha:]]*)((?:\\[[^]]*\\])?{[^}\\ ]*|)")

function preAutocomplete(bp)
    local buf, cur = bp.Buf, bp.Cursor
    if buf:FileType() ~= "tex" or cur:HasSelection() or buf.HasSuggestions then return true end

    local loc = -cur.Loc
    local macro, tags, r

    local match = buf:FindUpSubmatch(rgrp_macro_arg, buffer.Loc(0, loc.Y), loc)
    if not match or -match[2] ~= loc then return true end

    if -match[5] == -match[6] then -- macro
        r = "\\"
        tags = findall_macros(buf)
    else -- tag
        r = "{"
        macro = get_string(buf, -match[3], -match[4])

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
                for _, bib in pairs(bibs) do
                    if insert_bibtags(tags, getAbsPath(buf, bib)) then
                        micro.InfoBar():Error("Error reading bib file "..bib..": "..err:Error())
                        return false
                    end
                end
                sort_unique(tags)
            end
        end
    end

    completions, suggestions = completer(tags, r)(buf)
    if #suggestions > 0 then
        if macro == "begin" then
            buf.Settings["latex.envs"] = suggestions
        end
        -- TODO: this is a hack
        buf.Completions, buf.Suggestions = completions, suggestions
        buf.HasSuggestions = true
        buf.CurSuggestion = -1
    end

    return true
end

-- compare a Lua list with a Go list
function list_equal(v, w)
    if #v ~= #w then return false end
    for i = 1, #v do
        if v[i] ~= w[i] then return false end
    end
    return true
end

function on_cycle_autocomplete(bp)
    local buf, loc = bp.Buf, -bp.Cursor.Loc
    local envs = buf.Settings["latex.envs"]
    if envs and buf.HasSuggestions and list_equal(buf.Suggestions, envs) then
        local env = buf.Suggestions[buf.CurSuggestion+1]
        change_env_end(buf, loc, env)
        buf.HasSuggestions = true
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

rgrp_stop = buffer.NewRegexpGroup("^! Emergency stop")
rgrp_line = buffer.NewRegexpGroup("^l\\.(\\d+)")

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
        local match = logbuf:FindUp(rgrp_stop, logbuf:Start(), logbuf:End())
        if match then
            local loc = -match[1]
            logbp:GotoLoc(loc)
            logbp:Center()
            local match = logbuf:FindDownSubmatch(rgrp_line, loc, logbuf:End())
            if match then
                local line = get_string(logbuf, -match[3], -match[4])
                if line-1 ~= bp.Cursor.Loc.Y then
                    bp:GotoLoc(buffer.Loc(0, line-1))
                    bp:Center()
                end
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
        shell.JobStart(prog.." "..path, nil, nil, nil)
    else
        micro.InfoBar():Error("File name not supported")
    end
end

function onBufferOpen(buf)
    if buf:FileType() == "tex" then
        buf:SetOptionNative("autoclose.pairs", {"()", "{}", "[]", "$$", "`'"})
    end
end

function onQuit(bp)
    if bp.Buf == logbuf then
        logbp = nil
    end
    return true
end

function preRune(bp, r)
    local buf, cur = bp.Buf, bp.Cursor
    if buf:FileType() ~= "tex" then return true end
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
        for _, pair in autoclosePairs() do
            if r == util.RuneAt(pair, 0) then
                bp:Insert(r.."\\"..util.RuneAt(pair, 1))
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
    if buf:FileType() == "tex" and config.GetGlobalOption("latex.smartbraces") and (r == "^" or r == "_") then
        bp:Insert("{}")
        bp:CursorLeft()
    end
end

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
    ["."] = "\\dots",
    [":"] = "\\colon",
    ["<"] = "\\langle",
    [">"] = "\\rangle",
    ["~"] = "\\tilde",
    ["0"] = "\\emptyset",
}

function preinit()
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
end

function init()
    local mod = config.GetGlobalOption("latex.keymod")
    for key, val in pairs(keys) do
        key = string.sub(mod, 1, 1) ~= "<" and key or "<"..key..">"
        config.TryBindKey(mod..key, "command:insert '"..val.."'", false)
    end

    config.MakeCommand("latex_insert_brackets", function(bp, args)
            if #args == 2 then
                insert_brackets(bp, args[1], args[2])
            else
                micro.InfoBar():Error("Wrong number of arguments")
            end
        end, completer({"\\bigl(", "\\Bigl(", "\\biggl(", "\\Biggl("}))
    config.MakeCommand("latex_insert_env", function(bp, args)
            for _, arg in args() do
                insert_env(bp, arg)
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
