-- One of every building type for every player.
--
-- A development aid, like userdiamond.sql beside it: every player is given each
-- building the catalogue lists that they do not already have, finished at
-- level 1 and standing on its own plot. A type a player already holds is left
-- alone the capital, the Troop Camp and the rest are one to a base, and the
-- game finds them by type so it adds one of each, never a second.
--
--   psql -h localhost -U postgres -d game_0 -v ON_ERROR_STOP=1 -f allbuildings.sql
--
-- Run again it adds nothing.
--
-- Where each one goes, by the base's own placement rules (PlayerBase3D), in
-- tiles of 30 points: a building's plot is 4 tiles square and a statue's 3,
-- and the stored X and Y are the plot's top-left corner. A plot is kept
--   inside the palisade, the 84 x 56 grid, with a tile to spare;
--   off the three roads the capital puts down: in from the gate to the cross
--     street, the cross street wall to wall, and on out of the back;
--   a tile clear of every other building, so no two plots touch.
-- Of the plots that fit, the one nearest the capital, so the base fills out
-- from its middle rather than from a corner.
--
-- The four resource buildings get their collector too, at level 1 and empty,
-- the way laying one in the game writes it (BuildingMutations.CreateBuilding).
--
-- The types are the catalogue's (Objects.json): the general, army, resource
-- and decoration buildings. A building added to the catalogue is added here.

DO $$
DECLARE
    u record;
    t text;
    -- In the order they are placed: the capital first, should a player be
    -- without one, then what matters most to have near it.
    kinds text[] := ARRAY['c', 'rh', 'ah', 'b', 'gt', 'hc', 'at', 'wc', 'wt',
                          'cf', 'cm', 'ce', 'cw', 'sh', 'st'];
    collectors text[] := ARRAY['cf', 'cm', 'ce', 'cw'];
    cap_x numeric;
    cap_z numeric;
    street numeric;
    size int;
    spot record;
    next_id int;
    added int := 0;
    no_room int := 0;
BEGIN
    CREATE TEMP TABLE IF NOT EXISTS taken (x0 numeric, z0 numeric, x1 numeric, z1 numeric) ON COMMIT DROP;

    FOR u IN SELECT "Id" FROM public."User" ORDER BY "Id" LOOP
        TRUNCATE taken;

        -- The ground the player's buildings already claim, in tiles. The
        -- capital reaches a plot's half beyond its own on every side; a statue
        -- is three tiles; everything else four.
        INSERT INTO taken (x0, z0, x1, z1)
        SELECT CASE WHEN b.kind = 'c' THEN b.x - 2 ELSE b.x END,
               CASE WHEN b.kind = 'c' THEN b.z - 2 ELSE b.z END,
               b.x + CASE WHEN b.kind = 'c' THEN 6 WHEN b.kind IN ('sh', 'st') THEN 3 ELSE 4 END,
               b.z + CASE WHEN b.kind = 'c' THEN 6 WHEN b.kind IN ('sh', 'st') THEN 3 ELSE 4 END
          FROM (SELECT "Type" AS kind,
                       coalesce("X", 0) / 30 AS x,
                       coalesce("Y", 0) / 30 AS z
                  FROM public."Building" WHERE "UserId" = u."Id") b;

        FOREACH t IN ARRAY kinds LOOP
            CONTINUE WHEN EXISTS (
                SELECT 1 FROM public."Building" WHERE "UserId" = u."Id" AND "Type" = t);

            IF t = 'c' THEN
                -- The capital's own spot, centred on the gate: where every
                -- account is given one (BuildingMutations.StaticInitializeBuildings).
                SELECT 39 AS gx, 25 AS gz INTO spot;
                size := 4;
            ELSE
                -- Roads come off the capital, which is placed first.
                SELECT coalesce(min("X") / 30, 39) + 2, coalesce(min("Y") / 30, 25) + 2
                  INTO cap_x, cap_z
                  FROM public."Building" WHERE "UserId" = u."Id" AND "Type" = 'c';
                -- The front road runs out of the capital's column where the gate
                -- allows it, and as near as the gateway lets it otherwise.
                street := LEAST(GREATEST(cap_x, 40), 44);
                size := CASE WHEN t IN ('sh', 'st') THEN 3 ELSE 4 END;

                SELECT g.gx, h.gz INTO spot
                  FROM generate_series(1, 83 - size) AS g(gx)
                 CROSS JOIN generate_series(1, 55 - size) AS h(gz)
                 WHERE NOT (
                        -- in from the gate to the cross street
                        (g.gx < street + 2 AND g.gx + size > street - 2 AND h.gz < 56 AND h.gz + size > cap_z + 1)
                        -- the cross street, wall to wall
                     OR (h.gz < cap_z + 1 AND h.gz + size > cap_z - 1)
                        -- and on out of the back
                     OR (g.gx < cap_x + 2 AND g.gx + size > cap_x - 2 AND h.gz < cap_z - 1 AND h.gz + size > 0))
                   AND NOT EXISTS (
                        SELECT 1 FROM taken k
                         WHERE g.gx - 1 < k.x1 AND g.gx + size + 1 > k.x0
                           AND h.gz - 1 < k.z1 AND h.gz + size + 1 > k.z0)
                 ORDER BY power(g.gx + size / 2.0 - cap_x, 2) + power(h.gz + size / 2.0 - cap_z, 2), h.gz, g.gx
                 LIMIT 1;

                IF NOT FOUND THEN
                    no_room := no_room + 1;
                    CONTINUE;
                END IF;
            END IF;

            SELECT coalesce(max("Id"), -1) + 1 INTO next_id
              FROM public."Building" WHERE "UserId" = u."Id";

            -- Finished, the way a laid building is left once its half minute is
            -- up: level 1, no longer going up, its build time on the row.
            INSERT INTO public."Building"
                ("UserId", "Id", "Type", "Upgrading", "Level", "StartTime",
                 "PreviousMinRequired", "MinRequired", "BuffAmount", "BuffType", "X", "Y")
            VALUES
                (u."Id", next_id, t, false, 1, now() - interval '30 seconds',
                 0, 30, 0, '', spot.gx * 30, spot.gz * 30);

            INSERT INTO taken (x0, z0, x1, z1)
            VALUES (CASE WHEN t = 'c' THEN spot.gx - 2 ELSE spot.gx END,
                    CASE WHEN t = 'c' THEN spot.gz - 2 ELSE spot.gz END,
                    spot.gx + CASE WHEN t = 'c' THEN 6 ELSE size END,
                    spot.gz + CASE WHEN t = 'c' THEN 6 ELSE size END);

            -- A resource building's collector, keyed to it, at level 1 and empty.
            IF t = ANY (collectors) THEN
                INSERT INTO public."Collector" ("UserId", "Id", "Type", "LastCollect", "Max", "Base", "Level")
                VALUES (u."Id", next_id, t, now(), 100000, 0, 1);
            END IF;

            added := added + 1;
        END LOOP;
    END LOOP;

    RAISE NOTICE 'buildings added: %', added;
    IF no_room > 0 THEN
        RAISE NOTICE 'left out for want of a clear plot: %', no_room;
    END IF;
END
$$;
