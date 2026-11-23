// 중앙 HUD 개선안 SVG 목업 생성기 (node tests/hud_mockups/gen.js)
// 각도 규칙: LÖVE와 동일하게 +x 기준 시계방향(화면 y-down) 도(degree) 단위.
const fs = require('fs');
const path = require('path');

const S = { shield: 28, maxShield: 40, armor: 30, maxArmor: 30, hull: 3, maxHull: 5, battery: 0.65, speed: 184, maxSpeed: 320 };
const C = { cyan: '#6EDEF2', armor: '#E8D4A3', hull: '#F28A6E', amber: '#FFB84D', amberCore: '#FFE69E', dim: '#8FC4D2' };
const RES = [
  { key: 'shield', max: 'maxShield', unit: 10, color: C.cyan, tag: 'SHD' },
  { key: 'armor', max: 'maxArmor', unit: 10, color: C.armor, tag: 'ARM' },
  { key: 'hull', max: 'maxHull', unit: 1, color: C.hull, tag: 'HUL' },
];
const FONT = "Consolas, 'Cascadia Mono', 'Segoe UI', monospace";

const rad = d => d * Math.PI / 180;
const f2 = v => +v.toFixed(2);
const P = (r, a) => [f2(r * Math.cos(rad(a))), f2(r * Math.sin(rad(a)))];
const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
function arc(r, a0, a1) {
  const [x0, y0] = P(r, a0), [x1, y1] = P(r, a1);
  return `M${x0} ${y0}A${r} ${r} 0 ${a1 - a0 > 180 ? 1 : 0} 1 ${x1} ${y1}`;
}
function sector(r0, r1, a0, a1, skew = 0) {
  const [ax, ay] = P(r1, a0 + skew), [bx, by] = P(r1, a1 + skew), [cx, cy] = P(r0, a1), [dx, dy] = P(r0, a0);
  const L = a1 - a0 > 180 ? 1 : 0;
  return `M${ax} ${ay}A${r1} ${r1} 0 ${L} 1 ${bx} ${by}L${cx} ${cy}A${r0} ${r0} 0 ${L} 0 ${dx} ${dy}Z`;
}
const line = (r0, r1, a, attrs) => { const [x0, y0] = P(r0, a), [x1, y1] = P(r1, a); return `<line x1="${x0}" y1="${y0}" x2="${x1}" y2="${y1}" ${attrs}/>`; };
const pathEl = (d, attrs) => `<path d="${d}" ${attrs}/>`;
const text = (x, y, s, size, fill, extra = '') => `<text x="${x}" y="${y}" font-family="${FONT}" font-size="${size}" fill="${fill}" ${extra.includes('text-anchor') ? '' : 'text-anchor="middle"'} ${extra}>${s}</text>`;
function segs(res) {
  const max = S[res.max], val = clamp(S[res.key], 0, max), n = Math.ceil(max / res.unit), out = [];
  for (let i = 0; i < n; i++) { const used = i * res.unit, cap = Math.min(res.unit, max - used); out.push(clamp((val - used) / cap, 0, 1)); }
  return { n, out, frac: val / max };
}

let seed = 7;
const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
function stars() {
  seed = 7; let s = '';
  for (let i = 0; i < 60; i++) s += `<circle cx="${f2(rnd() * 240 - 120)}" cy="${f2(rnd() * 240 - 120)}" r="${f2(0.2 + rnd() * 0.5)}" fill="#cfe6ff" opacity="${f2(0.15 + rnd() * 0.5)}"/>`;
  return s;
}
const GLOW = `<filter id="glow" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="1.4" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>`;
function wrap(title, body, defs = '') {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="480" height="480" viewBox="-110 -110 220 220">
<defs>${GLOW}${defs}</defs>
<rect x="-110" y="-110" width="220" height="220" fill="#060a12"/>${stars()}
<g opacity="0.8">${body}</g>
${text(-106, -102, title, 6, '#9fb8c4', 'text-anchor="start" letter-spacing="0.6"')}
</svg>`;
}

// ---------- 0. 현재 HUD 재현 ----------
function current() {
  let b = `<circle r="82" fill="rgb(5,9,15)" fill-opacity="0.96" stroke="rgb(82,143,171)" stroke-opacity="0.42" stroke-width="1"/>`;
  for (let i = 0; i <= 24; i++) { const a = 150 + 240 * i / 24; b += line(i % 4 ? 76 : 74, 79, a, `stroke="#87b8cc" stroke-opacity="${i % 4 ? 0.24 : 0.55}"`); }
  RES.forEach((res, i) => {
    const { n, out } = segs(res); const r = 70 - i * 11, sw = 240 / n, gap = Math.min(4.58, sw * 0.18);
    out.forEach((v, k) => { const a0 = 150 + k * sw + gap / 2, a1 = a0 + sw - gap;
      b += pathEl(arc(r, a0, a1), `fill="none" stroke="${res.color}" stroke-opacity="0.15" stroke-width="5"`);
      if (v > 0) b += pathEl(arc(r, a0, a0 + (a1 - a0) * v), `fill="none" stroke="${res.color}" stroke-opacity="0.96" stroke-width="5"`); });
  });
  b += `<circle r="39" fill="rgb(8,14,21)" fill-opacity="0.34" stroke="rgb(99,173,194)" stroke-opacity="0.3"/>`;
  const depleted = (1 - S.battery) * 20;
  for (let c = 0; c < 20; c++) { const charge = clamp(c + 1 - depleted, 0, 1);
    for (let r = 0; r < 4; r++) { const R = 16 + r * 5.5, pad = Math.min(18 * 0.28, (1.35 / R) * 180 / Math.PI), a0 = -90 + c * 18 + pad, a1 = -90 + (c + 1) * 18 - pad;
      b += pathEl(arc(R, a0, a1), `fill="none" stroke="rgb(107,79,46)" stroke-opacity="0.22" stroke-width="4"`);
      if (charge > 0) b += pathEl(arc(R, a0, a1), `fill="none" stroke="${C.amber}" stroke-opacity="${0.94 * charge}" stroke-width="4"`) + pathEl(arc(R, a0, a1), `fill="none" stroke="${C.amberCore}" stroke-opacity="${0.78 * charge}" stroke-width="1.8"`); } }
  b += `<circle r="11" fill="rgb(6,10,15)" stroke="#9ea8ad" stroke-opacity="0.55" stroke-width="1.2"/><circle r="7.5" fill="none" stroke="#526b7a" stroke-opacity="0.45"/>`;
  b += pathEl(arc(70, 34.6, 145.4), `fill="none" stroke="${C.cyan}" stroke-opacity="0.15" stroke-width="4"`);
  b += pathEl(arc(70, 34.6, 34.6 + 110.8 * S.speed / S.maxSpeed), `fill="none" stroke="${C.cyan}" stroke-width="4"`);
  b += text(0, 53, S.speed, 15, '#d9f7ff') + text(0, 63, 'PX/S', 7, C.cyan);
  return wrap('0 · CURRENT', b);
}

// ---------- A. Hairline Glass : 얇은 선 + 글로우, 숫자 중심 ----------
function glass() {
  const defs = `<radialGradient id="gA"><stop offset="0.35" stop-color="#04101c" stop-opacity="0.15"/><stop offset="0.8" stop-color="#04101c" stop-opacity="0.7"/><stop offset="1" stop-color="#04101c" stop-opacity="0"/></radialGradient>`;
  let b = `<circle r="90" fill="url(#gA)"/>`;
  b += `<circle r="82" fill="none" stroke="${C.dim}" stroke-opacity="0.28" stroke-width="0.5"/>`;
  b += `<circle r="85" fill="none" stroke="${C.dim}" stroke-opacity="0.35" stroke-width="0.6" stroke-dasharray="0.5 3"/>`;
  [270, 0, 180].forEach(a => { b += line(80, 86, a, `stroke="${C.cyan}" stroke-opacity="0.7" stroke-width="0.8"`); });
  RES.forEach((res, i) => {
    const { n, out, frac } = segs(res); const r = 72 - i * 8, sw = 240 / n, gap = 1.6;
    out.forEach((v, k) => { const a0 = 150 + k * sw + gap / 2, a1 = a0 + sw - gap;
      b += pathEl(arc(r, a0, a1), `fill="none" stroke="${res.color}" stroke-opacity="0.13" stroke-width="2.6"`);
      if (v > 0) b += pathEl(arc(r, a0, a0 + (a1 - a0) * v), `fill="none" stroke="${res.color}" stroke-width="2.6" filter="url(#glow)"`); });
    const endA = 150 + 240 * frac;
    if (frac > 0 && frac < 1) b += line(r - 3, r + 3, endA, `stroke="#ffffff" stroke-width="0.8"`);
    const [tx, ty] = P(r, 393);
    b += text(tx + 4, ty + 1.6, res.tag[0], 4.4, res.color, 'text-anchor="start" opacity="0.85"');
  });
  // 커패시터: 48개 방사형 눈금
  const N = 48, lit = Math.round(S.battery * N);
  for (let k = 0; k < N; k++) { const a = -90 + k * 360 / N + 3.75, on = k >= N - lit;
    b += line(24, 36, a, on ? `stroke="${C.amber}" stroke-width="1.7" filter="url(#glow)"` : `stroke="#6b4f2e" stroke-opacity="0.45" stroke-width="1.7"`); }
  b += `<circle r="40" fill="none" stroke="${C.dim}" stroke-opacity="0.18" stroke-width="0.5"/>`;
  b += `<circle r="20" fill="#05090f" fill-opacity="0.8" stroke="${C.amber}" stroke-opacity="0.35" stroke-width="0.5"/>`;
  b += text(0, 3.2, Math.round(S.battery * 100), 10, C.amberCore, 'font-weight="300"') + text(0, 9.5, 'CAP %', 3.4, C.amber, 'letter-spacing="0.6" opacity="0.8"');
  // 속도: 하단 눈금 스케일 (좌→우)
  const T = 25, litT = Math.round(S.speed / S.maxSpeed * (T - 1));
  for (let k = 0; k < T; k++) { const a = 140 - k * 100 / (T - 1), major = k % 6 === 0;
    b += line(major ? 73 : 75, 79, a, k <= litT ? `stroke="${C.cyan}" stroke-width="${major ? 1.1 : 0.8}" filter="url(#glow)"` : `stroke="${C.dim}" stroke-opacity="0.25" stroke-width="0.7"`); }
  b += text(0, 59, S.speed, 14, '#e6fbff', 'font-weight="300" letter-spacing="1"') + text(0, 66, 'PX/S', 3.8, C.cyan, 'letter-spacing="1.2"');
  return wrap('A · HAIRLINE GLASS', b, defs);
}

// ---------- B. Tactical Angular : 기울어진 블록 셀 + 각진 프레임 ----------
function tactical() {
  const defs = `<pattern id="hex" width="8" height="13.86" patternUnits="userSpaceOnUse"><path d="M4 0L8 2.31L8 6.93L4 9.24L0 6.93L0 2.31Z M4 9.24L4 13.86" fill="none" stroke="${C.dim}" stroke-opacity="0.07" stroke-width="0.4"/></pattern>
<linearGradient id="capB" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${C.amberCore}"/><stop offset="1" stop-color="${C.amber}"/></linearGradient>`;
  let b = `<circle r="80" fill="#050a12" fill-opacity="0.92"/><circle r="80" fill="url(#hex)"/>`;
  b += `<circle r="80" fill="none" stroke="${C.dim}" stroke-opacity="0.3" stroke-width="0.6"/>`;
  [[200, 250], [290, 340]].forEach(([a0, a1]) => { b += pathEl(arc(85, a0, a1), `fill="none" stroke="${C.cyan}" stroke-opacity="0.75" stroke-width="1.2"`);
    b += line(82, 88, a0, `stroke="${C.cyan}" stroke-opacity="0.75" stroke-width="1.2"`) + line(82, 88, a1, `stroke="${C.cyan}" stroke-opacity="0.75" stroke-width="1.2"`); });
  b += `<path d="M-3 -88L3 -88L0 -84Z" fill="${C.cyan}"/>`;
  RES.forEach((res, i) => {
    const { n, out } = segs(res); const r1 = 74 - i * 9, r0 = r1 - 6, sw = 240 / n, gap = 2.6, skew = 2.5;
    out.forEach((v, k) => { const a0 = 150 + k * sw + gap / 2, a1 = a0 + sw - gap;
      b += pathEl(sector(r0, r1, a0, a1, skew), `fill="${res.color}" fill-opacity="0.07" stroke="${res.color}" stroke-opacity="0.35" stroke-width="0.4"`);
      if (v > 0) b += pathEl(sector(r0, r1, a0, a0 + (a1 - a0) * v, skew), `fill="${res.color}" fill-opacity="0.92"`); });
    const [tx, ty] = P(r1 - 3, 147);
    b += text(tx - 1, ty + 1.4, res.tag, 3.6, res.color, 'text-anchor="end" font-weight="bold" letter-spacing="0.3"');
  });
  // 커패시터: 단일 링 20셀(사다리꼴) + 육각 허브
  const N = 20, depleted = (1 - S.battery) * N;
  for (let c = 0; c < N; c++) { const charge = clamp(c + 1 - depleted, 0, 1), a0 = -90 + c * 18 + 2, a1 = a0 + 14;
    b += pathEl(sector(23, 37, a0, a1), charge > 0 ? `fill="url(#capB)" fill-opacity="${0.25 + 0.7 * charge}"` : `fill="#6b4f2e" fill-opacity="0.18" stroke="#6b4f2e" stroke-opacity="0.5" stroke-width="0.4"`); }
  const hex = [0, 1, 2, 3, 4, 5].map(k => P(18, -90 + k * 60).join(' ')).join('L');
  b += `<path d="M${hex}Z" fill="#070d15" stroke="${C.amber}" stroke-opacity="0.6" stroke-width="0.7"/>`;
  b += text(0, 2.5, `${Math.round(S.battery * 100)}<tspan font-size="4">%</tspan>`, 8.5, C.amberCore, 'font-weight="bold"') + text(0, 8.6, 'CAP', 3.3, C.amber, 'letter-spacing="0.8"');
  // 속도: 노치형 디지털 박스 + 수평 세그먼트 바
  b += `<path d="M-24 44L20 44L24 48L24 60L-20 60L-24 56Z" fill="#071019" stroke="${C.cyan}" stroke-opacity="0.55" stroke-width="0.6"/>`;
  b += text(-2, 56.5, String(S.speed).padStart(3, '0'), 12, '#e6fbff', 'font-weight="bold" letter-spacing="1"') + text(19, 58, 'PX/S', 2.8, C.cyan, 'text-anchor="end"');
  const bars = 12, litB = Math.round(S.speed / S.maxSpeed * bars);
  for (let k = 0; k < bars; k++) b += `<path d="M${-24 + k * 4.1 + 1} 63L${-24 + k * 4.1 + 4.1} 63L${-24 + k * 4.1 + 3.1} 66L${-24 + k * 4.1} 66Z" fill="${C.cyan}" fill-opacity="${k < litB ? 0.95 : 0.15}"/>`;
  return wrap('B · TACTICAL ANGULAR', b, defs);
}

// ---------- C. Split Gauge : 좌 방어 / 우 커패시터 / 중앙 속도계 ----------
function split() {
  const defs = `<linearGradient id="gC" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#0a1626"/><stop offset="1" stop-color="#03070d"/></linearGradient>`;
  let b = `<circle r="82" fill="url(#gC)" fill-opacity="0.94" stroke="${C.dim}" stroke-opacity="0.35" stroke-width="0.6"/><circle r="78.5" fill="none" stroke="${C.dim}" stroke-opacity="0.12" stroke-width="0.4"/>`;
  b += line(46, 82, 270, `stroke="${C.dim}" stroke-opacity="0.3" stroke-width="0.5"`) + line(46, 82, 90, `stroke="${C.dim}" stroke-opacity="0.3" stroke-width="0.5"`);
  RES.forEach((res, i) => {
    const { n, out } = segs(res); const r = 72 - i * 8.5, span = 150, sw = span / n, gap = 2.2;
    out.forEach((v, k) => { const a0 = 105 + k * sw + gap / 2, a1 = a0 + sw - gap; // 하단→상단으로 충전
      b += pathEl(arc(r, a0, a1), `fill="none" stroke="${res.color}" stroke-opacity="0.14" stroke-width="5"`);
      if (v > 0) b += pathEl(arc(r, a0, a0 + (a1 - a0) * v), `fill="none" stroke="${res.color}" stroke-width="5"`); });
  });
  b += text(-30, -86, 'DEFENSE', 3.6, C.dim, 'letter-spacing="1" opacity="0.8"');
  // 커패시터: 우측 2열 셀 밴드, 하단부터 충전
  const N = 20, lit = S.battery * N;
  for (let c = 0; c < N; c++) { const a0 = 75 - (c + 1) * 7.5 + 0.9, a1 = a0 + 5.7, charge = clamp(lit - c, 0, 1);
    [[64, 72], [55, 62]].forEach(([r0, r1]) => {
      b += pathEl(sector(r0, r1, a0, a1), charge > 0 ? `fill="${C.amber}" fill-opacity="${0.95 * charge}"` : `fill="#6b4f2e" fill-opacity="0.25"`); }); }
  b += text(30, -86, `CAP ${Math.round(S.battery * 100)}%`, 3.6, C.amber, 'letter-spacing="1"');
  // 중앙 속도계 (270° 스윕, 하단 개구)
  b += `<circle r="44" fill="#03070d" fill-opacity="0.7" stroke="${C.dim}" stroke-opacity="0.2" stroke-width="0.5"/>`;
  b += pathEl(arc(38, 135, 405), `fill="none" stroke="${C.cyan}" stroke-opacity="0.13" stroke-width="3"`);
  const endA = 135 + 270 * S.speed / S.maxSpeed;
  b += pathEl(arc(38, 135, endA), `fill="none" stroke="${C.cyan}" stroke-width="3" filter="url(#glow)"`);
  for (let k = 0; k <= 10; k++) b += line(k % 5 ? 31.5 : 30, 33.5, 135 + 27 * k, `stroke="${C.dim}" stroke-opacity="${k % 5 ? 0.35 : 0.8}" stroke-width="0.6"`);
  const [nx, ny] = P(41.5, endA);
  b += `<circle cx="${nx}" cy="${ny}" r="1.6" fill="#ffffff"/>`;
  b += text(0, 6, S.speed, 19, '#e6fbff', 'font-weight="300"') + text(0, 14, 'PX/S', 4, C.cyan, 'letter-spacing="1.2"');
  return wrap('C · SPLIT GAUGE', b, defs);
}

// ---------- D. Holographic Reticle : 점선 링 + 도트 매트릭스 커패시터 + 피해 잔상 ----------
function holo() {
  const defs = `<radialGradient id="gD"><stop offset="0.5" stop-color="#021018" stop-opacity="0.55"/><stop offset="0.92" stop-color="#021018" stop-opacity="0.75"/><stop offset="1" stop-color="#021018" stop-opacity="0"/></radialGradient>
<linearGradient id="spdD" x1="-1" y1="0" x2="1" y2="0" gradientUnits="objectBoundingBox"><stop offset="0" stop-color="${C.cyan}" stop-opacity="0.5"/><stop offset="1" stop-color="#ffffff"/></linearGradient>`;
  let b = `<circle r="88" fill="url(#gD)"/>`;
  b += `<circle r="84" fill="none" stroke="${C.cyan}" stroke-opacity="0.55" stroke-width="0.9" stroke-dasharray="0.4 2.2"/>`;
  b += pathEl(arc(80, 160, 380), `fill="none" stroke="${C.dim}" stroke-opacity="0.35" stroke-width="0.4"`);
  [210, 330].forEach(a => { const [x, y] = P(80, a); b += `<circle cx="${x}" cy="${y}" r="1" fill="${C.cyan}"/>`; });
  b += `<path d="M0 -79L-2.4 -84.5L2.4 -84.5Z" fill="${C.cyan}" opacity="0.9"/>`;
  const ghost = { shield: 0.1, armor: 0, hull: 0 }; // 최근 피해 잔상 비율 예시
  RES.forEach((res, i) => {
    const { n, frac } = segs(res); const r = 71 - i * 9;
    b += pathEl(arc(r, 150, 390), `fill="none" stroke="${res.color}" stroke-opacity="0.12" stroke-width="4.2"`);
    const g = ghost[res.key];
    if (g > 0) b += pathEl(arc(r, 150 + 240 * frac, 150 + 240 * Math.min(1, frac + g)), `fill="none" stroke="#ffffff" stroke-opacity="0.55" stroke-width="4.2"`);
    if (frac > 0) b += pathEl(arc(r, 150, 150 + 240 * frac), `fill="none" stroke="${res.color}" stroke-width="4.2" filter="url(#glow)"`);
    for (let k = 1; k < n; k++) b += line(r - 2.6, r + 2.6, 150 + 240 * k / n, `stroke="#04101a" stroke-width="1.3"`);
    const [tx, ty] = P(r, 150);
    b += text(tx - 1, ty + 6, Math.round(frac * 100), 3.8, res.color, 'opacity="0.9"');
  });
  // 커패시터: 24열 × 3행 도트 매트릭스
  const N = 24, depleted = (1 - S.battery) * N;
  for (let c = 0; c < N; c++) { const charge = clamp(c + 1 - depleted, 0, 1), a = -90 + (c + 0.5) * 15;
    [21, 27, 33].forEach((R, ri) => { const [x, y] = P(R, a), rr = 1.1 + ri * 0.35;
      b += charge > 0 ? `<circle cx="${x}" cy="${y}" r="${rr}" fill="${C.amber}" fill-opacity="${0.35 + 0.65 * charge}" filter="url(#glow)"/>` : `<circle cx="${x}" cy="${y}" r="${rr}" fill="none" stroke="${C.amber}" stroke-opacity="0.25" stroke-width="0.4"/>`; }); }
  b += `<circle r="14" fill="#03080e" stroke="${C.amber}" stroke-opacity="0.45" stroke-width="0.5"/>`;
  [0, 90, 180, 270].forEach(a => { b += line(14, 16.5, a, `stroke="${C.amber}" stroke-opacity="0.6" stroke-width="0.6"`); });
  b += text(0, 2.6, Math.round(S.battery * 100), 8, C.amberCore) + text(0, 7.6, 'CAP', 2.8, C.amber, 'letter-spacing="0.8"');
  // 속도: 하단 스피도 틱 + 포인터
  const T = 31, f = S.speed / S.maxSpeed;
  for (let k = 0; k < T; k++) { const t = k / (T - 1), a = 140 - t * 100, on = t <= f;
    b += line(k % 5 ? 73.5 : 72, 77, a, on ? `stroke="${C.cyan}" stroke-opacity="${0.45 + 0.55 * t / f}" stroke-width="0.9"` : `stroke="${C.dim}" stroke-opacity="0.22" stroke-width="0.6"`); }
  const pa = 140 - f * 100, [px, py] = P(78, pa), [qx, qy] = P(82.5, pa - 2.2), [sx, sy] = P(82.5, pa + 2.2);
  b += `<path d="M${px} ${py}L${qx} ${qy}L${sx} ${sy}Z" fill="#ffffff"/>`;
  b += text(0, 56, S.speed, 15, '#e6fbff', 'letter-spacing="1"') + text(0, 63, 'PX/S', 3.6, C.cyan, 'letter-spacing="1.2"');
  return wrap('D · HOLOGRAPHIC RETICLE', b, defs);
}

const outDir = __dirname;
const files = { '0_current.svg': current(), 'A_hairline_glass.svg': glass(), 'B_tactical_angular.svg': tactical(), 'C_split_gauge.svg': split(), 'D_holographic_reticle.svg': holo() };
for (const [name, svg] of Object.entries(files)) fs.writeFileSync(path.join(outDir, name), svg);
if (process.argv[2]) { fs.mkdirSync(process.argv[2], { recursive: true }); for (const [name, svg] of Object.entries(files)) fs.writeFileSync(path.join(process.argv[2], name), svg); }
console.log('generated', Object.keys(files).join(', '));
