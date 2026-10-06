const SUFFIXES = ['', 'K', 'M', 'B', 'T', 'Qa', 'Qi', 'Sx', 'Sp', 'Oc', 'No', 'Dc'];

// Números no padrão brasileiro: vírgula decimal (1,5K; 0,3/s).
export function fmt(n, decimals = 1) {
  return fmtRaw(n, decimals).replace('.', ',');
}

function fmtRaw(n, decimals) {
  if (!Number.isFinite(n)) return 'infinito';
  const sign = n < 0 ? '-' : '';
  n = Math.abs(n);
  if (n < 1000) {
    if (n < 10 && n % 1 !== 0) return sign + n.toFixed(decimals);
    return sign + Math.floor(n).toString();
  }
  const tier = Math.min(SUFFIXES.length - 1, Math.floor(Math.log10(n) / 3));
  const scaled = n / 10 ** (tier * 3);
  return sign + scaled.toFixed(scaled < 100 ? decimals : 0) + SUFFIXES[tier];
}

export function fmtRate(n) {
  return (n >= 0 ? '+' : '') + fmt(n) + '/s';
}

export function fmtPct(f) {
  return (f >= 0 ? '+' : '') + Math.round(f * 100) + '%';
}

export function fmtTime(sec) {
  sec = Math.max(0, Math.floor(sec));
  const d = Math.floor(sec / 86400);
  const h = Math.floor((sec % 86400) / 3600);
  const m = Math.floor((sec % 3600) / 60);
  const s = sec % 60;
  if (d > 0) return `${d}d ${h}h`;
  if (h > 0) return `${h}h ${m}m`;
  if (m > 0) return `${m}m ${String(s).padStart(2, '0')}s`;
  return `${s}s`;
}

