"""Generate the standalone Hebrew help document and proposed import data.

Run: python docs/help/generate.py [--check]
Only FAQ.he.json and FAQ.he.html in this directory are written.
No app assets, configuration, or runtime code are modified.
"""

from __future__ import annotations

import argparse
import html
import json
import re
from pathlib import Path


DIRECTORY = Path(__file__).resolve().parent
TOPICS = [
    ("start", ["התחלה", "הרשמה", "אינטרנט", "מתחילים"]),
    ("projects", ["פרויקט", "הזמנה", "מבנה", "מחיר"]),
    ("timer", ["טיימר", "שעון", "שורה", "הפסקה", "ישיבה"]),
    ("manual", ["הזנה", "ידנית", "תאריך", "שמירה", "טיוטה"]),
    ("paged", ["ספר תורה", "מגילה", "עמוד", "חפיפה"]),
    ("mezuza", ["מזוזה", "מזוזות", "22", "המשך"]),
    ("tefillin", ["תפילין", "פרשייה", "פרשיה", "פרשיות", "ראש", "יד"]),
    ("corrections", ["תיקון", "מחיקה", "פסילה", "נפסל", "סל מחזור"]),
    ("journal", ["יומן", "שבוע", "טבלה", "פרשת השבוע"]),
    ("orders", ["הזמנות", "לקוח", "אספקה", "מסירה", "אימייל"]),
    ("goals", ["יעד", "קצב", "תכנון", "צפי", "סיום"]),
    ("calendar", ["תאריך", "לוח", "יום", "חגים", "חול"]),
    ("money", ["כסף", "כספים", "רווח", "הוצאות", "תשלום", "מטבע"]),
    ("proofreading", ["הגהה", "מגיה", "תיקונים", "כשרות"]),
    ("quotes", ["הצעה", "מחשבון", "מחיר", "רווחיות"]),
    ("reports", ["סיכום", "דוח", "דוחות", "דוח שנתי", "PDF", "Excel", "אקסל"]),
    ("backup", ["גיבוי", "שחזור", "העברה", "סנכרון", "ענן", "JSON"]),
    ("settings", ["הגדרות", "עיצוב", "נגישות", "צליל", "מטרונום", "התראה"]),
    ("desktop", ["מחשב", "Windows", "ווינדוס", "מקלדת", "חלון צף"]),
    ("support", ["תקלה", "תקלות", "שגיאה", "עדכון", "התקנה", "עזרה"]),
]
TOPIC_TITLES = [
    "צעדים ראשונים", "פרויקטים ומרכז הפרויקט", "כתיבה, טיימר והפסקות",
    "הזנה ידנית והשלמת רישומים", "ספר תורה ומגילה", "מזוזות", "תפילין",
    "תיקונים, פסילה וסל המחזור", "יומן כתיבה", "הזמנות ולקוחות",
    "יעדים, קצב ותכנון", "תאריכים וימי עבודה", "רווח, הוצאות, תשלומים ומטבע",
    "מעקב הגהה", "הצעת מחיר והשוואת רווחיות", "סיכומים ודוחות",
    "גיבוי, שחזור והעברה בין מכשירים", "התאמה אישית, צלילים ונגישות",
    "שימוש במחשב וקיצורי מקלדת", "התקנה, עדכון ופתרון תקלות",
]
TOPIC_BY_TITLE = dict(zip(TOPIC_TITLES, TOPICS, strict=True))

RELATED = {
    "start-first-session": ["project-create", "start-modes"],
    "timer-finish-partial": ["timer-two-clocks", "timer-finish-completes", "timer-partial-dates"],
    "timer-forgot-line": ["timer-switch-mode", "manual-page-range"],
    "manual-no-time": ["manual-no-date", "money-hourly"],
    "manual-save-error": ["manual-recovery", "support-storage"],
    "mezuza-double": ["mezuza-manual-partial", "correction-delete-invalid"],
    "tefillin-comparable": ["tefillin-pair-value", "quote-weights"],
    "correction-delete-invalid": ["reports-invalid-time", "correction-restore"],
    "correction-restore": ["correction-bin-limits", "backup-old-delete"],
    "journal-add": ["manual-open", "support-journal-rows"],
    "goals-deadline": ["goals-estimate", "calendar-workdays"],
    "money-profit-vs-payment": ["money-payment-record", "reports-annual-income"],
    "money-double-expense": ["money-expense-allocation", "proofread-cost"],
    "backup-live-enable": ["backup-live-failure", "backup-live-file"],
    "backup-restore": ["backup-merge", "backup-exclusions", "support-backup-unreadable"],
    "backup-merge": ["backup-old-delete", "backup-repeat-import"],
    "backup-transfer": ["backup-exclusions", "backup-sync"],
    "settings-session-target": ["settings-target-sound", "settings-end-time"],
    "support-update": ["backup-manual", "support-android-install"],
    "support-missing-record": ["manual-no-date", "calendar-day-boundary", "correction-restore"],
    "support-report": ["support-version", "backup-private"],
}


def parse_document() -> dict:
    source = (DIRECTORY / "FAQ.he.md").read_text(encoding="utf-8")
    parts = re.split(r"^## (.+)$", source, flags=re.MULTILINE)
    intro_lines = parts[0].strip().splitlines()
    if len(parts[1::2]) != len(TOPICS) or set(parts[1::2]) != set(TOPIC_BY_TITLE):
        raise ValueError("Topic definitions must match the Markdown sections")
    sections = []
    for heading, body in zip(parts[1::2], parts[2::2]):
        topic_id, keywords = TOPIC_BY_TITLE[heading]
        entries = re.split(
            r'^<a id="([a-z][a-z0-9-]+)"></a>\n### ([^\n]+)\n',
            body,
            flags=re.MULTILINE,
        )
        if entries[0].strip() or (len(entries) - 1) % 3:
            raise ValueError(f"Unexpected content in {heading}")
        questions = []
        for at in range(1, len(entries), 3):
            question_id, question, answer = entries[at : at + 3]
            answer = answer.strip()
            if not question.strip() or not answer or "\ufffd" in answer:
                raise ValueError(f"Invalid question or answer: {question_id}")
            platforms = ["android", "windows"]
            if topic_id == "desktop" or question_id == "support-install-windows":
                platforms = ["windows"]
            elif question_id == "support-android-install":
                platforms = ["android"]
            questions.append({
                "id": question_id,
                "question": question.strip(),
                "answerMarkdown": answer,
                "keywords": keywords,
                "platforms": platforms,
                "relatedIds": RELATED.get(question_id, []),
            })
        if not questions:
            raise ValueError(f"Empty section: {heading}")
        sections.append({"id": topic_id, "title": heading.strip(), "questions": questions})

    all_ids = [q["id"] for s in sections for q in s["questions"]]
    if len(all_ids) != len(set(all_ids)):
        raise ValueError("Question IDs must be unique")
    known_ids = set(all_ids)
    if set(RELATED) - known_ids:
        raise ValueError("Related-question map has an unknown source")
    for section in sections:
        for question in section["questions"]:
            if set(question["relatedIds"]) - known_ids:
                raise ValueError(f"Unknown related ID: {question['id']}")
    return {
        "schemaVersion": 1,
        "documentId": "sofer-vmone-help-he",
        "locale": "he",
        "direction": "rtl",
        "title": intro_lines[0].removeprefix("# "),
        "updatedAt": "2026-10-15",
        "appVersion": "0.6.0+7",
        "status": "integrated-as-native-help",
        "releaseStage": "development",
        "introductionMarkdown": "\n".join(intro_lines[1:]).strip(),
        "sections": sections,
    }


def prose(text: str) -> str:
    """Render this document's paragraph/bold subset after escaping all HTML."""
    return "\n".join(
        "<p>" + re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", html.escape(p)) + "</p>"
        for p in text.split("\n\n") if p.strip()
    )


def render_html(document: dict) -> str:
    sections = document["sections"]
    all_questions = {q["id"]: q for s in sections for q in s["questions"]}
    navigation = []
    blocks = []
    for section in sections:
        title = html.escape(section["title"])
        anchor = "topic-" + section["id"]
        navigation.append(f'<a href="#{anchor}">{title}<span>{len(section["questions"])}</span></a>')
        questions = []
        for question in section["questions"]:
            question_id = question["id"]
            related = ""
            if question["relatedIds"]:
                links = "".join(
                    f'<li><a href="#{item}">{html.escape(all_questions[item]["question"])}</a></li>'
                    for item in question["relatedIds"]
                )
                related = f'<aside class="related"><p>שאלות קשורות</p><ul>{links}</ul></aside>'
            tags = html.escape(" ".join(question["keywords"]), quote=True)
            questions.append(
                f'<details id="{question_id}" data-keywords="{tags}">'
                f'<summary>{html.escape(question["question"])}</summary>'
                f'<div class="answer">{prose(question["answerMarkdown"])}{related}</div></details>'
            )
        blocks.append(f'<section class="topic" id="{anchor}"><h2>{title}</h2>{"".join(questions)}</section>')
    template = HTML_TEMPLATE
    substitutions = {
        "TITLE": html.escape(document["title"]),
        "COUNT": str(len(all_questions)),
        "SECTIONS": str(len(sections)),
        "INTRO": prose(document["introductionMarkdown"]),
        "NAV": "\n".join(navigation),
        "BODY": "\n".join(blocks),
    }
    for key, value in substitutions.items():
        template = template.replace("@@" + key + "@@", value)
    if re.search(r"@@[A-Z]+@@", template):
        raise ValueError("Unresolved HTML placeholder")
    return template


HTML_TEMPLATE = r'''<!doctype html>
<html lang="he" dir="rtl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>@@TITLE@@</title>
<style>
:root{color-scheme:light;--ink:#193447;--muted:#526573;--line:#d5dee3;--paper:#fff;--accent:#855814}
*{box-sizing:border-box}html{scroll-padding-top:1rem}body{margin:0;background:#f3f6f7;color:var(--ink);font:17px/1.8 "Segoe UI",Arial,sans-serif}
a{color:#175d86;text-underline-offset:3px}button,input{font:inherit}button{cursor:pointer;border:1px solid #a9bac4;border-radius:8px;background:white;color:var(--ink);padding:7px 15px}
button:hover{background:#ecf3f6}a:focus-visible,button:focus-visible,input:focus-visible,summary:focus-visible{outline:3px solid #ac7722;outline-offset:4px}
.skip{position:absolute;inset-inline-start:12px;top:-80px;background:white;padding:10px;z-index:2}.skip:focus{top:12px}
header{background:var(--ink);color:white;padding:35px max(24px,calc((100vw - 1180px)/2));border-bottom:5px solid #c49956}
.eyebrow{font-size:14px;color:#e8d1ad;margin:0 0 8px}h1{font-size:clamp(27px,4vw,40px);line-height:1.3;margin:0 0 15px;font-weight:650}
header p{margin:8px 0;max-width:900px}header p:not(.eyebrow){font-size:15px;color:#e1e9ee}
.layout{max-width:1228px;margin:28px auto;padding:0 24px;display:grid;grid-template-columns:250px minmax(0,1fr);gap:32px;align-items:start}
nav{position:sticky;top:18px;max-height:calc(100vh - 36px);overflow:auto;background:white;border:1px solid var(--line);border-radius:12px;padding:16px}
nav h2{font-size:18px;margin:0 0 10px}nav a{display:flex;justify-content:space-between;gap:10px;font-size:14px;text-decoration:none;padding:6px 0;border-bottom:1px solid #edf1f3;line-height:1.6}
nav span{color:var(--muted);font-variant-numeric:tabular-nums}main{min-width:0}.controls{background:white;border:1px solid var(--line);border-radius:12px;padding:20px}
label{display:block;font-weight:650;margin-bottom:7px}input{width:100%;min-height:48px;border:1px solid #8fa4b2;border-radius:8px;padding:9px 12px;color:var(--ink);background:white}
.actions{display:flex;flex-wrap:wrap;gap:9px;margin-top:12px}.count{font-size:14px;color:var(--muted);margin:9px 0 0}.topic{margin-top:28px}.topic h2{font-size:23px;margin:0 0 12px}
details{background:var(--paper);border:1px solid var(--line);border-radius:9px;margin:9px 0;overflow:hidden;scroll-margin-top:18px}
summary{cursor:pointer;padding:13px 18px;font-weight:600;line-height:1.7}summary::marker{color:var(--accent)}details[open] summary{border-bottom:1px solid #e5ebee;background:#fafcfd}
.answer{padding:3px 20px 14px}.answer p{margin:12px 0;overflow-wrap:anywhere}.related{border-top:1px solid #e5ebee;margin-top:14px;font-size:14px}.related p{color:var(--muted);margin:8px 0 0}.related ul{padding-inline-start:21px;margin:3px 0}
.empty{background:white;border:1px solid var(--line);padding:24px;border-radius:10px;margin-top:20px}footer{text-align:center;color:var(--muted);font-size:13px;margin:35px 15px}
[hidden]{display:none!important}@media(max-width:900px){.layout{display:block;max-width:760px;padding:0 16px;margin-top:18px}nav{position:static;max-height:220px;margin-bottom:18px}header{padding:26px 20px}.topic h2{font-size:22px}body{font-size:17px}}
@media print{@page{size:A4;margin:16mm}body{background:white;font-size:11pt;line-height:1.6}header{background:white;color:black;padding:0 0 12px;border-bottom:1px solid #888}header p:not(.eyebrow),.eyebrow{color:#333}h1{font-size:24pt}.layout{display:block;margin:0;padding:0}.controls,nav,.skip,.related,footer,.empty{display:none!important}.topic{margin-top:18px}.topic h2{font-size:16pt;break-after:avoid}details{border:0;border-bottom:1px solid #ccc;border-radius:0;break-inside:avoid;margin:8px 0}summary{list-style:none;padding:4px 0;background:none!important;border:0!important}.answer,details:not([open])>.answer{display:block!important;padding:0}details::details-content{display:block;content-visibility:visible}.answer p{margin:3px 0 8px}}
</style>
</head>
<body>
<a class="skip" href="#main">דלג לשאלות ולתשובות</a>
<header>
<p class="eyebrow">@@COUNT@@ שאלות ותשובות · @@SECTIONS@@ נושאים · מסמך עצמאי לקריאה</p>
<h1>@@TITLE@@</h1>
@@INTRO@@
</header>
<div class="layout">
<nav aria-label="נושאי העזרה"><h2>תוכן העניינים</h2>@@NAV@@</nav>
<main id="main">
<div class="controls">
<label for="search">חיפוש בשאלות ובתשובות</label>
<input id="search" type="search" placeholder="למשל: שורה חלקית, גיבוי, רווח לשעה" autocomplete="off">
<div class="actions"><button id="clear" type="button">ניקוי חיפוש</button><button id="expand" type="button">פתיחת כל התשובות</button><button id="collapse" type="button">סגירת כל התשובות</button><button id="print" type="button">הדפסה / PDF</button></div>
<p class="count" id="count" role="status" aria-live="polite">@@COUNT@@ שאלות ב־@@SECTIONS@@ נושאים. ההדפסה כוללת את תוצאות החיפוש.</p>
</div>
<p class="empty" id="empty" hidden>לא נמצאו שאלות מתאימות. נסה מילה קצרה יותר או נקה את החיפוש.</p>
@@BODY@@
</main>
</div>
<footer>המסמך פועל מקומית וללא חיבור לאינטרנט. עדכון תוכן: 08.10.2026.</footer>
<script>
'use strict';
const input = document.getElementById('search');
const questions = [...document.querySelectorAll('details')];
const topics = [...document.querySelectorAll('.topic')];
function normalize(text) {
  return text.toLocaleLowerCase().normalize('NFKD').replace(/[\u0591-\u05c7]/g, '')
    .replace(/["'״׳־–—.,?!():/+-]/g, ' ').replace(/\s+/g, ' ').trim();
}
const searchable = new Map(questions.map(q => [q, normalize(
  q.querySelector('summary').textContent + ' ' +
  [...q.querySelectorAll('.answer > p')].map(p => p.textContent).join(' ') + ' ' + q.dataset.keywords
)]));
function search() {
  const words = normalize(input.value).split(' ').filter(Boolean);
  let count = 0;
  questions.forEach(q => {
    q.hidden = !words.every(word => searchable.get(q).includes(word));
    if (!q.hidden) count++;
  });
  topics.forEach(topic => {
    topic.hidden = ![...topic.querySelectorAll('details')].some(q => !q.hidden);
    const link = document.querySelector('nav a[href="#' + topic.id + '"]');
    link.hidden = topic.hidden;
  });
  document.getElementById('count').textContent = count + ' שאלות מוצגות. ההדפסה כוללת את תוצאות החיפוש.';
  document.getElementById('empty').hidden = count !== 0;
}
input.addEventListener('input', search);
document.getElementById('clear').addEventListener('click', () => { input.value = ''; search(); input.focus(); });
document.getElementById('expand').addEventListener('click', () => questions.filter(q => !q.hidden).forEach(q => q.open = true));
document.getElementById('collapse').addEventListener('click', () => questions.forEach(q => q.open = false));
document.getElementById('print').addEventListener('click', () => window.print());
let printState;
window.addEventListener('beforeprint', () => {
  printState = questions.map(q => q.open);
  questions.filter(q => !q.hidden).forEach(q => q.open = true);
});
window.addEventListener('afterprint', () => {
  if (printState) questions.forEach((q, i) => q.open = printState[i]);
});
function showAnchor() {
  const target = document.getElementById(location.hash.slice(1));
  if (!target || !(target.matches('details') || target.matches('.topic'))) return;
  if (target.hidden) { input.value = ''; search(); }
  if (target.matches('details')) target.open = true;
  target.scrollIntoView();
}
window.addEventListener('hashchange', showAnchor);
showAnchor();
</script>
</body>
</html>
'''


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Verify generated files without writing")
    arguments = parser.parse_args()
    document = parse_document()
    outputs = {
        "FAQ.he.json": json.dumps(document, ensure_ascii=False, indent=2) + "\n",
        "FAQ.he.html": render_html(document),
    }
    for name, content in outputs.items():
        target = DIRECTORY / name
        if arguments.check:
            if not target.exists() or target.read_text(encoding="utf-8") != content:
                raise SystemExit(f"Outdated generated document: {name}")
        else:
            target.write_text(content, encoding="utf-8", newline="\n")
    count = sum(len(section["questions"]) for section in document["sections"])
    print(f"{'Verified' if arguments.check else 'Generated'}: {count} questions, {len(document['sections'])} sections")


if __name__ == "__main__":
    main()
