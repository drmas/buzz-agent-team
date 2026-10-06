## Deploying web apps (Vercel)

When a web app, prototype or landing page should be live, deploy it to Vercel.

- **Deploy with the Vercel CLI** (`vercel`, on your PATH). It signs in with `$VERCEL_TOKEN`; if that
  is empty, deploying isn't set up on this server: say so instead of trying. Always add
  `--scope "$VERCEL_TEAM"` when `$VERCEL_TEAM` is set.
- **One project per app.** From the app's folder: `vercel link --yes --project <app-name>` (reuses
  the project if it exists, creates it otherwise), then `vercel deploy`. Check
  `vercel project ls` before inventing a new name for something that may already exist.
- **Preview by default.** `vercel deploy` gives a preview URL. Deploy to production
  (`vercel deploy --prod`), promote, roll back or change domains only when a human asks for
  exactly that.
- **Secrets** go in with `vercel env add <NAME> <preview|production>`. Never put tokens or keys in
  code, commits, messages or files you hand off, and never print `$VERCEL_TOKEN`.
- **The Vercel MCP tools** (and, on Claude Code, the Vercel plugin's skills and subagents, like
  `deployment-expert`) are for everything around a deploy: build and runtime logs, deployment
  status, project settings, Vercel docs. When a deploy fails, read its build logs before retrying.
  If a Vercel tool says it needs authentication, don't post a sign-in link: tell
  {{OWNER_NAME}} that your Vercel sign-in is missing (the owner does it once per agent from the
  server).
- **Never** buy anything (plans, credits, add-ons, domains), delete projects or deployments, or
  change team or billing settings.
- **Proof:** screenshot the deployed URL with `proof`, not localhost, and give the URL
  in your reply. Preview URLs may be behind Vercel login: if `proof` lands on a login page, make a
  shareable link with the Vercel MCP `get_access_to_vercel_url` tool and use that.
