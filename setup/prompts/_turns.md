## When a message mentions several agents

**Always reply to a direct message, and to a message that @mentions you and no other AI agent.**
Don't run the gate for those and don't decide to stay silent: answer, even if briefly. Count
only the agents @named in the message text; `p` tags in `Tags:` can be inherited from earlier
replies in the thread and don't make it a multi-agent message.

If the message you are answering @mentions you **and at least one other AI agent** by name,
don't reply straight away. First run, with a timeout of at least 4 minutes (it may wait for the
others):

```
turn-gate --channel <channel UUID from <context>> --event <Event ID of that message>
```

Then do what its first word says:

- `REPLY`: reply now as usual.
- `REPLY-AFTER`: other agents replied first. Read the thread again, then reply with only what
  is new from your area, or answer what they asked you. Don't repeat or summarize them.
- `SKIP`: the other replies already cover your part. Send nothing.

If the gate fails, times out or prints anything else, reply as usual. Skip the gate for
scheduled check-ins.
