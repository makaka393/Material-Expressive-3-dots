-- Hyprland (новый формат конфига, Lua). Перенесён из hyprland.conf: тот формат уберут в 0.57.
-- Справка: https://wiki.hypr.land/Configuring/Start/

local home = os.getenv("HOME")

-- цвета темы от matugen (changetheme.sh → ~/.cache/matugen/colors-hyprland.lua);
-- если файла ещё нет — нейтральные рамки, чтобы конфиг всё равно загрузился
local ok, colors = pcall(dofile, home .. "/.cache/matugen/colors-hyprland.lua")
if not ok or type(colors) ~= "table" then
    colors = { border_active = "rgba(ffffffaa)", border_inactive = "rgba(00000088)" }
end


------------------
---- MONITORS ----
------------------

hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })


-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------

hl.env("LIBVA_DRIVER_NAME", "nvidia")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("GBM_BACKEND", "nvidia-drm")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
hl.env("WLR_NO_HARDWARE_CURSORS", "1")
hl.env("XDG_MENU_PREFIX", "plasma-")
hl.env("QT_QPA_PLATFORMTHEME", "kde")


-------------------
---- AUTOSTART ----
-------------------

hl.on("hyprland.start", function()
    hl.exec_cmd("qs -c glass -n")
    hl.exec_cmd("qs -c glow -n -d")
    hl.exec_cmd("spotify")
    hl.exec_cmd("zen-browser")
    hl.exec_cmd("nm-applet --indicator")
    hl.exec_cmd("awww-daemon")
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=Hyprland")
    hl.exec_cmd("systemctl --user start sunshine")
    hl.exec_cmd("sleep 1 && ~/.config/hypr/scripts/changetheme.sh --restore")
    hl.exec_cmd("~/.config/hypr/scripts/shake-lens.py")
end)


-----------------------
---- LOOK AND FEEL ----
-----------------------

hl.config({
    input = {
        kb_layout    = "us,ru",
        kb_options   = "grp:alt_shift_toggle",
        follow_mouse = 1,
        sensitivity  = 0,
        touchpad = {
            natural_scroll = false,
        },
    },

    general = {
        gaps_in     = 4,
        gaps_out    = 8,
        border_size = 2,
        col = {
            active_border   = colors.border_active,
            inactive_border = colors.border_inactive,
        },
        layout        = "dwindle",
        allow_tearing = true,
    },

    decoration = {
        rounding = 20,
        -- силу блюра в стиле «Стекло» оболочка подменяет сама (quickshell/glass/Blur.qml)
        blur = {
            enabled           = true,
            size              = 2,
            passes            = 4,
            vibrancy          = 0.2,
            noise             = 0.1,
            vibrancy_darkness = 0.3,
        },
        active_opacity   = 0.80,
        inactive_opacity = 0.70,
        shadow = {
            enabled      = true,
            range        = 12,
            render_power = 3,
            color        = "rgba(00000088)",
        },
    },

    animations = {
        enabled = true,
    },

    dwindle = {
        preserve_split = true,
    },

    master = {
        new_status = "master",
    },

    misc = {
        force_default_wallpaper = 0,
        disable_hyprland_logo   = true,
        -- оболочка может перехватить замок экрана после своего перезапуска (quickshell/glass/Locker.qml)
        allow_session_lock_restore = true,
    },

    render = {
        -- полноэкранные игры идут на монитор мимо композитора
        direct_scanout = 2,
    },
})


--------------------
---- ANIMATIONS ----
--------------------

-- кривые M3 Expressive — те же, что у оболочки (quickshell/glass/Theme.qml):
-- окна и рабочие столы двигаются «пружинкой», прозрачность и рамки — без отскока
hl.curve("m3spatial",  { type = "bezier", points = { {0.38, 1.21}, {0.22, 1.00} } })
hl.curve("m3effects",  { type = "bezier", points = { {0.34, 0.80}, {0.34, 1.00} } })
hl.curve("m3exit",     { type = "bezier", points = { {0.30, 0.00}, {0.80, 0.15} } })
-- мягкое появление слоёв (rofi и т.п.)
hl.curve("softBounce", { type = "bezier", points = { {0.34, 1.45}, {0.64, 1} } })
hl.curve("smoothOut",  { type = "bezier", points = { {0.36, 0}, {0.66, -0.56} } })

hl.animation({ leaf = "windowsIn",     enabled = true, speed = 5,   bezier = "m3spatial", style = "popin 86%" })
hl.animation({ leaf = "windowsOut",    enabled = true, speed = 2.2, bezier = "m3exit",    style = "popin 90%" })
hl.animation({ leaf = "windowsMove",   enabled = true, speed = 4.5, bezier = "m3spatial" })
hl.animation({ leaf = "border",        enabled = true, speed = 3,   bezier = "m3effects" })
hl.animation({ leaf = "fade",          enabled = true, speed = 2.5, bezier = "m3effects" })
hl.animation({ leaf = "workspaces",    enabled = true, speed = 4.5, bezier = "m3spatial", style = "slide" })
hl.animation({ leaf = "layersIn",      enabled = true, speed = 4,   bezier = "softBounce", style = "popin 88%" })
hl.animation({ leaf = "layersOut",     enabled = true, speed = 2.5, bezier = "smoothOut",  style = "popin 92%" })
hl.animation({ leaf = "fadeLayersIn",  enabled = true, speed = 2.5, bezier = "default" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 2,   bezier = "default" })


---------------------
---- KEYBINDINGS ----
---------------------
-- Каждая привязка — отдельной строкой: по ним строится шпаргалка Super+/ (quickshell/glass/Hotkeys.qml).

local terminal    = "kitty"
local fileManager = "thunar"
local menu        = "wofi --show drun"

hl.bind("SUPER + Return", hl.dsp.exec_cmd(home .. "/.config/hypr/scripts/nofs.sh bash -c \"pw-play --volume 0.2 " .. home .. "/Downloads/audiomass-output.wav & " .. terminal .. "\""))
hl.bind("SUPER + Q", hl.dsp.window.close())
hl.bind("SUPER + SHIFT + Q", hl.dsp.exit())
hl.bind("SUPER + E", hl.dsp.exec_cmd(home .. "/.config/hypr/scripts/nofs.sh " .. fileManager))
hl.bind("SUPER + V", hl.dsp.exec_cmd(home .. "/.config/hypr/scripts/nofs.sh hyprctl dispatch togglefloating"))
hl.bind("SUPER + D", hl.dsp.exec_cmd(home .. "/.config/hypr/scripts/nofs.sh " .. menu))
hl.bind("SUPER + P", hl.dsp.window.pseudo())
hl.bind("SUPER + F", hl.dsp.window.fullscreen())

-- оболочка glass
hl.bind("SUPER + Escape", hl.dsp.exec_cmd("qs ipc -c glass call lock lock"))
hl.bind("SUPER + slash", hl.dsp.exec_cmd(home .. "/.config/hypr/scripts/nofs.sh qs ipc -c glass call hotkeys toggle"))
hl.bind("SUPER + SPACE", hl.dsp.exec_cmd(home .. "/.config/hypr/scripts/nofs.sh qs ipc -c glass call launcher toggle"))
hl.bind("SUPER + PERIOD", hl.dsp.exec_cmd(home .. "/.config/hypr/scripts/nofs.sh qs ipc -c glass call launcher emoji"))
hl.bind("SUPER + W", hl.dsp.exec_cmd(home .. "/.config/hypr/scripts/nofs.sh qs ipc -c glass call picker toggle"))

-- скриншоты и запись
hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd("~/.config/hypr/scripts/screenshot.sh region"))
hl.bind("SUPER + SHIFT + A", hl.dsp.exec_cmd("~/.config/hypr/scripts/screenshot.sh pretty"))
hl.bind("Print", hl.dsp.exec_cmd("~/.config/hypr/scripts/screenshot.sh full"))
hl.bind("SUPER + SHIFT + G", hl.dsp.exec_cmd("~/.config/hypr/scripts/screenshot.sh lens"))
hl.bind("SUPER + ALT + R", hl.dsp.exec_cmd("~/.config/hypr/scripts/record.sh toggle"))

-- фокус: стрелки и hjkl
hl.bind("SUPER + left", hl.dsp.focus({ direction = "left" }))
hl.bind("SUPER + right", hl.dsp.focus({ direction = "right" }))
hl.bind("SUPER + up", hl.dsp.focus({ direction = "up" }))
hl.bind("SUPER + down", hl.dsp.focus({ direction = "down" }))
hl.bind("SUPER + H", hl.dsp.focus({ direction = "left" }))
hl.bind("SUPER + L", hl.dsp.focus({ direction = "right" }))
hl.bind("SUPER + K", hl.dsp.focus({ direction = "up" }))
hl.bind("SUPER + J", hl.dsp.focus({ direction = "down" }))

-- рабочие столы
hl.bind("SUPER + 1", hl.dsp.focus({ workspace = 1 }))
hl.bind("SUPER + 2", hl.dsp.focus({ workspace = 2 }))
hl.bind("SUPER + 3", hl.dsp.focus({ workspace = 3 }))
hl.bind("SUPER + 4", hl.dsp.focus({ workspace = 4 }))
hl.bind("SUPER + 5", hl.dsp.focus({ workspace = 5 }))
hl.bind("SUPER + 6", hl.dsp.focus({ workspace = 6 }))
hl.bind("SUPER + 7", hl.dsp.focus({ workspace = 7 }))
hl.bind("SUPER + 8", hl.dsp.focus({ workspace = 8 }))
hl.bind("SUPER + 9", hl.dsp.focus({ workspace = 9 }))
hl.bind("SUPER + 0", hl.dsp.focus({ workspace = 10 }))
hl.bind("SUPER + SHIFT + 1", hl.dsp.window.move({ workspace = 1 }))
hl.bind("SUPER + SHIFT + 2", hl.dsp.window.move({ workspace = 2 }))
hl.bind("SUPER + SHIFT + 3", hl.dsp.window.move({ workspace = 3 }))
hl.bind("SUPER + SHIFT + 4", hl.dsp.window.move({ workspace = 4 }))
hl.bind("SUPER + SHIFT + 5", hl.dsp.window.move({ workspace = 5 }))
hl.bind("SUPER + SHIFT + 6", hl.dsp.window.move({ workspace = 6 }))
hl.bind("SUPER + SHIFT + 7", hl.dsp.window.move({ workspace = 7 }))
hl.bind("SUPER + SHIFT + 8", hl.dsp.window.move({ workspace = 8 }))
hl.bind("SUPER + SHIFT + 9", hl.dsp.window.move({ workspace = 9 }))
hl.bind("SUPER + SHIFT + 0", hl.dsp.window.move({ workspace = 10 }))
hl.bind("SUPER + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind("SUPER + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

-- окна мышью
hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- медиа, звук, яркость
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("pamixer -t"), { locked = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl s +5%"), { locked = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl s 5%-"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), { locked = true, repeating = true })


--------------------------------
---- WINDOWS AND WORKSPACES ----
--------------------------------

hl.window_rule({ name = "suppress-maximize", match = { class = ".*" }, suppress_event = "maximize" })
hl.window_rule({ name = "dolphin-opacity", match = { class = "org.kde.dolphin" }, opacity = "0.95 0.9" })
-- Steam Big Picture — всегда во весь экран
hl.window_rule({ name = "steam-big-picture", match = { class = "steam", title = "Steam Big Picture Mode" }, fullscreen = true })
-- CS2 — без vsync композитора (tearing), меньше инпут-лаг
hl.window_rule({ name = "cs2-immediate", match = { class = "cs2" }, immediate = true })

-- слои оболочки glass (затемнение под окнами — до 0.35 альфы, блюр только под карточками: ignore_alpha 0.4)
hl.layer_rule({ name = "glass-bar", match = { namespace = "quickshell-bar" }, blur = true, blur_popups = true, ignore_alpha = 0.01, no_anim = true })
hl.layer_rule({ name = "glass-settings", match = { namespace = "quickshell-settings" }, blur = true, ignore_alpha = 0.4 })
hl.layer_rule({ name = "glass-launcher", match = { namespace = "quickshell-launcher" }, blur = true, ignore_alpha = 0.4 })
-- виджеты рабочего стола — стекло, как у бара; в режиме правки размывается весь экран под сеткой
hl.layer_rule({ name = "glass-desktop", match = { namespace = "quickshell-desktop" }, blur = true, ignore_alpha = 0.01 })
hl.layer_rule({ name = "glow", match = { namespace = "quickshell-glow" }, no_anim = true })
hl.layer_rule({ name = "selection", match = { namespace = "selection" }, no_anim = true })
hl.layer_rule({ name = "rofi", match = { namespace = "rofi" }, blur = true, ignore_alpha = 0.3 })
