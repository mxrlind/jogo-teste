// Temporadas, passe de temporada e missões diárias.
import { SEASON_EPOCH, SEASON_LENGTH_DAYS, SEASON_THEMES, SEASON_TIERS, XP_PER_TIER, MISSION_POOL, tierReward } from '../data/seasons.js';
import { mulberry32, hashString, dayKey } from './rng.js';

const DAY = 86400000;

export function seasonInfo(now) {
  const len = SEASON_LENGTH_DAYS * DAY;
  const index = Math.max(0, Math.floor((now - SEASON_EPOCH) / len));
  const start = SEASON_EPOCH + index * len;
  const end = start + len;
  const theme = SEASON_THEMES[index % SEASON_THEMES.length];
  return { index, number: index + 1, theme, start, end, remaining: (end - now) / 1000 };
}

export function tierOf(xp) {
  return Math.min(SEASON_TIERS, Math.floor(xp / XP_PER_TIER));
}

// Garante que o estado da temporada corresponde à temporada atual (troca de temporada = passe zera).
export function syncSeason(state, now) {
  const info = seasonInfo(now);
  if (state.season.number !== info.number) {
    state.season = { number: info.number, xp: 0, claimed: [], missions: state.season.missions };
    return true;
  }
  return false;
}

export function dailyMissions(dateKey, goldScale = 1) {
  const rand = mulberry32(hashString('missoes-' + dateKey));
  const pool = [...MISSION_POOL];
  const out = [];
  for (let i = 0; i < 3; i++) {
    const m = pool.splice(Math.floor(rand() * pool.length), 1)[0];
    const tier = Math.floor(rand() * m.amounts.length);
    let target = m.amounts[tier];
    if (m.scale) target = Math.round(target * goldScale);
    out.push({ id: m.id, track: m.track, target, xp: m.xp + tier * 20, progress: 0, claimed: false });
  }
  return out;
}

export function syncMissions(state, now, goldScale) {
  const key = dayKey(now);
  if (state.season.missions?.day !== key) {
    state.season.missions = { day: key, list: dailyMissions(key, goldScale) };
    return true;
  }
  return false;
}

export function missionText(m) {
  const def = MISSION_POOL.find((p) => p.id === m.id);
  return def ? def.text(m.target) : m.id;
}

export function rewardFor(tier, state) {
  const info = { number: state.season.number };
  const themeIdx = (info.number - 1) % SEASON_THEMES.length;
  return tierReward(tier, info.number, SEASON_THEMES[themeIdx].id);
}
