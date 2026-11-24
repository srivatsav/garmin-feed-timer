// Builds the CSV that My Baby's "Import data" accepts.
//
// My Baby only imports files exported by the Nara Baby app (confirmed by the developer),
// so we write a Nara export: the 70-column header of a real Nara export, every cell
// quoted, one "Breastfeed" row per feed, and Nara's 69-cell "Profile" footer row.
// test/nara-known-good.csv has the exact structure of a file My Baby imported successfully
// (names, times and ids replaced with made-up ones); the tests compare our output to it byte for byte.

export const NARA_COLUMNS = ["Type","Profile Name","Start Date/time","Start Date/time (Epoch)","Created By Caregiver","Last Updated By Caregiver","Note","Time Zone","[Pump] Duration (Seconds)","[Pump] End Date/time","[Pump] End Date/time (Epoch)","[Pump] Left Volume","[Pump] Left Volume Unit","[Pump] Right Volume","[Pump] Right Volume Unit","[Pump] Total Volume","[Pump] Total Volume Unit","[Baby First] Baby First","[Milestone] Milestone","[Growth] Head Size","[Growth] Head Size Unit","[Growth] Height","[Growth] Height Unit","[Growth] Weight","[Growth] Weight Unit","[Medical] Medication","[Medical] Temperature","[Medical] Temperature Unit","[Sleep] Duration (Seconds)","[Sleep] End Date/time","[Sleep] End Date/time (Epoch)","[Vaccine] Vaccine","[Diaper] Type","[Diaper] Detail","[Diaper] Dirty Color","[Diaper] Dirty Texture","[Breastfeed] Begin Side","[Breastfeed] End Side","[Breastfeed] Left Duration (Seconds)","[Breastfeed] Right Duration (Seconds)","[Routine] Routine","[Solid Feed] Food","[Solid Feed] Meal","[Bottle Feed] Type","[Bottle Feed] Breast Milk Volume","[Bottle Feed] Breast Milk Volume Unit","[Bottle Feed] Formula Name","[Bottle Feed] Formula Volume","[Bottle Feed] Formula Volume Unit","[Bottle Feed] Volume","[Bottle Feed] Volume Unit","[Combo Feed] Begin Side","[Combo Feed] End Side","[Combo Feed] Left Duration (Seconds)","[Combo Feed] Right Duration (Seconds)","[Combo Feed] Type","[Combo Feed] Breast Milk Volume","[Combo Feed] Breast Milk Volume Unit","[Combo Feed] Formula Name","[Combo Feed] Formula Volume","[Combo Feed] Formula Volume Unit","[Combo Feed] Volume","[Combo Feed] Volume Unit","[Profile] Birth Date","[Profile] Birth Date (Adjusted)","[Profile] Sex","[Profile] Type","_familyKey","_profileKey","_activityKey"];

export const NARA_DEFAULTS = {
  profileName: 'Baby',
  caregiver: 'Parent',
  sex: '',
  familyKey: 'garminfam1',
  profileKey: 'garminbaby1',
};

// epoch seconds -> "2026-01-15 07:00:00" in the given IANA zone
export function fmtLocal(epoch, tz) {
  const f = new Intl.DateTimeFormat('en-GB', {
    timeZone: tz, year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23',
  });
  const p = Object.fromEntries(f.formatToParts(new Date(epoch * 1000)).map((x) => [x.type, x.value]));
  return `${p.year}-${p.month}-${p.day} ${p.hour}:${p.minute}:${p.second}`;
}

const quote = (v) => '"' + String(v ?? '').replace(/"/g, '""') + '"';
const line = (cells) => cells.map(quote).join(',');

function row(values) {
  return NARA_COLUMNS.map((c) => values[c] ?? '');
}

// e: { id, first_side:'L'|'R', left_s, right_s, start_ts }
export function naraFeedRow(e, tz, o) {
  const l = Number(e.left_s) | 0;
  const r = Number(e.right_s) | 0;
  const side = (s) => (s === 'L' ? 'LEFT' : 'RIGHT');
  const begin = l > 0 && r > 0 ? side(e.first_side) : (l > 0 ? 'LEFT' : 'RIGHT');
  const end = l > 0 && r > 0 ? (begin === 'LEFT' ? 'RIGHT' : 'LEFT') : begin;
  return row({
    'Type': 'Breastfeed',
    'Profile Name': o.profileName,
    'Start Date/time': fmtLocal(e.start_ts, tz),
    'Start Date/time (Epoch)': String(e.start_ts * 1000),
    'Created By Caregiver': o.caregiver,
    'Last Updated By Caregiver': o.caregiver,
    'Time Zone': tz,
    '[Breastfeed] Begin Side': begin,
    '[Breastfeed] End Side': end,
    '[Breastfeed] Left Duration (Seconds)': String(l),
    '[Breastfeed] Right Duration (Seconds)': String(r),
    '_familyKey': o.familyKey,
    '_profileKey': o.profileKey,
    '_activityKey': 'garmin-' + e.id,
  });
}

export function toCsv(events, tz, opts = {}) {
  const o = { ...NARA_DEFAULTS, ...opts };
  const footer = row({
    'Type': 'Profile', 'Profile Name': o.profileName, '[Profile] Sex': o.sex, '[Profile] Type': 'CHILD',
    '_familyKey': o.familyKey, '_profileKey': o.profileKey,
  }).slice(0, NARA_COLUMNS.length - 1);   // real Nara exports end with a 69-cell Profile row
  return [line(NARA_COLUMNS), ...events.map((e) => line(naraFeedRow(e, tz, o))), line(footer)].join('\n') + '\n';
}
