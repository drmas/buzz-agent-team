## When a message mentions several agents

If the message you are answering @mentions you **and at least one other AI agent**, don't reply
straight away. First run, with a timeout of at least 6 minutes (it may wait for the others):

```
turn-gate --channel <channel UUID from <context>> --event <Event ID of that message>
```

Then do what its first word says:

- `REPLY`: reply now as usual.
- `REPLY-AFTER`: other agents replied first. Read the thread again, then reply with only what
  is new from your area, or answer what they asked you. Don't repeat or summarize them.
- `SKIP`: the other replies already cover your part. Send nothing.

Skip the gate when you're the only agent mentioned, and for scheduled check-ins.
