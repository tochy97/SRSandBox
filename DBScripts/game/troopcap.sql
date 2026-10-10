-- 150 and five men a level: a camp holds 155 at level 1, 160 at level 2, and
-- 500 at level 70 (Camp.MaxTroopsAt). It was 250 + 20 a level, 1,630 at the
-- top, and for a while five a level, 350 at the top; this brings a world from
-- either to the present rule.
--
-- For a world built before the change, run once against its game database:
--
--   psql -h localhost -U postgres -d game_0 -v ON_ERROR_STOP=1 -f troopcap.sql
--
-- A world generated after the change already has these numbers, and running
-- it twice changes nothing the second time.
--
-- 1. Every settlement's camp is brought to its level's room, and men over it
--    are turned out; a camp that was full under a smaller room is filled to
--    the new one, the way a freshly generated settlement starts. Nothing else
--    would do it: a settlement's camp is set when the world is generated and
--    never looked at again.
-- 2. Every player's camp the same, by their Troop Camp's level. The server
--    does this itself the next time a player's camp is read
--    (TroopMutations.SyncUserCap); doing it here means the numbers are right
--    before anybody looks. A player with no finished Troop Camp keeps what
--    they have, the same as the server leaves them (Camp.CapFor).
-- 3. Every settlement's stored power, which a war's siege is measured from
--    (WarMutations), is written again the way GenerateServer.sql writes it:
--    from the level and the full complement it now has.
--
-- One DO is one statement, and all or nothing on its own.

DO $$
DECLARE
    zones_capped integer;
    players_capped integer;
    powered integer;
BEGIN
    -- 1. Settlements, by their own level. A camp at full strength stays at full
    --    strength, whichever way its room moved; one that has lost men keeps
    --    the men it has, up to the room.
    UPDATE public."Troop" t
       SET "MaxCount" = cap.n,
           "Count" = CASE WHEN t."Count" >= t."MaxCount" THEN cap.n ELSE LEAST(t."Count", cap.n) END,
           updated = now()
      FROM (SELECT "Id", CASE WHEN "Level" <= 0 THEN 0 ELSE 155 + ("Level" - 1) * 5 END AS n
              FROM public."Zone") cap
     WHERE t."ZoneId" = cap."Id"
       AND (t."MaxCount" <> cap.n OR t."Count" > cap.n);
    GET DIAGNOSTICS zones_capped = ROW_COUNT;

    -- 2. Players, by their Troop Camp ("at") once it is finished.
    UPDATE public."Troop" t
       SET "MaxCount" = cap.n,
           "Count" = LEAST(t."Count", cap.n),
           updated = now()
      FROM (SELECT "UserId", 155 + (max("Level") - 1) * 5 AS n
              FROM public."Building"
             WHERE "Type" = 'at' AND "Level" > 0
             GROUP BY "UserId") cap
     WHERE t."UserId" = cap."UserId"
       AND (t."MaxCount" <> cap.n OR t."Count" > cap.n);
    GET DIAGNOSTICS players_capped = ROW_COUNT;

    -- 3. Settlements' stored power, from the very figures GenerateServer.sql
    --    seeds a settlement with: five heroes of the level, and its men.
    UPDATE public."Zone" z
       SET "Power" = ROUND(
               ((5 * s.h_strength) + s.t_strength * s.t_count)             -- what it lands
               * ((5 * s.h_hp)                                             -- heroes' health
                   + s.t_hp::NUMERIC * s.t_count                           -- the men's
                   + (5 * (100 + (s.lvl - 1) * 200)))                      -- the camp
               / 200
           )::BIGINT
      FROM (SELECT "Id",
                   "Level" AS lvl,
                   (10 + ("Level" - 1) * 2)::NUMERIC(8,2)          AS h_strength,
                   1500 + ("Level" - 1) * 300                      AS h_hp,
                   155 + ("Level" - 1) * 5                         AS t_count,
                   ((10 + ("Level" - 1) * 2) * 0.07)::NUMERIC(8,2) AS t_strength,
                   ROUND((1500 + ("Level" - 1) * 300) * 0.6)::INT  AS t_hp
              FROM public."Zone"
             WHERE "Level" > 0) s
     WHERE z."Id" = s."Id"
       AND z."Power" IS DISTINCT FROM ROUND(
               ((5 * s.h_strength) + s.t_strength * s.t_count)
               * ((5 * s.h_hp) + s.t_hp::NUMERIC * s.t_count + (5 * (100 + (s.lvl - 1) * 200)))
               / 200
           )::BIGINT;
    GET DIAGNOSTICS powered = ROW_COUNT;

    RAISE NOTICE 'settlement camps capped: %', zones_capped;
    RAISE NOTICE 'player camps capped: %', players_capped;
    RAISE NOTICE 'settlement power rewritten: %', powered;
END
$$;
