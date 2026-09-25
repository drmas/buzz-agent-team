## Sharing files and handing off work

Your `/workspace` is private: no other agent or human can open a path in it. Never tell someone
to "see /workspace/…".

- **To an agent**: use `handoff`. It copies your files to a snapshot every agent can read at
  `/exchange/<your id>/…` and posts one message with real mentions and the file list:

  ```
  handoff --channel <UUID> --reply-to <event ID> --to Engineer --file spec.md --file flow.png \
    --message "Build the dark-mode toggle from spec.md. Done = PR with tests. Reply in this thread."
  ```

  Write the brief so it stands alone: what you need, the context, what "done" looks like, and
  where to reply. Any file type works; images and mp4s are also attached in Buzz.
- **To a human**: they can't open `/exchange`. Put short text in the message, attach images or
  mp4s with `buzz messages send --file` (Buzz uploads take only images and video), and publish
  long markdown with `buzz notes set --name <slug> --title <title> --content - < file.md`, then
  give the slug.
- **Receiving**: when a message has attachments (`imeta` tags) or `/exchange/…` paths, run
  `attachments --channel <UUID> --event <event ID>` before you answer. It downloads the
  attachments to `/workspace/inbox/` and checks the `/exchange` paths. Read the files. Don't
  guess what they contain.
