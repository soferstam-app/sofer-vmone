# On-disk data format for the sofer stam app — Design B

*(Spec written in English because every field name, section title and JSON key in it is English; the summary returned to the user is in Hebrew.)*

Status: clean-sheet design. Format name `sofer-stam-data`, version 1.0.

---

## 1. Principles

Each rule, then the failure it exists to prevent.

**P1 — Only assertions are stored. Anything a program could compute is computed.**
An "assertion" is something a human decided or a sensor measured: *I wrote lines 30–42 of page 5*, *the timer ran from 19:00 to 20:10*, *the price is 350 a page*, *I quoted the customer 42,000*. A "derivation" is anything a function of assertions produces: total written, progress %, profit, average minutes per line, the Hebrew date of a sitting, an expense's share per commission.
*Prevents:* the failure that has already happened twice — a wrong calculation freezing into the data, so that fixing the code cannot fix the past.

**P2 — Where a calculation depends on a user policy that can change, store the policy that was in force, never the calculation's result.**
The day-boundary rule is snapshotted onto each work record. The *day* is not.
*Prevents:* both halves of the trap. Storing the computed day means a nightfall bug is permanent. Storing nothing means changing the setting silently re-files years of history under different days.

**P3 — Snapshot only what determines a record's identity or attachment. Never snapshot what only feeds an aggregate.**
Day-boundary rule and location: snapshotted (they decide *which day this work belongs to*). Working-day calendar, price of a page, target hourly rate, expense-split policy: not snapshotted (they only feed sums, and a corrected model should correct the sums).
*Prevents:* snapshot creep, where every setting is copied onto every record and no mistake can ever be corrected retroactively.

**P4 — Absence is a value. A field that is not there means "not stated" and nothing else.**
There is no "0 means unknown", no sentinel dates, no empty string for null. `time` absent ≠ `time.declaredMs == 0`.
*Prevents:* the single biggest arithmetic error available here — scribes who never record time dragging every average towards zero.

**P5 — Every collection is an id-keyed map, never a positional array — unless the array is an atomic value written by one device in one act.**
`priceTerms`, `vacations`, `expenses` are maps. `items` and `marks` inside one work record are arrays, and merge as one indivisible value.
*Prevents:* the classic CRDT array disaster where two devices append and the result interleaves, or where index 2 means different things on two devices.

**P6 — Every field carries an ordering stamp; merge is per-field last-writer-wins over a hybrid logical clock.**
*Prevents:* one device's edit to the price silently discarding the other device's edit to the page count.

**P7 — Deletion is a field, not an absence. It is absorbing.**
*Prevents:* resurrection. A concurrent edit can never undelete.

**P8 — A reader preserves verbatim everything it does not understand, including stamps, including whole document types.**
*Prevents:* the phone → old desktop → phone round trip losing data.

**P9 — A reader that cannot compute correctly says so rather than computing.**
Documents may declare required capability tokens. An older build shows the record, preserves it, exports it, and marks affected totals as *incomplete on this device*.
*Prevents:* an old build quietly reporting the wrong profit because it does not know what a new field means.

**P10 — Money is decimal strings with an explicit currency. Never a binary float.**
*Prevents:* 0.1 + 0.2, and currency-free numbers that become meaningless the day a scribe abroad is added.

**P11 — No cache, index, or memo is ever written to the file.**
Caches live in a disposable KV namespace keyed by a `calcEpoch` constant that is bumped whenever any derivation changes.
*Prevents:* a stale cache being mistaken for data by a future reader, or by a hand-repairing human.

**P12 — The file is line-oriented so that damage is local and a human can repair it.**

---

## 2. The entities and their fields

### 2.0 Conventions used in every table

- **Class** is one of:
  - `RAW` — an assertion by a human or a sensor. The ground truth.
  - `SNAP` — a copy of a setting as it stood when the record was made. Every one is justified in place.
  - `META` — identity, ordering, deletion, versioning. Not domain data.
- **Opt** = may be absent, and absence is meaningful.
- Types: `str`, `int`, `bool`, `dec` (decimal string), `instant` (ISO-8601 with explicit offset, milliseconds, e.g. `"2026-07-30T19:00:00.000+03:00"`), `day` (see 2.1), `stamp` (see 3.1), `uuid`.
- All line and unit numbering is **1-based inclusive**. There is no line 0 and no page 0.

### 2.1 Shared value types

**`day` — an asserted calendar day.** A tagged object; exactly one of the two forms.

```json
{"cal":"hebrew","y":5786,"m":"AV","d":12}
{"cal":"gregorian","date":"2026-07-26"}
```

`m` is a token from a fixed list: `TISHREI NISAN IYAR SIVAN TAMUZ AV ELUL CHESHVAN KISLEV TEVET SHVAT ADAR ADAR_I ADAR_II`. `ADAR` is only legal in a common year; `ADAR_I`/`ADAR_II` only in a leap year. A `day` stores **the calendar the human actually used**; the other calendar is derived. Rejected: storing both, which creates two sources of truth and guarantees they will disagree after a conversion-table fix.

**`money`**

```json
{"value":"2400.00","currency":"ILS"}
```

**`address` — a path into a commission's geometry.** An array alternating token and index-or-name:
`["page",5]`, `["mezuza",7]`, `["set",2,"head","kadesh"]`. `[]` addresses the commission as a whole.

**`stamp`** — see §3.1. Format `"001785489262418-00007-9f2c1ab40e77"`.

### 2.2 Document envelope (every document, every type)

| Field | Type | Opt | Class | Meaning / why stored |
|---|---|---|---|---|
| `id` | uuid | no | META | Opaque identity. Carries no meaning — not a date, not a sequence. Derived nothing from it, ever. |
| `type` | str | no | META | `commission` `work` `expense` `quote` `settings` `device`. |
| `_c` | stamp | no | META | Creation stamp. Also the default stamp for any field that has never been edited since creation — this is what keeps `_s` nearly empty. |
| `_s` | map str→stamp | yes | META | Per-field write stamps, only for fields edited after creation, plus `_s["_del"]`. Absent means "nothing edited since creation". |
| `_del` | bool | yes | META | Deletion register. Absent = alive. Absorbing (§3.3). |
| `_req` | array of str | yes | META | Capability tokens a reader needs to compute this document correctly, e.g. `["work.marks.v1"]`. Unknown token ⇒ preserve, display, and flag totals (P9). |
| `_x` | object | yes | META | Extension/experimental bag and merge-conflict retention. Never read by core logic. |

Unknown top-level keys on any document are **kept verbatim** and re-emitted (P8).

### 2.3 `commission`

| Field | Type | Opt | Class | Meaning / why stored |
|---|---|---|---|---|
| `kind` | str | no | RAW | Opaque token: `sefer-torah`, `mezuzot`, `tefillin`, later `megilla`, `ketuba`, anything. Only used for labels and defaults; **no calculation branches on it** — calculations branch on `geometry`. This is what makes new kinds free. |
| `title` | str | no | RAW | User label. |
| `client` | str | yes | RAW | Free text. |
| `status` | str | no | RAW | `active` `paused` `done` `cancelled`. User assertion; *not* derived from progress, because a scribe can finish a job at 97% (the customer changed the order). |
| `startedOn` | day | yes | RAW | User-asserted. Not derived from the earliest work record, which may be backlog with no date. |
| `dueOn` | day | yes | RAW | Target date, if the customer set one. |
| `geometry` | object | no | RAW | The shape of the job (§2.4). Stored because every historical record's addresses are meaningless without it, forever. |
| `priceTerms` | map uuid→term | yes | RAW | Price per unit, over time (§2.5). |
| `materialCostTerms` | map uuid→term | yes | RAW | Estimated material cost per unit, over time. Same shape. This is the scribe's *estimate*; what materials really cost is derived from `expense` documents and reported separately. |
| `note` | str | yes | RAW | |

Deliberately absent: `linesWritten`, `progress`, `remaining`, `totalEarned`, `hoursSpent`, `lastWorkedOn`, `currentPosition`. All derived (P1). "Current position" in particular is a trap — it is `max` over the coverage set and must never be a stored cursor that can drift out of sync with the records.

### 2.4 `geometry` — the extensibility hinge

```json
{
  "schema": "nested.v1",
  "root": {"token":"page","count":245,"lines":42,"linesOverride":{"223":70}}
}
```

A **node** has:

| Field | Type | Opt | Meaning |
|---|---|---|---|
| `token` | str | no | Address segment name: `page`, `mezuza`, `set`, `head`, `hand`, `parshiya`. |
| `count` | int | yes | Number of indexed siblings. Present ⇒ addressed by 1-based integer. |
| `names` | array of str | yes | Named siblings, e.g. `["kadesh","vehaya-ki-yeviacha","shema","vehaya-im-shamoa"]`. Present ⇒ addressed by name. Exactly one of `count`/`names`; both absent ⇒ a single unnamed instance. |
| `lines` | int | yes | Leaf: number of writable lines. |
| `linesOverride` | map str→int | yes | Per-index/per-name exceptions (Ha'azinu's long page, a short parshiya). |
| `children` | array of node | yes | Non-leaf. Exactly one of `lines`/`children`. |
| `priceable` | bool | yes | Default `false` except on the node the price term names. Marks which level the money is quoted per. |
| `label` | object | yes | `{"he":"עמוד","en":"page"}` for display only. |

Sefer Torah: root `page`, count 245, lines 42.
Mezuzot: root `mezuza`, count N, lines 22.
Tefillin: root `set`, count N, children `head` (children: `parshiya` names ×4, lines 4) and `hand` (children: `parshiya` names ×4, lines 7).

A new kind needs a new `geometry` document value and zero code. A genuinely new *shape* (say, a megilla with columns of variable width and a separate blank margin allowance) gets `"schema":"nested.v2"` and lives side by side with v1 — old commissions are never migrated, because their v1 geometry is still correct.

### 2.5 `term` (price / material cost)

| Field | Type | Opt | Class | Meaning |
|---|---|---|---|---|
| `unit` | str | no | RAW | Geometry token the price is per: `page`, `mezuza`, `set`. |
| `amount` | money | no | RAW | |
| `effectiveFrom` | day | yes | RAW | Absent = from the beginning of the commission. |
| `note` | str | yes | RAW | e.g. "renegotiated after the ktav was upgraded". |

Why a map of dated terms rather than a scalar `pricePerUnit`: prices get renegotiated mid-scroll. With a scalar, the day the price changes, every past profit figure silently changes too. **Rejected alternative:** snapshot the price onto each work record. That is worse — it freezes a typo. A mistyped price should be fixable once and correct everywhere; a genuine renegotiation should be a new term. The two cases are different acts and need different representations.

### 2.6 `work` — the central record

| Field | Type | Opt | Class | Meaning / why stored |
|---|---|---|---|---|
| `commissionId` | uuid | no | RAW | |
| `dating` | str | no | RAW | `instant` \| `asserted` \| `backlog`. The scribe's *intent*, not an inference from which fields are present. `backlog` means "there is no date and there never will be" — distinct from a dated record whose date got lost, which is corruption. A validator cross-checks intent against the fields; a mismatch is reported, never auto-fixed. |
| `startedAt` | instant | yes | RAW | Required iff `dating=="instant"`. Local offset preserved, not UTC-normalised — the wall clock is what the day boundary reasons about. |
| `endedAt` | instant | yes | RAW | |
| `day` | day | yes | RAW | Required iff `dating=="asserted"`. Must be absent when `dating=="instant"` — the day is derived there, and storing it would violate P1. |
| `dayRule` | object | yes | **SNAP** | See below. Present iff `dating=="instant"`. |
| `time` | object | yes | RAW | Absent = **no time was given**. See §2.7. |
| `marks` | array | yes | RAW | Live position tracking (§2.8). |
| `items` | array of item | no | RAW | What was written (§2.9). Atomic for merge purposes. |
| `attribution` | object | yes | RAW | Present only if the user *chose* how to split the sitting's time across items. Absent = "use the app's current best policy", which is a calculation and may improve. |
| `note` | str | yes | RAW | |
| `derivedFrom` | array of uuid | yes | RAW | Provenance when a record was split or two were combined. The originals get tombstones; the lineage survives, so a later "that split was wrong" is recoverable. |
| `enteredAt` | instant | yes | META | When the row was typed. Never used in any domain calculation — only for audit and for "you entered this at 23:50, did you mean yesterday?" prompts. |

**`dayRule` — the one snapshot on a work record, and its justification.**

```json
{"mode":"nightfall","algo":"tzeit_8p5deg","tz":"Asia/Jerusalem",
 "place":{"lat":31.7683,"lon":35.2137,"elevM":754,"label":"ירושלים"},
 "settingStamp":"001785401111000-00002-9f2c1ab40e77"}
```

`mode` ∈ `midnight` | `sunset` | `nightfall` | `custom` (with `offsetMinutes`).

This is a snapshot of a **policy**, never of a **result**. The record does not say "this was 16 Av". It says "this was reckoned by nightfall, computed with the 8.5° algorithm, at these coordinates". The day is recomputed from `startedAt` plus this rule every single time it is displayed.

Consequences, all of them intended:
- The scribe changes the setting to midnight next year → nothing already recorded moves. (P2)
- A bug is found in the 8.5° nightfall implementation → fix the code, and every historical record's day corrects itself. (P1)
- The *definition* changes (a new opinion, e.g. 18-minute fixed) → that is a new token `tzeit_18min`, applied to new records; old records keep theirs. Changing the token and fixing a bug in a token are deliberately different operations.
- A scribe travels abroad → `place` was captured at the time, so a sitting in Manchester is reckoned by Manchester's nightfall for ever, even after he moves home. This is precisely the "per-city sunset added later" case in the brief: the field is already there, and records made before the feature existed carry the home coordinates, which is what they meant.

`settingStamp` is the stamp of the settings write this was copied from, so an audit can trace a snapshot back to the setting that produced it.

### 2.7 `time`

```json
{"kind":"segments","segments":[{"from":"…","to":"…"},{"from":"…","to":"…"}]}
{"kind":"declared","declaredMs":7200000}
{"kind":"segments","segments":[…],"declaredMs":6600000,
 "override":{"reason":"forgot to pause for the phone call"}}
```

| Field | Type | Opt | Class | Meaning |
|---|---|---|---|---|
| `kind` | str | no | RAW | `segments` \| `declared`. |
| `segments` | array of `{from,to}` instants | yes | RAW | **Writing** intervals. Breaks are the *gaps between* them. |
| `declaredMs` | int | yes | RAW | A duration the human stated. |
| `override` | object | yes | RAW | Present when the human overrode a measured figure; keeps both facts. |
| `source` | str | yes | RAW | `timer` \| `typed-hours` \| `typed-duration`. Provenance for confidence display. |

Not stored: `netMs`, `grossMs`, `breakMs`, `breaks[]`. All three are functions of `segments` (P1). Net = Σ(to−from). Gross = last.to − first.from. Break time = gross − net. Break intervals = the complement.
**Rejected alternative:** storing `breaks[]` plus a gross window. Equivalent in information, but it makes net a subtraction across two independently-editable lists, and any inconsistency between them is unresolvable. Segments cannot be internally inconsistent.

Precedence when both are present: `declaredMs` wins for totals; `segments` still drive per-line attribution, scaled by `declaredMs / Σsegments`. This precedence is code, not data, so it can be corrected later.

**The distinction that matters most:** `time` absent means the scribe recorded no time. `{"kind":"declared","declaredMs":0}` means he asserted zero. The first is excluded from every time-based average. The second is included and drags it down. They are different facts and the format keeps them apart for ever. (P4)

### 2.8 `marks` — live line-by-line tracking

```json
[{"at":"2026-07-30T19:23:00.000+03:00","pos":["page",6,"line",1]}]
```

Semantics: *at time `at`, the scribe was about to begin `pos`.* The last mark is the frontier — the first line **not** written. This makes every interval closed-open and removes all off-by-one arguments.

Stored, not derived: these are sensor readings. **Not stored:** per-line durations, which are `netBetween(mark[i].at, mark[i+1].at)` — a subtraction against the segment set, so breaks are excluded automatically and correctly, and a bug in that subtraction is fixable across all history.

On devices that only detect unit crossings, there are 3–4 marks. On devices that track every line, there are as many marks as lines. Same field, no schema difference, and a record made on the coarse device is never mistaken for one that has finer data — it simply has fewer marks.

### 2.9 `items` — what was written

```json
[{"at":["page",5],"lines":{"from":30,"to":42}},
 {"at":["page",6]},
 {"at":["set",2,"head","kadesh"],"lines":{"from":1,"to":3},"rewrite":true}]
```

| Field | Type | Opt | Class | Meaning |
|---|---|---|---|---|
| `at` | address | no | RAW | Where. |
| `lines` | `{from:int,to:int}` | yes | RAW | 1-based inclusive. **Absent means "the whole of that unit, whatever the geometry says it is".** |
| `rewrite` | bool | yes | RAW | Tri-state. Absent = not asserted (the engine infers correction by address overlap). `true`/`false` = the scribe asserted it. |
| `note` | str | yes | RAW | |

Two deliberate decisions:

**Absent `lines` is late binding, and that is a feature.** If the scribe says "I finished page 6", the honest record is "the whole of page 6". If the geometry is later corrected from 42 to 43 lines, that record correctly becomes 43 lines. If instead he said "lines 30 to 42", that span is an assertion and stays 30–42 whatever happens to the geometry. The UI must write whichever the scribe actually said.

**One item per addressed unit. No `count` shorthand.** "3 mezuzot" is three items, addressing mezuza 7, 8 and 9. The addresses are proposed by the app and become raw input the moment the scribe accepts them.
*Rejected alternative:* `{"at":["mezuza"],"n":3}` with no indices. It is 60 bytes cheaper and it destroys the ability to tell a correction from new work, so "what remains" can go negative and progress can exceed 100%. Correctness beats compactness. The cost is real — a 40-page range costs ~2 KB — and at a few thousand records a year it is irrelevant.

For a future kind with genuinely unaddressable units, `geometry` gets a node with `count` and no `lines`, and items address it by index the same way. There is no second mechanism.

### 2.10 `expense`

| Field | Type | Opt | Class | Meaning |
|---|---|---|---|---|
| `label` | str | no | RAW | What was bought. |
| `amount` | money | no | RAW | |
| `paidOn` | day | yes | RAW | Absent = date unknown; such an expense counts towards totals but not towards any period. |
| `paidAt` | instant | yes | RAW | If a precise time is known. |
| `vendor` | str | yes | RAW | |
| `charge` | object | no | RAW | How it is attributed. Tagged union: |

```json
{"mode":"commissions","commissionIds":["c-a","c-b"],"split":"even"}
{"mode":"period","from":{"cal":"hebrew","y":5786,"m":"IYAR","d":1},
                 "to":{"cal":"hebrew","y":5786,"m":"AV","d":29},
                 "spread":"per-working-day"}
{"mode":"month","cal":"hebrew"}
```

`spread` ∈ `per-day` | `per-working-day` | `per-hour-written`.
`mode:"month"` requires `cal`, because a Hebrew month and a Gregorian month are different windows and the scribe means one of them.

**Never stored:** the per-commission share, the per-day slice, the monthly amortisation. `split:"even"` is the *rule*; 2400 ÷ 2 is arithmetic. If a weighted split is added later, it is a new `split` value, and every historical even split still recomputes correctly.

### 2.11 `quote`

| Field | Type | Opt | Class | Meaning |
|---|---|---|---|---|
| `kind`, `geometry` | | no | RAW | The job being quoted, same shapes as a commission. |
| `basis` | object | no | RAW | Inputs to the suggestion: `{"targetHourlyRate":{"value":"120","currency":"ILS"},"marginPct":"15","materialPerUnit":{…},"paceSource":"last-90-working-days"}`. |
| `quotedAmount` | money | yes | RAW | **The number actually given to the customer.** |
| `quotedOn` | day | yes | RAW | |
| `outcome` | str | yes | RAW | `pending` \| `accepted` \| `declined`. |
| `commissionId` | uuid | yes | RAW | Set when accepted. |

This is the sharpest illustration of P1. The *suggested* price is never stored — it must recompute if the pace model or the profit formula is fixed. The *quoted* price is stored, because "I told this customer 42,000 on 3 Iyar" is a historical fact about a conversation, not a calculation. The two live in different fields and the UI shows both, side by side, including how far the suggestion has drifted since.

### 2.12 `settings` (singleton, `id: "settings"`)

| Field | Type | Opt | Class | Meaning |
|---|---|---|---|---|
| `dayBoundary` | object | no | RAW | Current rule; same shape as `dayRule` minus `settingStamp`. Copied onto each new timed record. |
| `defaultPlace` | object | yes | RAW | |
| `workCalendar` | object | no | RAW | `{"weekdayMask":[true,true,true,true,true,false,false],"shabbat":false,"yomTov":false,"cholHamoed":true,"choleHamoedHours":"half","fasts":false,"erevPesach":false,"purim":false,"tishaBav":false,"beinKesehLeAsor":true,"erevYomTov":"half"}` |
| `vacations` | map uuid→`{from:day,to:day,reason:str}` | yes | RAW | Individual known non-working stretches. |
| `dailyTargetLines` | int | yes | RAW | |
| `displayCalendar` | str | no | RAW | `hebrew` \| `gregorian` \| `both`. Display only. |
| `currency` | str | no | RAW | Default for new documents. |
| `firstDayOfWeek`, `locale`, … | | | RAW | |

**`workCalendar` is not snapshotted onto work records, and that is a considered decision.** Under P3: the day-boundary rule decides *which day a record is attached to* — changing it retroactively would re-file facts, so it is snapshotted. The working-day calendar decides only *the denominator of an average*. If the scribe corrects "actually I never work on chol hamoed", the honest answer is that his historical output-per-working-day was always computed against the wrong denominator and should now be right. A specific day he did not work for a specific reason is a *fact*, and that goes in `vacations` with dates.

The honest cost: historical averages shift when he edits the calendar. The UI must show the calendar version alongside any long-run average so this is never a surprise.

### 2.13 `device`

`{"id":…,"type":"device","shortId":"9f2c1ab40e77","label":"טלפון","firstSeenAt":…,"lastExportAt":…,"clockSkewMsObserved":…}`

Exists so that a stamp's 12-hex short id can be resolved to a human-readable device, and so clock skew can be surfaced rather than silently absorbed.

---

## 3. Identity, time and merging

### 3.1 Stamps — hybrid logical clock

```
001785489262418-00007-9f2c1ab40e77
└─ 15-digit ms ┘ └ 5 ┘ └ 12 hex device ┘
```

Zero-padded so that **lexical string comparison is the total order**. Comparison is: millis, then counter, then device short id. Total, deterministic, no ties.

Local rule on any write:
```
now = wallClockMs()
if now > lastMs: lastMs = now; counter = 0
else:            counter += 1
```
On import: `lastMs = max(lastMs, wallClockMs(), maxRemoteMs)`, counter reset if it advanced. This is a standard HLC; it guarantees that anything a device saw before writing sorts before what it writes.

Why not a vector clock: it would let us distinguish "concurrent" from "sequential" instead of guessing, but it costs a per-device entry on every field of every record, and this app has two or three devices and a human who can adjudicate. Named as a rejected alternative in §7.

### 3.2 Identity

- Every document has a UUIDv4 `id`. **v4, not v7**, deliberately: v7 embeds a timestamp, and the moment an id looks sortable somebody will sort by it, and device clocks here are not trustworthy. Ids are opaque (P1 applies to ids too — a date must not be recoverable from an id, because then it is stored twice).
- Ids are never reused. Splitting one record into two mints two new ids and tombstones the original, with `derivedFrom` on both.

### 3.3 Deletion

`_del` is an ordinary LWW register with its own stamp in `_s["_del"]`. It is compared **only against its own previous value**, never against other fields.

Therefore:
- Device A deletes at stamp S1. Device B, not knowing, edits `items` at S2 > S1. Merged: `_del: true` and B's `items`. The record stays deleted. **No resurrection** (P7).
- Undelete is an explicit act: write `_del: false` at a new stamp. B's edit is then revealed intact — nothing was lost while the record was dead.
- Tombstones are retained for ever. With a few thousand records over years and no server to negotiate a safe collection horizon, garbage-collecting them is a way to resurrect records and nothing else. Cost noted in §8.

### 3.4 Merge

Import file R into local store L. For every document id in R:

1. Not in L → insert whole, including every unknown field and unknown `_s` entry.
2. In L → merge field-by-field over the **union** of keys in both:
   - `stampOf(doc, key) = doc._s[key] ?? doc._c`
   - Take the side with the greater stamp. Equal stamps ⇒ equal values (same device, same counter), so either.
   - This includes keys the reader has never heard of. Unknown fields merge by exactly the same rule; no domain knowledge is required. (P8)
3. Nested id-keyed maps (`priceTerms`, `vacations`) merge recursively with their own per-entry stamps and their own `_del`.
4. Atomic fields (`items`, `marks`, `time`, `geometry`) merge as one indivisible value. A half-merged line range would describe work that never happened.
5. When a merge discards a value that *differs* from the winner, the loser is appended to `_x.conflicts[key]` with its stamp, capped at 8 entries per key, oldest evicted. The UI surfaces a conflict badge. Storage cost is negligible; the alternative is a silently lost evening's work.
6. `_del` handled per §3.3.
7. Advance the local HLC past every stamp seen.

Properties: LWW over a total order is commutative, associative and idempotent, so the merge is **order-independent and deterministic**, and importing the same file twice is a no-op. Two devices that exchange files in any order and any number of times converge to byte-identical state.

### 3.5 The round-trip rule for the envelope

The exported `formatMinor` is `max(this build's minor, highestMinorEverImported)`, where `highestMinorEverImported` is kept in the local store.

Without this rule, the phone → old desktop → phone trip loses nothing *inside* documents but makes the returning file *claim* to be old, and the phone would then run a forward migration over data that is already migrated. With it, an old desktop honestly reports "this file contains 1.7-era data that I preserved but did not understand".

---

## 4. Versioning and unknown data

### 4.1 File layout — NDJSON

```
<line 1>   envelope
<line 2…n> one document per line
<line n+1> footer
```

Envelope:

```json
{"format":"sofer-stam-data","formatMajor":1,"formatMinor":0,"minReaderMajor":1,"exportedAt":"2026-07-31T09:14:22.418+03:00","exportedHlc":"001785489262418-00007-9f2c1ab40e77","generator":{"app":"sofer","build":"2026.07.3","platform":"android","deviceId":"9f2c1ab4-0e77-4a51-b3d1-6c1f2a884e10"},"devices":{"9f2c1ab40e77":"9f2c1ab4-0e77-4a51-b3d1-6c1f2a884e10","41d0e9c7a2b1":"41d0e9c7-a2b1-4c33-9f00-2d55e1c4b7a9"}}
```

Footer:

```json
{"_end":true,"count":1482,"sha256":"3f9c…"}
```

Why line-oriented rather than one pretty-printed JSON object: a truncated or corrupted file loses the affected lines, not the file. Import in recovery mode keeps every line that parses and reports the rest by line number, which a human can then repair in any text editor. The app also offers a *pretty* export (a JSON array, indented) for hand repair; import sniffs the first non-whitespace character (`{` on line 1 with `"format"` ⇒ NDJSON, `[` ⇒ pretty) and accepts both.

Key order within a document is stable — `id`, `type`, domain fields in declared order, then `_`-prefixed metadata last — so that diffing two exports in a text tool is useful.

### 4.2 Version semantics

- **`formatMajor`** — incompatible restructuring. A reader whose major < `minReaderMajor` **refuses to import** and says which app version is needed. It does not attempt a partial read, because a partial read of restructured data is how records get destroyed.
- **`formatMinor`** — purely additive: new fields, new document types, new enum values, new `geometry` schemas. Older readers open the file.
- **`_req` capability tokens** — per document. A reader that meets `minReaderMajor` but sees an unknown token in `_req` must: store the document, display it, export it, and mark every headline figure it feeds as *incomplete on this device* (P9). It must not compute a profit number it cannot vouch for.

### 4.3 What an older build does with fields it has never heard of

Mechanically, and this is the whole of it:

1. Parse each line into a `Map<String,dynamic>`.
2. Project the known fields into the typed Dart model. **Keep the full raw map** on the model as `_raw`.
3. Persist the raw map, unchanged, as the KV value. The typed model is a *view*; the raw map is the record.
4. On any edit, patch the raw map for the changed keys only, set `_s[key]`, and re-serialise the raw map. Every unknown key, and every `_s` entry for an unknown key, survives byte-identical.
5. On merge, §3.4 step 2 handles unknown keys with no domain knowledge at all.
6. On export, emit raw maps.

The invariant to test in CI: *import a file, change one unrelated field, export — the diff must touch exactly that field, its stamp, and the envelope.* Run it against a fixture file full of synthetic future fields.

Unknown **document types** are stored in the same KV space with their type token intact; they are merged and re-exported, and simply never rendered.

### 4.4 Migration forward

Migrations are pure functions `minor n → minor n+1`, run at import and at load, in order, idempotent.

The hard rule: **a migration may never lose information.** If a migration cannot be expressed losslessly, it writes the pre-migration value into `_x.legacy.<field>` before overwriting. Example: if `time.declaredMs` were ever replaced by a richer structure, the original integer stays in `_x.legacy.time`. This is what makes it safe to ship a migration that later turns out to have been wrong — the input is still there and a corrective migration can run.

Migrations never touch stamps. A migration is not a user edit and must not win a merge against a peer's genuine edit.

---

## 5. Worked examples

Shown pretty-printed for readability; on disk each document is one line.

### 5.0 Context: the commission

```json
{
  "id": "b1a4c8e2-3f70-4d19-9c22-7e5a0d61f4aa",
  "type": "commission",
  "kind": "sefer-torah",
  "title": "ספר תורה — משפחת לוי",
  "status": "active",
  "startedOn": {"cal": "hebrew", "y": 5786, "m": "IYAR", "d": 3},
  "geometry": {
    "schema": "nested.v1",
    "root": {"token": "page", "count": 245, "lines": 42,
             "linesOverride": {"223": 70}, "priceable": true,
             "label": {"he": "עמוד", "en": "page"}}
  },
  "priceTerms": {
    "0c7b1f2a-9d44-4a10-8c5e-1b2f3a4d5e60":
      {"unit": "page", "amount": "350.00", "currency": "ILS", "effectiveFrom": null},
    "5e8d2c31-77b0-4f92-a1d3-9c0e4b6a2f18":
      {"unit": "page", "amount": "390.00", "currency": "ILS",
       "effectiveFrom": {"cal": "hebrew", "y": 5786, "m": "TAMUZ", "d": 1},
       "note": "עודכן לאחר שדרוג הכתב"}
  },
  "materialCostTerms": {
    "a3f0d5b6-2e11-4c88-b7a9-0d1e2f3a4b5c":
      {"unit": "page", "amount": "48.00", "currency": "ILS", "effectiveFrom": null}
  },
  "_c": "001785401110000-00001-9f2c1ab40e77",
  "_s": {"priceTerms.5e8d2c31-77b0-4f92-a1d3-9c0e4b6a2f18":
         "001785466200000-00000-41d0e9c7a2b1"}
}
```

### (a) A measured 2-hour sitting crossing pages 5, 6 and 7

The scribe started at page 5 line 30, took a 15-minute break, and stopped at page 7 line 12. The device tracks unit crossings.

```json
{
  "id": "d4e5f601-8a2b-4c3d-9e0f-1a2b3c4d5e6f",
  "type": "work",
  "commissionId": "b1a4c8e2-3f70-4d19-9c22-7e5a0d61f4aa",
  "dating": "instant",
  "startedAt": "2026-07-30T19:00:00.000+03:00",
  "endedAt":   "2026-07-30T21:15:00.000+03:00",
  "dayRule": {
    "mode": "nightfall",
    "algo": "tzeit_8p5deg",
    "tz": "Asia/Jerusalem",
    "place": {"lat": 31.7683, "lon": 35.2137, "elevM": 754, "label": "ירושלים"},
    "settingStamp": "001785401111000-00002-9f2c1ab40e77"
  },
  "time": {
    "kind": "segments",
    "source": "timer",
    "segments": [
      {"from": "2026-07-30T19:00:00.000+03:00", "to": "2026-07-30T20:10:00.000+03:00"},
      {"from": "2026-07-30T20:25:00.000+03:00", "to": "2026-07-30T21:15:00.000+03:00"}
    ]
  },
  "marks": [
    {"at": "2026-07-30T19:00:00.000+03:00", "pos": ["page", 5, "line", 30]},
    {"at": "2026-07-30T19:23:00.000+03:00", "pos": ["page", 6, "line", 1]},
    {"at": "2026-07-30T20:53:00.000+03:00", "pos": ["page", 7, "line", 1]},
    {"at": "2026-07-30T21:15:00.000+03:00", "pos": ["page", 7, "line", 13]}
  ],
  "items": [
    {"at": ["page", 5], "lines": {"from": 30, "to": 42}},
    {"at": ["page", 6], "lines": {"from": 1,  "to": 42}},
    {"at": ["page", 7], "lines": {"from": 1,  "to": 12}}
  ],
  "enteredAt": "2026-07-30T21:15:41.000+03:00",
  "_req": ["work.marks.v1"],
  "_c": "001785484541000-00000-9f2c1ab40e77"
}
```

Note what is **not** here: no `netMs` (= 7,200,000, derived), no `grossMs` (= 8,100,000), no break list (the 20:10→20:25 gap), no per-page minutes, no Hebrew date, no line count (67), no earned amount. All of it recomputes in §6.

The last mark points at line 13 — the first line *not* written — which is why `items` ends at 12 with no ambiguity.

### (b) Typed in, date but no hours, 3 mezuzot

```json
{
  "id": "77c1b2a3-4d5e-4f60-8a9b-0c1d2e3f4a5b",
  "type": "work",
  "commissionId": "9d3e5f71-2a4b-4c6d-8e0f-1a2b3c4d5e60",
  "dating": "asserted",
  "day": {"cal": "hebrew", "y": 5786, "m": "AV", "d": 12},
  "items": [
    {"at": ["mezuza", 7]},
    {"at": ["mezuza", 8]},
    {"at": ["mezuza", 9]}
  ],
  "enteredAt": "2026-08-01T22:40:12.000+03:00",
  "_c": "001785620412000-00001-41d0e9c7a2b1"
}
```

There is **no `time` key at all**. That is the point: this record contributes 66 lines to output and contributes *nothing whatsoever* to any average-minutes-per-line, not even a zero. There is also no `dayRule`, because the day was asserted, not computed — a rule would be meaningless here and its presence would be a bug.

`lines` is absent on every item: he finished three whole mezuzot. If the geometry is later corrected from 22 lines to 21, this record correctly becomes 63 lines.

### (c) Backlog, no date

```json
{
  "id": "1f2e3d4c-5b6a-4978-8695-a4b3c2d1e0f9",
  "type": "work",
  "commissionId": "b1a4c8e2-3f70-4d19-9c22-7e5a0d61f4aa",
  "dating": "backlog",
  "items": [
    {"at": ["page", 1]},
    {"at": ["page", 2]},
    {"at": ["page", 3]}
  ],
  "note": "נכתב לפני התקנת האפליקציה",
  "enteredAt": "2026-05-12T09:02:33.000+03:00",
  "_c": "001778000553000-00000-9f2c1ab40e77"
}
```

No `day`, no `dayRule`, no `time`. `dating:"backlog"` is the explicit statement that the absence is permanent and intentional, so a validator does not flag it as a dated record with a lost date.

### (d) An expense split across two commissions

```json
{
  "id": "6a7b8c9d-0e1f-4a2b-9c3d-4e5f6a7b8c9d",
  "type": "expense",
  "label": "קלף — 30 יריעות",
  "amount": {"value": "2400.00", "currency": "ILS"},
  "paidOn": {"cal": "gregorian", "date": "2026-06-18"},
  "vendor": "קלפי מהדרין",
  "charge": {
    "mode": "commissions",
    "commissionIds": ["b1a4c8e2-3f70-4d19-9c22-7e5a0d61f4aa",
                      "9d3e5f71-2a4b-4c6d-8e0f-1a2b3c4d5e60"],
    "split": "even"
  },
  "_c": "001781000000000-00000-41d0e9c7a2b1"
}
```

The number `1200.00` appears nowhere. `split:"even"` plus a list of length 2 is the assertion; the division is arithmetic. When weighted splits are added, `split` gains a value and this record still divides evenly for ever.

### (e) A tombstone, for completeness

```json
{
  "id": "d4e5f601-8a2b-4c3d-9e0f-1a2b3c4d5e6f",
  "type": "work",
  "commissionId": "b1a4c8e2-3f70-4d19-9c22-7e5a0d61f4aa",
  "dating": "instant",
  "items": [{"at": ["page", 5], "lines": {"from": 30, "to": 42}}],
  "_del": true,
  "_c": "001785484541000-00000-9f2c1ab40e77",
  "_s": {"_del": "001785900000000-00003-41d0e9c7a2b1"}
}
```

Full content is retained, not blanked. A deleted record can be inspected and undeleted.

---

## 6. The re-derivation algorithm

Everything below runs from stored data only. Nothing here is ever written back to the file.

### 6.1 Primitives

**`linesOf(item, geometry)`**
```
if item.lines != null: return item.lines.to - item.lines.from + 1   // assert to >= from >= 1
node = resolve(geometry, item.at)                                   // must be a leaf
return node.linesOverride[lastKey(item.at)] ?? node.lines
```

**`addressesOf(item, geometry)`** — the set of canonical line keys, one string per line:
`"page/5#30" … "page/5#42"`, `"set/2/head/kadesh#1"`. Canonical form: segments joined by `/`, then `#`, then the 1-based line number.

**`coverage(commission)`** = the **union** of `addressesOf` over the items of every live, non-tombstoned work record of that commission, backlog included. Union, so a rewrite of a line already written is idempotent and cannot inflate progress.

**`labour(recordSet)`** = Σ over items of `linesOf` — a **multiset** sum, so rewrites *do* count. Rewriting 12 lines was 12 lines of work.

Two different numbers, both real, both reported, neither stored:
- `linesCovered` — how much of the scroll exists. Drives progress and money.
- `linesWritten` — how much writing was done. Drives output, pace and averages.

**`net(time)`**
```
if time == null:                    return ABSENT   // not zero. ABSENT.
if time.declaredMs != null:         return time.declaredMs
return Σ over segments of (to - from)
```

**`netAt(time, t)`** — net writing milliseconds elapsed from the record's start up to instant `t`:
```
Σ over segments of max(0, min(t, seg.to) - seg.from)
```
scaled by `declaredMs / Σsegments` if both are present.

### 6.2 The day of a record

```
dating == "backlog"  → NO DAY
dating == "asserted" → day (converted to Hebrew if asserted Gregorian)
dating == "instant"  → hebrewDayOf(civilDayOf(startedAt, dayRule))
```

`civilDayOf(t, rule)`:
- `midnight` → the civil date of `t` in `rule.tz`.
- `custom` → the civil date of `t − rule.offsetMinutes` in `rule.tz`.
- `sunset` / `nightfall` → let `e = eventTime(rule.algo, rule.place, civilDate(t))`. If `t ≥ e`, the Hebrew day has already rolled over, so the answer is `civilDate(t) + 1 day`; otherwise `civilDate(t)`.

Then `hebrewDayOf` converts the civil date to the Hebrew date whose daytime falls on it.

The **start** instant anchors the record. Example (a) starts at 19:00, before nightfall in Jerusalem in late Tammuz, and so files under the Hebrew day whose daytime is 2026-07-30, even though it ran past nightfall.

That choice is a *calculation*, not data — and because `segments` and `marks` are stored, a future build could instead split the sitting at the boundary and attribute 19:00–20:10 to one Hebrew day and 20:25–21:15 to the next, retroactively, across all history, without a single stored record changing. That is the whole point of the design.

### 6.3 Attributing one record's time across its items

For record `r` with items `i₁…i_k` and `T = net(r.time)`:

- **`T == ABSENT`** → every item gets ABSENT. Not zero. Propagate the absence all the way to the top.
- **`r.attribution` present** → the user chose; honour it. `{"policy":"explicit","perItem":[…ms…]}` makes those raw inputs.
- **`marks` present and covering the items** → *exact*:
  ```
  for each consecutive pair (mᵢ, mᵢ₊₁):
      Δ = netAt(r.time, mᵢ₊₁.at) - netAt(r.time, mᵢ.at)
      assign Δ to the lines in [mᵢ.pos, mᵢ₊₁.pos)   // half-open, by address order
  item time = Σ of the Δ falling inside that item
  ```
  Break time is excluded automatically, because `netAt` only counts inside segments.
- **otherwise** → `policy: proportional-lines`, the current default:
  ```
  timeᵢ = T × linesOf(iᵢ) / Σⱼ linesOf(iⱼ)
  ```
  Rounding: compute in exact milliseconds, floor each, then hand the remainder to the largest item, so Σ timeᵢ == T exactly.

Worked on example (a): segments give 70 + 50 = 120 min net.
`netAt(19:23) = 23 min`; `netAt(20:53) = 70 + 28 = 98 min`; `netAt(21:15) = 120 min`.
- page 5, lines 30–42 (13 lines): 23 − 0 = **23 min** → 1.77 min/line
- page 6, lines 1–42 (42 lines): 98 − 23 = **75 min** → 1.79 min/line
- page 7, lines 1–12 (12 lines): 120 − 98 = **22 min** → 1.83 min/line

Sum 120 min. The 15-minute break appears in none of them. Had `marks` been absent, proportional-lines would have given 23.28 / 75.22 / 21.49 — close, and honestly labelled as an estimate.

### 6.4 Headline figures

**Total written.** `linesWritten = labour(all live records of the commission)`. `linesCovered = |coverage|`. In units: `unitsCovered = Σ over leaf units of coveredLines(u)/totalLines(u)` — a fractional count, so "213.4 of 245 pages" is honest. Remaining = `totalLines(geometry) − linesCovered`, where `totalLines` sums leaves with their overrides.

**Progress.** `linesCovered / totalLines(geometry)`. Bounded to [0,1] by construction, because coverage is a union over addresses that exist in the geometry. Addresses that no longer exist (geometry shrank) are counted separately and reported as **orphans**, never dropped.

**Output per day.** Group live records by §6.2 day; backlog records belong to no day and are excluded here. `output(d) = labour(records of day d)`.

**Output per working day**, over a window:
```
workedLines   = Σ output(d) for d in window
workingDays   = |{ d in window : isWorkingDay(d, settings.workCalendar, settings.vacations) }|
activeDays    = |{ d in window : output(d) > 0 }|
paceOverCalendar   = workedLines / workingDays
paceOverActiveDays = workedLines / activeDays
```
`isWorkingDay` consults the Hebrew calendar: Shabbat, yom tov, chol hamoed, fasts, the days between Yom Kippur and Sukkot, erev Pesach, Purim, Tisha B'Av — each toggled by `workCalendar`, then minus `vacations`. Both figures are shown; neither is stored. Denominator ≤ 0 → the figure is unavailable, not zero.

**Average time per line.** Numerator and denominator must come from *the same record set*:
```
R = { live records where net(time) != ABSENT }
avgMsPerLine = Σ_{r∈R} net(r.time) / Σ_{r∈R} labour(r)
coverage     = Σ_{r∈R} labour(r) / Σ_{all live r} labour(r)
```
The `coverage` fraction is displayed next to the average. A scribe who timed 4% of his work is told the average rests on 4%. Per unit type: the same, restricted to records whose items sit under a given geometry token. Per-line for a *specific* line requires `marks` and is available only where they exist.

**Revenue for a commission.** Walk live records in day order (backlog first, then by day). Maintain the coverage set incrementally. For each record, for each item, for each address newly added to coverage:
```
u        = the priceable ancestor unit of that address
price(u) = the priceTerm whose effectiveFrom is the latest ≤ this record's day
                                       (null effectiveFrom = from the beginning)
earned  += price(u).amount / totalLines(u)
```
So revenue is recognised pro rata by line, at the price in force on the day that line was written. Re-written lines earn nothing extra — they add no new address.

**Backlog records earn nothing**, per the brief: their addresses enter coverage (so progress is right) but contribute zero revenue. This is a *policy in code*, not in data. Flagged honestly: on a scroll half-written before the app existed, this understates revenue badly, and the UI must say so. Because the policy is code, the day the scribe wants backlog priced, one function changes and all history recomputes.

**Costs.**
```
estimatedMaterials = same walk, using materialCostTerms
actualExpenses(commission, window) = Σ over live expenses of share(expense, commission, window)
```
`share` by `charge.mode`:
- `commissions` → `amount / len(commissionIds)` if this commission is in the list, placed on `paidOn`.
- `period` → per `spread`:
  - `per-day` → `amount / daysIn(from..to)` on each day in the window
  - `per-working-day` → `amount / workingDaysIn(from..to)` on each working day
  - `per-hour-written` → `amount × hoursThatDay / totalHoursIn(from..to)`; if `totalHours == 0` fall back to `per-day` **and flag the fallback** rather than dividing by zero
  Then, for a per-commission view, split each day's slice across the commissions worked that day in proportion to that day's lines on each.
- `month` → the whole amount to the Hebrew or Gregorian month of `paidOn`, per `charge.cal`.

**Real material cost per unit** = `actualExpenses attributable to materials / unitsCovered`. Compared side by side with the estimate from `materialCostTerms`. The estimate is never overwritten by the actual — they are different facts.

**Profit** over a window = `revenue − estimatedMaterials(or actualExpenses, per the report's mode) − otherAttributedExpenses`. Never both material estimates and material expenses in the same total; the report picks one mode and names it.

**Profit per hour.**
```
hours = Σ net(r.time) over live, dated records in the window where time != ABSENT
if hours == 0: unavailable        // NOT infinity, NOT zero
profitPerHour = profit / hours
hoursKnownFraction = labour(records with time) / labour(all records in window)
```
The fraction is always displayed. A profit-per-hour resting on a fifth of the work is a different claim from one resting on all of it.

**Projected completion.**
```
remaining = totalLines(geometry) - linesCovered
window    = the last 30 working days that contain any dated work
pace      = labour(dated records in window) / workingDaysIn(window)
if pace <= 0: no projection
d = today; left = remaining
while left > 0:
    d = d + 1 Hebrew day
    if isWorkingDay(d): left -= pace
projected = d
```
Optionally a range, by re-running with the 25th and 75th percentiles of daily output instead of the mean. Uses only dated records — backlog has no date and would corrupt the pace.

**Quote suggestion.**
```
hoursPerUnit  = avgMsPerLine × linesPerUnit(quote.geometry) / 3_600_000
suggested     = units × (hoursPerUnit × basis.targetHourlyRate + basis.materialPerUnit)
                × (1 + basis.marginPct/100)
```
Never stored. Shown alongside `quotedAmount` (which *is* stored) so the drift between what he charges and what his own numbers say is visible.

---

## 7. What this survives

**Absorbed without touching any existing byte:**

1. **New kinds of work** — megillot, ketubot, batim, anything. A new `kind` token and a `geometry` value. No calculation branches on `kind`.
2. **New geometry shapes** — `nested.v2` ships beside `nested.v1`; existing commissions keep v1 and stay correct.
3. **Per-city sunset for scribes abroad** — `dayRule.place` is already on every timed record. Records written before the feature carry the home coordinates, which is exactly what they meant.
4. **Fixing a bug in the nightfall computation** — days across all history correct themselves, because the day was never stored.
5. **Changing the day-boundary opinion** — a new `algo` token for new records; old records keep theirs and do not move.
6. **Changing the day-boundary setting** — new records get the new rule, old records keep the snapshot. No silent re-filing.
7. **Fixing the profit formula, the pace model, the attribution policy, the expense spread** — all derivation, all retroactive. This is the requirement the whole design is built around.
8. **Splitting a sitting across the day boundary** — the segments and marks are already stored; a future build can do it retroactively.
9. **Splitting or combining records** — new ids, `derivedFrom` lineage, tombstones on the originals. Reversible.
10. **A device that gains line-level tracking** — more `marks`, same field, and older records are simply coarser rather than wrong.
11. **Price renegotiation, multi-currency, dated material costs** — id-keyed dated terms.
12. **New expense attribution modes, weighted splits** — new enum values; existing records keep their meaning.
13. **New settings** — added to the settings document; merge handles them; old builds preserve them.
14. **Importing the same file twice, or in a loop** — idempotent.
15. **A scribe correcting his geometry** — progress denominators recompute; records with explicit spans keep their assertions; orphaned addresses are reported, not deleted.
16. **Backlog becoming payable** — a policy change in code.
17. **A whole new document type** — old builds carry it through untouched.

**What it does not survive, honestly:**

1. **A badly wrong device clock.** HLC ordering degrades to "the device furthest in the future wins every conflict" until its clock is corrected. Mitigations: `device.clockSkewMsObserved` is recorded at every import, skew beyond a threshold raises a warning, and `_x.conflicts` retains the losing values so a human can adjudicate. **Rejected alternative:** vector clocks, which would correctly detect concurrency instead of guessing. Rejected because they cost a per-device entry on every field of every document, and this deployment has two or three devices and a human who can decide. This is the design's weakest joint and it is a deliberate trade.
2. **Concurrent edits to the same atomic field.** If both devices retype the `items` of one record, one loses. It is retained in `_x.conflicts` and flagged, but it is not auto-merged, and it cannot be — a line range merged half-and-half would describe work that never happened.
3. **Tombstones are permanent.** At thousands of records that is nothing. At a million it would matter, and there is no server to negotiate a safe collection horizon, so the alternative is worse.
4. **An older build cannot compute new semantics.** It preserves and displays; it refuses to total. That is a UX cost, not data loss, and it is the correct trade against silently wrong money.
5. **A `formatMajor` bump locks out old builds entirely.** By design — a partial read of restructured data destroys records.
6. **Geometry revisions are not yet versioned over time.** If a scribe genuinely re-cuts a scroll mid-job, records with explicit spans point at a shape that no longer exists. The format can absorb the fix (turn `geometry` into an id-keyed map of dated revisions, exactly like `priceTerms`) but v1.0 does not, and until then orphaned addresses are reported rather than silently dropped.
7. **Hand repair can break stamps.** Import validates stamp syntax and, in recovery mode, assigns a fresh local stamp to any malformed one, reporting each. That is a resolution, not a guarantee: a repaired document can lose a merge it should have won.
8. **No encryption, no integrity signature.** The footer's SHA-256 detects damage, not tampering. Out of scope, and it stays out of scope while the file must remain hand-editable.

---

## 8. Cost

**Storage.** A typed work record with 3 items and no timing: ~280 bytes. The measured sitting in example (a), with 4 marks: ~1,050 bytes. A record with per-line marks over 40 lines: ~2,800 bytes. Metadata (`_c`, sparse `_s`, `_req`) adds 60–200 bytes per document; `_s` is usually absent, because unedited fields inherit `_c` — that single decision removes roughly two thirds of the stamp overhead.

At 3,000 work records, 40 commissions and 400 expenses, a realistic export is **2–4 MB** of plain NDJSON, roughly 350–600 KB gzipped. Plain is the default because hand-repairability was a stated requirement; a `.json.gz` export is offered for transfer over a small channel. For a decade of one scribe's work this is negligible on any device that runs Flutter.

The two places compactness was deliberately spent:
- One item per unit (no `count` shorthand): ~50 bytes × the number of units. A 40-page catch-up entry costs ~2 KB instead of ~300 bytes. Bought: correction and rewrite tracking that cannot go wrong.
- Marks on line-tracking devices: ~70 bytes per line. Bought: exact per-line timing and exact cross-page attribution, plus the ability to re-attribute retroactively under a future policy.

**Write amplification.** One document per KV key, so editing one field rewrites one document — a few hundred bytes, O(1) in the size of the database. Export rewrites the whole file, but the whole file is small and export is a deliberate user action. **Rejected alternative:** one JSON blob for everything, which makes every edit an O(n) rewrite and turns any interrupted write into total loss.

**Complexity.** Honestly accounted:
- The CRDT document layer (HLC, stamps, per-field merge, absorbing delete, unknown-field retention): ~700–900 lines of Dart, written once, then boring.
- The geometry interpreter (resolve, expand, count, canonicalise addresses): ~300 lines.
- The derivation engine: the largest piece, and growing. **That is intentional.** The design moves complexity out of the file and into code, because code is what can be fixed. A simpler file with precomputed totals would be less code and would reproduce the bug that motivated this whole exercise.
- Per-field authoring cost: every new field needs a stamp-aware accessor. Mitigate with code generation from a single schema declaration; without it, hand-written accessors are where the round-trip guarantee will eventually be broken.
- The CI test that must never be allowed to fail: *import a fixture full of synthetic future fields, edit one known field, export, diff.* The diff must touch exactly that field, its stamp, and the envelope. If that test is green, requirement 2 holds. If it is deleted, this design's most important property dies silently.

**Runtime.** Full re-derivation over 3,000 records is a few million operations — single-digit milliseconds in Dart. Derived views are memoised in a disposable KV namespace keyed by `calcEpoch`, which is bumped in the source whenever any derivation changes. The memo is never written to the export file (P11), so a stale cache can never masquerade as data.
