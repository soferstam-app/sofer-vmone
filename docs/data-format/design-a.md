# On-disk data format — sofer stam work tracker (Design A)

Clean-sheet design. Written without reading the existing implementation.

Format name: `sofer.stam.data`. Encoding: UTF-8, no BOM, LF line endings, pretty-printed
with 2-space indent and keys emitted in a fixed canonical order. Non-ASCII is emitted raw
(`"כתב יד"`, never `"כ..."`) so a human can repair the file in any editor.

---

## 1. Principles

Each rule is stated with the failure it prevents.

**P1 — Only facts are stored. Every number the app shows is recomputed from facts.**
No total, average, percentage, profit, day-index, elapsed-time or attributed-share is ever
written to disk. *Prevents:* a wrong calculation baking itself into history. When a formula is
fixed, the fix applies to all data ever recorded, because all of its inputs are still there.

**P2 — Store the observation, not the reduction of the observation.**
Store timer start/stop moments and pause intervals, not "activeMs". Store line-advance marks,
not "line 7 took 4m12s". Store the attribution *rule*, not the attributed minutes.
*Prevents:* discovering that pauses were counted wrongly and having no way back.

**P3 — Pin what classifies a record; do not pin what interprets an aggregate.**
The day-boundary rule in force when work was recorded *classifies that work*, so the record
pins it (by reference). The working-day calendar profile ("do I write on chol hamoed?") only
*interprets aggregates*, so it is global and current. *Prevents:* both silent re-filing of past
work (requirement: work must not move between days) and frozen, unfixable history.

**P4 — Pin by reference, never by copy.**
A record points at `dayRuleId: "dr_…"`; the rule's parameters live once, in their own document.
*Prevents:* a bug in the sunset algorithm becoming unfixable because every record carries a
frozen answer. Fixing the algorithm re-derives ten years of days correctly, and no record moves
to a different *rule*.

**P5 — Absent, null, zero and empty are four different things.**
Key missing = never stated. Key present with `null` = explicitly cleared by a user (needed so a
clear can beat a stale value in a merge). `0` = a measured or entered zero. `[]` = known to be
empty. *Prevents:* "no time recorded" being averaged in as zero, forever.

**P6 — Every object is open. A reader preserves what it does not understand, byte-for-byte,
attached to the object it was found on.** *Prevents:* phone → old desktop → phone losing the
fields the desktop never heard of.

**P7 — Unknown means unknown. Never coerce to a default.**
An unrecognised `kind`, `nature` or enum value quarantines the record out of aggregates and is
reported on screen as "N records this build does not understand". *Prevents:* a silently wrong
total, which is worse than a visibly incomplete one.

**P8 — Merge is a pure function of state, not of order.**
Documents form a last-writer-wins map keyed by id, with per-field hybrid-logical clocks. Merge
is commutative, associative and idempotent. *Prevents:* "import twice, get different answers",
and any merge dialog the user could get wrong.

**P9 — A losing value is never destroyed.** When LWW discards a value, the discarded value is
appended to a `conflicts` collection. *Prevents:* the one case where P1 would otherwise fail —
a merge silently eating a user's input.

**P10 — Deletion is a tombstone that outlives the payload's usefulness, and it is never
garbage-collected.** *Prevents:* resurrection when a stale device syncs.

**P11 — Import merges. It never replaces.** Replacing is a separate, differently-worded,
confirmed action. *Prevents:* the classic "restored backup, lost this week".

**P12 — Money is integer minor units; durations are integer milliseconds; there are no floats
on disk.** *Prevents:* 0.1 + 0.2 in a profit report.

**P13 — Counting starts at 1.** Pages, lines, mezuzot and sets are 1-based, inclusive ranges.
There is no page 0 and no line 0; a zero index in a file is a corruption, not a value.

**P14 — Migrations are deterministic functions of the input file, and additive only.**
Two devices migrating the same v2 file independently must produce byte-identical v3 files. A
migration may add fields and documents; it may never delete or rewrite a raw input.
*Prevents:* migration itself becoming an unmergeable divergence.

### Rejected alternatives (design-level)

| Rejected | Why |
|---|---|
| SQLite with normalised tables | Not repairable by hand, schema migrations are destructive, merging two databases needs the same machinery anyway. A SQLite *index* built from the JSON is fine — see §8. |
| Append-only event log / operation CRDT | Solves more than the problem has. One human on two devices does not need concurrent-text CRDTs, and a log is much harder to hand-repair. LWW over immutable inputs gives the same recoverability. |
| Storing computed totals for speed | Requirement 1. Caches live in RAM (§8). |
| Storing the resolved Hebrew day on each record | It is a derived value stored as an input — exactly the failure that already happened twice. Replaced by P3/P4. |
| Snapshotting the price onto each work record | Same reason. Replaced by a versioned price schedule. |
| Whole-record LWW | Two devices editing different fields of the same commission would lose one edit. |
| Arrays for collections | Merging arrays is ambiguous and duplicates ids. Collections are objects keyed by id. |
| Protobuf / MessagePack / CBOR | Not human-readable. Ruled out by the repair-by-hand requirement. |

---

## 2. The entities and their fields

### 2.0 Conventions

- **Reserved keys** begin with `_`. Domain fields never do.
- **Ids**: `<prefix>_<ULID>` — ULID is 26 chars of Crockford base32, so ids sort by creation
  time and are readable. Prefixes: `cm_` commission, `rc_` recording, `wk_` work,
  `ex_` expense, `dr_` day rule, `cp_` calendar profile, `kd_` kind template,
  `sv_` structure version, `pv_` price version, `cf_` conflict.
  *Rejected:* integers (collide across devices), UUIDv4 (unsortable, harder to eyeball).
- **Clock** (`_clock`): a hybrid logical clock as a string `"<13-digit ms>-<4-digit counter>-<deviceId>"`,
  e.g. `"1785391200123-0000-d7QK3M8V"`. Fixed widths make plain string comparison a total order
  (valid until year 2286 — stated assumption). On write: `ms = max(now, lastSeenMs)`;
  counter increments on tie, else resets. On merge, absorb the maximum clock seen. Ties break on
  `deviceId`, then on canonical-JSON byte order — so the outcome never depends on which file was
  "first".
- **Moment**: `{"w": "<RFC3339 with offset>", "t": <int, optional>}` — wall clock plus, when the
  device offered one, a monotonic stopwatch tick in ms. Both are raw instrument readings; `t`
  survives clock changes and DST, `w` survives app restarts. Neither is derived from the other.
- **Id-map**: an object all of whose keys match the id pattern. A merger may recurse into an
  id-map *without knowing the schema* — this is what lets an old build correctly merge a nested
  collection it has never heard of.
- **Money**: `{"minor": 120000, "currency": "ILS"}` — integer minor units plus ISO 4217.
- **HebrewDate**: `{"year": 5786, "month": "av", "day": 14}`. Month is a string enum:
  `tishrei cheshvan kislev tevet shevat adar adar_i adar_ii nisan iyar sivan tammuz av elul`.
  *Rejected:* numeric months — Nisan-first vs Tishrei-first and Adar I/II make numbers a trap.

### 2.1 File envelope

| Field | Type | Opt | Meaning | Why stored |
|---|---|---|---|---|
| `_format` | string | no | Always `"sofer.stam.data"` | Lets a human and a parser identify the file |
| `_formatVersion` | int | no | Monotonic format version | Drives migrations |
| `_minReader` | int | no | Lowest reader version that may **write** this file | The only structural safety valve (§4) |
| `_note` | string | no | One paragraph, in Hebrew and English, saying what this file is and how to repair it | The repair-by-hand requirement; not machine-read |
| `_generator` | object | no | `{app, build, platform, deviceId}` of the last writer | Forensics when a calculation is found wrong |
| `_exportedAt` | Moment | no | When the export was produced | Forensics; never used in calculations |
| `_integrity` | object | yes | `{algo:"sha256", value}` over canonical JSON minus this field | Detects truncation. **Advisory only** — a mismatch warns, never refuses, because hand-repair legitimately breaks it |
| `devices` | id-map | no | `deviceId → {label, firstSeen, lastSeen}` | Clock tie-breaks and "which device wrote this" |
| `migrations` | id-map | no | `migrationId → {at, by}` | Idempotence of migrations (P14) |
| `settings` | object | no | Single singleton document | — |
| `dayRules` | id-map | no | Versioned day-boundary rules | §2.4 |
| `calendarProfiles` | id-map | no | Working-day profiles | §2.5 |
| `kinds` | id-map | no | Work-kind templates | §2.6 |
| `commissions` | id-map | no | §2.7 | |
| `recordings` | id-map | no | §2.8 | |
| `works` | id-map | no | §2.9 | |
| `expenses` | id-map | no | §2.10 | |
| `conflicts` | id-map | no | Values discarded by merges (P9) | |

All collections are objects keyed by id. The document also repeats its own `_id` inside — a
deliberate redundancy so a hand-repaired file can be re-keyed automatically. **The map key wins**
on disagreement; the mismatch is reported.

### 2.2 Document header (every document)

| Field | Type | Opt | Meaning | Why stored |
|---|---|---|---|---|
| `_id` | string | no | The id | Self-healing after hand-repair |
| `_type` | string | no | `"commission"`, `"work"`, … | A generic merger and a human both need it |
| `_clock` | clock | no | Clock at creation; the default clock for every field | Merge |
| `_fieldClocks` | object | yes | `fieldName → clock`, only for fields modified **after** creation | Per-field LWW without paying for it on write-once records. Includes fields the writing build does not understand |
| `_deleted` | bool | yes | Tombstone flag; clocked in `_fieldClocks` like any field | §3 |
| `_minReader` | int | yes | Per-document refuse-to-compute threshold | One exotic new record must not lock the whole file (§4) |
| `_supersedes` | array of ids | yes | This document replaces those (split/combine) | Provenance for requirement 5; atomic value, LWW as a whole |

`_fieldClocks` is the mechanism that makes P6 work in both directions: an old build that edits
`note` writes `_fieldClocks.note` and leaves the clocks of fields it never heard of untouched, so
the new build's fields still win on merge.

### 2.3 Settings (singleton, `settings`)

Every field here is a **raw user input**. None is a snapshot; none is derived.

| Field | Type | Opt | Meaning | Why stored |
|---|---|---|---|---|
| `activeDayRuleId` | id | no | Which `dayRules` entry new recordings pin | The current setting; past records keep their own pointer |
| `activeCalendarProfileId` | id | no | Working-day profile used for aggregates and projections | P3: interprets aggregates, so current-only |
| `defaultCurrency` | string | no | ISO 4217 | New commissions inherit it |
| `israelYomTov` | bool | yes | One-day vs two-day yom tov | Changes which days are working days |
| `paceWindowDays` | int | yes | Trailing Hebrew days used for pace | An input to the projection; the formula stays in code |
| `paceHalfLifeDays` | int | yes | EWMA half-life; absent = flat average | ditto |
| `includeZeroDays` | bool | yes | Do working days with no output count in the average? | A genuine editorial choice, hence an input |
| `revenueRecognition` | enum | yes | `onCompletion` \| `proRata` | Decides how a half-written sefer contributes to profit |
| `quoteHourlyTarget` | Money | yes | Target rate used when quoting | Input to the quote formula |
| `quoteMarginPct` | int | yes | Margin in basis points ×100, integer | ditto; integer, never a float |
| `calendarDisplay` | enum | yes | `hebrew` \| `both` \| `civil` | Display only |
| `locale` | string | yes | e.g. `"he_IL"` | Display only |

### 2.4 Day-boundary rule (`dayRules`, append-only)

A rule is **immutable once referenced**. Changing the setting appends a new rule; it never edits
an old one. This is the whole answer to "work must never be silently re-filed".

| Field | Type | Opt | Meaning | Why stored |
|---|---|---|---|---|
| `mode` | enum | no | `midnight` \| `sunset` \| `nightfall` \| `fixedClock` | Raw input |
| `fixedTime` | string | yes | `"01:00"`, for `fixedClock` | Raw input |
| `offsetMinutes` | int | yes | Signed shift applied to the computed boundary | Raw input; absent ≠ 0 (absent = the user never adjusted) |
| `algorithm` | string | yes | e.g. `"noaa.v1"`, `"tzeit.72min"`, `"tzeit.8.5deg"` | Names the *intended* computation. If the implementation is later found wrong, fixing the code re-derives history correctly — which is the point |
| `location` | object | yes | `{lat, lon, elevationM, tz}` | Needed for sunset abroad. Absent = device timezone, which is a different fact from "the user set Jerusalem" |
| `label` | string | yes | What the user called it | Shown when explaining why a record sits on a given day |
| `createdAt` | Moment | no | When the rule was created | Ordering and display |

*Explicitly not stored:* the boundary instant for any given day. Derived, always.

### 2.5 Calendar profile (`calendarProfiles`)

| Field | Type | Opt | Meaning | Why stored |
|---|---|---|---|---|
| `label` | string | no | Name | Display |
| `classes` | object | no | `dayClass → {works: bool, capacityFactor?: int}` where `capacityFactor` is per-mille (integer). Classes: `regular erev_shabbat shabbat erev_yom_tov yom_tov chol_hamoed fast_day tisha_bav purim erev_pesach aseret_yemei_teshuva` | The scribe's own working habits; a policy input, not derivable |
| `exceptions` | id-map | yes | `{hebrewDate, works, capacityFactor?, note?}` | One-off facts ("wedding", "reserve duty") |
| `unknownClassDefault` | object | yes | What to assume for a day class this build classifies as unknown | P7 made explicit rather than hidden in code |

The *classification* of a Hebrew date into a class is code plus luach tables, never data — so
fixing a wrong classification fixes all history.

### 2.6 Kind template (`kinds`)

A convenience catalogue. Adding "megilla" is adding a document here, not shipping code.

| Field | Type | Opt | Meaning |
|---|---|---|---|
| `kindId` | string | no | `"sefer_torah"`, `"mezuza"`, `"tefillin"`, … |
| `label` | object | no | `{he, en}` |
| `defaultStructure` | object | no | The structure shape copied into new commissions (§2.7) |
| `builtin` | bool | yes | Shipped with the app vs user-created |

### 2.7 Commission (`commissions`)

| Field | Type | Opt | Meaning | Why stored |
|---|---|---|---|---|
| `kindId` | string | no | Which kind | Raw input |
| `title` | string | no | "Sefer Torah for the Cohen family" | Raw input |
| `customer` | object | yes | `{name?, phone?, note?}` | Raw input |
| `status` | enum | no | `quote` \| `accepted` \| `active` \| `paused` \| `delivered` \| `cancelled` | Raw input |
| `statusLog` | id-map | yes | `{status, at: Moment, note?}` | When work started/stopped is an input to projections and to "how long did the last sefer take" |
| `orderedAt` / `dueAt` | HebrewDate | yes | Dates agreed with the customer | Raw input; drives "am I behind" |
| `structures` | id-map | no | `sv_… → StructureVersion` (below) | Append-only history of the geometry |
| `prices` | id-map | no | `pv_… → PriceVersion` (below) | Append-only history of the money |
| `quote` | object | yes | `{basis: "hourly"\|"perUnit", hourlyTarget?: Money, marginPct?: int, assumedLinesPerHour?: int, note?}` | The **inputs** to a quote. The quoted figure itself is derived and never stored |
| `note` | string | yes | Free text | Raw input |

**StructureVersion** (`sv_…`) — *this is a snapshot, and here is the justification.* The geometry
is copied out of the kind template at creation rather than referenced, because the number of pages
and lines is a fact about **this physical scroll**, not a global setting. Editing the template
later must not silently change a scroll that is already half written. The template is a starting
value; the commission owns the truth.

| Field | Type | Opt | Meaning |
|---|---|---|---|
| `_clock` | clock | no | Also serves as "effective from"; current version = highest clock |
| `reason` | string | yes | Why the geometry changed ("customer wanted 42-line pages") |
| `levels` | array | no | Ordered, atomic. Each: `{id, label:{he,en}, kind:"indexed"\|"named", count?, firstIndex?, members?}` |
| `leafLines` | array | no | Ordered rules `{when?: {levelId: member}, lines: int}`; first match wins |
| `overrides` | id-map | yes | `{path: {...}, lines: int, note?}` — e.g. page 137 has 41 lines |
| `billingLevel` | string | no | Level id, or `"whole"` for a one-off like a sefer |

Examples of `levels`:
- Sefer Torah: `[{id:"page", kind:"indexed", count:245, firstIndex:1}]`, `leafLines:[{lines:42}]`, `billingLevel:"whole"`.
- Mezuzot: `[{id:"mezuza", kind:"indexed", count:40, firstIndex:1}]`, `leafLines:[{lines:22}]`, `billingLevel:"mezuza"`.
- Tefillin: `[{id:"set",kind:"indexed",count:12,firstIndex:1},{id:"piece",kind:"named",members:["head","hand"]},{id:"parshiya",kind:"named",members:["kadesh","vehaya_ki_yeviacha","shema","vehaya_im_shamoa"]}]`,
  `leafLines:[{when:{piece:"head"},lines:4},{when:{piece:"hand"},lines:7}]`, `billingLevel:"set"`.

**PriceVersion** (`pv_…`)

| Field | Type | Opt | Meaning | Why stored |
|---|---|---|---|---|
| `_clock` | clock | no | Effective from (clock order) | — |
| `effectiveFrom` | HebrewDate | yes | Explicit business effectivity, if different from when it was typed | The user may raise a price "as of Rosh Chodesh"; that is an input |
| `pricePerUnit` | Money | no | Per `billingLevel` unit, or the whole job | Raw input |
| `materialCostPerUnit` | Money | yes | The scribe's **estimate**. Absent ≠ zero | Raw input; compared against actual expenses |
| `unit` | string | no | Level id or `"whole"` | Removes ambiguity when `billingLevel` later changes |
| `note` | string | yes | Why | — |

**No work record ever carries a price.** Revenue is derived from (coverage × price schedule).

### 2.8 Recording (`recordings`) — the act of recording

One recording per user action, even when it produced a single work segment. Uniform shape is
worth the ~200 bytes; it is what makes splitting and re-attributing a sitting a local edit.

| Field | Type | Opt | Meaning | Why stored |
|---|---|---|---|---|
| `commissionId` | id | no | Owning commission | Raw input |
| `origin` | enum | no | `measured` \| `entered` \| `backlog` \| `imported` | **Provenance is a fact**, not a synonym for "has no date". Backlog work may later gain a remembered date and must still be flagged as backlog. The *policy* (backlog never counts toward earnings, averages or targets) lives in code and can be corrected |
| `dating` | object | yes | See below. Absent is illegal; use `{"mode":"none"}` | Explicit is better than inferred |
| `timing` | object | yes | See below. **Absent = no time was given.** Present with equal start/end = a measured zero | The single most important application of P5 |
| `attribution` | object | yes | `{method: "byLineMarks"\|"byLines"\|"byUnits"\|"equal"\|"explicit"}` | The **rule**, never the result. Required when the recording has more than one work segment |
| `lineMarks` | array | yes | Atomic array of `{unit, line, at: Moment}` — the moment the scribe began that line | Raw instrument readings. Per-line durations are derived from consecutive marks minus overlapping pauses, so a fix to "does a pause inside a line count" is retroactive |
| `note` | string | yes | Free text | Raw input |

**`dating`**

| Field | Type | Opt | Meaning |
|---|---|---|---|
| `mode` | enum | no | `instant` \| `civilDate` \| `hebrewDate` \| `none` |
| `at` | Moment | if mode=instant | The instant, RFC3339 **with offset** — the offset is part of the fact |
| `tz` | string | yes | IANA zone. Offset alone cannot compute sunset; zone alone cannot reproduce a historical offset if tzdata changes. Both are stored |
| `date` | string | if mode=civilDate | `YYYY-MM-DD` as the user picked it |
| `hebrewDate` | HebrewDate | if mode=hebrewDate | As the user picked it |
| `dayRuleId` | id | required for `instant` and `civilDate` | **A pinned reference (P4), not a snapshot.** It fixes *which rule* classified this work, while leaving the rule's computation fixable forever |
| `dayOverride` | HebrewDate | yes | The user overrode the computed day | A user assertion is an input and outranks any derivation |

`mode: "none"` is the backlog case: no `dayRuleId`, because no rule was applied.
`mode: "hebrewDate"` needs no `dayRuleId` either: the day was stated, not computed.

**`timing`**

| Field | Type | Opt | Meaning |
|---|---|---|---|
| `startedAt` | Moment | no | Timer start, or the "from" hour typed in |
| `endedAt` | Moment | no | Timer stop, or the "to" hour typed in |
| `pauses` | array of `{from: Moment, to: Moment}` | yes | Atomic array. **Absent = breaks were not tracked. `[]` = tracked, and there were none.** These are different facts and both appear in real use |
| `clockSource` | enum | yes | `monotonic` \| `wall` — which instrument the app trusted | A fact about the measurement, not a setting. Lets a later build re-decide how to handle a device whose clock jumped mid-sitting |

Active time is **never stored**. §6 derives it.

### 2.9 Work (`works`) — what was written

| Field | Type | Opt | Meaning | Why stored |
|---|---|---|---|---|
| `recordingId` | id | no | Parent recording | Time attribution and provenance |
| `commissionId` | id | no | Denormalised from the recording | Deliberate redundancy: a work orphaned by a hand-edit is still placeable. Mismatch is reported, never silently fixed |
| `path` | object | either `path` or `quantity` | `{levelId: index-or-member}`, e.g. `{"page": 6}` or `{"set":1,"piece":"head","parshiya":"shema"}` | The identified unit. Order comes from the structure's `levels` |
| `lines` | object | yes | `{from, to}`, 1-based inclusive | Raw input. Ranges, not counts, so overlapping rewrites can be detected |
| `quantity` | object | either | `{level: "mezuza", units: 3}` — anonymous, unidentified units | Real scribes say "3 mezuzot". Refusing to represent it would push the user to lie |
| `nature` | enum | no | `new` \| `rewrite` \| `repair` \| `scrap` \| `practice` | A rewrite consumes time but adds no progress; a scrap resets a unit. Without this, totals double-count |
| `explicitActiveMs` | int | yes | Only when `attribution.method == "explicit"` | Then the split **is** a user input and must be stored as one. Distinguishable forever from a derived share, which is never stored |
| `note` | string | yes | Free text | — |

Validation rule (enforced at entry, reported at read): a *partial* unit must use `path`, never
`quantity`. "One mezuza up to line 14" is `{"path":{"mezuza":7},"lines":{"from":1,"to":14}}`.
Anonymous quantities are whole units only — otherwise nothing can stop double counting.

### 2.10 Expense (`expenses`)

| Field | Type | Opt | Meaning | Why stored |
|---|---|---|---|---|
| `description` | string | no | "Klaf, 30 sheets" | Raw input |
| `amount` | Money | no | What was paid | Raw input |
| `paidAt` | Moment | no | When | Raw input |
| `dayRuleId` | id | yes | Rule pinned for Hebrew-month allocation | Same argument as §2.8 |
| `vendor` | string | yes | Who from | Raw input |
| `nature` | enum | no | `material` \| `tool` \| `overhead` \| `fee` | Only `material` feeds "what materials really cost per unit". Unknown values quarantine (P7) |
| `quantity` | object | yes | `{amount: int, unit: "sheet"}` | Lets cost-per-sheet be derived |
| `allocation` | object | no | See below | The **rule**, never the resulting split |
| `note` | string | yes | | |

**`allocation`**

| Field | Type | Opt | Meaning |
|---|---|---|---|
| `mode` | enum | no | `commissions` \| `period` \| `month` \| `unallocated` |
| `commissionIds` | array | mode=commissions | Atomic array of ids |
| `split` | enum | yes | `even` (default for `commissions`) \| `byWorkTime` \| `byLines` |
| `from` / `to` | HebrewDate or civil date | mode=period | Inclusive bounds |
| `month` | object | mode=month | `{basis:"hebrew", year, month}` or `{basis:"civil", year, month}` |
| `basis` | enum | yes | `hebrew` \| `civil`. **Assumption stated:** "the calendar month it was paid in" is ambiguous; the format stores which calendar was meant rather than guessing |

**No allocated amounts are stored.** §6 computes them, deterministically.

### 2.11 Conflict (`conflicts`)

`{docType, docId, field, losingValue, losingClock, winningClock, detectedAt}`. Written only by a
merge. Never read by any calculation; exists so P1 has no hole.

---

## 3. Identity, time and merging

**Identity.** ULID with a type prefix, generated offline on the device. No coordination, no
collisions in practice, and lexicographic order equals creation order — which gives a free
deterministic tiebreak for the ordered fold in §6.

**Time.** Three clocks, deliberately kept apart:
1. *Wall clock with offset* — what the user experienced. Used for display and for deriving days.
2. *Monotonic tick* — what the stopwatch measured. Immune to clock changes; used for durations
   when present (`clockSource: "monotonic"`).
3. *Hybrid logical clock* — used only for merging. Never displayed, never in a calculation.

Separating (3) from (1) is what makes a device with a wrong system clock a recoverable
annoyance rather than corruption: it may win a merge it should have lost, but the losing value
is in `conflicts` and every fact keeps its own timestamps.

**Deletion.** `_deleted: true` is an ordinary LWW field with an entry in `_fieldClocks`. The
payload is **retained** — requirement 1 says nothing the app shows may be unrecoverable, and a
deletion that shreds the data violates it. The document simply stops participating in
calculations. Undeleting writes `_deleted: false` with a newer clock, which is a real user
action, so nothing comes back by accident. A stale device that *edits* a deleted record bumps
only the edited field's clock; `_deleted` keeps its own, later clock and the record stays dead.

A separate, explicitly-worded **purge** exists for privacy: it writes a payload-free tombstone
`{_id,_type,_clock,_deleted:true,_purged:true}`. Tombstones are never garbage-collected, at any
size, because that is the only way resurrection becomes possible.

**Merge algorithm** (state-based, CRDT; deterministic regardless of order or repetition):

```
merge(A, B):
  assert both parse; if either fails -> abort, keep both files, report
  out._formatVersion = max(A,B);  out._minReader = max(A,B)
  out.devices = union
  for each top-level key k in A ∪ B:                 # including keys neither build knows
      if both are id-maps -> mergeIdMap
      else                 -> mergeValue at parent clock
mergeIdMap(a, b):
  for id in keys(a) ∪ keys(b):
      if only one side has it -> take it verbatim
      else -> mergeDoc
mergeDoc(x, y):
  out._clock = min(x._clock, y._clock)               # creation is the earlier one
  for field f in keys(x) ∪ keys(y):                  # including unknown fields
      cx = x._fieldClocks[f] ?? x._clock
      cy = y._fieldClocks[f] ?? y._clock
      if cx == cy and value differs -> tiebreak on deviceId, then canonical bytes
      winner = greater clock
      out[f] = winner value ; out._fieldClocks[f] = max(cx, cy)
      if values differ -> append a conflict document for the loser
      if both values are id-maps -> recurse instead (nested collections merge, they do not fight)
```

Three properties fall out. It is *commutative and associative* (max of clocks). It is
*idempotent* (merging a file with itself is a no-op). And it is **schema-blind**: the rules
depend only on `_clock`, `_fieldClocks` and the id-map key pattern, so an old build merges a new
build's nested collections correctly without understanding a single field in them.

---

## 4. Versioning and unknown data

**Declaring version.** `_formatVersion` (what this file is) and `_minReader` (the lowest reader
version permitted to write it). Additive changes — new fields, new collections, new enum values,
new kinds — never bump `_minReader`. Only a structural break does, and the design's whole point
is that structural breaks should not be needed.

**A newer build reading an older file.** Migrations run in order, are additive, and are
deterministic functions of the file (P14) so two devices produce identical output. A migration
that must reinterpret a field writes a *new* field and leaves the old one in place, marked
`"_deprecatedSince": <version>`. Old fields are frozen, never deleted. Each applied migration is
recorded in `migrations` so it never runs twice. Missing clocks in a pre-clock file are
synthesised from the document's own ULID timestamp plus a fixed pseudo-device id — identical on
every device that migrates the same file.

**An older build reading a newer file — precisely:**

1. **Unknown key on a known document.** Kept in the model object, written back byte-identically,
   and its entry in `_fieldClocks` is preserved. Implementation: every model holds
   `Map<String,Object?> _unknown`; decode puts leftover keys there; encode emits
   `{..._unknown, ...known}`. A round-trip test asserts byte equality after mutating one field.
2. **Unknown top-level collection.** Preserved verbatim. If it is an id-map, still merged
   correctly by the schema-blind rules above.
3. **Unknown enum value** (`nature: "gilding"`, `kindId: "megilla"`). The document is
   **quarantined**: preserved, editable only in ways that cannot corrupt it, excluded from every
   aggregate, and the UI reports "3 records this version does not understand — totals below
   exclude them". Never coerced to a default (P7). A visibly incomplete number is recoverable;
   a silently wrong one is not.
4. **Document with `_minReader` above the build's version.** Same quarantine, but the build also
   refuses to edit it at all.
5. **File with `_minReader` above the build's version.** The build enters read-only mode: it can
   display and re-export the file untouched, but cannot write. This is the last resort and
   should essentially never fire.
6. **Creating records that reference what it does not understand** — refused. An old build may
   not add work to a commission of an unknown kind, because it cannot validate the geometry.
7. **Never normalise.** No reader may reformat, re-key, renumber, drop empty objects or "clean
   up" anything. Writes are per-document.

**Consistency of dependent new fields.** A new field that is only meaningful relative to an
existing one carries the clock of what it depends on:
`"lineMarks": {"forClock": "<clock of works>", "marks": [...]}`. If an old build edits the line
range, its clock changes and the new build discards the now-stale marks instead of computing
from them. Preservation alone is not enough; invalidation must be expressible.

---

## 5. Worked examples

Hebrew dates below are illustrative. The sitting in (a) is fast for real scribal work — the
format does not care, and the example is the one specified.

### (a) A measured 2-hour sitting crossing pages 5, 6 and 7

One recording, three works. `activeMs` appears nowhere.

```json
{
  "recordings": {
    "rc_01JZC7M0A0000000000000SIT1": {
      "_id": "rc_01JZC7M0A0000000000000SIT1",
      "_type": "recording",
      "_clock": "1785399312004-0000-d7QK3M8V",
      "commissionId": "cm_01JZ8H4K2P000000000000SEFR",
      "origin": "measured",
      "dating": {
        "mode": "instant",
        "at": { "w": "2026-07-30T09:00:00+03:00", "t": 42000 },
        "tz": "Asia/Jerusalem",
        "dayRuleId": "dr_01JZ0AB000000000000000NGHT"
      },
      "timing": {
        "startedAt": { "w": "2026-07-30T09:00:00+03:00", "t": 42000 },
        "endedAt":   { "w": "2026-07-30T11:15:00+03:00", "t": 8142000 },
        "pauses": [
          { "from": { "w": "2026-07-30T10:00:00+03:00", "t": 3642000 },
            "to":   { "w": "2026-07-30T10:15:00+03:00", "t": 4542000 } }
        ],
        "clockSource": "monotonic"
      },
      "attribution": { "method": "byLines" },
      "lineMarks": {
        "forClock": "1785399312004-0000-d7QK3M8V",
        "marks": [
          { "unit": { "page": 5 }, "line": 30, "at": { "w": "2026-07-30T09:00:00+03:00", "t": 42000 } },
          { "unit": { "page": 5 }, "line": 31, "at": { "w": "2026-07-30T09:02:11+03:00", "t": 173000 } },
          { "unit": { "page": 6 }, "line": 1,  "at": { "w": "2026-07-30T09:26:40+03:00", "t": 1642000 } },
          { "unit": { "page": 7 }, "line": 1,  "at": { "w": "2026-07-30T11:00:31+03:00", "t": 7273000 } }
        ]
      },
      "note": "אחרי מנחה"
    }
  },
  "works": {
    "wk_01JZC7M0A1000000000000P005": {
      "_id": "wk_01JZC7M0A1000000000000P005",
      "_type": "work",
      "_clock": "1785399312005-0000-d7QK3M8V",
      "recordingId": "rc_01JZC7M0A0000000000000SIT1",
      "commissionId": "cm_01JZ8H4K2P000000000000SEFR",
      "path": { "page": 5 },
      "lines": { "from": 30, "to": 42 },
      "nature": "new"
    },
    "wk_01JZC7M0A1000000000000P006": {
      "_id": "wk_01JZC7M0A1000000000000P006",
      "_type": "work",
      "_clock": "1785399312006-0000-d7QK3M8V",
      "recordingId": "rc_01JZC7M0A0000000000000SIT1",
      "commissionId": "cm_01JZ8H4K2P000000000000SEFR",
      "path": { "page": 6 },
      "lines": { "from": 1, "to": 42 },
      "nature": "new"
    },
    "wk_01JZC7M0A1000000000000P007": {
      "_id": "wk_01JZC7M0A1000000000000P007",
      "_type": "work",
      "_clock": "1785399312007-0000-d7QK3M8V",
      "recordingId": "rc_01JZC7M0A0000000000000SIT1",
      "commissionId": "cm_01JZ8H4K2P000000000000SEFR",
      "path": { "page": 7 },
      "lines": { "from": 1, "to": 8 },
      "nature": "new"
    }
  }
}
```

`marks` is truncated here; the real file carries all 63. Note what is absent: no elapsed time,
no per-page minutes, no per-line durations, no Hebrew date.

### (b) Typed in, with a date but no hours: 3 mezuzot

`timing` is absent — the fact is "no time was given", not "zero minutes".

```json
{
  "recordings": {
    "rc_01JZD1P4B0000000000000TYP1": {
      "_id": "rc_01JZD1P4B0000000000000TYP1",
      "_type": "recording",
      "_clock": "1785512400900-0000-d7QK3M8V",
      "commissionId": "cm_01JZ8H4K2Q000000000000MZZT",
      "origin": "entered",
      "dating": {
        "mode": "hebrewDate",
        "hebrewDate": { "year": 5786, "month": "av", "day": 14 }
      }
    }
  },
  "works": {
    "wk_01JZD1P4B1000000000000MZ03": {
      "_id": "wk_01JZD1P4B1000000000000MZ03",
      "_type": "work",
      "_clock": "1785512400901-0000-d7QK3M8V",
      "recordingId": "rc_01JZD1P4B0000000000000TYP1",
      "commissionId": "cm_01JZ8H4K2Q000000000000MZZT",
      "quantity": { "level": "mezuza", "units": 3 },
      "nature": "new"
    }
  }
}
```

### (c) Backlog, no date at all: the four head parshiyot of tefillin set 1

No `dating.at`, no `dayRuleId`, no `timing`. `origin` records the provenance so the exclusion
policy stays in code and remains correctable.

```json
{
  "recordings": {
    "rc_01JZD2Q5C0000000000000BKL1": {
      "_id": "rc_01JZD2Q5C0000000000000BKL1",
      "_type": "recording",
      "_clock": "1785512999100-0000-d7QK3M8V",
      "commissionId": "cm_01JZ8H4K2R000000000000TFLN",
      "origin": "backlog",
      "dating": { "mode": "none" },
      "note": "נכתב לפני שהתחלתי לרשום"
    }
  },
  "works": {
    "wk_01JZD2Q5C1000000000000T1H1": {
      "_id": "wk_01JZD2Q5C1000000000000T1H1",
      "_type": "work",
      "_clock": "1785512999101-0000-d7QK3M8V",
      "recordingId": "rc_01JZD2Q5C0000000000000BKL1",
      "commissionId": "cm_01JZ8H4K2R000000000000TFLN",
      "path": { "set": 1, "piece": "head", "parshiya": "kadesh" },
      "lines": { "from": 1, "to": 4 },
      "nature": "new"
    },
    "wk_01JZD2Q5C1000000000000T1H2": {
      "_id": "wk_01JZD2Q5C1000000000000T1H2",
      "_type": "work",
      "_clock": "1785512999102-0000-d7QK3M8V",
      "recordingId": "rc_01JZD2Q5C0000000000000BKL1",
      "commissionId": "cm_01JZ8H4K2R000000000000TFLN",
      "path": { "set": 1, "piece": "head", "parshiya": "vehaya_ki_yeviacha" },
      "lines": { "from": 1, "to": 4 },
      "nature": "new"
    },
    "wk_01JZD2Q5C1000000000000T1H3": {
      "_id": "wk_01JZD2Q5C1000000000000T1H3",
      "_type": "work",
      "_clock": "1785512999103-0000-d7QK3M8V",
      "recordingId": "rc_01JZD2Q5C0000000000000BKL1",
      "commissionId": "cm_01JZ8H4K2R000000000000TFLN",
      "path": { "set": 1, "piece": "head", "parshiya": "shema" },
      "lines": { "from": 1, "to": 4 },
      "nature": "new"
    },
    "wk_01JZD2Q5C1000000000000T1H4": {
      "_id": "wk_01JZD2Q5C1000000000000T1H4",
      "_type": "work",
      "_clock": "1785512999104-0000-d7QK3M8V",
      "recordingId": "rc_01JZD2Q5C0000000000000BKL1",
      "commissionId": "cm_01JZ8H4K2R000000000000TFLN",
      "path": { "set": 1, "piece": "head", "parshiya": "vehaya_im_shamoa" },
      "lines": { "from": 1, "to": 4 },
      "nature": "new"
    }
  }
}
```

### (d) An expense split across two commissions

1,200 ILS of klaf, split evenly. The two 600s are not written down.

```json
{
  "expenses": {
    "ex_01JZD3R6D0000000000000KLAF": {
      "_id": "ex_01JZD3R6D0000000000000KLAF",
      "_type": "expense",
      "_clock": "1785513600000-0000-d7QK3M8V",
      "description": "קלף, 30 יריעות",
      "amount": { "minor": 120000, "currency": "ILS" },
      "paidAt": { "w": "2026-07-29T12:40:00+03:00" },
      "dayRuleId": "dr_01JZ0AB000000000000000NGHT",
      "vendor": "בית מלאכה שילוני",
      "nature": "material",
      "quantity": { "amount": 30, "unit": "sheet" },
      "allocation": {
        "mode": "commissions",
        "commissionIds": [
          "cm_01JZ8H4K2P000000000000SEFR",
          "cm_01JZ8H4K2R000000000000TFLN"
        ],
        "split": "even"
      }
    }
  }
}
```

---

## 6. The re-derivation algorithm

All figures below come from the stored data alone. Integer arithmetic throughout; a division is
only performed at the last step, for display.

### 6.1 Active time of a recording — `activeMs(r)`

```
if r.timing is absent            -> UNDEFINED            # not zero. Never enters an average.
ticks = startedAt.t and endedAt.t both present
elapsed = ticks ? endedAt.t - startedAt.t
                : endedAt.w.epochMs - startedAt.w.epochMs
if r.timing.pauses is absent -> pauseMs = 0, flag breaksNotTracked
else pauseMs = Σ over pauses of (ticks ? p.to.t - p.from.t : p.to.w - p.from.w)
active = elapsed - pauseMs
if active < 0 -> mark invalid, exclude from aggregates, surface to the user (never clamp)
```

Example (a): ticks 8_142_000 − 42_000 = 8_100_000; pause 4_542_000 − 3_642_000 = 900_000;
active = **7_200_000 ms**.

### 6.2 Attributing a stretch of time across several works

The core of "one action, several units". Input: `total = activeMs(r)`, and weights derived from
`attribution.method`:

| method | weight of work *i* |
|---|---|
| `byLineMarks` | Σ of measured durations of the marks inside that work (see 6.3). Falls back to `byLines` for works with no marks |
| `byLines` (default when >1 work) | `lineCount(i)` |
| `byUnits` | 1 per identified unit, `quantity.units` for anonymous |
| `equal` | 1 |
| `explicit` | not attributed at all — each work carries `explicitActiveMs`, a stored input |

Then, **largest-remainder in integer milliseconds**, so the parts always sum exactly to the whole
and the result never depends on iteration order:

```
W = Σ weights;  if W == 0 -> use weights = [1,1,…]
base[i]  = (total * w[i]) ~/ W                       # integer floor
rem[i]   = (total * w[i]) %  W
short    = total - Σ base
order    = indices sorted by (rem descending, then _id ascending)   # total order
give +1 ms to the first `short` indices in `order`
```

Example (a), total 7_200_000, weights 13 / 42 / 8 (W = 63):

| page | total×w | ÷63 floor | remainder | +1? | share (ms) |
|---|---|---|---|---|---|
| 5 | 93_600_000 | 1_485_714 | 18 | no | 1_485_714 |
| 6 | 302_400_000 | 4_800_000 | 0 | no | 4_800_000 |
| 7 | 57_600_000 | 914_285 | 45 | **yes** | 914_286 |
| | | Σ 7_199_999 | | | **Σ 7_200_000** |

### 6.3 Per-line durations (only where `lineMarks` exist)

Sort marks by `at`. `duration(mark_k) = at(mark_{k+1}) - at(mark_k) - (pause time inside that
window)`; the last mark runs to `endedAt`. If `lineMarks.forClock` ≠ the current clock of the
work it describes, discard the marks (§4) and fall back to `byLines`.

### 6.4 The day a record belongs to — `day(r)`

```
mode "none"        -> NO DAY. Excluded from anything per-day, per-month, earnings or targets.
mode "hebrewDate"  -> exactly what is stored.
mode "instant"     -> rule = dayRules[r.dating.dayRuleId]
                      b = boundaryInstantFor(rule, r.dating.at, rule.location ?? deviceZone)
                      hd = hebrewDateOfCivilDay(r.dating.at)
                      if r.dating.at >= b -> hd = hd + 1 day
mode "civilDate"   -> the Hebrew day whose *daytime* falls on that civil date (documented
                      convention, applied through the pinned rule so it is fixable).
if r.dating.dayOverride is present -> it wins outright.
```

Because `dayRuleId` is pinned, changing the setting never moves old work. Because it is a
*reference*, fixing `boundaryInstantFor` fixes every day the app ever displayed.

### 6.5 Coverage, total written, rework — the ordered fold

Rewrites and scraps make this a fold, not a sum.

```
order works by:  (day sort key; undated backlog first) then
                 (recording.timing.startedAt if known) then (_id)
cover  : unitKey -> IntervalSet<line>       # unitKey = level ids joined in structure order
rework : unitKey -> int
anon   : levelId -> int
for w in order, skipping w._deleted and quarantined:
    if w.quantity:  if w.nature == "new" -> anon[level] += w.quantity.units ; continue
    k = unitKey(w.path)
    switch w.nature:
      "new"                    -> cover[k] |= [from..to]
      "rewrite" | "repair"     -> rework[k] += (to - from + 1)
                                  if [from..to] ⊄ cover[k] -> validation warning
      "scrap"                  -> cover[k] = ∅ ; rework[k] += |lines of the unit|
      "practice"               -> ignored for coverage and for progress
writtenLines = Σ |cover[k]|  +  Σ anon[level] × linesPerUnit(level)
totalLines   = Σ over every leaf unit of the current StructureVersion of linesFor(unit)
                (leafLines rules, first match wins; overrides win over those)
remaining    = totalLines - writtenLines
```

`totalLines`: sefer 245 × 42 = 10 290; mezuzot N × 22; tefillin N × (4×4 + 4×7) = N × 44.

**Progress** = `writtenLines / totalLines`, formatted at display time. Unit progress
(`unitsComplete / unitCount`) is computed the same way and shown alongside, because for a
tefillin order the scribe thinks in sets, not lines.

### 6.6 Average time per line

```
timedMs = 0 ; timedLines = 0 ; netTimedLines = 0
for r in recordings where activeMs(r) is DEFINED and r.origin != "backlog":
    shares = attribute(activeMs(r), r.works)          # 6.2
    for (w, ms) in shares, w not deleted/quarantined:
        timedMs      += ms
        timedLines   += lineCount(w)                       # includes rewrites
        netTimedLines += coverageGainedBy(w)               # from the 6.5 fold
avgMsPerLine    = timedMs / timedLines           # "how long does a line take me"
avgMsPerNetLine = timedMs / netTimedLines        # "how long does a line of progress take me"
timeCoverage    = timedLines / totalLinesWrittenExcludingBacklog
```

Two averages, not one: rewrites make them different, and the projection needs the second.
`timeCoverage` is displayed next to any hourly figure so the scribe knows how much of his work
carried a measurement. Records with no time never contribute a zero.

### 6.7 Output per day and per working day

```
byDay[hebrewDay] = Σ coverage gained that day        (dated, non-backlog work only)
span = [firstDay … lastDay] in the requested range
workingDays = { d in span : profile.classes[classOf(d)].works == true },
              with profile.exceptions overriding classOf
outputPerWorkingDay = settings.includeZeroDays
        ? Σ byDay over span / |workingDays|
        : Σ byDay over span / |{ d in workingDays : byDay[d] > 0 }|
outputPerMonth = the same, grouped by Hebrew month (or civil, per calendarDisplay)
```

`classOf(d)` is code plus luach tables. It is never stored, so a wrong classification is a fix,
not a migration.

### 6.8 Money

```
price(c, day)     = the PriceVersion of c with the greatest effectiveFrom <= day,
                    falling back to _clock order; for undated (backlog) units, the earliest.
revenue(c) =
  if revenueRecognition == "onCompletion":
        Σ over billing units fully covered of price(c, dayOfLastLine(u)).pricePerUnit
  else  # proRata
        Σ over billing units u of  price(c, dayOfLastLine(u)).pricePerUnit
                                   × |cover(u)| / linesOf(u)
        (integer minor units; largest-remainder over units so the parts sum to the whole)

allocatedExpenses(c) =
  mode "commissions", split "even":
        amount ÷ n, largest remainder over commissionIds sorted ascending
  mode "commissions", split "byWorkTime"/"byLines":
        amount × metric(c) / Σ metric, same rounding
  mode "period"/"month":
        metric(c) = attributed active ms (byWorkTime, default) or net lines (byLines)
                    of c's work whose derived day falls in the window, using `basis`
        if Σ metric == 0 -> the expense stays in an explicit `unallocated` bucket,
                            reported on screen. It is never silently dropped and never
                            spread over commissions that did no work.

materialsActual(c)   = Σ allocatedExpenses(c) where nature == "material"
overheadActual(c)    = Σ allocatedExpenses(c) where nature != "material"
materialsEstimate(c) = unitsCounted(c) × materialCostPerUnit(current version)
                       (UNDEFINED if materialCostPerUnit is absent — not zero)

profitActual(c)    = revenue(c) - materialsActual(c) - overheadActual(c)
profitEstimated(c) = revenue(c) - materialsEstimate(c)          # only if defined
realMaterialPerUnit(c) = materialsActual(c) / unitsComplete(c)  # "what materials really cost"
hours(c)           = Σ attributed shares over c's timed, non-backlog recordings / 3_600_000
profitPerHour(c)   = profitActual(c) / hours(c)                 # shown with timeCoverage
```

Profit per hour excludes untimed work from the denominator, which biases it upward. That bias is
disclosed by displaying `timeCoverage` beside it rather than hidden by imputing zeros or averages.

### 6.9 Projected completion

```
pace = net lines per working day over the trailing settings.paceWindowDays Hebrew days,
       EWMA with settings.paceHalfLifeDays if set, else flat;
       dated non-backlog work only.
if pace <= 0 -> report "not enough data", never "never" and never a date.
reworkRate = rework lines / net lines over the same window
remaining  = (totalLines - writtenLines) × (1 + reworkRate)
d = today's Hebrew day (via the *active* day rule — this is about the future)
while remaining > 0:
    d = d + 1 day
    cls = classOf(d) ; e = profile.exceptions[d] ?? profile.classes[cls]
    if not e.works -> continue
    remaining -= pace × (e.capacityFactor ?? 1000) / 1000
return d
```

### 6.10 A quote for a job not yet accepted

```
lines   = totalLines of the draft StructureVersion
msPerLine = c.quote.assumedLinesPerHour ? 3_600_000 / it : global avgMsPerNetLine
hours   = lines × msPerLine / 3_600_000
labour  = hours × (c.quote.hourlyTarget ?? settings.quoteHourlyTarget)
material= unitsOf(structure) × materialCostPerUnit  (or realMaterialPerUnit of past jobs
          of the same kindId, when the estimate is absent — and it says which it used)
quote   = (labour + material) × (10000 + marginPct) / 10000
```

Only the inputs are stored. Re-opening a two-year-old quote recomputes it from that job's own
`quote` object, and a corrected pace formula corrects every past quote too.

---

## 7. What this survives

**Absorbed without touching existing data:**

- New kinds of work — megillot, ketubot, anything — as a `kinds` document plus a
  `StructureVersion`. No new fields, no migration.
- New geometry: deeper nesting (a level between set and parshiya), named members, per-unit line
  overrides, non-uniform pages.
- New units of counting: `billingLevel` can name any level, including one added later.
- A sefer whose page count is corrected mid-job: a new `StructureVersion`; last month's progress
  report is still reproducible from the old one.
- Price rises and material-cost corrections mid-job: a new `PriceVersion` with `effectiveFrom`.
  No work record changes.
- Changing the day boundary (midnight → nightfall → an hour the user picks): a new `dayRule`.
  Not one existing record moves.
- Per-city sunset for a scribe abroad: `location` on a new rule. Old records keep the old rule.
- Fixing a *bug* in sunset, nightfall or the Hebrew calendar: pure code fix, retroactive to every
  record ever made, because only the rule *reference* was pinned.
- New devices, and devices that were offline for a year.
- Splitting one recording into two, or merging two into one: new documents with `_supersedes`,
  tombstones on the originals, nothing rewritten.
- Discovering that pauses, rework, or backlog were counted wrongly: all three are stored as raw
  facts with explicit markers.
- Line-level timing on some devices and not others: `lineMarks` optional per recording, and
  attribution degrades to `byLines`.
- Adding settings: `settings` is an open object; unknown keys survive an old build untouched.
- Moving to SQLite, or to a server: documents map 1:1 to rows; HLC + LWW map is already a
  sync-ready CRDT.
- A new field that depends on an old one, edited by an old build: caught by `forClock`.

**Honestly, what it does not survive:**

- **Anonymous quantities cannot be de-duplicated.** "3 mezuzot" recorded twice by accident is
  indistinguishable from 6 mezuzot. The only mitigations are the validation rule that partials
  must be indexed, and a UI nudge toward indexing. This is a real, accepted hole; the alternative
  (forbidding anonymous counts) would make the app lie about how scribes actually work.
- **Redefining an existing field's meaning.** Old builds will show the old meaning. The design
  forbids it (add a new field instead), but the format cannot enforce the discipline.
- **A badly wrong device clock** can win merges it should lose until it is corrected. The losing
  values are in `conflicts`, so nothing is destroyed, but the user has to look. A refuse-to-write
  guard for clocks far ahead of the maximum seen is possible and is not in this design.
- **Concurrent edits to the same field on two devices**: one wins by rule. The loser is preserved,
  not merged.
- **Referential integrity is checked, not enforced.** A hand-edit that deletes a commission leaves
  orphaned works; they are quarantined and reported, never silently dropped.
- **Hand-repair breaks `_integrity` and can break clocks.** Deliberately tolerated: the checksum
  is advisory and a repaired document simply gets a fresh clock on next write.
- **No encryption, no privacy at rest.** Out of scope, and it would fight hand-repair.
- **Single scribe.** A workshop with several scribes needs a `scribeId` on recordings and
  per-scribe aggregates. The field can be added additively; the reports cannot.
- **A dispute about the luach itself** (which day a festival falls on) is a code change that moves
  history. `dayOverride` handles the individual case; there is no per-record luach pin, and adding
  one would be the same machinery as `dayRules`.
- **File size grows monotonically.** Tombstones and deprecated fields are never removed. At this
  data volume that is the right trade; at 10⁶ records it would not be.

---

## 8. Cost

**Storage.** Pretty-printed, keys sorted, no compression:

| | bytes each | count over ~5 years | total |
|---|---|---|---|
| work | ~300 | 3 000 | ~0.9 MB |
| recording (no marks) | ~450 | 1 500 | ~0.7 MB |
| recording with 42 line marks | ~4 500 | 250 (a full sefer) | ~1.1 MB |
| expense | ~450 | 400 | ~0.2 MB |
| commission (with versions) | ~1 800 | 20 | ~0.04 MB |
| tombstones | ~140 | 200 | ~0.03 MB |
| conflicts | ~250 | rare | — |

Roughly **2–3 MB** for a busy scribe over five years; ~200–300 KB gzipped, which is what the
export should be if the file is ever attached to anything. `lineMarks` are half the size and are
the one place where the design pays real money for recoverability — and they are optional per
recording, so a device that does not track lines pays nothing.

Per-field clocks cost ~45 bytes per field *modified after creation*. Since most records are
written once, the typical document carries no `_fieldClocks` at all. Whole-record LWW would have
saved that and lost concurrent edits; the trade is right at this ratio.

**Write amplification.** The KV store holds one JSON document per key (`doc/work/wk_…`), so
editing one work rewrites ~300 bytes, not the file. Editing a commission's price appends a
`PriceVersion` inside one ~2 KB document. The only whole-file write is an export, which is user
initiated. Import is a merge, so it writes only the documents that actually changed. **Rejected:**
one big JSON blob as the live store — it turns every keystroke into a megabyte write and makes a
crash mid-write catastrophic.

**Read cost.** Every headline figure is a full fold over that commission's works. 3 000 works with
interval-set unions is well under a millisecond in Dart. Derived values may be cached **in RAM**,
keyed by a store revision counter, or in a separate cache file that is never merged, never
exported, and deleted without hesitation on any version change. No cache is ever part of the data
format — that is principle 1 in operational form.

**Complexity.** The genuinely new machinery is: a hybrid logical clock (~80 lines), the
schema-blind merge (~200), unknown-key preservation on a model base class (~60 plus discipline in
every model), the interval-set fold (~120), and largest-remainder attribution (~40). Call it
600–900 lines of Dart, plus one non-negotiable test: parse a file containing invented future
fields, mutate one known field, serialise, and assert every unknown byte is unchanged. That test
is what makes requirement 2 real rather than aspirational.

The discipline cost is higher than the code cost. Every new feature must answer one question
before a field is added: *is this a fact the scribe asserted, or an answer the app computed?*
Only the first kind goes on disk.
