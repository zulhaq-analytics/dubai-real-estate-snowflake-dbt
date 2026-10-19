"""Dubai Property Advisor: Streamlit app (release 6a: chat).

The agent answers from Dubai Land Department open data, refreshed daily by the Oracle Cloud
pipeline. Every figure comes from read-only tools; answers containing a figure that cannot be
traced to the data are flagged.
"""
import streamlit as st

import agent

MAX_QUESTIONS_PER_VISITOR = 10
EXAMPLES = [
    "I have AED 1.5 million for a 1-bedroom apartment to rent out. Where are yields highest?",
    "How have prices and rents moved in JVC?",
    "Compare 2-bedroom apartments in Dubai Marina and Business Bay.",
]

st.set_page_config(page_title="Dubai Property Advisor", page_icon="🏙️", layout="centered")


@st.cache_resource(ttl=6 * 3600, show_spinner="Loading the latest Dubai Land Department data…")
def get_advisor():
    return agent.Advisor(api_key=st.secrets["GEMINI_API_KEY"], data_url=st.secrets["DATA_URL"])


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

clicked = None
if not state.messages:
    st.write("**Try one of these:**")
    for i, example in enumerate(EXAMPLES):
        if st.button(example, key=f"example_{i}", use_container_width=True):
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
        with st.spinner("Checking the data…"):
            try:
                result = advisor.ask(prompt, history=state.history)
                answer, note = result["answer"], ""
                state.history = result["history"]
                state.asked += 1
                if result["unverified_numbers"]:
                    note = ("⚠️ Some figures in this answer could not be matched to the data: "
                            + ", ".join(result["unverified_numbers"]) + ". Please treat them with caution.")
            except Exception:
                answer = "The AI service is busy right now. Please try again in a minute."
                note = ""
        st.markdown(answer)
        if note:
            st.caption(note)
    state.messages.append({"role": "assistant", "content": answer, "note": note})

st.divider()
st.caption("Source: Dubai Land Department open data (Dubai Data). Independent project, not affiliated with "
           "or endorsed by Dubai Land Department. Built by Zia Malik.")