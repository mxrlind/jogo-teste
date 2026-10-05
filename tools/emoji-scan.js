// Varredura de emoji. Uso: node tools/emoji-scan.js [--all]
// Por padrão varre só o que é publicado como jogo (index.html, styles.css, src/, assets/*.svg|json).
// --all inclui documentação e ferramentas (informativo).
// Sai com código 1 se encontrar qualquer ocorrência nos arquivos do jogo.
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative, extname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('..', import.meta.url));
const all = process.argv.includes('--all');

// \p{Extended_Pictographic}: pictogramas (inclui U+2600-U+27BF, U+1F300-U+1FAFF etc.)
// \p{Emoji_Presentation}: caracteres renderizados como emoji por padrão
// U+FE0E/U+FE0F: seletores de variação; U+200D: ZWJ; U+20E3: keycap;
// U+1F1E6-1F1FF: indicadores regionais (bandeiras); U+1F3FB-1F3FF: tons de pele; U+E0020-E007F: tags.
const EMOJI = /[\p{Extended_Pictographic}\p{Emoji_Presentation}\u{FE0E}\u{FE0F}\u{200D}\u{20E3}\u{1F1E6}-\u{1F1FF}\u{1F3FB}-\u{1F3FF}\u{E0020}-\u{E007F}]/gu;

const GAME = ['index.html', 'estilo.html', 'styles.css', 'src', 'assets', 'manifest.webmanifest'];
const EXTRA = ['docs', 'tools', 'tests', 'README.md', 'GDD.md', 'ROADMAP.md', 'CHANGELOG.md', 'ASSETS.md', 'EXECUTAR.md', 'package.json'];
const TEXT_EXT = new Set(['.js', '.html', '.css', '.json', '.md', '.svg', '.webmanifest', '.txt', '']);

function walk(p, out) {
  let st;
  try { st = statSync(p); } catch { return; }
  if (st.isDirectory()) for (const f of readdirSync(p)) walk(join(p, f), out);
  else if (TEXT_EXT.has(extname(p))) out.push(p);
}

function scan(targets) {
  const files = [];
  for (const t of targets) walk(join(root, t), files);
  const hits = [];
  for (const f of files) {
    const lines = readFileSync(f, 'utf8').split('\n');
    lines.forEach((line, i) => {
      for (const m of line.matchAll(EMOJI)) {
        const cp = m[0].codePointAt(0).toString(16).toUpperCase().padStart(4, '0');
        hits.push({ file: relative(root, f), line: i + 1, col: m.index + 1, cp: `U+${cp}` });
      }
    });
  }
  return { files: files.length, hits };
}

const game = scan(GAME);
console.log(`Arquivos do jogo varridos: ${game.files}`);
console.log(`Ocorrências de emoji no jogo: ${game.hits.length}`);
const byFile = {};
for (const h of game.hits) (byFile[h.file] ||= []).push(h);
for (const [f, hs] of Object.entries(byFile)) {
  console.log(`  ${f}: ${hs.length} (ex.: linha ${hs[0].line} col ${hs[0].col} ${hs[0].cp})`);
}
if (all) {
  const extra = scan(EXTRA);
  console.log(`\n[informativo] docs/ferramentas: ${extra.files} arquivos, ${extra.hits.length} ocorrências`);
  const bf = {};
  for (const h of extra.hits) bf[h.file] = (bf[h.file] || 0) + 1;
  for (const [f, n] of Object.entries(bf)) console.log(`  ${f}: ${n}`);
}
process.exit(game.hits.length ? 1 : 0);
