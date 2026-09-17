-- Event store for Backhaul webhooks. Run once, as a superuser, in the target
-- database. The writer's password is set separately so it never lands in git.
--
-- Role names match the laemmlein deployment: "backhaul-ingest" is the
-- insert-only login n8n uses, "hermes" is the reader.

CREATE ROLE "backhaul-ingest" LOGIN;

CREATE SCHEMA backhaul;

CREATE TABLE backhaul.events (
    id           text        PRIMARY KEY,
    event        text        NOT NULL,
    ts           timestamptz NOT NULL,
    -- The watch's own calendar day. Null for builds that predate the field;
    -- do not derive it from ts, the watch timezone can differ from yours.
    local_date   date,
    utc_offset_s integer,
    steps        integer,
    received_at  timestamptz NOT NULL DEFAULT now(),
    payload      jsonb       NOT NULL
);

CREATE INDEX events_local_date_idx ON backhaul.events (local_date);
CREATE INDEX events_ts_idx         ON backhaul.events (ts);

-- True for a new event, null for a repeat delivery of one already stored.
CREATE FUNCTION backhaul.ingest(p jsonb) RETURNS boolean
LANGUAGE sql AS $$
    INSERT INTO backhaul.events (id, event, ts, local_date, utc_offset_s, steps, payload)
    VALUES (p->>'id',
            p->>'event',
            to_timestamp((p->>'ts')::bigint),
            (p->>'local_date')::date,
            (p->>'utc_offset_s')::integer,
            (p->'health'->>'steps')::integer,
            p)
    ON CONFLICT (id) DO NOTHING
    RETURNING true
$$;

REVOKE ALL ON FUNCTION backhaul.ingest(jsonb) FROM PUBLIC;

GRANT USAGE   ON SCHEMA backhaul                TO "backhaul-ingest", hermes;
GRANT EXECUTE ON FUNCTION backhaul.ingest(jsonb) TO "backhaul-ingest";
GRANT INSERT  ON backhaul.events                TO "backhaul-ingest";
-- ON CONFLICT (id) needs to read the arbiter column, nothing more.
GRANT SELECT (id) ON backhaul.events            TO "backhaul-ingest";
GRANT SELECT  ON backhaul.events                TO hermes;
