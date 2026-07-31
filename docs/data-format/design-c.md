# On-disk data format — design C

A clean-sheet format for the sofer stam app. Written without reading the existing implementation.

---

## 1. Principles

Each rule is stated with the failure it exists to prevent.

**P1 — Store choices, never conclusions.**
A field may be stored only if a human or a sensor supplied it. Anything the app worked out is recomputed on every read. *Prevents:* a wrong formula becoming permanent. Both recent miscalculations are fixable only if their inputs survive.

**P2 — When a computation must be stable across a setting change, freeze the *rule*, not the *result*.**
Work is not stamped with a Hebrew date; it is stamped with a reference to the day-boundary rule that was in force. The date is re-derived every time. *Prevents:* the two-headed failure where either (a) changing the boundary setting silently re-files five years of work, or (b) fixing a bug in the Hebrew-date code cannot reach history.

**P3 — Absence is a value.** A key that is missing means "never stated". A key whose value is `null` means "stated, then cleared". Zero means zero. Writers never fill defaults into the file. *Prevents:* "no time recorded" being indistinguishable from "took no time" — the single most damaging confusion in this domain, since most scribes never record time at all.

**P4 — Every reader is a custodian of what it cannot read.** Unknown keys, unknown record types, unknown enum members are carried verbatim through load → edit → save. *Prevents:* the phone → old desktop → phone round trip losing data.

**P5 — Deletion is a fact, not an absence.** Tombstones are written, kept forever, and win every concurrent conflict. *Prevents:* resurrection on merge, and prevents "the record is gone" being confused with "the record was never on this device".

**P6 — Merge is total and deterministic, and never discards.** Any two files merge to the same result regardless of order or direction; the losing side of a genuine conflict is archived inside the record, not dropped. *Prevents:* silent data loss on a two-device workflow with no server and no clock authority.

**P7 — Geometry is data; identity of geometry is a template in code.** A commission stores the parameters the scribe entered plus his explicit deviations. The shape those imply lives in code so that a wrong shape can be corrected retroactively. *Prevents:* both "a new kind of work requires a schema migration" and "the built-in line count was wrong and history is stuck with it".

**P8 — Work is recorded as addresses, not counts.**
"Page 5 lines 31–42" not "12 lines". *Prevents:* rewrites being double-counted as progress. Progress is the size of a *union* of line addresses; totals are a *sum*. Both are computable only if addresses are stored.

**P9 — Human-repairable.** Canonical formatting: UTF-8 without BOM, LF, two-space indent, keys sorted, money as decimal strings, timestamps as ISO-8601 with offset. Integrity hash is advisory and never blocks an import. *Prevents:* a corrupt export being unrecoverable for a user with no network and no support channel.

**P10 — Correctness beats compactness.** Where the two conflict, the verbose option is chosen and the cost is stated in §8.

---

## 2. Entities and fields

### 2.0 Common envelope (every record)

| field | type | opt | meaning | why stored |
|---|---|---|---|---|
| `type` | string | no | record type key (`workEntry`, `commission`, …) | discriminator; lets an old build route unknown types to the preservation bucket |
| `id` | string | no | `<prefix>_<ulid>`, e.g. `we_01J9Q7X2K4M8ZB3TQ7YV` | raw input (generated at creation); ULID is time-sortable, offline-safe, and readable |
| `rev` | object | no | `{lamport:int, at:instant, by:deviceId}` | merge ordering + audit; raw facts of the write event |
| `vc` | object | no | version vector: deviceId → write count for *this record* | causality. Lets merge tell "newer" from "concurrent" without a server |
| `deleted` | bool | yes | present and `true` = tombstone | P5 |
| `provenance` | object | yes | `{op:"split"\|"combine"\|"correct"\|"import", from:[ids], note?}` | when a record is split or combined, the lineage is an input fact, not derivable |
| `_x` | object | yes | preserved unknown keys (see §4) | P4 |
| `_conflicts` | array | yes | archived losing versions (see §3) | P6 |
| `_derived` | object | yes | explicitly-labelled cache, regenerated on every write, never consumed by a build that can recompute it | see §4.4 |

`instant` = `"2026-07-30T22:33:29.004+03:00"` — ISO-8601 with a real offset, plus a sibling `tz` field (`"Asia/Jerusalem"`) on records where the instant is meaningful. **Three facts are needed and all three are stored:** the absolute moment (offset makes it unambiguous), the wall clock the scribe saw (needed to display "he wrote 20:00–22:33" and to apply a fixed-hour boundary), and the zone id (needed if the offset was recorded wrongly, or if zone rules change, or if the scribe travels). *Rejected:* bare UTC (loses the wall clock the user typed); bare local string (ambiguous across DST); epoch integers (unreadable by hand).

`decimal` = string, e.g. `"2400.00"`. *Rejected:* JSON floats (0.1+0.2), and bare minor-unit integers (unreadable, and the minor-unit count of a currency is itself a moving target).

### 2.1 `device`

`id`, `label` ("טלפון"), `firstSeenAt`, `platform`. Purpose: merge tie-breaks are by device id, and a user debugging a merge needs to know which device is `dev_2a10`.

### 2.2 `dayRule` — **immutable**

The single most important design object.

| field | type | opt | meaning |
|---|---|---|---|
| `id` | string | no | `dr_02` — short on purpose; it appears on every timed entry |
| `mode` | enum | no | `midnight` \| `sunset` \| `nightfall` \| `fixedHour` |
| `fixedHour` | string | yes | `"03:00"`, required when `mode=fixedHour` |
| `offsetMinutes` | int | yes | user's shift relative to the computed moment |
| `opinion` | string | yes | e.g. `"tzeis_8.5deg"`, `"tzeis_72min"` — *which halachic opinion*, a user choice, not an implementation detail |
| `place` | object | yes | `{lat, lon, tz, label}` — absent today, present once per-city sunset ships |
| `createdAt` | instant | no | |

Rules are **never edited**. Changing the setting creates a new rule record. There will be a handful in a lifetime; they are never pruned from an export.

**All fields here are raw inputs.** The *computation* (where the sun is, what nightfall means for a given opinion) lives in code and may be corrected at any time, which retroactively fixes every affected day — exactly what P1 demands. The *choice* is frozen by reference, which is what stops a settings change from re-filing history — exactly what P2 demands. This split is the reason no work record contains a Hebrew date.

*Rejected:* copying the rule fields inline into each work entry (drift between copies, 5× the bytes on the hottest record). *Rejected:* storing the resolved Hebrew date (fast, but permanently un-fixable — the exact failure mode requirement 1 names).

### 2.3 `settings` — merge class *per-field*

`currentDayRuleId`, `defaultCurrency`, `dateDisplay` (`hebrew`|`gregorian`|`both`), `weekStart`, `locale`, `workRulesId`. Raw inputs, all optional, none defaulted on disk.

### 2.4 `workRules` — merge class *per-field*

Which Hebrew day-types the scribe does not work: `excludes: ["shabbat","yomtov","erev_pesach_after_chatzot","tisha_bav", …]`, `cholHamoed: "partial"|"none"|"full"`, `dailyTargetLines?`, `typicalHoursPerDay?`.
Used **only for forecasts and targets** — never to file historical work. Forecasts are statements about the future and must follow the current setting, so `workRules` is *not* snapshotted anywhere. This is the deliberate mirror image of `dayRule`.

### 2.5 `commission` — merge class *per-field*

| field | type | opt | meaning / why stored |
|---|---|---|---|
| `id`, envelope | | no | |
| `kindKey` | string | no | `seferTorah` \| `mezuzot` \| `tefillin` \| future |
| `title`, `customer`, `notes` | string | yes | raw |
| `geometry` | object | no | see below |
| `preWritten` | array of segments | yes | work inherited from another scribe, or from before this commission was tracked; raw input, affects progress but not output |
| `pricing` | array of price components | no | see below |
| `materialEstimate` | array of price components | yes | *estimate* per unit, used for quoting only — see §6.5 |
| `acceptedOn` | `when` | yes | |
| `dueBy` | `when` | yes | |
| `status` | enum | yes | `active`\|`paused`\|`done`\|`cancelled` — a declared state, not derived from progress |

**`geometry`** (P7):

```json
"geometry": {
  "template": {"key": "tefillin", "version": 1},
  "params": {"sets": 12},
  "overrides": [
    {"match": {"page": 137}, "lines": 41}
  ]
}
```

`params` are what the scribe typed (`pages: 245`, `linesPerPage: 42`, `count: 40`, `sets: 12`). `overrides` are explicit deviations he entered (a page that really has 41 lines). Code resolves template + params into a **level model**:

```
levels:  ordered list, each either {key, kind:"count", n} or {key, kind:"enum", members:[…]}
lines:   ordered rules  [{match: {partial address}, lines: n}]  — most specific wins
```

- Sefer Torah: levels `[{page, count 245}]`, lines `[{match:{}, lines:42}]`.
- Mezuzot: levels `[{mezuza, count N}]`, lines `[{match:{}, lines:22}]`.
- Tefillin: levels `[{set, count N}, {piece, enum [head,hand]}, {parshiya, enum [kadesh, vehaya_ki_yeviacha, shema, vehaya_im_shamoa]}]`, lines `[{match:{piece:"head"}, lines:4}, {match:{piece:"hand"}, lines:7}]`.
- Escape hatch for kinds with no line geometry at all: `template.key = "freeform"`, `params: {units: N, unitLabel: "…"}`, lines rule absent → the unit itself is the countable thing and line-based figures are reported as unavailable rather than as zero.

The **canonical order** of the address space is lexicographic over `levels` in declared order, enum levels in declared member order. This is what makes a range like "set 1 head kadesh … set 3 hand vehaya_im" expandable, and it is derivable from geometry alone, so it never needs storing.

**`pricing`** — an array so that models compose and new models are additive:

```json
"pricing": [
  {"model": "perUnit", "level": "page", "amount": {"cur": "ILS", "amt": "620.00"}}
]
```
Other models: `{"model":"fixedTotal", …}`, `{"model":"perLine", …}`, `{"model":"perUnit","level":"set", …}`. An old build that meets an unknown `model` marks the commission's money figures unavailable (never zero) and preserves the component untouched.

### 2.6 `when` — the dating union (used by work entries and expenses)

Exactly one `kind`. This union is where "absent vs zero" is won or lost.

```
{"kind": "undated"}                                        backlog
{"kind": "day",   "hebrew": {"y":5786,"m":"av","d":16}}    user picked a Hebrew day
{"kind": "day",   "civil":  "2026-07-28"}                  user picked a Gregorian day
{"kind": "span",  "from": instant, "to": instant,
                  "tz": "…", "dayRuleId": "dr_02",
                  "breaks": [{"from": instant, "to": instant}]}
{"kind": "timed", "tz": "…", "dayRuleId": "dr_02",
                  "timer": [ …events… ]}
```

- **`day` stores whichever calendar the user actually chose.** A Hebrew date typed by a scribe is a raw input, not a conversion; the Gregorian equivalent is derived. Store the other one and you have stored a conclusion. Hebrew months are **string keys** (`"av"`, `"adar_i"`, `"adar_ii"`) — numeric Hebrew months are a leap-year trap that silently shifts dates by a month in seven years out of nineteen.
- `day` and `undated` carry **no** `dayRuleId`, because no boundary computation is involved: the scribe named the day.
- `dayRuleId` is required on `span` and `timed`, because there the day must be derived from an instant.

**`timer` — a raw event list, not a duration:**

```json
{"e": "start"|"pause"|"resume"|"stop", "t": instant, "m": monotonicMs}
```

`m` is the device's monotonic clock reading — an independent instrument, immune to the wall clock jumping (NTP correction, manual change, DST). Duration is computed from `m` when both endpoints have it, from `t` otherwise. The event list also survives crashes, double-pauses, and a stop that never arrived; the algorithm has a defined rule for each (§6.1) and can be corrected later.

*Rejected:* storing `durationSeconds` and `pausedSeconds`. They are conclusions; a bug in pause handling would be unrecoverable, and they cannot express "the app died mid-sitting".

### 2.7 `workEntry` — merge class *atomic*

| field | type | opt | meaning / why stored |
|---|---|---|---|
| `commissionId` | id | no | |
| `when` | union | no | §2.6 |
| `segments` | array | no | ≥1, see below |
| `lineMarks` | array | yes | live per-line tracking: `{"unit":{…}, "line":31, "t":instant, "m":monotonicMs}` — the instant each line *finished*. Raw observations; per-line durations are derived from consecutive marks |
| `groupId` | string | yes | ties together the several stretches entered in one evening sitting-down, so they can be reviewed or undone as a unit |
| `note` | string | yes | |
| `enteredAt` | instant | no | when the record was created, as distinct from when the work happened. Needed to audit "typed in afterwards", and to explain a suspicious backdate |
| `enteredBy` | deviceId | no | |
| `mood`/`quality` | — | — | *not modelled*; if added later it is an additive optional field |

**`segment`:**

```json
{
  "n": 1,
  "unitFrom": {"page": 5},  "lineFrom": 31,
  "unitTo":   {"page": 7},  "lineTo": 12,
  "varyLevels": ["set","parshiya"],
  "whole": true,
  "purpose": "write" | "rewrite" | "repair" | "check",
  "weight": "1.0"
}
```

- A segment is one **contiguous run** in canonical order, from `unitFrom`/`lineFrom` to `unitTo`/`lineTo` inclusive, 1-based (there is no line 0 and no page 0; a zero on screen is a bug).
- `unitTo` absent ⇒ same unit as `unitFrom`. `whole: true` ⇒ all lines of every unit in the run; `lineFrom`/`lineTo` must then be absent.
- `varyLevels` (optional, default: all levels) restricts which address levels may change across the run. `varyLevels: ["set"]` with `unitFrom {set:1, piece:"head"}` and `unitTo {set:3, piece:"head"}` expresses **"heads only, sets 1–3"** — which is not a contiguous range in canonical order and would otherwise need three segments.
- Several segments per entry cover the discontinuous case (a correction on page 3 during a sitting spent on page 7).
- `purpose` absent means *not stated*; the algorithm treats not-stated as `write` but the raw absence is preserved, so a future UI that asks the question can tell "he said write" from "he was never asked".
- `weight` (optional decimal) is an explicit user statement of how the sitting's time divided across segments, overriding proportional attribution. It is an input (the scribe saying "most of it went on the correction"), not a computed share.

**No line counts, no durations, no per-segment minutes are stored anywhere on a work entry.**

### 2.8 `expense` — merge class *atomic*

| field | type | opt | meaning |
|---|---|---|---|
| `label` | string | no | what was bought |
| `amount` | money | no | `{"cur":"ILS","amt":"2400.00"}` |
| `paidOn` | `when` | yes | absent = date unknown; the allocation mode then must not be time-based |
| `allocation` | union | no | below |
| `quantity` | object | yes | `{n: 30, unitLabel: "יריעות"}` — raw, enables "what did a sheet cost" |
| `note` | string | yes | |

Allocation modes:
```json
{"mode": "commissions", "commissionIds": ["cm_a","cm_b"], "split": "even"}
{"mode": "period", "from": when, "to": when, "spread": "perWorkingDay"}
{"mode": "month", "calendar": "hebrew" | "gregorian", "month": {…}}
```
`split` and `spread` are named explicitly rather than implied, so that adding `split: "byLinesWritten"` later does not change what existing records meant. `calendar` on `month` is **mandatory and undefaulted**: the brief says all calendar reasoning is Hebrew, but bookkeeping months are usually Gregorian — the ambiguity is resolved per record, in data, instead of by a code default that would be impossible to revisit. No computed share is ever stored.

### 2.9 `quote` — merge class *atomic*

Inputs to a price quote for a job not yet accepted: `kindKey`, `geometry` (same shape as a commission's), `assumedPricing`, `assumedMaterial`, `paceSource` (`{mode:"myAverage", window:"lastNDays", n:90}` or `{mode:"stated", linesPerHour:"…"}`), `quotedOn`, `validUntil`, `acceptedAsCommissionId?`. The quoted number itself is derived and never stored — a quote reprinted after a pricing fix must show the corrected figure, or the fix was pointless.

---

## 3. Identity, time and merging

### 3.1 Identity
`<typePrefix>_<ULID>`; ULID is generated locally with millisecond time + randomness, so two offline devices never collide. Ids are never reused, never recycled after deletion. Hand-repair note: the prefix means a dangling reference is diagnosable by eye.

### 3.2 Clocks
- `rev.lamport` — a true Lamport counter per device: on any write, `lamport = (max lamport ever seen) + 1`; on import, absorb the maximum. Gives a total order that respects causality.
- `rev.at` — the device's wall clock, honestly recorded, used only for display and as a tie-break. It is not trusted.
- `vc` — a per-record version vector, deviceId → count of writes that device has made to that record. This is what distinguishes "newer" from "concurrent" with no server.

Two devices, a few thousand records: a `vc` is two integers, ~40 bytes.

### 3.3 Merge (deterministic, order-independent)

For each `id` present in either file:

1. Only one side has it → take it.
2. `A.vc` dominates `B.vc` (≥ on every device, > somewhere) → **A wins, B discarded.** This is ordinary supersession and must not be flagged.
3. `B` dominates → symmetric.
4. **Concurrent.** Then:
   - a. If either side is a tombstone, **the tombstone wins** — unconditionally. Delete is monotone; this is what makes "a record never comes back from the dead" an absolute guarantee rather than a probable one. The surviving edit is archived, so an accidental delete is undone by un-deleting, not by data archaeology.
   - b. Merge class **per-field** (`commission`, `settings`, `workRules`): three-way merge against the stored merge base (§3.4). Field changed on one side only → take it. Changed on both to different values → deterministic winner, loser archived.
   - c. Merge class **atomic** (`workEntry`, `expense`, `quote`, `dayRule`): whole-record deterministic winner, loser archived. A work entry is one assertion; splicing a start time from one device onto an extent from another produces a record no one ever wrote.
   - Deterministic winner = highest `rev.lamport`, then latest `rev.at`, then lexicographically greatest `rev.by`. Total, and identical on both devices.
5. The result's `vc` is the pointwise maximum of the inputs, so the conflict is not re-detected on the next sync.

Archiving: `_conflicts: [{rev, vc, payload:{…the losing record verbatim…}}]`. Never pruned (P6). The UI surfaces a badge; the user can promote an archived version, which is an ordinary new write.

*Rejected:* per-field CRDT registers everywhere (a `rev` per field triples record size and still cannot merge two different `segments` arrays sensibly). *Rejected:* an operation log / full event sourcing (a genuinely elegant fit for requirement 1, but it makes hand repair impossible — you cannot fix a scribe's typo by editing an append-only log with a text editor — and it grows without bound; the record store plus lineage in `provenance` recovers most of the benefit). *Rejected:* tombstone GC after N days (needs a clock authority, which does not exist here; the storage saved is a few kilobytes).

### 3.4 Merge base
For per-field classes only, the device keeps the last-merged version under a parallel key. ~50 records; the storage is noise and it turns a guess into an exact three-way merge.

### 3.5 Storage layout
Key-value store, **one key per record**: `sofer/v1/rec/<type>/<id>`, plus `sofer/v1/meta`, `sofer/v1/device`, `sofer/v1/base/<type>/<id>`. Loading scans keys (a few thousand — trivial). No stored index: an index is a derived structure that can drift out of step with the data it indexes, and rebuilding it at load costs milliseconds.
*Rejected:* one JSON blob per store — every edit rewrites the entire dataset (§8).

The **backup file** is a single JSON document (§4.1) — one file, as the deployment demands.

---

## 4. Versioning and unknown data

### 4.1 File header

```json
{
  "format": "sofer-stam/data",
  "formatVersion": {"major": 1, "minor": 4},
  "minReaderMajor": 1,
  "generator": {"app": "sofer", "build": "2026.7.3+188", "device": "dev_phone_7f21"},
  "exportedAt": "2026-07-31T09:12:44.101+03:00",
  "integrity": {"sha256": "9f2c…", "advisory": true},
  "records": { "device": [], "dayRule": [], "settings": [], "workRules": [],
               "commission": [], "workEntry": [], "expense": [], "quote": [] },
  "_unknownTypes": {}
}
```

- **Minor bump = additive only.** New optional fields, new record types, new enum members, new templates. Any build may read and write the file.
- **Major bump = a construct older builds cannot process safely.** They may read it (preserving everything) but must open read-only and say so.
- `integrity.advisory: true` means a mismatch produces a warning, never a refusal. A user who hand-edited a file to rescue it must still be able to import it (P9).

### 4.2 What an older build does, exactly

1. **Unknown key inside a known record** → moved into that record's `_x` map, held in memory, re-emitted verbatim on every write of that record. The `_x` bag is at *record* granularity, which is the same granularity as the merge unit — so a record that an old build edits carries its unknowns forward under the winning version. For per-field merge, the whole `_x` bag counts as one field.
2. **Unknown record type** → stored under `_unknownTypes[typeName]` as raw JSON, merged by `id`/`rev`/`vc` alone (the envelope is stable across all versions and is the reason the envelope is defined once), re-exported unchanged.
3. **Unknown enum member** (`purpose: "tikkun_sofrim"`, `mode: "someNewBoundary"`) → the record is *displayed* but excluded from the specific computation that needed that enum, and the affected figure is reported as **unavailable, never as zero**. Silence beats a wrong number.
4. **Unknown geometry template** → the commission is opaque: shown by title, progress and line figures unavailable, record preserved intact.
5. **`minReader` on a record** (optional int) → a record may declare "a build older than format major N must treat me as opaque". This is the escape valve for a future construct that would be actively misread rather than merely not understood.
6. An old build must **never** rewrite a record it holds opaquely, except to merge it — and merging opaque records needs only the envelope.

The enabling mechanism is a discipline in the Dart layer: every model class round-trips an `unknown` map, and there is a **mandatory property test** — take a real file, inject junk keys at every level, load, edit one unrelated field, save, and assert every injected key is byte-identical. Without that test in CI, requirement 2 decays within three releases.

### 4.3 Forward migration
Migrations are pure, ordered, idempotent functions `1.3→1.4`, `1.4→1.5`, applied in sequence on load, never on import-in-place of a foreign file (import merges first at the record level, then migrates). The file records `"migrations": [{"from":"1.3","to":"1.4","at":…,"by":…}]`.
**No migration may lose information.** Where a migration reinterprets a field, the original is moved to `legacy: {"1.3": {…}}` on that record rather than dropped. This is the only place the format tolerates redundancy, and it is bounded by how often a lossy reinterpretation actually happens (rarely).

### 4.4 The `_derived` namespace
A record may carry `_derived: {…}` — for example a resolved geometry for a commission whose template a foreign build may not know. Rules, enforced by convention and by the round-trip test: it is **discarded and regenerated on every write**; it is **never read by a build that can recompute the value**; it is never an argument to arithmetic that a capable build performs. It exists so an older or foreign build can still show something useful, and it is namespaced so nobody can mistake it for input. This is the one deliberate exception to P1, and it is safe only because of the "never consumed when recomputable" rule.

---

## 5. Worked examples

### (a) A measured 2-hour sitting crossing pages 5, 6 and 7

```json
{
  "type": "workEntry",
  "id": "we_01J9Q7X2K4M8ZB3TQ7YV",
  "rev": {"lamport": 118, "at": "2026-07-30T22:33:41.880+03:00", "by": "dev_phone_7f21"},
  "vc": {"dev_phone_7f21": 1},
  "commissionId": "cm_01J8A0R3P9V2WQKD5N",
  "when": {
    "kind": "timed",
    "tz": "Asia/Jerusalem",
    "dayRuleId": "dr_02",
    "timer": [
      {"e": "start",  "t": "2026-07-30T20:02:11.000+03:00", "m": 4192},
      {"e": "pause",  "t": "2026-07-30T20:47:03.000+03:00", "m": 2695092},
      {"e": "resume", "t": "2026-07-30T21:02:40.000+03:00", "m": 3632110},
      {"e": "stop",   "t": "2026-07-30T22:33:29.000+03:00", "m": 9081402}
    ]
  },
  "segments": [
    {"n": 1,
     "unitFrom": {"page": 5}, "lineFrom": 31,
     "unitTo":   {"page": 7}, "lineTo": 12,
     "purpose": "write"}
  ],
  "enteredAt": "2026-07-30T22:33:41.880+03:00",
  "enteredBy": "dev_phone_7f21"
}
```

Nothing here is a conclusion. Elapsed (9081402 − 4192 = 9 077 210 ms = 2h 31m 17s), break (3632110 − 2695092 = 937 018 ms = 15m 37s), writing time (8 140 192 ms = 2h 15m 40s), 66 lines (12 + 42 + 12), the Hebrew day, and lines-per-hour are all derived at read time. `dr_02` is what makes the day stable if the scribe later switches from midnight to nightfall.

### (b) Typed in, date but no hours, 3 mezuzot

```json
{
  "type": "workEntry",
  "id": "we_01J9QA1B7C3D5E7F9G",
  "rev": {"lamport": 119, "at": "2026-07-31T21:14:02.310+03:00", "by": "dev_desk_2a10"},
  "vc": {"dev_desk_2a10": 1},
  "commissionId": "cm_01J8B2M4K6P8R0T2V4",
  "when": {"kind": "day", "hebrew": {"y": 5786, "m": "av", "d": 16}},
  "segments": [
    {"n": 1, "unitFrom": {"mezuza": 5}, "unitTo": {"mezuza": 7}, "whole": true}
  ],
  "groupId": "grp_01J9QA1B7C",
  "enteredAt": "2026-07-31T21:14:02.310+03:00",
  "enteredBy": "dev_desk_2a10"
}
```

No `timer`, no `span`, no duration key of any kind: time was not given. Compare a genuinely zero-length measured sitting, which would carry a `timer` whose `start` and `stop` share a monotonic reading. No `dayRuleId`: he named the day himself, so no boundary rule participates. `groupId` links the other stretches he typed in the same evening.

### (c) Backlog, no date

```json
{
  "type": "workEntry",
  "id": "we_01J9QB0N2M4L6K8J0H",
  "rev": {"lamport": 120, "at": "2026-07-31T21:19:44.002+03:00", "by": "dev_desk_2a10"},
  "vc": {"dev_desk_2a10": 1},
  "commissionId": "cm_01J8A0R3P9V2WQKD5N",
  "when": {"kind": "undated"},
  "segments": [
    {"n": 1, "unitFrom": {"page": 1}, "unitTo": {"page": 4}, "whole": true}
  ],
  "note": "נכתב לפני שהתחלתי לרשום",
  "enteredAt": "2026-07-31T21:19:44.002+03:00",
  "enteredBy": "dev_desk_2a10"
}
```

`kind: "undated"` is a positive assertion, distinct from a missing `when` (which is invalid and would be flagged for repair). Every earnings, average and daily-target computation filters on `when.kind != "undated"`; output and progress do not.

### (d) Expense split across two commissions

```json
{
  "type": "expense",
  "id": "ex_01J9QB3M5N7P9R1S3T",
  "rev": {"lamport": 121, "at": "2026-07-31T21:26:10.775+03:00", "by": "dev_desk_2a10"},
  "vc": {"dev_desk_2a10": 1},
  "label": "קלף — 30 יריעות",
  "amount": {"cur": "ILS", "amt": "2400.00"},
  "quantity": {"n": 30, "unitLabel": "יריעה"},
  "paidOn": {"kind": "day", "civil": "2026-07-12"},
  "allocation": {
    "mode": "commissions",
    "commissionIds": ["cm_01J8A0R3P9V2WQKD5N", "cm_01J8B2M4K6P8R0T2V4"],
    "split": "even"
  }
}
```

`"1200.00"` per commission is never written down. If "even" is later found to be the wrong default for a case, or a `byLinesWritten` split is added, every historical expense re-splits correctly because only the instruction was stored.

---

## 6. The re-derivation algorithm

Notation: `G(c)` = resolved geometry of commission `c`; `E(c)` = its non-deleted work entries.

### 6.1 Writing duration of an entry — `dur(e)`

- `when.kind ∈ {undated, day}` → **absent** (not zero). Every consumer must handle absent by exclusion.
- `kind = span` → `(to − from) − Σ(break.to − break.from)`. A break with `to` absent is closed at `to` of the span and the entry is flagged `incomplete`.
- `kind = timed` → walk `timer` in order; accumulate every `start→pause`, `resume→pause`, `start→stop`, `resume→stop` interval. Use `m₂ − m₁` when both endpoints carry `m`; otherwise `t₂ − t₁`. A trailing `start`/`resume` with no `stop` (crash) is closed at the last event's timestamp and the entry is flagged `incomplete`; the flag is derived, so the closing rule can be changed later.
- Negative or absurd results (clock jumped backwards, `m` missing on one side) → the interval is dropped and the entry flagged, never silently clamped to zero.

### 6.2 Expanding work — `expand(seg, G)`

Enumerate leaf unit addresses in canonical order from `unitFrom` to `unitTo`, holding fixed every level not in `varyLevels`. For each unit, take `lines(unit)` from the geometry's line rules (most specific match wins, then `overrides`). Then clip: on the first unit start at `lineFrom` (default 1), on the last stop at `lineTo` (default `lines(unit)`), all units in between whole. `whole: true` overrides the clipping. Result: an ordered list of `(unitAddress, lineNo)` pairs.

Two aggregates, always distinguished:
- `linesWritten(X) = Σ_{e∈X} Σ_{s∈e.segments} |expand(s)|` — with multiplicity. A rewritten line counts again, because it consumed effort.
- `linesCovered(c) = | ⋃_{e∈E(c)} ⋃_{s} expand(s) |` — a set union, plus `preWritten`. A rewritten line counts once, because it is one line of a scroll.

### 6.3 Filing to a day — `day(e)`

- `kind = day` → the stated day (converted if the user displays the other calendar).
- `kind = undated` → no day; excluded from every per-day figure.
- `kind ∈ {span, timed}` → take the entry's first writing instant, look up `dayRule[e.when.dayRuleId]`, compute the boundary moment for the civil date of that instant in `e.when.tz` (or `rule.place` if present), and file to the Hebrew day that instant falls in under that rule. All of this is code, all of it re-runnable.
- **Crossing a boundary.** The record is never split. For per-day reporting, the writing intervals from §6.1 are clipped at the boundary moment and each day receives its share of time; lines follow `lineMarks` exactly if present, otherwise pro rata by clipped time. Both views are derived, so a change of opinion costs nothing.

### 6.4 Attributing one stretch of time across several records — the delicate case

An entry has one duration `D` and segments `s₁…s_k`.

1. **If `lineMarks` are present**, per-line duration is exact: line *i*'s duration is `mark_i − mark_{i−1}` (monotonic `m` preferred), the first line measured from the first `start`. Time in a break interval is subtracted before the difference. A segment's time is the sum over its lines. Any line not covered by a mark falls back to step 2 for the residual time.
2. **Else if any segment carries `weight`**, split `D` in proportion to weights: `Dᵢ = D × wᵢ / Σw`.
3. **Else** split in proportion to line count: `Dᵢ = D × |expand(sᵢ)| / Σ|expand(s)|`.
4. Splitting further, to a single page or a single day, applies the same proportional rule to the clipped sub-extent.

This ladder is **code, not data**. If the proportional rule is later judged wrong (say, a `rewrite` segment should be weighted differently), the new rule applies to all history immediately — precisely because no `Dᵢ` was ever written down. The only stored input in the ladder is the optional `weight`, because that is the scribe's own statement.

### 6.5 Money

- `earned(c) = Σ over pricing components`:
  - `perUnit(level L)` → `amount × completedUnits_L`, where `completedUnits_L = Σ_{u at level L} coveredLines(u)/lines(u)` — a half-written page earns half. *Rejected:* recognising only whole units; it makes profit-per-hour lurch and makes an in-progress sefer look unprofitable for a week at a time.
  - `perLine` → `amount × linesCovered(c)`.
  - `fixedTotal` → `amount × progress(c)`.
- `spent(c) = Σ` of each expense's share attributed to `c`:
  - `mode: commissions` → `amount / |commissionIds|` (for `split: "even"`).
  - `mode: period` → `amount × (working days of the period that fall inside the report range and on which `c` was worked) / (all working days of the period)`; working days per current `workRules`.
  - `mode: month` → the month's total distributed over the commissions worked in that month, pro rata by `linesWritten`.
- `profit(c) = earned(c) − spent(c)`. **`materialEstimate` never enters realised profit** — it is a quoting input. The report "what materials really cost per unit" is `spent(c) / completedUnits`, and its whole point is to be compared against `materialEstimate`. Using the estimate in profit would make that comparison circular. *(This resolves an ambiguity in the brief; it is resolved in code, not frozen into data, so it is revisable.)*
- `hours(range) = Σ dur(e)` over entries with a duration. `profitPerHour = profit(range) / hours(range)`, reported alongside **`coverage = linesWritten(entries with time) / linesWritten(all non-backlog)`**. For a scribe who times one sitting in five, an unqualified ₪/hour is a fiction; the coverage figure is what makes it honest.
- Backlog (`kind: undated`) is excluded from `earned`, `spent`, averages and targets, and included in `linesCovered` and totals.

### 6.6 Progress and remaining

`totalLines(c) = Σ_{leaf u ∈ G(c)} lines(u)`; `progress(c) = linesCovered(c) / totalLines(c)`; `remaining(c) = totalLines(c) − linesCovered(c)`. Because `linesCovered` is a union, a scribe who rewrote thirty lines does not show 101%. Percentage is never stored.

### 6.7 Output per working day

For a Hebrew-day range `R`: `workingDays(R)` = Hebrew days in `R` minus those excluded by current `workRules` (Shabbat, yamim tovim, the excluded fasts, erev Pesach after chatzot, chol hamoed per setting). `outputPerWorkingDay = linesWritten(entries with day(e) ∈ R) / |workingDays(R)|`. Days on which he did work but which the rules call non-working still count in the numerator and are added to the denominator, so a Shabbat entry cannot inflate the average.

### 6.8 Average time per line

`avgTimePerLine = Σ dur(e) over entries with a duration / linesWritten(those same entries)`. Entries without time are excluded from **both** sides. Reported per `purpose` as well, since a rewrite line and a fresh line are not the same work.

### 6.9 Projected completion

1. `pace` = `linesCovered` gained per working day over a trailing window (default: the last 90 Hebrew days containing any non-backlog entry). Use *covered*, not *written*, so a week of corrections does not project a finish date the scroll cannot reach.
2. `daysNeeded = ceil(remaining(c) / pace)`.
3. Walk the Hebrew calendar forward from today, skipping days excluded by current `workRules`, until `daysNeeded` working days have passed. That date is the projection.
4. If `pace` is unknown (no timed or dated work yet) the projection is **unavailable**, not infinite and not today.

### 6.10 Quote

Expand the quote's geometry to `totalLines`, price it with `assumedPricing`, subtract `assumedMaterial`, and estimate elapsed working days from `paceSource` against the Hebrew working-day calendar. Every number recomputed from stored inputs on every view.

---

## 7. What this survives

**Absorbed without touching existing data:**

- New kinds of work (megillot, ketubot, anything) — a new template key plus `params`; old builds preserve them opaquely.
- New geometry within a kind — a sefer with variable lines per page (`overrides`), a tefillin variant with different parshiya lengths (a new line rule), a kind with four address levels.
- A kind with no line geometry at all — the `freeform` template.
- Per-city sunset for scribes abroad — new `dayRule` records with `place`; old records keep pointing at their old rule and do not move.
- The scribe changing his day boundary — new rule record, history untouched, future work filed the new way.
- A bug found in Hebrew-date conversion, in nightfall computation, in line counting, in time attribution, in revenue recognition, in expense spreading — all pure code, all retroactive on the next launch.
- Recording time later where none was recorded before, or adding per-line tracking to a device that lacked it — additive fields on existing records.
- Splitting one entry into two, or combining several — tombstone plus new records carrying `provenance.from`, so the lineage stays inspectable.
- New price models, new expense allocation modes, new currencies, multi-currency commissions.
- New settings — additive records; old builds carry them through untouched.
- A third device; a future sync server (records already carry ids, Lamport stamps and version vectors); a second scribe sharing a workshop (add an `authorId`).

**Not absorbed cleanly — stated honestly:**

- **Concurrent edits to the same work entry lose one side to `_conflicts`.** Nothing is destroyed and the UI can offer both, but a truly automatic field-level merge of a segments array is not attempted, because the merged result would be a record no human wrote.
- **No clock authority means "last writer" can be the wrong writer.** When Lamport counters tie (two devices that have never merged), the tie-break falls to wall clocks that may be skewed. The conflict archive is the mitigation; there is no fix without a server.
- **An old build cannot compute anything for a geometry template it does not know.** It preserves the commission perfectly, and `_derived` may give it enough to show a total, but its progress figures for that commission are unavailable. The alternative — putting the full resolved geometry in the file as input — would have made a wrong built-in line count permanent, which is worse.
- **Correcting a commission's `params` retroactively rewrites all its history.** That is intended, but it means a percentage the scribe screenshotted last year may not reproduce. There is no stored history of parameter values; adding one would be a straightforward additive change if it ever matters.
- **Duplicate ids from hand editing** would be merged as one record. ULIDs make accidental collision essentially impossible; a careless copy-paste during hand repair is the real risk, and it is not detectable.
- **Volumes far beyond the brief** (hundreds of thousands of entries) would outgrow a scan-all-keys load and an in-memory union of line addresses. At that point an index and a coverage bitmap per commission become necessary — both derived, both addable, neither changing the file.
- **`_derived` is a discipline, not an enforcement.** If a future developer reads a cached value in arithmetic, P1 is quietly broken. The round-trip and re-derivation tests are the only guard.

---

## 8. Cost

**Storage.** A measured work entry with four timer events pretty-printed is ~700 bytes; a typed entry ~330; an expense ~380. Two thousand entries plus a hundred other records ≈ **1.0–1.3 MB**, plus tombstones (~200 bytes each, never pruned) and the merge base for the few dozen per-field records. A live-tracked sitting with 60 `lineMarks` adds ~4 KB, so a scribe who tracks every line for years might reach 8–10 MB. All of it is fine for a phone, and all of it compresses ~8:1 if an export ever needs it. Compact alternatives — integer timestamps, elided keys, per-record duration totals — would save perhaps 45%, and each of them costs either readability or recoverability. Not taken (P10).

**Write amplification.** One key per record means an edit writes ~0.7 KB, not the whole dataset. Against the single-blob alternative at ~1.2 MB per keystroke-triggered save, that is roughly a 1,700× reduction — the difference between a responsive form and a phone that heats up. The backup file is written whole, but only on explicit export.

**Read cost.** Nothing is precomputed, so every screen re-derives. The heavy items are geometry expansion and the coverage union: a full sefer is 245 × 42 = 10,290 line addresses, which is a set of ten thousand small tuples — a few milliseconds in Dart, and only for the commission on screen. Mitigate in RAM with a memo keyed by the highest Lamport stamp seen for that commission; invalidate on any write. **Never persist the memo.**

**Complexity — where the real cost sits.**
1. *The unknown-field discipline.* Every model class must carry and re-emit an `_x` bag. This is a permanent tax on every future field and is best paid with a shared base class plus code generation, guarded by the injected-junk round-trip test. Skipping it silently breaks requirement 2.
2. *Geometry resolution and address expansion.* One module, perhaps 300 lines, that everything else depends on. It must be exhaustively tested per template, because a single off-by-one in canonical ordering corrupts every downstream figure.
3. *The Hebrew calendar and the boundary rules.* Substantial, but unavoidable in this domain and cleanly isolated behind `day(e)`.
4. *Merge.* Version vectors plus a three-way merge for two entity classes and an archive for the rest — perhaps 200 lines, but it needs property tests asserting commutativity, idempotence and no-resurrection over randomly generated edit histories.
5. *Discipline in review.* The one rule that must be enforced by humans forever: **if a reviewer can compute a field from the other fields, it does not belong in the file.**
