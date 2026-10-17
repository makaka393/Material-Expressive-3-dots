#version 440
// Подложка виджета рабочего стола (WidgetSurface): скруглённый прямоугольник со сглаженным краем.
//   blur  — размытые обои под виджетом (своя текстура Desktop.qml, без зерна Hyprland) + оттенок темы;
//   solid — просто цвет темы с прозрачностью поверх обоев.
// Обои под виджетом берутся по экранным координатам пикселя (gl_FragCoord) — подложка совпадает
// с обоями, даже пока виджет едет, растёт или пружинит.
// Собрать: /usr/lib/qt6/bin/qsb --qt6 -o glass.frag.qsb glass.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 res;        // размер окна, пиксели
    vec2 size;       // размер виджета, пиксели (без масштаба)
    float radius;
    float flipY;     // 1 — у OpenGL начало gl_FragCoord снизу
    float solid;     // 0 — размытие, 1 — цвет
    float amount;    // сила оттенка (размытие) или непрозрачность (цвет)
    float sheen;     // блик и светлая кромка стекла 0…1
    vec4 tint;       // цвет темы
};
layout(binding = 1) uniform sampler2D backdrop;

void main() {
    vec2 p = qt_TexCoord0 * size;
    vec2 q = abs(p - size * 0.5) - (size * 0.5 - radius);
    float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
    float cover = 1.0 - smoothstep(-0.8, 0.8, d);

    vec2 uv = gl_FragCoord.xy / res;
    if (flipY > 0.5) uv.y = 1.0 - uv.y;
    vec3 b = texture(backdrop, uv).rgb;

    float t = qt_TexCoord0.y;
    // кромка: тонкая светлая линия по краю, ярче сверху
    float rim = (smoothstep(-2.2, -0.6, d) - smoothstep(-0.6, 0.6, d)) * (0.35 + 0.65 * (1.0 - smoothstep(0.0, 0.5, t)));
    float top = 1.0 - smoothstep(0.0, 0.42, t);

    vec4 col;
    if (solid > 0.5) {
        float a = amount * cover;
        vec3 c = tint.rgb + vec3(0.06) * top * sheen;
        col = vec4(c * a, a);
        col += vec4(vec3(0.22), 0.22) * rim * sheen * cover;
    } else {
        vec3 c = mix(b, tint.rgb, amount);
        c += vec3(0.07) * top * sheen;            // блик сверху
        c = mix(c, vec3(1.0), rim * 0.3 * sheen);  // светлая кромка
        col = vec4(c, 1.0) * cover;
    }
    fragColor = col * qt_Opacity;
}
