-- Phase S10 follow-up — daily per-topic triage cron.
--
-- The S10 PR added topic: scoping at runtime (Triage::Claude.run +
-- /triage?topic=) but the cron still produced one cross-topic run
-- per day. The follow-up loops the cron across [nil, 'technology',
-- 'sports'] to persist three rows. The new topic column lets the
-- /triage list view show which scope each row was generated under.
--
-- NULL topic = cross-topic legacy run (the historical default).
ALTER TABLE triages ADD COLUMN topic TEXT;
