#version 440
// Сетка рабочего стола в режиме правки виджетов: светящиеся точки на углах клеток.
// Появляются волной из центра; рядом с курсором точки крупнее и ярче — сетка «тянется» к руке.
// Под сеткой лёгкое затемнение (и блюр Hyprland — у слоя quickshell-desktop блюр включён).
// Собрать: /usr/lib/qt6/bin/qsb --qt6 -o griddots.frag.qsb griddots.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 res;        // размер, пиксели
    vec2 start;      // первая точка сетки (левый верхний угол клетки 0,0 минус полшага зазора)
    vec2 count;      // клеток по горизонтали и вертикали
    float pitch;     // шаг сетки
    float progress;  // 0 → 1: волна появления
    vec2 mouse;      // курсор (далеко за экраном — нет курсора)
    float dim;       // затемнение под сеткой
    vec4 tint;       // цвет точек
    vec4 shade;      // цвет затемнения
};

void main() {
    vec2 p = qt_TexCoord0 * res;
    vec2 id = floor((p - start) / pitch + 0.5);
    vec2 c = start + id * pitch;
    float d = distance(p, c);
    float inside = step(0.0, id.x) * step(0.0, id.y) * step(id.x, count.x) * step(id.y, count.y);

    // волна из центра сетки
    vec2 mid = start + count * pitch * 0.5;
    float reach = length(count * pitch) * 0.5 + pitch * 2.0;
    float on = clamp((progress * reach - distance(c, mid)) / (pitch * 1.5), 0.0, 1.0);

    // курсор рядом — крупнее и ярче
    float m = exp(-pow(distance(c, mouse) / (pitch * 1.7), 2.0));
    float r = (2.0 + 2.8 * m) * on;
    float core = 1.0 - smoothstep(r - 0.8, r + 0.8, d);
    float s = 3.5 + 6.0 * m;
    float halo = exp(-d * d / (2.0 * s * s)) * (0.22 + 0.6 * m) * on;
    float k = (core * 0.85 + halo) * inside;

    float a = dim * smoothstep(0.0, 0.6, progress);
    vec4 col = vec4(shade.rgb * a, a);
    col.rgb += tint.rgb * k;
    col.a = min(1.0, col.a + core * inside * 0.5);
    fragColor = col * qt_Opacity;
}
