-- Where whoever sacked a player came from: the camp's tents or the raider's
-- base, as they stood when the stores came down (Sack.FromX / FromY). game.sql
-- builds them into a new world; this puts them on a world built before them.
-- Rows already filed keep nulls, since where they came from was never kept.
-- Safe to run again it adds nothing that is already there.
--
--   psql -h localhost -U postgres -d game_0 -v ON_ERROR_STOP=1 -f sackorigin.sql

ALTER TABLE public."Sack" ADD COLUMN IF NOT EXISTS "FromX" double precision;
ALTER TABLE public."Sack" ADD COLUMN IF NOT EXISTS "FromY" double precision;
