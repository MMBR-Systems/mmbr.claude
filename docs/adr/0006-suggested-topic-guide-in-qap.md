# Suggested Topic guided-response lives in the QAP agent prompt, not the frontend

When a user clicks a Suggested Topic pill, the frontend only attaches `source: "suggested_topic"` to the chat POST; the BFF forwards it, and the **QAP agent** has a prompt branch that skips retrieval and returns a guide (acknowledge the category, list 3-5 sub-areas, offer 2-3 example questions, no citations). Kellen's feedback was that a pill's first response should help narrow the question, not retrieve "AI mumbo jumbo." Hardcoding per-pill copy on the frontend was rejected (we don't own the MBR domain taxonomy for all pills, and it's the wrong layer); wrapping a prompt string as the `message` was rejected (the scaffolding text would show as the user's own bubble); a parallel `displayText` field was inferior once a 2-repo change was already accepted. Flagging the click keeps the frontend dumb, the pill label shows naturally, and adding a 6th pill needs zero code change.

## Consequences

Touches two repos (`web-platform` + `ai-platform`) and needs coordination; until the QAP side ships the flag is a harmless no-op. A small `source` API contract now exists — each new `source` value needs a matching agent branch. Reviewers should flag any future attempt to hardcode plant-specific taxonomy on the frontend as a violation. Status: planned, tracked in MMBR-209.
