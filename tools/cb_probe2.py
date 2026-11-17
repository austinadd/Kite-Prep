"""Wider structure-only sample of the College Board bank: which tags, SVG parts, image sources and answer
shapes real questions use. Prints statistics only, never question text."""
import json, re, collections, urllib.request, urllib.error, time
API = "https://qbank-api.collegeboard.org/msreportingquestionbank-prod/questionbank"
def call(url, payload=None):
    hdr = {"Origin": "https://austinadd.github.io"}; body = None
    if payload is not None: hdr["Content-Type"] = "application/json"; body = json.dumps(payload).encode()
    for _ in range(3):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, data=body, headers=hdr, method="POST" if body else "GET"), timeout=60) as r:
                return json.loads(r.read())
        except Exception as e:
            err = e; time.sleep(1)
    raise err
rows = {1: call(API + "/digital/get-questions", {"asmtEventId": 99, "test": 1, "domain": "INI,CAS,EOI,SEC"}),
        2: call(API + "/digital/get-questions", {"asmtEventId": 99, "test": 2, "domain": "H,P,Q,S"})}
tags, svgtags, svgattrs, imgsrc, hrefs, styles, classes, has = (collections.Counter() for _ in range(8))
types, spr, ibnstyle, ibnkey, ibnspr = (collections.Counter() for _ in range(5))
def scan(html, where):
    html = html or ""
    for t in re.findall(r"<\s*([a-zA-Z][\w:-]*)", html): tags[t.lower()] += 1
    for s in re.findall(r"<svg[\s\S]*?</svg>", html):
        has['svg_' + where] += 1
        for t in re.findall(r"<\s*([a-zA-Z][\w:-]*)", s): svgtags[t] += 1
        for a in re.findall(r"\s([a-zA-Z][\w:-]*)=", s): svgattrs[a] += 1
    for s in re.findall(r'<img[^>]*\ssrc="([^"]{0,60})', html): imgsrc[re.sub(r"[A-Za-z0-9+/=]{12,}.*", "…", s)[:48]] += 1
    for s in re.findall(r'\s(?:xlink:)?href="([^"]{0,40})', html): hrefs[s[:24]] += 1
    for s in re.findall(r'style="([^"]{0,80})"', html): styles[re.sub(r"\d+(\.\d+)?", "9", s)[:60]] += 1
    for c in re.findall(r'class="([^"]*)"', html):
        for x in c.split(): classes[x] += 1
    for k in ("table", "figure", "img", "math", "mfenced", "mtable"):
        if "<" + k in html: has[k + "_" + where] += 1
n = 0
ext_m = [r for r in rows[2] if r.get("external_id")][::8]
ibn_m = [r for r in rows[2] if r.get("ibn")][::8]
ext_rw = [r for r in rows[1] if r.get("external_id")][::30]
for r in ext_m + ext_rw:
    d = call(API + "/digital/get-question", {"external_id": r["external_id"]}); n += 1
    if isinstance(d, list): d = d[0]
    types[d.get("type")] += 1
    if d.get("type") == "spr": spr[len(d.get("correct_answer") or [])] += 1
    if d.get("type") == "mcq":
        L = (d.get("correct_answer") or ["?"])[0]
        if L not in "ABCD" or len(d.get("answerOptions") or []) != 4: types["odd_mcq"] += 1
    if r in ext_rw and not (d.get("stimulus") or "").strip(): has["rw_no_stimulus"] += 1
    if r in ext_m and (d.get("stimulus") or "").strip(): has["math_with_stimulus"] += 1
    w = "rw" if r in ext_rw else "m"
    for f in ("stem", "stimulus", "rationale"): scan(d.get(f), w)
    for o in d.get("answerOptions") or []: scan(o.get("content"), w + "opt")
    time.sleep(0.05)
for r in ibn_m:
    d = call("https://saic.collegeboard.org/disclosed/%s.json" % r["ibn"]); n += 1
    d = d[0] if isinstance(d, list) else d
    a = d.get("answer") or {}
    ibnstyle[a.get("style")] += 1; ibnkey[(a.get("style"), bool(a.get("correct_choice")))] += 1
    if not a.get("correct_choice") and a.get("style") != "Multiple Choice":
        t = re.sub(r"<[^>]+>", " ", a.get("rationale") or "")
        m = re.search(r"correct answer is\s*(either\s+)?([-−]?\s*(\d[\d,]*(\.\d+)?|\.\d+)(\s*/\s*\d+)?)", t, re.I)
        ibnspr["regex_ok" if m and not m.group(1) else ("either" if m else "no_match")] += 1
    for f in ("prompt", "body"): scan(d.get(f), "ibn")
    scan(a.get("rationale"), "ibn")
    for c in (a.get("choices") or {}).values(): scan(c.get("body"), "ibnopt")
    time.sleep(0.05)
print("fetched", n, "math ext", len(ext_m), "math ibn", len(ibn_m), "rw", len(ext_rw))
print("types", dict(types)); print("spr answer count", dict(spr))
print("ibn style", dict(ibnstyle)); print("ibn key", dict(ibnkey)); print("ibn spr answer from rationale", dict(ibnspr))
print("HAS", dict(sorted(has.items())))
print("TAGS", tags.most_common(70)); print("SVG TAGS", svgtags.most_common(40)); print("SVG ATTRS", svgattrs.most_common(60))
print("IMG SRC", imgsrc.most_common(20)); print("HREF", hrefs.most_common(20)); print("STYLE", styles.most_common(25)); print("CLASS", classes.most_common(30))
