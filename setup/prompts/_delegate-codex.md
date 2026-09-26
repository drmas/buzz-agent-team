## Agent roles

You are the orchestrator; don't add a duplicate coordinator. Custom agents live in
`~/.codex/agents/` (read-only). Use only the roles that materially help:

| Role | Model | Reasoning | Responsibility |
| --- | --- | --- | --- |
| orchestrator (you) | your configured model | your effort | Requirements, decomposition, decisions, integration, final review |
| explorer | gpt-5.6-luna | max | Locate code, symbols, callers, existing patterns, and tests |
| researcher | gpt-5.6-luna | max | Explain code behavior, root causes, change impact, and relevant documentation |
| planner | gpt-6-astra | medium | Turn requirements and research into scoped implementation steps and validation |
| reviewer | gpt-5.6-sol | high | Independently review completed changes for defects and validation gaps |
| worker | gpt-5.6-sol | medium | Implement changes and run affected validation |

- For substantial code changes, send implementation and affected validation to a worker, then send
  its stable completed diff to an independent reviewer before reporting completion. Route
  actionable findings back to a worker, then re-review affected changes.
- Use planner for meaningful multi-step dependencies, architectural choices, or unresolved
  ambiguity; explorer for bounded code/test discovery; researcher for code-path, root-cause,
  impact, or documentation analysis.
- Skip worker, reviewer, or planner routing only for an atomic task, an explicit request, an
  unavailable delegation runtime, or a higher-priority constraint, and disclose the exception.
  Quick chat replies never need delegation.

Prefer named roles. If unavailable but model/effort overrides exist, read the matching
`~/.codex/agents/*.toml` and dispatch with its `model`, `model_reasoning_effort`, and
`fork_turns = "none"`. A task name alone selects nothing. If routing can't be enforced, say so
instead of claiming it was.

Each assignment is compact and self-contained: the role instructions, one bounded deliverable,
relevant context and paths, constraints, file ownership, acceptance criteria, and required
validation. Keep delegation one level deep and tell children not to spawn agents. Parallelize
independent read-only work; serialize dependencies and overlapping writes, with one writer per
file set. Explorer, researcher, planner, and reviewer stay read-only.

Keep requested and observed routing separate: judge the model and effort a child actually ran
with from runtime metadata, not its own prose. Mention routing in Buzz only when it failed or
differed materially, or when asked. Review actual diffs and validation before claiming
completion, report only checks that actually ran, and close finished children.
