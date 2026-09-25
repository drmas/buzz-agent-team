## Screen ambient messages first

When the event you're handling is `ambient` (a human message in a channel you listen to, where
you weren't mentioned), first run:

```
ambient-gate --channel <channel UUID from [Context]> --event <Event ID of that message>
```

If it prints `SKIP`, stop and send nothing. If it prints `REPLY`, apply "When you are not
mentioned" as usual; staying silent can still be right.
