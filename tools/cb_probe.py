"""Structure-only probe of the College Board SAT question bank API.
Prints headers, counts, keys and tag statistics. Never prints question text."""
import json, re, collections, urllib.request, urllib.error

API = "https://qbank-api.collegeboard.org/msreportingquestionbank-prod/questionbank"
ORIGIN = "https://austinadd.github.io"
H = ("access-control-allow-origin", "access-control-allow-methods", "access-control-allow-headers", "content-type", "cache-control")

def call(url, payload=None, method=None, extra=None):
    hdr = {"Origin": ORIGIN}
    body = None
    if payload is not None:
        hdr["Content-Type"] = "application/json"
        body = json.dumps(payload).encode()
    if extra: hdr.update(extra)
    r = urllib.request.Request(url, data=body, headers=hdr, method=method or ("POST" if body else "GET"))
    try:
        with urllib.request.urlopen(r, timeout=60) as resp:
            raw = resp.read()
            hs = {k.lower(): v for k, v in resp.headers.items()}
            return resp.status, hs, raw
    except urllib.error.HTTPError as e:
        return e.code, {k.lower(): v for k, v in e.headers.items()}, e.read()

def show_headers(label, hs):
    print(label, {k: hs.get(k) for k in H})

# 1. CORS preflight for the two POST endpoints
for ep in ("/digital/get-questions", "/digital/get-question"):
    st, hs, _ = call(API + ep, method="OPTIONS", extra={"Access-Control-Request-Method": "POST", "Access-Control-Request-Headers": "content-type"})
    show_headers("PREFLIGHT %s status=%s" % (ep, st), hs)

tags = collections.Counter(); classes = collections.Counter(); attrs = collections.Counter(); imgsrc = collections.Counter()
def scan(html):
    for t in re.findall(r"<\s*([a-zA-Z][\w:-]*)", html or ""): tags[t.lower()] += 1
    for c in re.findall(r'class="([^"]*)"', html or ""):
        for x in c.split(): classes[x] += 1
    for a in re.findall(r"\s([a-zA-Z][\w:-]*)=", html or ""): attrs[a.lower()] += 1
    for s in re.findall(r'<img[^>]*\ssrc="([^"]{0,40})', html or ""): imgsrc[s[:30]] += 1

stubs_by = {}
for test, dom in ((1, "INI,CAS,EOI,SEC"), (2, "H,P,Q,S")):
    st, hs, raw = call(API + "/digital/get-questions", {"asmtEventId": 99, "test": test, "domain": dom})
    show_headers("LIST test=%d status=%s bytes=%d" % (test, st, len(raw)), hs)
    rows = json.loads(raw)
    stubs_by[test] = rows
    print("  count", len(rows), "type", type(rows).__name__)
    print("  keys", sorted(rows[0].keys()))
    print("  sample meta", {k: rows[0].get(k) for k in ("questionId", "skill_cd", "difficulty", "score_band_range_cd", "primary_class_cd", "program", "updateDate", "createDate")})
    print("  external_id vs ibn", sum(1 for r in rows if r.get("external_id")), sum(1 for r in rows if r.get("ibn")))
    print("  difficulty", collections.Counter(r.get("difficulty") for r in rows))
    print("  domains", sorted(collections.Counter((r.get("primary_class_cd"), r.get("primary_class_cd_desc")) for r in rows).items()))
    for (cd, desc), n in sorted(collections.Counter((r.get("skill_cd"), r.get("skill_desc")) for r in rows).items()):
        print("    skill %r %r %d" % (cd, desc, n))

st, hs, raw = call(API + "/lookup")
show_headers("LOOKUP status=%s" % st, hs)
lk = json.loads(raw)
print("  lookup keys", sorted(lk.keys()) if isinstance(lk, dict) else type(lk))
live = {}
for k in ("readingLiveItems", "mathLiveItems"):
    v = lk.get(k) if isinstance(lk, dict) else None
    print("  ", k, type(v).__name__, len(v) if v else 0, (v[:1] if v else None))
    live[k] = set(v or [])
for test, k in ((1, "readingLiveItems"), (2, "mathLiveItems")):
    ext = [r for r in stubs_by[test] if r.get("external_id")]
    print("  test", test, "ext in live list", sum(1 for r in ext if r["external_id"] in live[k]), "of", len(ext))

types = collections.Counter(); spr_shapes = collections.Counter(); opt_keys = collections.Counter(); resp_keys = collections.Counter()
def detail(r):
    st, hs, raw = call(API + "/digital/get-question", {"external_id": r["external_id"]})
    return st, hs, json.loads(raw)
picked = [r for r in stubs_by[1] if r.get("external_id")][::97][:12] + [r for r in stubs_by[2] if r.get("external_id")][::61][:20]
first = True
for r in picked:
    st, hs, d = detail(r)
    if first:
        show_headers("DETAIL status=%s" % st, hs); first = False
    if isinstance(d, list):
        print("  detail returned list len", len(d)); d = d[0] if d else {}
    resp_keys.update(d.keys())
    types[d.get("type")] += 1
    for o in d.get("answerOptions") or []: opt_keys.update(o.keys())
    if d.get("type") == "spr":
        ca = d.get("correct_answer") or []
        spr_shapes[tuple(sorted(set(re.sub(r"\d+", "9", str(a)) for a in ca)))] += 1
    for f in ("stem", "stimulus", "rationale"):
        scan(d.get(f))
    for o in d.get("answerOptions") or []: scan(o.get("content"))
    print("  q", r.get("skill_cd"), r.get("difficulty"), "type", d.get("type"), "lens", {f: len(d.get(f) or "") for f in ("stem", "stimulus", "rationale")},
          "nopt", len(d.get("answerOptions") or []), "ca", (d.get("correct_answer") if d.get("type") == "mcq" else len(d.get("correct_answer") or [])), "keys?", bool(d.get("keys")))
print("DETAIL keys", dict(resp_keys)); print("types", dict(types)); print("option keys", dict(opt_keys)); print("spr answer shapes", dict(spr_shapes))
print("TAGS", tags.most_common(60)); print("CLASSES", classes.most_common(40)); print("ATTRS", attrs.most_common(40)); print("IMG", dict(imgsrc))

ibn = [r for r in stubs_by[2] if r.get("ibn")][:2] + [r for r in stubs_by[1] if r.get("ibn")][:1]
for r in ibn:
    st, hs, raw = call("https://saic.collegeboard.org/disclosed/%s.json" % r["ibn"])
    show_headers("IBN status=%s" % st, hs)
    d = json.loads(raw)
    print("  ibn type", type(d).__name__, len(d) if isinstance(d, list) else "")
    d0 = d[0] if isinstance(d, list) else d
    print("  ibn keys", sorted(d0.keys()), "answer keys", sorted((d0.get("answer") or {}).keys()), "style", (d0.get("answer") or {}).get("style"),
          "choice keys", sorted(((d0.get("answer") or {}).get("choices") or {}).keys()), "has correct", bool((d0.get("answer") or {}).get("correct_choice")))
