#version 440
// Затемнение под окнами оболочки: мягкая виньетка и (стиль «Точки») светящиеся точки без сетки.
// Точки запечены заранее в бесшовный тайл (make-dots.py → dots.png): R — сердцевина, G — свечение,
// B — фаза мерцания. Здесь — два слоя этого тайла разного масштаба, они медленно плывут в разные
// стороны и чуть колышутся, каждая точка мерцает в своём ритме. На пиксель — две выборки из
// текстуры и немного синусов, никакого шума.
// Свет точек складывается с тем, что под затемнением (почти без альфы): точки светятся и на
// тёмном, и на светлом, а Hyprland не размывает под ними (ignore_alpha 0.4 у этих слоёв).
// Собрать: /usr/lib/qt6/bin/qsb --qt6 -o scrim.frag.qsb scrim.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 res;        // размер в пикселях
    vec2 origin;     // откуда идёт волна появления, пиксели
    float progress;  // 0 → 1: волна проходит весь экран
    float time;      // секунды
    float dim;       // сила затемнения по краям
    float flatness;     // 0 — сильная виньетка, 1 — ровное затемнение
    float dots;      // яркость точек; 0 — просто тёмный фон
    float zoom;      // размер тайла на экране, пиксели (1024 — один к одному)
    vec4 tintA;      // цвет дальнего слоя
    vec4 tintB;      // цвет ближнего слоя
    vec4 shade;      // цвет затемнения
};
layout(binding = 1) uniform sampler2D tile;

// один слой точек: свет, уже окрашенный. keep — какие точки слоя видны (по их фазе):
// у слоёв разные половины точек, так что они не повторяют друг друга и не слишком густо
vec3 layer(vec2 p, float size, vec2 drift, vec2 seed, vec3 tint, vec2 keep) {
    vec4 t = texture(tile, (p + drift * time) / size + seed);
    float ph = t.b;
    if (ph < keep.x || ph > keep.y) return vec3(0.0);
    // у каждой точки своя скорость и фаза: период от ~4 до ~10 секунд
    float tw = 0.5 + 0.5 * sin(time * (0.6 + ph * 1.1) + ph * 40.0);
    float core = t.r * (0.3 + 0.7 * tw);
    float halo = t.g * (0.2 + 0.8 * tw);
    // сердцевина почти белая, свечение — цвета темы
    return mix(tint, vec3(1.0), 0.6) * core * 0.85 + tint * halo * 0.75;
}

void main() {
    vec2 p = qt_TexCoord0 * res;

    // виньетка: в центре светлее, к краям темнее
    vec2 uv = (qt_TexCoord0 - 0.5) * vec2(res.x / res.y, 1.0);
    float vig = smoothstep(0.1, 0.95, length(uv));
    float a = dim * mix(0.5 + 0.5 * vig, 0.8 + 0.2 * vig, flatness) * smoothstep(0.0, 0.35, progress);
    vec4 col = vec4(shade.rgb * a, a);

    if (dots > 0.001) {
        // волна появления из origin: за фронтом точки разгораются, на самом фронте вспыхивают
        float diag = length(res);
        float d = distance(p, origin);
        float front = progress * diag * 1.15;
        float behind = clamp((front - d) / (diag * 0.12), 0.0, 1.0);
        float ring = exp(-pow((front - d) / (diag * 0.03), 2.0)) * (1.0 - smoothstep(0.8, 1.0, progress));

        // плавное течение — как пылинки в луче света
        vec2 flow = vec2(sin(p.y * 0.0031 + time * 0.23) + 0.6 * sin(p.y * 0.0057 - time * 0.13 + 1.7),
                         cos(p.x * 0.0027 - time * 0.19) + 0.6 * cos(p.x * 0.0049 + time * 0.11 + 0.4)) * 8.0;

        // дальний слой мельче и тусклее, ближний крупнее; плывут в разные стороны
        vec3 glow = layer(p + flow * 0.5, zoom, vec2(6.0, -3.5), vec2(0.0), tintA.rgb, vec2(0.28, 1.0)) * 0.7
                  + layer(p + flow, zoom * 1.6, vec2(-4.5, -8.0), vec2(0.37, 0.61), tintB.rgb, vec2(0.0, 0.62));
        glow *= dots * (behind * (0.6 + 0.4 * vig) + ring * 1.8);

        col.rgb += glow;
        col.a = min(0.39, col.a + dot(glow, vec3(0.06)));
    }
    fragColor = col * qt_Opacity;
}
