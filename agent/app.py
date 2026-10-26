"""Dubai Property Advisor: Streamlit app (releases 6a-6d: chat, evidence and charts, usage protection,
report and About tabs).

The agent answers from Dubai Land Department open data, refreshed daily by the Oracle Cloud
pipeline. Every figure comes from read-only tools; answers containing a figure that cannot be
traced to the data are flagged. Charts are drawn by code from the tool results, never by the AI.
"""
import datetime as dt
import json
import threading
import time
import urllib.request
import uuid
from collections import deque

import altair as alt
import pandas as pd
import streamlit as st

import agent

APP_VERSION = "2026-10-26 region gate + question log"
MAX_QUESTIONS_PER_VISITOR = 10
REPORT_URL = ("https://app.powerbi.com/view?r=eyJrIjoiN2FkZTRmYTQtOGY3ZC00YjA4LTg5ZTktZTY0MjY3NjVkMTc0IiwidCI6"
              "ImEyYjYxNTdiLWZlM2ItNGRlZi05OTAzLTc4YTRlMmU5NTNhYiJ9")
DATA_URL_PUBLIC = "https://data.dubai/en/entity-list?com_dda_issuingentity_details_issuingEntityIds=62035"
DAILY_QUESTION_CAP = 100      # about 4 Gemini calls per question; the app's key allows 500 calls a day
QUESTIONS_PER_MINUTE = 4      # keeps the whole app under the free limit of 15 calls a minute
QUEUE_WAIT_SECONDS = 45
EXAMPLES = [
    "I have AED 1.5 million for a 1-bedroom apartment to rent out. Where are yields highest?",
    "How have prices and rents moved in JVC?",
    "Compare 2-bedroom apartments in Dubai Marina and Business Bay.",
]
SOURCE_LABELS = {
    "get_segment": "Figures for one area and home type",
    "find_segments": "Ranking of areas within the budget",
    "find_rentals": "Areas within the rent budget",
    "get_area_trend": "Yearly trend for the area",
    "get_market_forecast": "Citywide 12-month forecast",
}

# Google's Gemini API terms: only paid services may be made available to users in the European
# Economic Area, Switzerland or the United Kingdom. This demo runs on the free tier, so visitors whose
# browser time zone is in those regions see example answers only (no live questions), and everyone
# else confirms their location once per visit. Built from tzdata 2026.5 zone.tab (EU and EEA states,
# their EU territories, UK, Switzerland and nearby dependencies, plus legacy aliases).
RESTRICTED_TIMEZONES = {
    "Africa/Ceuta", "America/Cayenne", "America/Guadeloupe", "America/Marigot", "America/Martinique",
    "Arctic/Longyearbyen", "Asia/Famagusta", "Asia/Nicosia", "Atlantic/Azores", "Atlantic/Canary",
    "Atlantic/Faeroe", "Atlantic/Faroe", "Atlantic/Jan_Mayen", "Atlantic/Madeira", "Atlantic/Reykjavik",
    "CET", "EET", "Eire", "Europe/Amsterdam", "Europe/Athens", "Europe/Belfast", "Europe/Berlin",
    "Europe/Bratislava", "Europe/Brussels", "Europe/Bucharest", "Europe/Budapest", "Europe/Busingen",
    "Europe/Copenhagen", "Europe/Dublin", "Europe/Gibraltar", "Europe/Guernsey", "Europe/Helsinki",
    "Europe/Isle_of_Man", "Europe/Jersey", "Europe/Lisbon", "Europe/Ljubljana", "Europe/London",
    "Europe/Luxembourg", "Europe/Madrid", "Europe/Malta", "Europe/Mariehamn", "Europe/Nicosia", "Europe/Oslo",
    "Europe/Paris", "Europe/Prague", "Europe/Riga", "Europe/Rome", "Europe/Sofia", "Europe/Stockholm",
    "Europe/Tallinn", "Europe/Vaduz", "Europe/Vienna", "Europe/Vilnius", "Europe/Warsaw", "Europe/Zagreb",
    "Europe/Zurich", "GB", "GB-Eire", "Iceland", "Indian/Mayotte", "Indian/Reunion", "MET", "Poland",
    "Portugal", "WET",
}
PRIVACY_NOTE = ("Please don't enter personal information. Questions are processed by Google's Gemini API "
                "(free tier), and Google may review them to improve its services. Questions and answers are "
                "saved anonymously (no names or IP addresses) to improve this advisor.")
REGION_REASON = ("This free demo runs on Google's Gemini API free tier, which can't be offered to people in "
                 "the European Economic Area, the UK or Switzerland.")

st.set_page_config(page_title="Dubai Property Advisor", page_icon="🏙️", layout="centered")


# ------------------------------------------------------------------------------------------------
# Shared resources (one copy for all visitors)
# ------------------------------------------------------------------------------------------------
@st.cache_resource(ttl=6 * 3600, show_spinner="Loading the latest Dubai Land Department data…")
def get_advisor():
    return agent.Advisor(api_key=st.secrets["GEMINI_API_KEY"], data_url=st.secrets["DATA_URL"])


@st.cache_resource
def get_gate():
    """Usage counters shared by every visitor: questions today and questions in the last minute."""
    return {"lock": threading.Lock(), "day": None, "count": 0, "recent": deque()}


@st.cache_resource
def get_example_cache():
    """Answers to the example questions, reused by every visitor until the data date changes."""
    return {}


def take_slot(on_wait) -> str:
    """Reserve capacity for one question. Returns 'ok', 'daily_cap' or 'busy'.
    Waits in a short queue when the per-minute limit is reached; on_wait() is called once if so."""
    gate, deadline, waited = get_gate(), time.time() + QUEUE_WAIT_SECONDS, False
    while True:
        with gate["lock"]:
            today = dt.datetime.now(dt.timezone.utc).date()
            if gate["day"] != today:
                gate["day"], gate["count"] = today, 0
            if gate["count"] >= DAILY_QUESTION_CAP:
                return "daily_cap"
            now = time.time()
            while gate["recent"] and now - gate["recent"][0] > 60:
                gate["recent"].popleft()
            if len(gate["recent"]) < QUESTIONS_PER_MINUTE:
                gate["recent"].append(now)
                gate["count"] += 1
                return "ok"
        if time.time() > deadline:
            return "busy"
        if not waited:
            on_wait()
            waited = True
        time.sleep(2)


# ------------------------------------------------------------------------------------------------
# Anonymous question log: one JSON file per event in a private Oracle bucket, through a write-only
# link (it cannot read or list anything). No names or IP addresses. Failures never affect the visitor.
# ------------------------------------------------------------------------------------------------
def _put_log(name: str, record: dict):
    try:
        req = urllib.request.Request(st.secrets["LOG_PAR_URL"] + name, method="PUT",
                                     data=json.dumps(record, ensure_ascii=False, default=str).encode("utf-8"),
                                     headers={"Content-Type": "application/json"})
        urllib.request.urlopen(req, timeout=15).close()
    except Exception as e:
        print(f"LOG WRITE FAILED {name}: {type(e).__name__}: {e}", flush=True)


def log_event(kind: str, record: dict):
    """Write one log record in the background so the visitor never waits for it."""
    now = dt.datetime.now(dt.timezone.utc)
    record = {"type": kind, "time_utc": now.isoformat(timespec="seconds"), "app_version": APP_VERSION, **record}
    name = f"{kind}/{now:%Y/%m/%d}/{now:%H%M%S}_{uuid.uuid4().hex[:8]}.json"
    threading.Thread(target=_put_log, args=(name, record), daemon=True).start()


@st.cache_resource
def get_warmup_state():
    return {"lock": threading.Lock(), "as_of": None}


def warm_examples(advisor):
    """Prepare the example answers once per data date, in the background, so they are ready for every
    visitor (including those who can only read examples). About 12 Gemini calls per data date."""
    state = get_warmup_state()
    with state["lock"]:
        if state["as_of"] == advisor.as_of:
            return
        state["as_of"] = advisor.as_of

    cache = get_example_cache()      # fetched here: background threads have no Streamlit session
    get_gate()

    def run():
        for example in EXAMPLES:
            key = (example, advisor.as_of)
            if key in cache or take_slot(lambda: None) != "ok":
                continue
            try:
                result = advisor.ask(example)
                if not result["unverified_numbers"]:
                    cache[key] = result
            except Exception as e:
                print(f"WARMUP FAILED: {type(e).__name__}: {e}", flush=True)

    threading.Thread(target=run, daemon=True).start()


# ------------------------------------------------------------------------------------------------
# Evidence and charts, built only from tool results
# ------------------------------------------------------------------------------------------------
NAMES = {"area_display_name": "Area", "property_type": "Type", "room_category": "Bedrooms",
         "as_of_date": "Data date", "year": "Year"}


def _pretty(col: str) -> str:
    if col in NAMES:
        return NAMES[col]
    words = col.replace("_pct", " (%)").replace("_aed", " (AED)").replace("_sqft", " sq ft") \
               .replace("_sqm", " sqm").replace("_12m", " (12 months)").replace("_", " ")
    return words[:1].upper() + words[1:]


RENT_FIRST = ["area_display_name", "room_category", "median_annual_rent_aed", "rents_12m",
              "median_rent_per_sqft_aed"]
RANK_FIRST = ["area_display_name", "room_category", "gross_yield_ready_pct", "ready_price_per_sqm_change_pct",
              "median_ready_price_aed", "median_annual_rent_aed", "median_size_all_sales_sqft"]


def _fmt(v):
    if v is None or (isinstance(v, float) and pd.isna(v)):
        return "—"
    if isinstance(v, bool):
        return str(v)
    if isinstance(v, float) and v.is_integer():
        v = int(v)
    if isinstance(v, (int, float)):
        return f"{v:,}"
    return str(v)


def _table(rows: list, first: list = None) -> pd.DataFrame:
    df = pd.DataFrame(rows)
    if first:
        df = df[[c for c in first if c in df.columns] + [c for c in df.columns if c not in first]]
    for c in df.columns:
        df[c] = df[c].astype(object).map(str if c == "year" else _fmt)
    return df.rename(columns={c: _pretty(c) for c in df.columns})


def _visitor_note(note: str) -> str:
    """Tool notes are written for the AI; keep the explanation and drop instructions such as 'Do not…'."""
    kept = [x.strip() for x in note.split(".") if x.strip() and not x.strip().lower().startswith("do not")]
    return (". ".join(kept) + ".").replace("NOT published", "not published")


def _segment_label(r: dict) -> str:
    return f"{r.get('area_display_name', '')} · {r.get('room_category', '')} {r.get('property_type', '').lower()}"


def _ranked_bars(df: pd.DataFrame, key: str, title: str):
    """Horizontal bars, highest first, with full labels and the value printed on each bar."""
    base = alt.Chart(df).encode(
        y=alt.Y("label:N", sort="-x", title=None, axis=alt.Axis(labelLimit=320)),
        x=alt.X(f"{key}:Q", title=title))
    chart = base.mark_bar() + base.mark_text(align="left", dx=4, color="#9aa0a6", fontSize=12).encode(
        text=alt.Text(f"{key}:Q", format=",.2~f"))
    st.altair_chart(chart.properties(height=34 * len(df) + 40), width="stretch")


def _height(rows: int) -> int:
    return 35 * (rows + 1) + 3


def render_visuals(trace: list):
    """Draw charts and an evidence panel from the tools the agent used. Nothing is drawn by the AI."""
    calls = [t for t in trace if t.get("tool") in SOURCE_LABELS and isinstance(t.get("result"), dict)
             and "error" not in t["result"]]
    if not calls:
        return

    segments = [t["result"]["segment"] for t in calls if t["tool"] == "get_segment" and t["result"].get("segment")]
    for t in calls:
        res = t["result"]
        if t["tool"] == "get_area_trend" and res.get("years"):
            df = pd.DataFrame(res["years"])
            df["year"] = df["year"].astype(str)
            df = df.set_index("year")
            st.caption(f"{res.get('area', '')}: median price per sqm, all sales (AED). Latest year is partial.")
            st.line_chart(df[["median_price_per_sqm_aed"]], height=220)
            if df["gross_yield_ready_pct"].notna().any():
                st.caption("Gross yield, ready homes (%)")
                st.line_chart(df[["gross_yield_ready_pct"]], height=200)
        elif t["tool"] == "find_segments" and res.get("results"):
            key = res.get("ranked_by", "")
            df = pd.DataFrame(res["results"])
            if key in df.columns:
                df["label"] = df.apply(_segment_label, axis=1)
                title = ("Gross yield, ready homes (%)" if "yield" in key else
                         "Ready price per sqm change, last 12 months (%) — past performance" if "change" in key else
                         "Median home size, all sales (sqm)")
                st.caption(f"Top results: {title}")
                _ranked_bars(df, key, title)
        elif t["tool"] == "find_rentals" and res.get("results"):
            df = pd.DataFrame(res["results"])
            df["label"] = df.apply(_segment_label, axis=1)
            st.caption("Busiest rental areas within the budget: median yearly rent of new leases (AED)")
            _ranked_bars(df, "median_annual_rent_aed", "Median yearly rent (AED)")
    if 2 <= len(segments) <= 4:
        st.caption("Side by side (medians, last 12 months; — means the sample is too small to publish)")
        for col, seg in zip(st.columns(len(segments)), segments):
            with col:
                st.markdown(f"**{seg.get('area_display_name', '')}**  \n{seg.get('room_category', '')} "
                            f"{seg.get('property_type', '').lower()}")
                y, p = seg.get("gross_yield_ready_pct"), seg.get("median_ready_price_aed")
                st.metric("Gross yield, ready", "—" if y is None else f"{y}%")
                st.metric("Median ready price", "—" if p is None else f"AED {p:,}")

    with st.expander("Show the data behind this answer"):
        for t in calls:
            res = t["result"]
            st.markdown(f"**{SOURCE_LABELS[t['tool']]}**")
            if t["tool"] == "get_segment":
                seg = _table([res["segment"]]).T.rename(columns={0: "Value"})
                st.dataframe(seg, width="stretch", height=_height(len(seg)))
                for n in res.get("notes", []):
                    st.caption(_visitor_note(n))
            elif t["tool"] == "find_segments":
                rows = res.get("results", [])
                st.dataframe(_table(rows, RANK_FIRST), width="stretch", hide_index=True, height=_height(len(rows)))
            elif t["tool"] == "find_rentals":
                rows = res.get("results", [])
                st.dataframe(_table(rows, RENT_FIRST), width="stretch", hide_index=True, height=_height(len(rows)))
            elif t["tool"] == "get_area_trend":
                st.dataframe(_table(res.get("years", [])), width="stretch", hide_index=True)
                st.caption(res.get("note", ""))
            elif t["tool"] == "get_market_forecast":
                rows = []
                for s in res.get("series", []):
                    for h in ("last_actual", "forecast_6m", "forecast_12m"):
                        if s.get(h):
                            rows.append({"series": s["series"], "point": h.replace("_", " "), **s[h]})
                st.dataframe(_table(rows), width="stretch", hide_index=True)
                st.caption(res.get("note", ""))
        st.caption("Medians over the last 12 months to the data date. Source: Dubai Land Department open data.")


def feedback_widget(qid: str):
    """👍/👎 under an answer; each rating is logged once, linked to the question by its id."""
    key = f"fb_{qid}"

    def on_change():
        score = st.session_state.get(key)
        if score is not None:
            log_event("feedback", {"question_id": qid, "session_id": st.session_state.get("session_id"),
                                   "rating": "up" if score == 1 else "down"})

    st.feedback("thumbs", key=key, on_change=on_change)


# ------------------------------------------------------------------------------------------------
# Page
# ------------------------------------------------------------------------------------------------
try:
    advisor = get_advisor()
except Exception:
    st.error("The advisor could not load its data right now. Please try again in a few minutes.")
    st.stop()

st.title("Dubai Property Advisor")
st.caption(f"Answers from Dubai Land Department open data · Data as of {advisor.as_of} · "
           "Information, not financial advice")

tab_ask, tab_report, tab_about = st.tabs(["Ask the advisor", "Explore the report", "About"])

# Footer first in code so it always shows below the tabs, even if the chat stops early.
st.divider()
st.caption(f"Source: [Dubai Land Department open data on Data Dubai]({DATA_URL_PUBLIC}), "
           "used under the Data Dubai Open Data Licence. Independent project, not affiliated with or endorsed "
           "by Dubai Land Department or the Dubai Government. Built by Zia Malik.")

with tab_report:
    st.write("The full 11-page Power BI report on the same data, refreshed every morning.")
    st.iframe(REPORT_URL, height=460)
    st.markdown(f"[Open the report full screen in a new tab]({REPORT_URL})")

with tab_about:
    st.markdown(
        "**What this is.** An AI assistant that answers questions about Dubai's residential property market "
        "from Dubai Land Department open data: prices, rents, yields, trends and where a budget fits.\n\n"
        "**How it works.** The AI never sees the raw data and is not allowed to work out numbers itself. "
        "It can only call read-only tools that look up the data, and it must quote what they return. "
        "Every number in an answer is checked against those results; if a figure cannot be traced, "
        "the AI has to look it up and rewrite the answer. Charts and tables are drawn by code, not by the AI.\n\n"
        "**How it is tested.** 113 test questions, including tricky ones (wrong premises, follow-ups, "
        "Arabic, attempts to make it reveal its instructions, off-topic requests). The latest version "
        "passed all 113.\n\n"
        "**Limits.** Figures are medians for the last 12 months up to the data date, and small samples are "
        "not published. It cannot predict which area's prices will rise. This is information, not financial "
        "advice; please do your own due diligence.\n\n"
        "**Availability.** Live questions are not offered in the European Economic Area, the UK or "
        "Switzerland, because the free tier of Google's Gemini API can't serve those regions. Visitors "
        "there can read the example answers and explore the report.\n\n"
        "**Privacy.** Questions are processed by Google's Gemini API (free tier) and may be reviewed by Google "
        "to improve its services. Questions, answers and 👍/👎 ratings are saved anonymously (no names or IP "
        "addresses) and used only to test and improve this advisor. Please don't enter personal information.\n\n"
        "Built by Zia Malik."
    )

with tab_ask:
    st.info(PRIVACY_NOTE, icon="🔒")

    state = st.session_state
    if "messages" not in state:
        state.messages, state.history, state.asked = [], [], 0
        state.session_id = uuid.uuid4().hex[:12]

    if st.context.timezone in RESTRICTED_TIMEZONES:
        st.warning(REGION_REASON + " You can still read the example answers below and explore the full report "
                   "in the next tab.", icon="🌍")
        examples = get_example_cache()
        for example in EXAMPLES:
            with st.container(border=True):
                st.markdown(f"**{example}**")
                cached = examples.get((example, advisor.as_of))
                if cached:
                    st.markdown(cached["answer"])
                    render_visuals(cached["trace"])
                else:
                    st.caption("This example answer isn't ready yet. Please check back later.")
        st.stop()

    if not state.get("region_ok"):
        st.write(REGION_REASON)
        if st.button("I'm not located in the EEA, the UK or Switzerland. Start", type="primary"):
            state.region_ok = True
            st.rerun()
        st.stop()

    warm_examples(advisor)

    chat_box = st.container()      # messages go here, so new answers appear above the input box
    with chat_box:
        for m in state.messages:
            with st.chat_message(m["role"]):
                st.markdown(m["content"])
                if m.get("note"):
                    st.caption(m["note"])
                if m.get("trace"):
                    render_visuals(m["trace"])
                if m.get("qid"):
                    feedback_widget(m["qid"])

        clicked = None
        if not state.messages:
            st.write("**Try one of these:**")
            for i, example in enumerate(EXAMPLES):
                if st.button(example, key=f"example_{i}", width="stretch"):
                    clicked = example

    prompt = st.chat_input("Ask about Dubai property prices, rents or yields…") or clicked

    if prompt:
        with chat_box:
            if state.asked >= MAX_QUESTIONS_PER_VISITOR:
                st.warning(f"You've reached the limit of {MAX_QUESTIONS_PER_VISITOR} questions for this visit. "
                           "Thanks for trying the advisor!")
                st.stop()

            state.messages.append({"role": "user", "content": prompt})
            with st.chat_message("user"):
                st.markdown(prompt)

            with st.chat_message("assistant"):
                answer, note, trace, outcome = "", "", [], "error"
                qid = uuid.uuid4().hex[:12]
                cache, cache_key = get_example_cache(), (prompt, advisor.as_of)
                result = cache.get(cache_key) if (prompt in EXAMPLES and not state.history) else None

                if result is None:
                    waiting = st.empty()
                    slot = take_slot(lambda: waiting.info("Many people are asking right now. "
                                                          "Your question is in a short queue…", icon="⏳"))
                    waiting.empty()
                    outcome = slot
                    if slot == "daily_cap":
                        answer = ("The advisor has reached its daily limit of free questions. "
                                  "Please come back tomorrow. You can still explore the report tab.")
                    elif slot == "busy":
                        answer = "The advisor is very busy right now. Please try again in a minute."
                    else:
                        with st.spinner("Checking the data…"):
                            try:
                                result = advisor.ask(prompt, history=state.history)
                            except Exception:
                                outcome = "error"
                                answer = ("The AI service is busy right now. Please try again in a minute, "
                                          "or explore the report tab meanwhile.")
                        if result is not None and prompt in EXAMPLES and not state.history \
                                and not result["unverified_numbers"]:
                            cache[cache_key] = result

                elif result is not None:
                    outcome = "cached_example"

                if result is not None:
                    if outcome != "cached_example":
                        outcome = "answered"
                    answer, trace = result["answer"], result["trace"]
                    state.history = result["history"]
                    state.asked += 1
                    if result["unverified_numbers"]:
                        note = ("⚠️ Some figures in this answer could not be matched to the data: "
                                + ", ".join(result["unverified_numbers"]) + ". Please treat them with caution.")

                st.markdown(answer)
                if note:
                    st.caption(note)
                if trace:
                    render_visuals(trace)
                tools_used = [t.get("tool") for t in trace]
                log_event("question", {
                    "question_id": qid, "session_id": state.session_id, "turn": state.asked,
                    "question": prompt, "answer": answer, "outcome": outcome,
                    "tools": [t for t in tools_used if not str(t).startswith("_")],
                    "guardrail": [t for t in tools_used if str(t).startswith("_")],
                    "unverified_numbers": result["unverified_numbers"] if result else [],
                    "steps": result.get("steps") if result else None,
                    "seconds": result.get("seconds") if result else None,
                    "data_as_of": advisor.as_of,
                })
                if result is not None:
                    feedback_widget(qid)
            state.messages.append({"role": "assistant", "content": answer, "note": note, "trace": trace,
                                   "qid": qid if result is not None else None})
