#version 440
// Затемнение под окнами оболочки в духе Pixel: мягкая виньетка и живая сетка мелких точек
// разного размера. Точки проявляются волной из origin, потом медленно «дышат»: у каждой свой
// размер и ритм мерцания, а по сетке плывёт плавное поле, которое то укрупняет, то гасит их.
// Собрать: /usr/lib/qt6/bin/qsb --qt6 -o scrim.frag.qsb scrim.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 res;        // размер в пикселях
    vec2 origin;     // откуда идёт волна, пиксели
    float progress;  // 0 → 1: волна проходит весь экран
    float time;      // секунды — для «дыхания» точек
    float dim;       // сила затемнения по краям (в центре — вдвое меньше)
    float cell;      // шаг сетки, пиксели
    float dots;      // яркость точек 0…1
    vec4 tint;       // цвет точек
    vec4 shade;      // цвет затемнения
};

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

// плавный шум: билинейно смешанные случайные значения в узлах решётки
float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x),
               mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void main() {
    vec2 p = qt_TexCoord0 * res;

    // виньетка: в центре светлее, к краям темнее
    vec2 uv = (qt_TexCoord0 - 0.5) * vec2(res.x / res.y, 1.0);
    float vig = smoothstep(0.1, 0.95, length(uv));
    float a = dim * (0.5 + 0.5 * vig) * smoothstep(0.0, 0.35, progress);

    // клетка, её случайные числа и чуть сдвинутый центр — сетка не выглядит линейкой
    vec2 id = floor(p / cell);
    float r1 = hash(id), r2 = hash(id + 17.31), r3 = hash(id + 41.7);
    vec2 c = (id + 0.5 + (vec2(r1, r2) - 0.5) * 0.4) * cell;
    float d = distance(p, c);

    // волна появления
    float dist = distance(c, origin);
    float front = progress * length(res) * 1.1;
    float behind = clamp((front - dist) / (cell * 14.0), 0.0, 1.0);
    float ring = exp(-pow((front - dist) / (cell * 2.5), 2.0));

    // «дыхание»: плывущее поле + своё мерцание у каждой точки
    float field = noise(id * 0.09 + vec2(time * 0.07, -time * 0.05));
    float twinkle = 0.5 + 0.5 * sin(time * (0.5 + r3 * 1.3) + r1 * 6.2832);
    float size = (0.3 + 0.7 * r2) * (0.35 + 0.65 * field) * (0.65 + 0.35 * twinkle);

    float r = cell * (0.04 + 0.13 * size * behind * (0.55 + 0.45 * vig) + 0.16 * ring) * step(dist, front);
    float dot = 1.0 - smoothstep(r - 0.7, r + 0.7, d);
    float da = dot * dots * (0.3 + 0.4 * vig * field + 0.3 * twinkle + 0.6 * ring) * tint.a;

    // смешиваем в предумноженной альфе
    vec4 col = vec4(shade.rgb * a, a);
    col = col * (1.0 - da) + vec4(tint.rgb * da, da);
    fragColor = col * qt_Opacity;
}
