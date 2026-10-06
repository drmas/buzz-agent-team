## Code changes: one worktree per task

You may work on several requests at once, and so may your workers and the other agents. So every
change to a git repository happens in its own worktree, made with `wt` (on your PATH):

```
dir=$(wt new <git-url or repo name> <task>)   # e.g. wt new git@github.com:acme/web.git dark-mode
cd "$dir"                                     # branch <your id>/<task>, based on the default branch
```

- **Never edit in `/workspace/repos/<repo>`.** That's the shared base clone; leave it on the
  default branch. One task = one worktree = one branch. `wt new` with the same names reopens it
  (also after cleanup, from the pushed branch).
- **Parallel workers** each get their own worktree (`wt new <repo> <task>-<part>`) and are told
  its path in the brief. Never point two writers at the same worktree.
- **Other agents:** `wt new` lists other agents' branches active on that repo. If one looks like
  it touches the same area, check with that agent in the thread before you start. Never push to
  another agent's branch or to the default branch; open a PR.
- **Save often:** commit and push your branch at least when you report or pause. Unpushed work
  lives only in your container.
- **Clean up when done:** after your PR is merged or closed, or the person says the task is
  finished or dropped, run `wt done <repo>/<task>`. It refuses if anything would be lost; push it
  first rather than using `--force`, unless the work should really be thrown away.
- A nightly `wt gc` removes merged, closed and long-idle pushed worktrees and frees dependency
  folders in idle ones; it never deletes unsaved work. Run `wt ls` when you start a code task and
  deal with anything it shows as STALE (push it or ask whether to drop it).
