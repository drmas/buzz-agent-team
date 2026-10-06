## Show proof when you report work

Whenever you report that you built, fixed or changed something (a feature, a bug fix, UI, an
API, a script, a PR), test it yourself and attach proof to that same message: screenshots of the
test you actually ran. The people reading the chat validate your work from them. Work reported
without proof counts as not done. Screenshots are enough: a video is never required.

Capture it with `proof` (on your PATH; full usage: `sed -n 2,30p "$(command -v proof)"`):

- **UI or user flow**: run the real flow with captioned steps, covering the acceptance criteria.
  `proof steps` screenshots the page at the end of every step and puts them all on one
  storyboard image, so a reader can follow the flow from a single attachment:

  ```
  proof steps http://localhost:3000 --script /workspace/proof/flow.mjs --out /workspace/proof/flow.png
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

### Video: only when stills can't show it

A video takes far more memory than screenshots and can push your container out of memory, which
kills your work in progress. Record one only when it is really needed:

- the thing to verify is motion or timing that screenshots can't show (an animation or
  transition, drag and drop, live or streaming updates, a flicker or race you fixed), or
- a person explicitly asked for a video.

Otherwise use `proof steps`. When you do record:

- One video at a time. `proof video` waits while another one is recording in your container, so
  never record from parallel workers or subagents: record once, yourself, at the end.
- Free memory first: stop e2e runs, extra dev servers and browsers you no longer need. `proof
  video` refuses to start when too little memory is free; then use `proof steps` instead.
- Keep it short: record only the moment that needs motion (under 30 s; it stops at 60 s), and
  attach the storyboard alongside it.

  ```
  proof video http://localhost:3000 --script /workspace/proof/drag.mjs --out /workspace/proof/drag.mp4
  ```

### Rules

- Look at every capture before sending it (open the PNG; for a video, check the `step` lines
  and the `page problems` it printed). It must show what you claim, not a blank page, an error,
  a login screen or a stale build. If `proof` reports a failure, fix it or report the failure.
- Never stage or fake proof: no mock data presented as real, no screenshots of a different
  build. If part of it can't be tested here (needs production, credentials or a device), say
  exactly what you couldn't verify.
- Attach the files to the message that reports the work, in the thread you were asked in:
  `buzz messages send --channel <UUID> --reply-to <event ID> --file flow.png --file settings.png --content "…"`
  (for an agent, `handoff --file …`). In the text, say what you tested and what each file shows.
- When you open a PR, list in its description what you tested and how.
- When you hand work to another agent, make proof part of "done", and ask for screenshots, not
  a video, unless motion is the point. When you review work that comes without proof, ask for it.
