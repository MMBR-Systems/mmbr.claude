# Harness Engineering

> A beginner-friendly explainer. What it is, why it matters, and when to use it.

> _Also known as **agent orchestration**, **LLM orchestration**, or **AI agent infrastructure**. "Harness Engineering" is a newer term — growing in 2026 but not yet the official/universal name. The concept matters more than the label._

## The one-sentence version

**Harness Engineering = everything around an LLM that helps it actually do the job right.**

The model (Claude, GPT, etc.) is just the "engineer." The harness is the office, the onboarding doc, the code review process, the CI pipeline, the tests, the team conventions — all the stuff that turns a smart person into a productive teammate.

## The analogy

Imagine you hire a brilliant new developer. Day one, you:

- Don't give them a README.
- Don't show them the architecture.
- Don't tell them how tests are run.
- Don't pair them with anyone.
- Just say: "build the new feature."

They'll write *something*. It'll probably compile. But it'll also:

- Ignore your conventions
- Duplicate existing code
- Break things in weird places
- Mark work as "done" when it isn't

That's an LLM agent without a harness. Not dumb — just contextless.

The harness is the onboarding. It's how you turn raw intelligence into a reliable contributor.

## Why "just prompting better" isn't enough

For a small task ("rename this variable"), a good prompt is fine.

For a real feature, or god forbid a whole app, the model hits problems that prompting alone can't fix:

| Problem | What it looks like |
|---|---|
| **One-shot hero** | Tries to build everything in one giant run. Context window overflows. Half-done features everywhere. |
| **Premature victory** | Declares the task "done" without actually testing it. Returns a 200, calls it a day, feature is broken end-to-end. |
| **Session amnesia** | Next session starts from zero. Re-reads the whole codebase, forgets what was decided yesterday, redoes work. |
| **Slop accumulation** | Each session the code gets a little worse. Architecture drifts. Patterns duplicate. In 20 sessions, the codebase is unrecognizable. |
| **Self-judgment bias** | When asked "did you do this right?", it says yes. Agents are bad judges of their own work. |

Harness engineering exists to **design out** these failure modes.

## The two pillars (borrowed from control engineering)

### 1. Feedforward — guide *before* execution

Tell the agent what to do and how, *before* it writes any code.

- Specs (what to build)
- Architecture docs (how things fit)
- Conventions / style guides
- Task breakdowns
- Skills / prompts

Think: **the GPS plotting the route before you drive off.**

### 2. Feedback — correct *after* execution

Observe what actually happened and course-correct.

- Tests (unit, integration, e2e)
- Linters
- Type checkers
- Build step
- Review agents

Think: **the GPS recalculating when you take a wrong turn.**

**You need both.** Specs without tests = plans nobody verifies. Tests without specs = corrections with no destination.

## What a real harness looks like

A harness is **not** just a folder of `.md` files. It's a system. Minimum ingredients:

```
harness/
├── specs/            # what to build (feedforward)
├── architecture/     # how to build it (feedforward)
├── progress/         # what's been done (memory)
├── contracts/        # acceptance criteria per task
├── agents/           # specialized roles (builder, validator)
├── orchestrator/     # runs the build→validate loop
└── sensors/          # tests, lint, typecheck, build
```

The **loop** is the important part:

```
plan → build → validate → pass? → next task
                   ↓ fail
              fix → validate → ...
```

And critically: **the builder and validator are different agents.** Same model, different missions. If you give one agent both jobs, it'll convince itself everything is fine. Separate them, and they keep each other honest.

## Advantages

- **Quality stays consistent** across long projects. Without a harness, quality decays ~5% per feature. Over 100 features, that's catastrophic.
- **Sessions become resumable.** Progress files mean a new session doesn't start from scratch.
- **Work is actually done when it says it's done.** Sensors (tests, linters) decide — not the agent.
- **Scales from features to whole systems.** This is what OpenAI and Anthropic used to generate million-line codebases that actually worked.
- **Humans stay in the loop where it matters** (design, review), out of it where it doesn't (running tests, checking lint).

## Disadvantages

- **Higher token cost.** Separate build + validate agents means 2x+ calls. Not free.
- **Setup overhead.** Building the harness itself takes work. For a weekend project, it's overkill.
- **Rigidity.** A well-tuned harness on project A doesn't transfer cleanly to project B. Every codebase needs its own.
- **Complexity shifts, doesn't disappear.** Bugs move from the code to the harness. Debugging an orchestrator is harder than debugging a prompt.
- **Early-stage tooling.** The ecosystem (LangGraph, CrewAI, OpenDevin, etc.) is still maturing. Expect churn.

## When to use it

**Use a harness when:**

- Building something bigger than a single feature
- Multiple sessions will work on the same codebase
- Quality matters (production code, not throwaway scripts)
- You'll run the agent semi-autonomously

**Skip it when:**

- One-off script or prototype
- You'll manually review every line anyway
- The task fits in one context window with room to spare

## Frameworks and tools to know

| Tool | What it is | Harness fit |
|---|---|---|
| **Spec-driven dev** (e.g. TLC Spec Driven) | Structured specs + task breakdown | Covers feedforward. Partial harness. |
| **LangGraph** | State machines for agent orchestration | Strong fit. Build your own harness on top. |
| **CrewAI** | Multi-agent with roles (dev, reviewer, tester) | Close to harness out of the box. |
| **OpenDevin** | Autonomous software engineer agent | Full harness attempt. Still experimental. |
| **Devin** (closed) | Cognition's commercial agent | The "north star" — full harness, not open source. |
| **QAF** (Qubika) | Our in-house framework | Spec-driven + orchestration + skills + QA sensors. Real harness. |
| **Claude Code** (this tool) | CLI with skills, hooks, subagents | The building blocks for a harness. You assemble it. |

## The one-liner to remember

> The bottleneck is no longer model intelligence. It's the quality of the environment the model operates in.

Build the environment. The model will do the rest.

## Further reading

- Anthropic blog posts on agent failure modes (Feb 2026)
- OpenAI's writeups on large autonomous code generation runs
- Martin Fowler's blog on harness patterns
