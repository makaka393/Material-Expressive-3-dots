#version 440
// Фон режима правки виджетов на весь экран: обои закрывают окна и плавно «расфокусируются»
// (своё гладкое размытие, без зерна), поверх — светящиеся точки на углах клеток сетки.
// Точки появляются волной из центра; рядом с курсором — крупнее и ярче.
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
    float progress;  // 0 → 1: волна точек
    vec2 mouse;      // курсор (далеко за экраном — нет курсора)
    float veil;      // 0 → 1: обои закрывают окна
    float blurAmt;     // 0 — чёткие обои, 1 — размытые
    float dim;       // затемнение поверх обоев
    vec4 tint;       // цвет точек
    vec4 shade;      // цвет затемнения
};
layout(binding = 1) uniform sampler2D sharp;
layout(binding = 2) uniform sampler2D blurred;

void main() {
    vec2 p = qt_TexCoord0 * res;

    // обои: чёткие → размытые, к краям чуть темнее
    vec3 wall = mix(texture(sharp, qt_TexCoord0).rgb, texture(blurred, qt_TexCoord0).rgb, blurAmt);
    vec2 uv = (qt_TexCoord0 - 0.5) * vec2(res.x / res.y, 1.0);
    float vig = smoothstep(0.2, 1.0, length(uv));
    wall = mix(wall, shade.rgb, dim * blurAmt * (0.7 + 0.3 * vig));
    vec4 col = vec4(wall, 1.0) * veil;

    // точки сетки
    vec2 id = floor((p - start) / pitch + 0.5);
    vec2 c = start + id * pitch;
    float d = distance(p, c);
    float inside = step(0.0, id.x) * step(0.0, id.y) * step(id.x, count.x) * step(id.y, count.y);
    vec2 mid = start + count * pitch * 0.5;
    float reach = length(count * pitch) * 0.5 + pitch * 2.0;
    float on = clamp((progress * reach - distance(c, mid)) / (pitch * 1.5), 0.0, 1.0);
    float m = exp(-pow(distance(c, mouse) / (pitch * 1.7), 2.0));
    float r = (1.5 + 2.4 * m) * on;
    float core = 1.0 - smoothstep(r - 0.8, r + 0.8, d);
    float s = 3.0 + 5.0 * m;
    float halo = exp(-d * d / (2.0 * s * s)) * (0.14 + 0.5 * m) * on;
    float k = (core * 0.7 + halo) * inside;

    col.rgb += tint.rgb * k * veil;
    fragColor = col * qt_Opacity;
}
