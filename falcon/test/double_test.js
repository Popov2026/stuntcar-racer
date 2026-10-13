// double_test.js : logique accélérée (touche F1 de SCRF030 : facteur 2 ou 3) contre jeu
// d'origine, dans le moteur fidèle (replica/js/engine.js : le code 68000 du jeu exécuté en
// JavaScript). Mêmes modifications que falcon/src/scrf030.s (dbl_patch, yaw_div, chrono).
//   node falcon/test/double_test.js DISQUE.st traj   [facteur] [circuit] [tours]
//      trajectoires, mêmes commandes au même instant (position, vitesse, lacet, chrono)
//   node falcon/test/double_test.js DISQUE.st degats [facteur] [circuits] [tours]
//      dégâts : les mêmes 12 tours rejoués depuis un même état, normal puis accéléré
global.window = global;
const fs = require('fs'), path = require('path');
for (const f of ['scrdata', 'cpu68k', 'engine']) require(path.join(__dirname, '..', '..', 'replica', 'js', f + '.js'));
const [disk, what] = process.argv.slice(2);
const F = +(process.argv[4] || 2);
const bytes = new Uint8Array(fs.readFileSync(disk));
const SITES = [0x48a08, 0x4b124, 0x4efaa, 0x4efc6, 0x4efe2, 0x4f014, 0x4f02c, 0x4f044, 0x4f136, 0x4f14e, 0x4f166,
  0x4f180, 0x4f198, 0x4f1b0, 0x507fe, 0x509ea, 0x50ed4, 0x50eec, 0x50f06, 0x50f1e, 0x50f38, 0x50f50];
const DT = { 1: 0xee, 2: 0x77, 3: 0x4f }, REL = { 1: 6, 2: 3, 3: 2 }, DAMP = { 1: 0x114, 2: 0x228, 3: 0x33c }, MUL = { 2: 0x8000, 3: 0x5556 };
// yaw_div posé en $E0100 : muls.w d3,d0 ; add.l d0,d0 ; swap d0 ; lsr.w #7,d0 ; mulu.w mul(pc),d0 ; swap d0 ; rts
const YAW = [0xc1, 0xc3, 0xd0, 0x80, 0x48, 0x40, 0xee, 0x48, 0xc0, 0xfa, 0x00, 0x06, 0x48, 0x40, 0x4e, 0x75, 0x55, 0x56];
const YAWO = [0xc1, 0xc3, 0xe3, 0x80, 0x48, 0x40, 0xee, 0x48], YAWN = [0x4e, 0xb9, 0, 0x0e, 0x01, 0x00, 0x4e, 0x71];
function setLevel(e, L) {
  for (const s of SITES) e.cpu.mem[s + 3] = DT[L];
  e.cpu.mem[0x4b0c5] = REL[L]; e.cpu.w16(0x4ee64, DAMP[L]);
  (L > 1 ? YAWN : YAWO).forEach((v, i) => e.cpu.mem[0x4e6fc + i] = v);
  if (L > 1) e.cpu.w16(0xe0100 + YAW.length - 2, MUL[L]);
  if (L === 1) e.cpu.mem[0x4b517] = 0x13;
}
function engine(trk) { const e = new SCR.Engine(bytes); e.renderOriginal = true; e.boot(); e.startPractice(trk); YAW.forEach((v, i) => e.cpu.mem[0xe0100 + i] = v); e.chrRem = 0; return e; }
// un tour d'origine (0,12 s) : 1 tour de 6 VBL, ou F tours de 6/F VBL pendant la course
function step(e, fast, inp) {
  const L = fast && e.b(0x109c9) === 0 ? F : 1; setLevel(e, L);
  for (let k = 0; k < L; k++) {
    if (L > 1) { const a = 13 * REL[L] + e.chrRem; e.cpu.mem[0x4b517] = Math.floor(a / 6); e.chrRem = a % 6; }
    e.setInput(inp); e.tick(REL[L]);
  }
}
const dmg = e => e.b(0x10939) + e.b(0x1093a) + e.b(0x1093b);
const CF = ['pc', 's', 'ipl', 't', 'x', 'n', 'z', 'v', 'c', 'usp', 'ssp', 'stopped', 'count'];
function clone(src, dst) {
  dst.cpu.mem.set(src.cpu.mem); dst.cpu.d = src.cpu.d.slice(); dst.cpu.a = src.cpu.a.slice(); for (const f of CF) dst.cpu[f] = src.cpu[f];
  dst.sinceVbl = src.sinceVbl; dst.vblCount = src.vblCount; dst.chrRem = 0;
  dst.io.palette.set(src.io.palette); dst.io.vbase = src.io.vbase; dst.io.ym.set(src.io.ym); dst.io.ymSel = src.io.ymSel; dst.io.mfp.set(src.io.mfp);
}
if (what === 'traj') {
  const trk = +(process.argv[5] || 0), N = +(process.argv[6] || 300);
  const inp = t => ({ up: t % 120 < 100, down: t % 120 >= 108, left: t % 50 >= 20 && t % 50 < 24, right: t % 50 >= 40 && t % 50 < 43, fire: t % 90 < 10 });
  const A = engine(trk), B = engine(trk);
  const st = e => [(e.l(0x10ac2) / 65536).toFixed(0), (e.l(0x10ac6) / 65536).toFixed(0), (e.l(0x10aca) / 65536).toFixed(0), 'v', Math.hypot(e.sw(0x10ad4), e.sw(0x10ad8)).toFixed(0), 'lacet', e.w(0x10ad0).toString(16), 'chrono', e.b(0x11002).toString(16) + ':' + e.b(0x1101a).toString(16) + '.' + e.b(0x11032).toString(16)].join(' ');
  for (let t = 0; t < N; t++) { step(A, false, inp(t)); step(B, true, inp(t)); if (t % 25 === 0) console.log(String(t).padStart(4), 'normal', st(A), ' | x' + F, st(B)); }
} else {
  const tracks = (process.argv[5] || '0,1,2,3,4,5,6,7').split(',').map(Number), N = +(process.argv[6] || 1500), H = 12;
  let n = 0, tn = 0, tf = 0;
  for (const trk of tracks) {
    const M = engine(trk), X = engine(trk);
    let s = trk * 7919 + 101; const r = () => (s = (s * 1103515245 + 12345) >>> 0, (s >>> 8) / 16777216);
    const inps = []; let cur = {};
    for (let t = 0; t < N + H; t++) { if (t % 6 === 0) { const x = r(); cur = { up: x < 0.85, down: x > 0.95, left: r() < 0.1, right: r() < 0.1, fire: r() < 0.25 }; } inps.push(cur); }
    for (let t = 0; t < N; t++) {
      if (t % 6 === 0 && M.b(0x109c9) === 0 && dmg(M) < 600) {
        let ok = true; const run = fast => { clone(M, X); const d0 = dmg(X); try { for (let k = 0; k < H; k++) step(X, fast, inps[t + k]); } catch (x) { ok = false; } return dmg(X) - d0; };
        const a = run(false), b = run(true);
        if (ok) { n++; tn += a; tf += b; }
      }
      try { step(M, false, inps[t]); } catch (x) { break; }
    }
    console.log('circuits jusqu\'à', trk, ':', n, 'passages, dégâts normal', tn, ' x' + F, tf);
  }
  console.log('total :', n, 'passages ; dégâts normal', tn, ' x' + F, tf, '(' + (tf / tn * 100 - 100).toFixed(0) + ' %)');
}
