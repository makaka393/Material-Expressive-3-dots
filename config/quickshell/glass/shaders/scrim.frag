#version 440
// Затемнение под окнами оболочки в духе Pixel: мягкая виньетка и сетка точек,
// которая проявляется волной из точки origin. Скомпилировать: qsb --qt6 -o scrim.frag.qsb scrim.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 res;        // размер в пикселях
    vec2 origin;     // откуда идёт волна, пиксели
    float progress;  // 0 → 1: волна проходит весь экран
    float dim;       // сила затемнения по краям (в центре — вдвое меньше)
    float cell;      // шаг сетки, пиксели
    float dots;      // яркость точек 0…1
    vec4 tint;       // цвет точек
    vec4 shade;      // цвет затемнения
};

void main() {
    vec2 p = qt_TexCoord0 * res;

    // виньетка: в центре светлее, к краям темнее
    vec2 uv = (qt_TexCoord0 - 0.5) * vec2(res.x / res.y, 1.0);
    float vig = smoothstep(0.1, 0.95, length(uv));
    float a = dim * (0.5 + 0.5 * vig) * smoothstep(0.0, 0.35, progress);

    // точки: центр клетки, расстояние от волны
    vec2 c = (floor(p / cell) + 0.5) * cell;
    float d = distance(p, c);
    float dist = distance(c, origin);
    float front = progress * length(res) * 1.1;
    float behind = clamp((front - dist) / (cell * 12.0), 0.0, 1.0);          // 0 — на гребне, 1 — давно позади
    float ring = exp(-pow((front - dist) / (cell * 2.5), 2.0));               // гребень волны
    float r = cell * (0.07 + 0.08 * behind * (0.4 + 0.6 * vig) + 0.2 * ring) * step(dist, front);
    float dot = 1.0 - smoothstep(r - 0.8, r + 0.6, d);
    float da = dot * dots * (0.25 + 0.45 * vig + 0.6 * ring) * tint.a;

    // смешиваем в предумноженной альфе
    vec4 col = vec4(shade.rgb * a, a);
    col = col * (1.0 - da) + vec4(tint.rgb * da, da);
    fragColor = col * qt_Opacity;
}
