#version 440
// Остров Веги — свет в стекле, в духе Gemini Live и Apple Intelligence:
//  • аврора внутри: «меш-градиент» цветов Gemini — цветовые точки плывут по кривым Лиссажу и
//    смешиваются по весу 1/d^3.5 (шёлковые переливы, а не полосы), пространство течёт синусами;
//    свет поднимается снизу под волнистым «горизонтом», горизонт растёт от голоса;
//  • край, как у Siri: цветные огни бегут по контуру в разные стороны, свечение из трёх слоёв —
//    ядро, ореол, дымка — складывается по яркости;
//  • при вызове — волна света из центра (рябь Apple Intelligence);
//  • стекло: тёмная полупрозрачная основа, блик сверху; мягкий тонмаппинг (1 − e^−x), чтобы
//    яркое светилось, а не выбивалось в белое; дизеринг против полос в градиенте.
//  listen — слушает: холоднее, бело-голубой; speak — говорит: вся палитра; think — думает: кружит.
// Техники меш-градиента, огней по контуру и дизеринга — по мотивам Paper Shaders (Apache-2.0,
// github.com/paper-design/shaders: mesh-gradient, pulsing-border, colorBandingFix).
// Собрать: /usr/lib/qt6/bin/qsb --qt6 -o gemini.frag.qsb gemini.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;       // пиксели
    float radius;
    float t;         // секунды
    float energy;    // 0…1 — голос: микрофон, пока слушает; речь Веги, пока говорит
    float listen;
    float speak;
    float think;
    float err;       // 0…1 — ошибка: красный
    float wake;      // 0…1 — волна при вызове (0 — нет)
};

const float TAU = 6.28318531;

// цвета Gemini / Google
const vec3 C0 = vec3(0.102, 0.451, 0.910);   // #1A73E8 — глубокий синий
const vec3 C1 = vec3(0.259, 0.522, 0.957);   // #4285F4 — синий Google
const vec3 C2 = vec3(0.420, 0.690, 1.000);   // #6BB0FF — небесный
const vec3 C3 = vec3(0.569, 0.467, 0.780);   // #9177C7 — фиолетовый Gemini
const vec3 C4 = vec3(0.792, 0.400, 0.451);   // #CA6673 — розовый Gemini

float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float vnoise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
               mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
    float s = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) {
        s += a * vnoise(p);
        p = p * 2.03 + 17.1;
        a *= 0.5;
    }
    return s;
}

float sdRoundBox(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

vec2 rot(vec2 p, float a) {
    float c = cos(a), s = sin(a);
    return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// позиция i-й цветовой точки — кривая Лиссажу
vec2 meshPos(int i, float tt) {
    float a = float(i) * 0.37;
    float b = 0.6 + fract(float(i) / 3.0) * 0.9;
    float c = 0.8 + fract(float(i + 1) / 4.0);
    return 0.5 + 0.5 * vec2(sin(tt * b + a), cos(tt * c + a * 1.5));
}

// меш-градиент: warm — доля фиолетового и розового (слушает — холоднее)
vec3 mesh(vec2 uv, float tt, float warm) {
    for (float i = 1.0; i <= 2.0; i += 1.0) {           // течение пространства
        uv.x += 0.32 / i * sin(tt + i * 1.2 * uv.y) * cos(0.2 * tt + i * 2.4 * uv.y);
        uv.y += 0.32 / i * cos(tt + i * 2.0 * uv.x);
    }
    vec3 col = vec3(0.0);
    float tw = 0.0;
    for (int i = 0; i < 5; i++) {
        vec3 c = i == 0 ? C0 : i == 1 ? C1 : i == 2 ? C2 : i == 3 ? C3 : C4;
        float w = 1.0 / (pow(length(uv - meshPos(i, tt)), 4.2) + 1e-3);
        if (i >= 3) w *= warm;                              // фиолетовый и розовый — прожилками
        col += c * w;
        tw += w;
    }
    return col / max(tw, 1e-4);
}

void main() {
    vec2 uv = qt_TexCoord0;                               // 0…1, y вниз
    vec2 p = uv * size;
    float d = sdRoundBox(p - size * 0.5, size * 0.5, radius);   // пиксели, внутри < 0
    float inside = 1.0 - smoothstep(-1.0, 0.5, d);
    if (inside <= 0.0) { fragColor = vec4(0.0); return; }

    float e = clamp(energy, 0.0, 1.0);
    float sp = clamp(speak, 0.0, 1.0), li = clamp(listen, 0.0, 1.0), th = clamp(think, 0.0, 1.0);
    float x = uv.x, y = uv.y;

    // ── стекло
    vec3 base = mix(vec3(0.050, 0.056, 0.075), vec3(0.080, 0.086, 0.110), y);
    vec3 L = vec3(0.0);                                   // свет, складывается

    // ── аврора: горизонт снизу, растёт от голоса
    float tt = t * (0.42 + 0.35 * sp + 0.25 * e);
    // верх — тёмное стекло, свет — в нижней половине: слушает — у дна, говорит — выше, громче — ещё выше
    float horizon = mix(mix(0.92, 0.62, e), mix(0.74, 0.48, e), sp);
    horizon += 0.12 * (fbm(vec2(x * 2.4 + t * 0.32, t * 0.21)) - 0.5) * (0.6 + sp);
    horizon += 0.05 * sin(x * TAU * 0.8 + t * 1.25) * sp;
    float rise = smoothstep(horizon - 0.22, horizon + 0.42, y);
    rise = pow(rise, 1.7);
    float crest = exp(-pow((y - horizon) * 7.5, 2.0)) * (0.22 + 0.55 * e);
    vec3 aur = mesh(vec2(x, y * 0.85 + 0.1), tt, mix(0.75, 0.25, li));
    aur = mix(aur, vec3(0.74, 0.84, 1.0), 0.48 * li);     // слушает — светлее, как иней
    aur = mix(vec3(dot(aur, vec3(0.299, 0.587, 0.114))), aur, 1.3);   // насыщеннее, без пастели
    // у самого дна — «горячая» кромка: будто источник света под стеклом
    float hot = exp(-(1.0 - y) * size.y / 9.0) * (0.55 + 0.6 * e);
    vec3 aurora = aur * (rise * (0.92 + 0.45 * e) + crest * 0.8) + mix(mix(C1, C2, 0.35), vec3(0.80, 0.88, 1.0), 0.45 * li) * hot * (0.6 + 0.4 * sp + 0.3 * li);

    // думает: по тёмному стеклу бежит луч цветов Gemini — входит из-за левого края и уходит за правый
    // (так светится загрузка у Gemini), снизу — слабая аврора
    float sweep = fract(t * 0.42) * 1.9 - 0.45;
    float beam = exp(-pow((x - sweep + (y - 0.5) * 0.35) * 3.4, 2.0));
    float beam2 = exp(-pow((x - fract(t * 0.42 + 0.5) * 1.9 + 0.45 + (y - 0.5) * 0.35) * 5.0, 2.0)) * 0.45;
    vec3 tc = mesh(vec2(x + t * 0.08, y), t * 0.9, 1.0);
    tc = mix(vec3(dot(tc, vec3(0.299, 0.587, 0.114))), tc, 1.35);
    vec3 thinkL = tc * ((beam + beam2) * 1.05 + 0.28 * smoothstep(0.55, 1.0, y));
    L += mix(aurora, thinkL, th);

    // ── край в духе Siri: цветные огни бегут по контуру
    vec2 cp = (p - size * 0.5) / (size * 0.5);
    float ang = atan(cp.y, cp.x) / TAU;
    vec3 rimCol = vec3(0.0);
    for (int i = 0; i < 4; i++) {
        vec3 c = i == 0 ? C1 : i == 1 ? C2 : i == 2 ? C3 : C4;
        for (int j = 0; j < 2; j++) {
            float fi = float(i), fj = float(j);
            float speed = (0.05 + 0.035 * fi + 0.03 * fj) * (1.0 + 2.6 * th + 0.6 * sp) * (j == 1 ? -1.0 : 1.0);
            float center = fract(0.21 * fi + 0.5 * fj + t * speed);
            float dd = abs(fract(ang - center + 0.5) - 0.5);
            float s = smoothstep(0.11 + 0.035 * fi, 0.0, dd);
            float pulse = 0.55 + 0.45 * sin(t * (1.1 + 0.35 * fi) + fj * 2.3);
            rimCol += c * s * pulse;
        }
    }
    float core = exp(d / 1.3), halo = exp(d / 5.0), haze = exp(d / 16.0);
    float rimGain = 0.22 + 0.30 * li * e + (0.30 + 0.40 * e) * sp + 0.55 * th;
    L += rimCol * (core * 0.8 + halo * 0.35 + haze * 0.08) * rimGain;
    L += vec3(0.85, 0.92, 1.0) * core * (0.06 + 0.22 * smoothstep(0.55, 0.0, y));   // губа стекла — светлее сверху

    // ── волна при вызове: кольцо света из центра
    if (wake > 0.001) {
        float rr = length((p - size * 0.5) * vec2(1.0, 1.6));
        float R = wake * length(size * 0.5) * 1.15;
        float ring = exp(-pow((rr - R) / 16.0, 2.0)) * pow(1.0 - wake, 1.4);
        L += mix(vec3(0.70, 0.84, 1.0), C2, 0.4) * ring * 1.1;
    }

    // ── блик стекла сверху
    L += vec3(1.0) * (smoothstep(0.6, 0.0, y) * 0.035
                    + exp(-pow((y - 0.10) * 10.0, 2.0)) * 0.05 * smoothstep(0.0, 0.25, x) * smoothstep(1.0, 0.75, x));

    // ── мягкий тонмаппинг и ошибка
    // тонмаппинг по яркости, оттенок сохраняется: яркий синий остаётся синим, а не бледнеет
    float lumL = dot(L, vec3(0.299, 0.587, 0.114));
    vec3 light = L * ((1.0 - exp(-lumL * 1.7)) / max(lumL, 1e-4));
    light = light / max(1.0, max(light.r, max(light.g, light.b)));
    vec3 col = base * (1.0 - 0.5 * clamp(max(light.r, max(light.g, light.b)), 0.0, 1.0)) + light;
    float lum = dot(col, vec3(0.299, 0.587, 0.114));
    col = mix(col, vec3(lum) * vec3(1.35, 0.42, 0.42) + vec3(0.08, 0.0, 0.0), clamp(err, 0.0, 1.0) * 0.85);

    col += (hash21(gl_FragCoord.xy + fract(t) * 61.0) - 0.5) / 255.0;   // дизеринг

    float alpha = 0.9 * inside;
    fragColor = vec4(clamp(col, 0.0, 1.0) * alpha, alpha) * qt_Opacity;
}
