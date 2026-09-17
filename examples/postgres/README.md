# Storing events in Postgres

`schema.sql` creates `backhaul.events`: one row per event, deduplicated on
`id`, with the raw payload plus the columns most queries need (`event`, `ts`,
`local_date`, `steps`).

Whatever receives the webhook only has to run one statement per delivery,
with the request body as its parameter:

```sql
SELECT backhaul.ingest($1::jsonb) AS inserted
```

`inserted` is `true` for a new event and null for a repeat delivery. Both are a
success: answer the watch with a 2xx either way. If the statement fails, answer
with a 5xx so the watch keeps the event queued and retries it.

The writer role can insert and nothing else. Set its password out of band,
for example with `\password "backhaul-ingest"` in psql.

Events from builds older than the `local_date` field have it null. Leave it
null rather than deriving it from `ts`: the watch's timezone is not
necessarily yours.
