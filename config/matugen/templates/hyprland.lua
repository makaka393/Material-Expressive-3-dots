-- сгенерировано matugen — не редактировать руками (шаблон: ~/.config/matugen/templates/hyprland.lua)
-- Цвета темы для ~/.config/hypr/hyprland.lua
return {
    primary           = "rgb({{colors.primary.default.hex_stripped}})",
    tertiary          = "rgb({{colors.tertiary.default.hex_stripped}})",
    surface           = "rgb({{colors.surface.default.hex_stripped}})",
    outline_variant   = "rgb({{colors.outline_variant.default.hex_stripped}})",
    surface_lowest    = "rgb({{colors.surface_container_lowest.default.hex_stripped}})",
    -- рамки окон: активная — градиент tertiary → primary, неактивная — самый тёмный фон
    border_active     = { colors = { "rgb({{colors.tertiary.default.hex_stripped}})", "rgb({{colors.primary.default.hex_stripped}})" }, angle = 45 },
    border_inactive   = "rgb({{colors.surface_container_lowest.default.hex_stripped}})",
}
