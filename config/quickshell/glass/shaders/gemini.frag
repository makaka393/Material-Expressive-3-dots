#version 440
// Остров Веги — весь остров в духе Gemini, в стекле: тёмный верх, свет снизу, гладкий градиент Google.
//   listen (0…1) — слушает: матовый шар, бело-голубой свет снизу поднимается от голоса;
//   speak  (0…1) — говорит: волна снизу — синий → голубой → фиолетовый → розовый, течёт и дышит;
//   think  (0…1) — думает: та же волна кружит быстрее, цвета перетекают.
// Края — сглаженный скруглённый прямоугольник (пилюля или круг), по краю тонкий светлый ободок и блик
// сверху — объём стекла. Непрозрачность чуть меньше 1: размытие Hyprland под островом просвечивает.
// Собрать: /usr/lib/qt6/bin/qsb --qt6 -o gemini.frag.qsb gemini.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;       // пиксели
    float radius;
    float t;         // секунды
    float energy;    // 0…1 — громкость голоса или «дыхание» речи
    float listen;
    float speak;
    float think;
    float err;       // 0…1 — ошибка: красный вместо синего
};

float sdRoundBox(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

// градиент Gemini по кругу: синий, голубой, фиолетовый, розовый, снова синий
vec3 gemini(float x) {
    vec3 blue   = vec3(0.259, 0.522, 0.957);   // #4285F4
    vec3 sky    = vec3(0.420, 0.690, 1.000);   // #6BB0FF
    vec3 violet = vec3(0.569, 0.467, 0.780);   // #9177C7
    vec3 rose   = vec3(0.792, 0.400, 0.451);   // #CA6673
    x = fract(x) * 4.0;
    vec3 c = mix(blue, sky, smoothstep(0.0, 1.0, x));
    c = mix(c, violet, smoothstep(1.0, 2.0, x));
    c = mix(c, rose, smoothstep(2.0, 3.0, x));
    return mix(c, blue, smoothstep(3.0, 4.0, x));
}

void main() {
    vec2 uv = qt_TexCoord0;                         // 0…1, y вниз
    vec2 p = uv * size;
    float d = sdRoundBox(p - size * 0.5, size * 0.5, radius);
    float inside = 1.0 - smoothstep(-1.0, 0.5, d);  // сглаженный край
    if (inside <= 0.0) { fragColor = vec4(0.0); return; }

    float e = clamp(energy, 0.0, 1.0);
    float x = uv.x, y = uv.y;

    // ── тёмное стекло сверху
    vec3 col = mix(vec3(0.075, 0.082, 0.102), vec3(0.11, 0.12, 0.15), y);

    // ── говорит / думает: волна снизу, верхняя граница течёт
    float sp = clamp(speak + think, 0.0, 1.0);
    float flow = t * (0.35 + think * 0.9);
    float h = 0.62 - e * 0.16
            + 0.07 * sin(x * 5.5 + t * 1.6 + think * t)
            + 0.045 * sin(x * 11.0 - t * 2.3)
            + 0.03 * sin(x * 2.3 + t * 0.7);
    float band = smoothstep(h - 0.38, h + 0.30, y);           // мягкий подъём света
    band *= mix(0.75, 1.25, y);                              // у дна ярче
    vec3 wave = gemini(x * 0.75 - flow * 0.12 + 0.08 * sin(y * 3.0 + t));
    // у самого дна — больше синего, выше — цвета смешиваются
    wave = mix(wave, vec3(0.30, 0.56, 1.0), smoothstep(0.75, 1.0, y) * 0.45);
    col = mix(col, wave, clamp(band, 0.0, 1.0) * sp);

    // ── слушает: матовый шар — снизу бело-голубой свет, полоса света поднимается от голоса
    float lh = 0.78 - e * 0.30 + 0.02 * sin(x * 4.0 + t * 1.3);
    float glow = smoothstep(lh - 0.45, lh + 0.18, y);
    vec3 frost = mix(vec3(0.30, 0.34, 0.45), vec3(0.62, 0.72, 0.95), glow);
    float streak = exp(-pow((y - lh) * 6.0, 2.0)) * (0.35 + e * 0.5);  // светлая полоса, как в инее
    frost += vec3(0.85, 0.90, 1.0) * streak * 0.55;
    col = mix(col, frost, clamp(listen, 0.0, 1.0) * clamp(0.35 + glow, 0.0, 1.0));

    // ── ошибка: тот же свет, но красный
    col = mix(col, col * vec3(1.25, 0.45, 0.45) + vec3(0.12, 0.0, 0.0), err);

    // ── объём стекла: блик сверху и светлый ободок по краю
    col += vec3(1.0) * pow(1.0 - y, 3.0) * 0.07;
    float rim = smoothstep(-3.5, -0.5, d) * (1.0 - smoothstep(-0.5, 0.5, d));
    col += vec3(0.85, 0.9, 1.0) * rim * 0.22;

    float alpha = 0.9 * inside;
    fragColor = vec4(col * alpha, alpha) * qt_Opacity;
}
