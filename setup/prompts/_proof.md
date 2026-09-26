## Show proof when you report work

Whenever you report that you built, fixed or changed something (a feature, a bug fix, UI, an
API, a script, a PR), test it yourself and attach proof to that same message: a screenshot or a
short video of the test you actually ran. The people reading the chat validate your work from
it. Work reported without proof counts as not done.

Capture it with `proof` (on your PATH; full usage: `sed -n 2,25p "$(command -v proof)"`):

- **UI or user flow**: record the real flow with captioned steps, covering the acceptance
  criteria, then a screenshot of the end state:

  ```
  proof video http://localhost:3000 --script /workspace/proof/flow.mjs --out /workspace/proof/demo.mp4
  proof shot  http://localhost:3000/settings --full --out /workspace/proof/settings.png
  ```

  `flow.mjs` exports `default async ({ page, step, snap }) => { await step('Open settings'); … }`
  (`page` is a Playwright page; `step` shows a caption; `snap(name)` saves an extra screenshot).
- **Backend, API, CLI or library**: screenshot of the tests or requests you ran, output included:

  ```
  proof term --title "API: create invoice" -- 'npm test -- invoices && curl -s localhost:8080/invoices/42'
  ```

- **Bug fix**: show the failing case before the fix and the same case passing after it, when
  you can reproduce it.

Rules:

- Look at every capture before sending it (open the PNG; for a video, check the `step` lines
  and the `page problems` it printed). It must show what you claim, not a blank page, an error,
  a login screen or a stale build. If `proof` reports a failure, fix it or report the failure.
- Never stage or fake proof: no mock data presented as real, no screenshots of a different
  build. If part of it can't be tested here (needs production, credentials or a device), say
  exactly what you couldn't verify.
- Attach the files to the message that reports the work, in the thread you were asked in:
  `buzz messages send --channel <UUID> --reply-to <event ID> --file demo.mp4 --file settings.png --content "…"`
  (for an agent, `handoff --file …`). In the text, say what you tested and what each file shows.
  Buzz takes images and MP4 video; keep videos under a minute.
- When you open a PR, list in its description what you tested and how.
- When you hand work to another agent, make proof part of "done". When you review work that
  comes without proof, ask for it.
