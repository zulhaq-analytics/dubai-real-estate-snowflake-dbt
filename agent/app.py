"""Dubai Property Advisor: Streamlit app (releases 6a-6c: chat, evidence and charts, usage protection).

The agent answers from Dubai Land Department open data, refreshed daily by the Oracle Cloud
pipeline. Every figure comes from read-only tools; answers containing a figure that cannot be
traced to the data are flagged. Charts are drawn by code from the tool results, never by the AI.
"""
import datetime as dt
import threading
import time
from collections import deque

import pandas as pd
import streamlit as st

import agent

MAX_QUESTIONS_PER_VISITOR = 10
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
    "get_area_trend": "Yearly trend for the area",
    "get_market_forecast": "Citywide 12-month forecast",
}

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
# Evidence and charts, built only from tool results
# ------------------------------------------------------------------------------------------------
def _pretty(col: str) -> str:
    words = col.replace("_pct", " (%)").replace("_aed", " (AED)").replace("_sqft", " sq ft") \
               .replace("_sqm", " sqm").replace("_12m", " (12 months)").replace("_", " ")
    return words[:1].upper() + words[1:]


def _table(rows: list) -> pd.DataFrame:
    df = pd.DataFrame(rows)
    return df.rename(columns={c: _pretty(c) for c in df.columns})


def _visitor_note(note: str) -> str:
    """Tool notes are written for the AI; keep the explanation and drop instructions such as 'Do not…'."""
    kept = [x.strip() for x in note.split(".") if x.strip() and not x.strip().lower().startswith("do not")]
    return (". ".join(kept) + ".").replace("NOT published", "not published")


def _segment_label(r: dict) -> str:
    return f"{r.get('area_display_name', '')} · {r.get('room_category', '')} {r.get('property_type', '').lower()}"


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
                title = "Gross yield, ready homes (%)" if "yield" in key else "Median home size, all sales (sqm)"
                st.caption(f"Top results: {title}")
                st.bar_chart(df.set_index("label")[[key]], height=260)
    if len(segments) >= 2 and any(s.get("gross_yield_ready_pct") is not None for s in segments):
        df = pd.DataFrame(segments)
        df["label"] = df.apply(_segment_label, axis=1)
        st.caption("Gross yield, ready homes (%). Blank means the sample is too small to publish.")
        st.bar_chart(df.set_index("label")[["gross_yield_ready_pct"]], height=220)

    with st.expander("Show the data behind this answer"):
        for t in calls:
            res = t["result"]
            st.markdown(f"**{SOURCE_LABELS[t['tool']]}**")
            if t["tool"] == "get_segment":
                seg = _table([res["segment"]]).T.rename(columns={0: "Value"})
                seg["Value"] = seg["Value"].map(lambda v: "—" if v is None or pd.isna(v) else
                                                (f"{v:,}" if isinstance(v, (int, float)) else str(v)))
                st.dataframe(seg, width="stretch")
                for n in res.get("notes", []):
                    st.caption(_visitor_note(n))
            elif t["tool"] == "find_segments":
                st.dataframe(_table(res.get("results", [])), width="stretch", hide_index=True)
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
st.info("Please don't enter personal information. Questions are processed by Google's Gemini API.", icon="🔒")

state = st.session_state
if "messages" not in state:
    state.messages, state.history, state.asked = [], [], 0

for m in state.messages:
    with st.chat_message(m["role"]):
        st.markdown(m["content"])
        if m.get("note"):
            st.caption(m["note"])
        if m.get("trace"):
            render_visuals(m["trace"])

clicked = None
if not state.messages:
    st.write("**Try one of these:**")
    for i, example in enumerate(EXAMPLES):
        if st.button(example, key=f"example_{i}", width="stretch"):
            clicked = example

prompt = st.chat_input("Ask about Dubai property prices, rents or yields…") or clicked

if prompt:
    if state.asked >= MAX_QUESTIONS_PER_VISITOR:
        st.warning(f"You've reached the limit of {MAX_QUESTIONS_PER_VISITOR} questions for this visit. "
                   "Thanks for trying the advisor!")
        st.stop()

    state.messages.append({"role": "user", "content": prompt})
    with st.chat_message("user"):
        st.markdown(prompt)

    with st.chat_message("assistant"):
        answer, note, trace = "", "", []
        cache, cache_key = get_example_cache(), (prompt, advisor.as_of)
        result = cache.get(cache_key) if (prompt in EXAMPLES and not state.history) else None

        if result is None:
            waiting = st.empty()
            slot = take_slot(lambda: waiting.info("Many people are asking right now. "
                                                  "Your question is in a short queue…", icon="⏳"))
            waiting.empty()
            if slot == "daily_cap":
                answer = ("The advisor has reached its daily limit of free questions. "
                          "Please come back tomorrow.")
            elif slot == "busy":
                answer = "The advisor is very busy right now. Please try again in a minute."
            else:
                with st.spinner("Checking the data…"):
                    try:
                        result = advisor.ask(prompt, history=state.history)
                    except Exception:
                        answer = "The AI service is busy right now. Please try again in a minute."
                if result is not None and prompt in EXAMPLES and not state.history \
                        and not result["unverified_numbers"]:
                    cache[cache_key] = result

        if result is not None:
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
    state.messages.append({"role": "assistant", "content": answer, "note": note, "trace": trace})

st.divider()
st.caption("Source: Dubai Land Department open data (Dubai Data). Independent project, not affiliated with "
           "or endorsed by Dubai Land Department. Built by Zia Malik.")