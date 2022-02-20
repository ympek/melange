vim.cmd("packadd lush.nvim")
local lush = require("lush")
local uv = vim.loop

-- Reload melange module
local function get_colorscheme(variant)
    package.loaded["melange"] = nil
    vim.opt.background = variant
    return require("melange")
end

-- Get the directory where the melange plugin is located
local function get_melange_dir()
    return debug.getinfo(1).source:match("@?(.*/)"):gsub("/lua/melange/$", "")
end

-- Write a string to a file
local function fwrite(str, file)
    local fd = assert(uv.fs_open(file, "w", 420), "Failed  to write to file " .. file) -- 0o644
    uv.fs_write(fd, str, -1)
    assert(uv.fs_close(fd))
end

local function mkdir(dir)
    return assert(uv.fs_mkdir(dir, 493), "Failed to create directory " .. dir) -- 0o755
end

-- Perl-like interpolation
local function interpolate(str, tbl)
    return str:gsub("%$([%w_]+)", function(k)
        return tostring(tbl[k])
    end)
end

-- Turn melange naming conventions into more common ANSI names
local function get_palette16(variant)
    local colors = get_colorscheme(variant).Melange.lush
    return {
        bg = colors.a.bg,
        fg = colors.a.fg,
        black = colors.a.overbg,
        red = colors.c.red,
        green = colors.c.green,
        yellow = colors.b.yellow,
        blue = colors.b.blue,
        magenta = colors.c.magenta,
        cyan = colors.c.cyan,
        white = colors.a.com,
        brblack = colors.a.sel,
        brred = colors.b.red,
        brgreen = colors.b.green,
        bryellow = colors.b.yellow,
        brblue = colors.b.blue,
        brmagenta = colors.b.magenta,
        brcyan = colors.b.cyan,
        brwhite = colors.a.faded,
    }
end

-- VIM --

local vim_term_colors = [[
let g:terminal_color_0  = '$black'
let g:terminal_color_1  = '$red'
let g:terminal_color_2  = '$green'
let g:terminal_color_3  = '$yellow'
let g:terminal_color_4  = '$blue'
let g:terminal_color_5  = '$magenta'
let g:terminal_color_6  = '$cyan'
let g:terminal_color_7  = '$white'
let g:terminal_color_8  = '$brblack'
let g:terminal_color_9  = '$brred'
let g:terminal_color_10 = '$brgreen'
let g:terminal_color_11 = '$bryellow'
let g:terminal_color_12 = '$brblue'
let g:terminal_color_13 = '$brmagenta'
let g:terminal_color_14 = '$brcyan'
let g:terminal_color_15 = '$brwhite'
]]

local viml_template = [[
" THIS FILE WAS AUTOMATICALLY GENERATED
hi clear
syntax reset
set t_Co=256
let g:colors_name = 'melange'
if &background == 'dark'
$dark_term
$dark
else
$light_term
$light
endif
]]

local function viml_build()
    local vimcolors = {}
    for _, l in ipairs({ "dark", "light" }) do
        -- Compile lush table, concatenate to a single string, and remove blend property
        vimcolors[l] = table.concat(vim.fn.sort(lush.compile(get_colorscheme(l), { exclude_keys = { "blend" } })), "\n")
        vimcolors[l .. "_term"] = interpolate(vim_term_colors, get_palette16(l))
    end
    return fwrite(interpolate(viml_template, vimcolors), get_melange_dir() .. "/colors/melange.vim")
end

-- ITERM2 --

local function iterm_color(color)
    local hsluv_to_rgb = require("lush.vivid.hsluv.lib").hsluv_to_rgb
    local tbl = hsluv_to_rgb({ color.h, color.s, color.l })
    return {
        ["Color Space"] = "sRGB",
        ["Red Component"] = tbl[1],
        ["Blue Component"] = tbl[2],
        ["Green Component"] = tbl[3],
    }
end

local function iterm_colors(l)
    local p = vim.tbl_map(iterm_color, get_palette16(l))
    return {
        ["Ansi 0 color"] = p.black,
        ["Ansi 1 color"] = p.red,
        ["Ansi 2 color"] = p.green,
        ["Ansi 3 color"] = p.yellow,
        ["Ansi 4 color"] = p.blue,
        ["Ansi 5 color"] = p.magenta,
        ["Ansi 6 color"] = p.cyan,
        ["Ansi 7 color"] = p.white,
        ["Ansi 8 color"] = p.brblack,
        ["Ansi 9 color"] = p.brred,
        ["Ansi 10 color"] = p.brgreen,
        ["Ansi 11 color"] = p.bryellow,
        ["Ansi 12 color"] = p.brblue,
        ["Ansi 13 color"] = p.brmagenta,
        ["Ansi 14 color"] = p.brcyan,
        ["Ansi 15 color"] = p.brwhite,
    }
end

local function write_plist(itermcolors, path)
    local stdin = uv.new_pipe()
    local handle, pid = uv.spawn("plutil", {
        args = { "-convert", "xml1", "-", "-o", path },
        stdio = { stdin, stdout, nil },
    }, function(code, signal)
        assert(code == 0, "Failed to spawn `plutil`")
    end)
    uv.write(stdin, vim.json.encode(itermcolors))
    uv.shutdown(stdin, function()
        -- print("stdin shutdown", stdin)
        uv.close(handle, function()
            -- print("process closed", handle, pid)
        end)
    end)
end

-- TODO: use iterm2 color name conventions
local function iterm2_build()
    local dir = get_melange_dir() .. "/term/iterm2"
    if not uv.fs_stat(dir) then
        mkdir(dir)
    end
    for _, l in pairs({ "dark", "light" }) do
        write_plist(vim.json.encode(iterm_colors(l)), string.format("%s/melange_%s.itermcolors", dir, l))
    end
end

-- OTHER TERMINALS --

-- stylua: ignore
local terminals = {
    alacritty  = { ext = ".yml" },
    kitty      = { ext = ".conf" },
    terminator = { ext = ".config" },
    termite    = { ext = "" },
    wezterm    = { ext = ".toml" },
}

local function build(terminals)
    for _, l in ipairs({ "dark", "light" }) do
        local palette = get_palette16(l)
        for term, attrs in pairs(terminals) do
            local dir = get_melange_dir() .. "/term/" .. term
            if not uv.fs_stat(dir) then
                mkdir(dir)
            end
            fwrite(interpolate(attrs.template, palette), string.format("%s/melange_%s%s", dir, l, attrs.ext))
        end
    end
end

terminals.alacritty.template = [[
colors:
  primary:
    foreground: '$fg'
    background: '$bg'
  normal:
    black:   '$black'
    red:     '$red'
    green:   '$green'
    yellow:  '$yellow'
    blue:    '$blue'
    magenta: '$magenta'
    cyan:    '$cyan'
    white:   '$white'
  bright:
    black:   '$brblack'
    red:     '$brred'
    green:   '$brgreen'
    yellow:  '$bryellow'
    blue:    '$brblue'
    magenta: '$brmagenta'
    cyan:    '$brcyan'
    white:   '$brwhite'
]]

terminals.kitty.template = [[
background $bg
foreground $fg
cursor     $fg
url_color  $blue
selection_background    $brblack
selection_foreground    $fg
tab_bar_background      $black
active_tab_background   $black
active_tab_foreground   $yellow
inactive_tab_background $black
inactive_tab_foreground $brwhite
color0  $black
color1  $red
color2  $green
color3  $yellow
color4  $blue
color5  $magenta
color6  $cyan
color7  $white
color8  $brblack
color9  $brred
color10 $brgreen
color11 $bryellow
color12 $brblue
color13 $brmagenta
color14 $brcyan
color15 $brwhite
]]

terminals.terminator.template = [=[
 [[melange]]
    background_color = "$bg"
    cursor_color = "$fg"
    foreground_color = "$fg"
    palette = "$black:$red:$green:$yellow:$blue:$magenta:$cyan:$white:$brblack:$brred:$brgreen:$bryellow:$brblue:$brmagenta:$brcyan:$brwhite"
]=]

terminals.termite.template = [[
[colors]
foreground = $fg
background = $bg
color0     = $black
color1     = $red
color2     = $green
color3     = $yellow
color4     = $blue
color5     = $magenta
color6     = $cyan
color7     = $white
color8     = $brblack
color9     = $brred
color10    = $brgreen
color11    = $bryellow
color12    = $brblue
color13    = $brmagenta
color14    = $brcyan
color15    = $brwhite
highlight  = $sel
]]

terminals.wezterm.template = [[
[colors]
foreground    = "$fg"
background    = "$bg"
cursor_bg     = "$fg"
cursor_border = "$fg"
cursor_fg     = "$bg"
selection_bg  = "$brblack"
selection_fg  = "$fg"
ansi = ["$black", "$red", "$green", "$yellow", "$blue", "$magenta", "$cyan", "$white"]
brights = ["$brblack", "$brred", "$brgreen", "$bryellow", "$brblue", "$brmagenta", "$brcyan", "$brwhite"]
]]

return {
    build = function()
        build(terminals)
        viml_build(viml_template, vim_term_colors)
        if vim.fn.has("mac") == 1 then
            iterm2_build()
        end
    end,
}
