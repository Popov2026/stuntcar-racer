// double_test.js : logique doublée (touche F1 de SCRF030) contre jeu d'origine, dans le moteur
// fidèle (replica/js/engine.js : le code 68000 du jeu exécuté en JavaScript).
//   node falcon/test/double_test.js DISQUE.st traj   [circuit] [tours]   : trajectoires
//   node falcon/test/double_test.js DISQUE.st degats [circuits] [tours] [échelle/256] : dégâts
// Les modifications sont celles de falcon/src/scrf030.s (dbl_dt, dbl_words). L'échelle donnée
// en mode « degats » essaie en plus une majoration de la force des roues pour les dégâts
// (petit code 68000 posé en $E0000 ; 256 = aucune, ce que fait SCRF030).
global.window = global;
const fs = require('fs'), path = require('path');
for (const f of ['scrdata', 'cpu68k', 'engine']) require(path.join(__dirname, '..', '..', 'replica', 'js', f + '.js'));
const [disk, what] = process.argv.slice(2);
const bytes = new Uint8Array(fs.readFileSync(disk));
const SITES = [0x48a08, 0x4b124, 0x4efaa, 0x4efc6, 0x4efe2, 0x4f014, 0x4f02c, 0x4f044, 0x4f136, 0x4f14e, 0x4f166,
  0x4f180, 0x4f198, 0x4f1b0, 0x507fe, 0x509ea, 0x50ed4, 0x50eec, 0x50f06, 0x50f1e, 0x50f38, 0x50f50];
// move.w $10b0a,d0 / bra.s / move.w $10b0c,d0 / bra.s / move.w $10b0e,d0 / muls.w scale(pc),d0 / asr.l #8,d0 /
// cmp.l #$7fff,d0 / ble.s / move.w #$7fff,d0 / rts / scale
const DMG = [0x30, 0x39, 0, 1, 0x0b, 0x0a, 0x60, 0x0e, 0x30, 0x39, 0, 1, 0x0b, 0x0c, 0x60, 0x06, 0x30, 0x39, 0, 1, 0x0b, 0x0e,
  0xc1, 0xfa, 0x00, 0x12, 0xe0, 0x80, 0xb0, 0xbc, 0, 0, 0x7f, 0xff, 0x6f, 0x04, 0x30, 0x3c, 0x7f, 0xff, 0x4e, 0x75, 0x01, 0x50];
const W = [[0x4b0c4, [0, 6], [0, 3]], [0x4e702, [0xee, 0x48], [0xe0, 0x48]], [0x4ee64, [0x01, 0x14], [0x02, 0x28]],
  [0x4f2b0, [0x30, 0x39, 0, 1, 0x0b, 0x0a], [0x4e, 0xb9, 0, 0x0e, 0, 0x00]],
  [0x4f3d8, [0x30, 0x39, 0, 1, 0x0b, 0x0c], [0x4e, 0xb9, 0, 0x0e, 0, 0x08]],
  [0x4f500, [0x30, 0x39, 0, 1, 0x0b, 0x0e], [0x4e, 0xb9, 0, 0x0e, 0, 0x10]]];
let SCALED = false;
function setMode(e, d) { for (const s of SITES) e.cpu.mem[s + 3] = d ? 0x77 : 0xee; W.forEach(([a, o, n], k) => ((d && (k < 3 || SCALED)) ? n : o).forEach((v, i) => e.cpu.mem[a + i] = v)); }
function engine(trk, scale) {
  const e = new SCR.Engine(bytes); e.renderOriginal = true; e.boot(); e.startPractice(trk);
  DMG.forEach((v, i) => e.cpu.mem[0xe0000 + i] = v); e.cpu.w16(0xe0000 + DMG.length - 2, scale);
  return e;
}
// un tour d'origine (0,12 s) : 1 tour de 6 VBL, ou 2 de 3 VBL en logique doublée (course en cours)
function step(e, dbl, inp) {
  const on = dbl && e.b(0x109c9) === 0; setMode(e, on);
  for (let k = 0; k < (on ? 2 : 1); k++) { e.setInput(inp); e.tick(on ? 3 : 6); }
  return on;
}
const dmg = e => [e.b(0x10939), e.b(0x1093a), e.b(0x1093b)];
if (what === 'traj') {
  const trk = +(process.argv[4] || 0), N = +(process.argv[5] || 300);
  const inp = t => ({ up: t % 120 < 100, down: t % 120 >= 108, left: t % 50 >= 20 && t % 50 < 24, right: t % 50 >= 40 && t % 50 < 43, fire: t % 90 < 10 });
  const A = engine(trk, 256), B = engine(trk, 256);
  const st = e => [(e.l(0x10ac2) / 65536).toFixed(0), (e.l(0x10ac6) / 65536).toFixed(0), (e.l(0x10aca) / 65536).toFixed(0), 'v', Math.hypot(e.sw(0x10ad4), e.sw(0x10ad8)).toFixed(0), 'lacet', e.w(0x10ad0).toString(16), 'dégâts', dmg(e).join('/')].join(' ');
  for (let t = 0; t < N; t++) { step(A, false, inp(t)); step(B, true, inp(t)); if (t % 25 === 0) console.log(String(t).padStart(4), 'normal', st(A), ' | doublé', st(B)); }
} else {
  const tracks = (process.argv[4] || '0,1,2,3,4,5,6,7').split(',').map(Number), N = +(process.argv[5] || 1200), scale = +(process.argv[6] || 256); SCALED = scale !== 256;
  let tot = [0, 0];
  for (const trk of tracks) {
    let s = trk * 7919 + 23; const r = () => (s = (s * 1103515245 + 12345) >>> 0, (s >>> 8) / 16777216);
    const inps = []; let cur = {};
    for (let t = 0; t < N; t++) { if (t % 6 === 0) { const x = r(); cur = { up: x < 0.85, down: x > 0.95, left: r() < 0.12, right: r() < 0.12, fire: r() < 0.2 }; } inps.push(cur); }
    const res = [false, true].map(dbl => { const e = engine(trk, scale); let tot = 0, prev = [0, 0, 0];
      for (let t = 0; t < N; t++) { try { step(e, dbl, inps[t]); } catch (x) { break; } const d = dmg(e); d.forEach((v, i) => { if (v > prev[i]) tot += v - prev[i]; }); prev = d; }
      return tot; });
    tot[0] += res[0]; tot[1] += res[1];
    console.log('circuit', trk, 'dégâts : normal', res[0], ' doublé', res[1]);
  }
  console.log('total : normal', tot[0], ' doublé', tot[1], ' (échelle ' + (scale / 256).toFixed(3) + ')');
}
