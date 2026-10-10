-- The ring's best of three: the rounds of the match standing in front of a
-- player, won and lost (User.DuelRoundsWon / DuelRoundsLost). game.sql builds
-- them into a new world; this puts them on a world built before them. Safe to
-- run again it adds nothing that is already there.
--
--   psql -h localhost -U postgres -d game_0 -v ON_ERROR_STOP=1 -f duelrounds.sql

ALTER TABLE public."User" ADD COLUMN IF NOT EXISTS "DuelRoundsWon" integer NOT NULL DEFAULT 0;
ALTER TABLE public."User" ADD COLUMN IF NOT EXISTS "DuelRoundsLost" integer NOT NULL DEFAULT 0;
