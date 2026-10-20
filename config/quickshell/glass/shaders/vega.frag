#version 440
// Остров Веги — как новая Siri: сверху остаётся обычный остров (стекло темы, часы, трек), снизу из него
// раскрывается линза Liquid Glass, на стыке — свет.
//  • линза: снимок экрана, сделанный в момент вызова (пока остров был компактным, — без петли «линза
//    в линзе»), преломляется: в центре увеличение, у края — отражение «за край», дисперсия (радужная
//    кромка), к краю — чуть матовее (мипмапы); блики: сверху-слева яркий, снизу-справа отсвет; к краю
//    стекло темнее — видна толщина;
//  • свет на стыке — четыре нити цветов Gemini. Пока Вега слушает, каждая колышется от своей полосы
//    голоса (voice: низ, середина, верх, шипящие) — длинной волной от низа, мелкой рябью от шипящих:
//    видно, что она слышит саму речь. Пока говорит — так же от её голоса, теплее. В тишине нити
//    сходятся в тонкую линию; думает — свет бегает из стороны в сторону;
//  • стекло линзы расходится кольцами от голоса — как вода от звука;
//  • при вызове — волна: кольцо преломления и света расходится от центра стыка (рябь Apple Intelligence).
// Выше стыка шейдер прозрачен — там обычный остров; рисует только свечение.
// Собрать: /usr/lib/qt6/bin/qsb --qt6 -o vega.frag.qsb vega.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;        // остров, пиксели
    float radius;     // скругление острова
    float seam;       // высота верхней части (обычного острова), пиксели
    vec2 origin;      // левый верх острова на экране, пиксели
    vec2 screen;      // размер экрана, пиксели
    float hasShot;    // 1 — снимок экрана есть
    float t;
    float energy;     // 0…1 — голос (микрофон или речь Веги)
    float listen;
    float speak;
    float think;
    float err;
    float wake;       // 0…1 — волна при вызове
    float open;       // 0…1 — линза раскрыта (растёт от стыка вниз)
    vec4 tint;        // оттенок стекла темы
    vec4 voice;       // 0…1 — голос по полосам: низ, середина, верх, шипящие
};
layout(binding = 1) uniform sampler2D shot;

const float TAU = 6.28318531;

float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float sdRoundBox(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

// цвета Gemini по кругу: синий, голубой, фиолетовый, розовый
vec3 gemini(float x) {
    vec3 blue = vec3(0.259, 0.522, 0.957), sky = vec3(0.420, 0.690, 1.000);
    vec3 violet = vec3(0.569, 0.467, 0.780), rose = vec3(0.880, 0.450, 0.470);
    x = fract(x) * 4.0;
    vec3 c = mix(blue, sky, smoothstep(0.0, 1.0, x));
    c = mix(c, violet, smoothstep(1.0, 2.0, x));
    c = mix(c, rose, smoothstep(2.0, 3.0, x));
    return mix(c, blue, smoothstep(3.0, 4.0, x));
}

// стык — дуга: в центре чуть ниже, как край «чёрной» части у Siri
float seamY(float x) {
    float u = x / size.x * 2.0 - 1.0;
    return seam + 8.0 * (1.0 - u * u);
}

float lensSDF(vec2 p) {
    float d = sdRoundBox(p - size * 0.5, size * 0.5, radius);
    return max(d, seamY(p.x) - p.y);
}

vec2 lensNormal(vec2 p) {
    vec2 g = vec2(lensSDF(p + vec2(1.0, 0.0)) - lensSDF(p - vec2(1.0, 0.0)),
                  lensSDF(p + vec2(0.0, 1.0)) - lensSDF(p - vec2(0.0, 1.0)));
    return g / max(length(g), 1e-4);
}

vec3 sampleShot(vec2 sp, vec2 ca, float lod) {
    vec2 uv = (origin + sp) / screen;
    vec2 c = ca / screen;
    return vec3(textureLod(shot, uv + c, lod).r, textureLod(shot, uv, lod).g, textureLod(shot, uv - c, lod).b);
}

// нить света: волна вдоль стыка — две гармоники (не голая синусоида), к краям острова сходит на нет.
// Возвращает высоту нити над x
float strand(float x, float base, float amp, float k, float w, float ph) {
    float u = x / size.x * 2.0 - 1.0;
    float env = pow(max(1.0 - u * u, 0.0), 1.5);
    float s = sin(x * k - t * w + ph) * 0.72 + sin(x * k * 1.83 + t * w * 0.57 + ph * 2.1) * 0.28;
    return base + amp * env * s;
}

void main() {
    vec2 p = qt_TexCoord0 * size;
    float dIsl = sdRoundBox(p - size * 0.5, size * 0.5, radius);
    float inIsl = 1.0 - smoothstep(-1.0, 0.5, dIsl);
    if (inIsl <= 0.0) { fragColor = vec4(0.0); return; }

    float e = clamp(energy, 0.0, 1.0);
    vec4 v = clamp(voice, 0.0, 1.0);
    float ve = max(max(v.x, v.y), max(v.z, v.w));                        // голос сейчас
    float sy = seamY(p.x);
    float opened = clamp(open * 1.5, 0.0, 1.0);
    // линза растёт от стыка вниз (open), её граница — под стыком
    float lensBottom = mix(sy, size.y, clamp(open, 0.0, 1.0));
    float below = smoothstep(sy - 0.8, sy + 0.8, p.y) * (1.0 - smoothstep(lensBottom - 1.0, lensBottom + 0.5, p.y));

    vec3 col = vec3(0.0);
    float a = 0.0;

    // ── волна при вызове: от центра стыка
    vec2 wc = vec2(size.x * 0.5, sy);
    float wr = length((p - wc) * vec2(1.0, 1.4));
    float ring = wake > 0.001 ? exp(-pow((wr - wake * size.x * 0.75) / 13.0, 2.0)) * pow(1.0 - wake, 1.3) : 0.0;
    // ── кольца от голоса: стекло «дрожит», как вода от звука — бегут от центра стыка, гаснут к краю
    float rip = sin(wr * 0.115 - t * 7.5) * exp(-wr / 110.0) * ve;

    if (below > 0.0) {
        float dl = lensSDF(p);
        vec2 n = lensNormal(p);
        float depth = max(-dl, 0.0);
        float bend = pow(1.0 - clamp(depth / 24.0, 0.0, 1.0), 2.2);      // 1 у края → 0 внутри
        vec2 c = vec2(size.x * 0.5, (sy + size.y) * 0.5 + 4.0);
        float zoom = 1.24 + 0.07 * e + 0.015 * sin(t * 1.6);              // линза «дышит» голосом
        vec2 sp = c + (p - c) / zoom;                                      // увеличение
        sp += n * depth * 2.0 * bend + n * bend * 7.0;                     // у края — отражение за край
        vec2 away = normalize(p - wc + 1e-3);
        sp += away * (ring * 9.0 + rip * 3.2);                              // волна и кольца голоса преломляют
        float lod = 2.4 * bend;                                            // в центре чётко, к краю матовее
        vec3 refr = hasShot > 0.5 ? sampleShot(sp, n * bend * 3.0, lod) : tint.rgb * 0.55;
        refr = mix(refr, tint.rgb, 0.035) * 1.03 + 0.006;                  // стекло: чуть светлее, оттенок темы
        refr *= 1.0 - 0.20 * exp(dl / 8.0);                                // к краю темнее — толщина
        // блики: сверху-слева яркий, снизу-справа отсвет
        float rimLine = exp(dl / 1.5);
        float spec = pow(max(dot(n, normalize(vec2(-0.55, -0.83))), 0.0), 2.5) * 0.8
                   + pow(max(dot(n, normalize(vec2(0.55, 0.83))), 0.0), 3.0) * 0.5;
        refr += vec3(1.0) * rimLine * (0.16 + spec * 0.9);
        refr += vec3(1.0) * exp(dl / 7.0) * spec * 0.10;
        refr += vec3(0.80, 0.88, 1.0) * ring * 0.30;
        refr += vec3(0.62, 0.76, 1.0) * max(rip, 0.0) * 0.045;            // гребни колец чуть светлее
        // под светом стекло темнее (как тёмный верх у Siri): нити видны и на светлых обоях
        refr *= 1.0 - exp(-max(p.y - sy, 0.0) / 34.0) * (0.10 + 0.24 * ve) * clamp(open, 0.0, 1.0);
        col = refr * below;
        a = below;
    }

    // ── свет на стыке: тонкая линия и мягкое свечение; думает — бегает
    float dy = p.y - sy;
    float xc = 0.5 + 0.26 * sin(t * 1.1) * think;
    float u = p.x / size.x - xc;
    float spread = 0.18 + 0.17 * e + 0.05 * speak;
    float prof = exp(-pow(u / spread, 2.0));
    float edge = exp(-pow(dy / 1.3, 2.0)) * (0.35 + 0.65 * prof);         // сам стык — тонкая светлая линия
    float halo = exp(-pow(dy / 6.5, 2.0)) * prof;
    float down = dy > 0.0 ? exp(-dy / 16.0) * prof : 0.0;                 // свет льётся в линзу
    vec3 gcol = gemini(u * 1.5 + t * 0.16 * (1.0 + speak + think));
    gcol = mix(gcol, vec3(0.62, 0.76, 1.0), 0.45 * listen);               // слушает — холоднее
    float gain = (0.45 + 1.0 * e + 0.2 * speak) * opened;
    float calm = 1.0 - 0.55 * ve;                                          // говорят — свечение уступает нитям
    vec3 glow = gcol * (edge * 0.9 + (halo * 0.5 + down * 0.35) * calm) * gain;

    // ── нити: в тишине лежат на стыке; заговорили — опускаются в стекло и колышутся, каждая от своей
    // полосы голоса: низ — длинная медленная волна, шипящие — мелкая быстрая рябь. Слушает — холодные
    // (синий, голубой, фиолетовый, розовый по кругу), говорит она — сдвиг в тёплые
    float W = size.x;
    float hueShift = 0.34 * speak;
    vec4 amp = v * vec4(20.0, 24.0, 16.0, 10.0);
    vec4 k = TAU / (W * vec4(0.95, 0.52, 0.29, 0.16));
    vec4 w = vec4(1.7, 2.6, 3.8, 5.6) * (1.0 + 0.3 * speak);
    vec4 ph = vec4(0.0, 1.9, 3.7, 5.3);
    float base = sy + (3.0 + 15.0 * ve) * opened;
    vec3 strands = vec3(0.0);
    float lit = 0.0;
    for (int i = 0; i < 4; i++) {
        float y = strand(p.x, base, amp[i], k[i], w[i], ph[i]);
        float y2 = strand(p.x + 1.0, base, amp[i], k[i], w[i], ph[i]);
        float d = abs(p.y - y) / sqrt(1.0 + (y2 - y) * (y2 - y));            // толщина не зависит от наклона
        float width = 1.2 + 1.3 * v[i];
        float core = exp(-pow(d / width, 2.0));
        float soft = exp(-pow(d / (width * 4.5), 2.0));
        float strength = (0.22 + 1.25 * v[i]) * (0.3 + 0.7 * prof);         // в центре ярче
        vec3 sc = gemini(float(i) * 0.25 + 0.03 + hueShift + 0.04 * sin(t * 0.5 + float(i) * 1.7));
        strands += sc * (core * 1.35 + soft * 0.32) * strength;
        lit += core * strength;
    }
    // где нити пересекаются — светлее, почти белое ядро
    strands += vec3(1.0, 0.98, 0.95) * pow(clamp(lit * 0.28, 0.0, 1.0), 2.0) * 0.35;
    glow += strands * opened * (1.0 - 0.75 * think);                       // думает — нити гаснут, свет бегает

    glow = mix(glow, vec3(dot(glow, vec3(0.333))) * vec3(1.4, 0.35, 0.35), clamp(err, 0.0, 1.0));
    // тональная компрессия с сохранением оттенка: яркое не выгорает в плоское белое пятно
    float m = max(max(glow.r, glow.g), glow.b);
    if (m > 1e-4) glow *= (1.0 - exp(-m * 1.25)) / (m * 1.25) * 1.18;

    col += glow;
    a = max(a, clamp(max(glow.r, max(glow.g, glow.b)), 0.0, 1.0));

    col += (hash21(gl_FragCoord.xy + fract(t) * 61.0) - 0.5) / 255.0;     // дизеринг
    fragColor = vec4(clamp(col, 0.0, 1.0), a) * inIsl * qt_Opacity;
}
