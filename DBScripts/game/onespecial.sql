-- One special a hero, and no ballista.
--
-- For a world built before either change, run once against its game database:
--
--   psql -h localhost -U postgres -d game_0 -v ON_ERROR_STOP=1 -f onespecial.sql
--
-- A world built from game.sql after the change has nothing for this to do, and
-- running it twice does nothing the second time.
--
-- 1. Every ballista becomes a catapult, on a hero and in a pack alike. The
--    ballista is gone from the catalogue, so one left as it was could be
--    neither used nor taken off for anything; the catapult is the nearest thing
--    to it, and sells for the same price.
-- 2. A hero carrying more than one special keeps the first he was given, and
--    the rest go back into his player's pack, one item each the same as
--    taking them off on his Specials tab would.
-- 3. Stacks of the same special in one pack are put together, the way the
--    server stacks them (UsableMutations.CreateUsable).
--
-- All or nothing: it runs in one transaction.

BEGIN;

DO $$
DECLARE
    r record;
    converted_heroes integer;
    converted_pack integer;
    returned integer := 0;
    merged integer := 0;
BEGIN
    -- 1. Ballistas into catapults.
    UPDATE public."Skill" SET "Type" = 'cat', updated = now() WHERE "Type" = 'bal';
    GET DIAGNOSTICS converted_heroes = ROW_COUNT;
    UPDATE public."Usable" SET "Type" = 'cat', updated = now()
        WHERE "Type" = 'bal' AND "ApplyType" = 'skl';
    GET DIAGNOSTICS converted_pack = ROW_COUNT;

    -- 2. Every special but each hero's first, back into the pack.
    FOR r IN
        SELECT "UserId", "Id", "Type"
        FROM (
            SELECT s."UserId", s."Id", s."Type",
                   row_number() OVER (PARTITION BY s."HeroId" ORDER BY s.created, s."Id") AS place
            FROM public."Skill" s
            WHERE s."HeroId" IS NOT NULL
        ) ranked
        WHERE place > 1
    LOOP
        -- Onto the stack the player already holds, or a new one of one.
        UPDATE public."Usable" u SET "Amount" = u."Amount" + 1, updated = now()
        WHERE (u."UserId", u."Id") = (
            SELECT x."UserId", x."Id" FROM public."Usable" x
            WHERE x."UserId" = r."UserId" AND x."Type" = r."Type" AND x."ApplyType" = 'skl'
            ORDER BY x."Id" LIMIT 1);
        IF NOT FOUND AND r."Type" <> '' THEN
            INSERT INTO public."Usable"
                ("Id", "UserId", "Type", "Category", "Amount", "IsActive", "BuffAmount", "BuffType", "ApplyType")
            VALUES (
                (SELECT coalesce(max(x."Id"), 0) + 1 FROM public."Usable" x WHERE x."UserId" = r."UserId"),
                r."UserId", r."Type", 'a', 1, true, 1, '', 'skl');
        END IF;
        DELETE FROM public."Skill" WHERE "UserId" = r."UserId" AND "Id" = r."Id";
        returned := returned + 1;
    END LOOP;

    -- 3. One stack per special per player: the rest added onto the first.
    FOR r IN
        SELECT "UserId", "Type", "Category", "BuffAmount", "BuffType", "IsActive",
               min("Id") AS keep, sum("Amount") AS total
        FROM public."Usable"
        WHERE "ApplyType" = 'skl'
        GROUP BY "UserId", "Type", "Category", "BuffAmount", "BuffType", "IsActive"
        HAVING count(*) > 1
    LOOP
        UPDATE public."Usable" SET "Amount" = r.total, updated = now()
            WHERE "UserId" = r."UserId" AND "Id" = r.keep;
        DELETE FROM public."Usable"
            WHERE "UserId" = r."UserId" AND "Type" = r."Type" AND "ApplyType" = 'skl'
              AND "Category" = r."Category" AND "BuffAmount" = r."BuffAmount"
              AND "BuffType" = r."BuffType" AND "IsActive" = r."IsActive"
              AND "Id" <> r.keep;
        merged := merged + 1;
    END LOOP;

    RAISE NOTICE 'ballistas made catapults: % on heroes, % pack stacks', converted_heroes, converted_pack;
    RAISE NOTICE 'specials returned to packs: %', returned;
    RAISE NOTICE 'pack stacks merged: %', merged;
END
$$;

COMMIT;
