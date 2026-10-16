.pragma library

// Калькулятор для лаунчера — свой разбор выражений, без eval.
// + − × ÷ ^ %, скобки, 2π, sqrt sin cos tan ln log abs round, pi e, запятая как точка.
//   evaluate("2+2*2") → 6;  evaluate("200*15%") → 30;  evaluate("firefox") → null

const FN = {
    sqrt: Math.sqrt, cbrt: Math.cbrt, abs: Math.abs, round: Math.round, floor: Math.floor, ceil: Math.ceil,
    sin: x => Math.sin(x), cos: x => Math.cos(x), tan: x => Math.tan(x),
    asin: Math.asin, acos: Math.acos, atan: Math.atan,
    ln: Math.log, log: Math.log10, lg: Math.log10, log2: Math.log2, exp: Math.exp,
    "√": Math.sqrt, "корень": Math.sqrt
};
const CONST = { pi: Math.PI, "π": Math.PI, e: Math.E, tau: 2 * Math.PI };

function tokenize(s) {
    const t = [];
    let i = 0;
    s = s.replace(/×|·/g, "*").replace(/÷|:/g, "/").replace(/−|–/g, "-").replace(/\*\*/g, "^");
    while (i < s.length) {
        const c = s[i];
        if (c === " " || c === " " || c === "_") { i++; continue; }
        if (/[0-9.,]/.test(c)) {
            let j = i;
            while (j < s.length && /[0-9.,_ ]/.test(s[j]) && !(s[j] === " " && !/[0-9]/.test(s[j + 1] || ""))) j++;
            // «1 000 000» и «1 000,5» — пробелы внутри числа — это разряды
            let n = s.slice(i, j).replace(/[ _]/g, "");
            if (n.indexOf(",") >= 0 && n.indexOf(".") < 0) n = n.replace(",", ".");
            else n = n.replace(/,/g, "");
            const v = Number(n);
            if (isNaN(v)) return null;
            t.push({ k: "n", v: v });
            i = j;
            continue;
        }
        if (/[a-zа-яё√π]/i.test(c)) {
            let j = i;
            while (j < s.length && /[a-zа-яё0-9√π]/i.test(s[j])) j++;
            let w = s.slice(i, j).toLowerCase();
            // log2 / sin2 → функция; «2pi» разбирается как число + константа
            if (FN[w] !== undefined) t.push({ k: "f", v: w });
            else if (CONST[w] !== undefined) t.push({ k: "n", v: CONST[w] });
            else return null;
            i = j;
            continue;
        }
        if ("+-*/^%()".indexOf(c) >= 0) { t.push({ k: c }); i++; continue; }
        return null;
    }
    return t;
}

function evaluate(src) {
    if (!src) return null;
    const t = tokenize(String(src));
    if (!t || t.length === 0) return null;
    let p = 0;
    const peek = () => t[p], next = () => t[p++];

    function primary() {
        const tk = next();
        if (!tk) throw 0;
        if (tk.k === "n") return tk.v;
        if (tk.k === "(") { const v = expr(); if (!peek() || peek().k !== ")") { if (peek()) throw 0; return v; } p++; return v; }
        if (tk.k === "f") {
            const f = FN[tk.v];
            const a = peek() && peek().k === "(" ? primary() : unary();
            return f(a);
        }
        throw 0;
    }
    // постфиксный процент и неявное умножение: 2π, 3(4+1), 2sqrt9
    function postfix() {
        let v = primary();
        for (;;) {
            const n = peek();
            if (n && n.k === "%") { p++; v = v / 100; continue; }
            if (n && (n.k === "n" || n.k === "(" || n.k === "f")) { v = v * postfixNoImplicit(); continue; }
            return v;
        }
    }
    function postfixNoImplicit() {
        let v = primary();
        while (peek() && peek().k === "%") { p++; v /= 100; }
        return v;
    }
    function power() {
        const b = postfix();
        if (peek() && peek().k === "^") { p++; return Math.pow(b, unary()); }
        return b;
    }
    function unary() {
        const n = peek();
        if (n && n.k === "-") { p++; return -unary(); }
        if (n && n.k === "+") { p++; return unary(); }
        return power();
    }
    function term() {
        let v = unary();
        for (;;) {
            const n = peek();
            if (n && n.k === "*") { p++; v *= unary(); }
            else if (n && n.k === "/") { p++; v /= unary(); }
            else return v;
        }
    }
    function expr() {
        let v = term();
        for (;;) {
            const n = peek();
            // 100 + 15% → 115 (как на телефонном калькуляторе)
            if (n && (n.k === "+" || n.k === "-")) {
                p++;
                const save = p;
                let r = term();
                const tk = t[p - 1];
                if (tk && tk.k === "%" && p - save === 2 && t[save].k === "n") r = v * r;
                v = n.k === "+" ? v + r : v - r;
            } else return v;
        }
    }

    try {
        const v = expr();
        if (p !== t.length) return null;
        if (typeof v !== "number" || !isFinite(v)) return null;
        return v;
    } catch (e) {
        return null;
    }
}

// похоже ли на пример: есть цифра/константа и хотя бы один оператор или функция
function looksLike(s) {
    if (!s) return false;
    return /[0-9π]/.test(s) && /[-+*/^%×÷()√π]|sqrt|sin|cos|tan|ln|log|lg|abs|pi|exp/i.test(s.replace(/^-/, ""));
}

function format(v) {
    if (Math.abs(v) >= 1e15 || (Math.abs(v) < 1e-6 && v !== 0)) return v.toExponential(6).replace(/\.?0+e/, "e");
    const r = Number(v.toPrecision(12));
    return String(r);
}

// красиво для показа: 1 234 567,89
function pretty(v, ru) {
    const s = format(v);
    if (s.indexOf("e") >= 0) return s;
    const parts = s.split(".");
    const int = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, " ");
    return parts.length > 1 ? int + (ru ? "," : ".") + parts[1] : int;
}
