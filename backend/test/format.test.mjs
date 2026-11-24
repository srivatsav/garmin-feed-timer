// The generated CSV must match test/nara-known-good.csv: the exact structure of a file My Baby
// imported successfully, with made-up names, times and ids.
import { toCsv, NARA_COLUMNS, fmtLocal } from '../src/format.js';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const TZ = 'Europe/London';
const ist = (s) => Math.floor(Date.parse(s.replace(' ', 'T') + 'Z') / 1000);   // London = UTC in January
const known = readFileSync(new URL('./nara-known-good.csv', import.meta.url), 'utf8');

// 1. byte-for-byte match with the file My Baby accepted
const events = [
  { id: 'a1', first_side: 'L', left_s: 840, right_s: 0, start_ts: ist('2026-01-15 07:00:00') },
  { id: 'a2', first_side: 'R', left_s: 0, right_s: 900, start_ts: ist('2026-01-15 09:30:00') },
];
const OPTS = { profileName: 'Baby', caregiver: 'Parent', sex: 'FEMALE' };
assert.equal(toCsv(events, TZ, OPTS), known);

// 2. shape: 70 columns, 69-cell profile footer
assert.equal(NARA_COLUMNS.length, 70);
const lines = toCsv(events, TZ, OPTS).trim().split('\n');
assert.equal(lines[0].split('","').length, 70);
assert.equal(lines[lines.length - 1].split('","').length, 69);

// 3. both sides: begin = first side, end = the other one
const both = toCsv([{ id: 'b', first_side: 'R', left_s: 300, right_s: 420, start_ts: ist('2026-01-15 12:00:00') }], TZ);
const cells = both.split('\n')[1].slice(1, -1).split('","');
const col = (name) => cells[NARA_COLUMNS.indexOf(name)];
assert.equal(col('[Breastfeed] Begin Side'), 'RIGHT');
assert.equal(col('[Breastfeed] End Side'), 'LEFT');
assert.equal(col('[Breastfeed] Left Duration (Seconds)'), '300');
assert.equal(col('[Breastfeed] Right Duration (Seconds)'), '420');
assert.equal(col('_activityKey'), 'garmin-b');

// 4. local time
assert.equal(fmtLocal(ist('2026-01-15 23:59:59'), TZ), '2026-01-15 23:59:59');

console.log('all Nara format checks passed (byte-identical to the file My Baby accepted)');
