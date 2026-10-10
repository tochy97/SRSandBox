-- GenerateServer.sql
-- Inserts 869 Zones (169 grid + 500 resource + 200 outlaw), each with 1 Region,
-- 5 Heroes, and one body of Troops.
--
-- ── GRID ZONES (169) ──────────────────────────────────────────────────────────
-- 13×13 grid covering the full map (4000 × 2000 tile coordinates).
-- One zone at the centre of each cell.
-- Ring depth determines level: outer edge = 10, centre cell = 70.
--   ring = LEAST(col, row, 12-col, 12-row)
--   level = (ring + 1) * 10
--
-- Every one of them is 'bh' (Masses). The grid is the map's backbone the
-- settled country a player works through and one type across all of it is
-- what makes the outlaw zones below read as the exceptions they are.
--
-- They used to be drawn from {bh, bt, mh} with one 'bg' per ring. Two of those
-- four are not zone types at all: Objects.json lists bh, bt and br and nothing
-- named 'mh' or 'bg', so a good part of the map was generated as something no
-- screen could name.
--
-- ── RANDOM ZONES (500) ────────────────────────────────────────────────────────
-- Random tile coordinates (X ∈ [4, 3996], Y ∈ [4, 1996]).
-- Types are the resource nodes {rm, rw, re, rg, rm2, rf, re2, rg2}; each
-- zone's Resource column matches its type, so a Metal Deposit carries metal.
--
-- Level depends on the node's tier. Metal, gold and oil come in a pair each,
-- so the plain one of {rm, re, rg} draws 1–25 and its deep twin {rm2, re2, rg2}
-- draws 25–50. Wood and food have no pair: rw and rf are the only nodes that
-- yield either, so both draw the full 1–70 and a player of any level can find
-- one worth the trip.
--
-- Stock is level * 2000, jittered +/-15%, and sits in that one resource column
-- with the others left at zero. Same level, similar haul, never identical.
--
-- ── OUTLAW ZONES (200) ────────────────────────────────────────────────────────
-- Thieves Hideouts ('bt') and Rouge Armies ('br'), scattered anywhere on the
-- map at levels 1-70.
--
-- Every level of both kinds is guaranteed to exist: the roster is built as one
-- of each level of each kind first (2 x 70 = 140 of the 200), and the remaining
-- 60 are drawn at random. The zone finder lets a player ask for a named type at
-- a typed level, and an answer of "there is no such thing" for a level in the
-- range is a worse answer than a long ride.
--
-- Level is deliberately not tied to where the zone lands. A grid zone's level
-- comes from its ring, which is what makes the map a difficulty gradient; these
-- are outlaws hiding in it, and a hard camp in soft country is the point of
-- them.
--
-- ── ZONE NAMES ───────────────────────────────────────────────────────────────
-- Generated from ZoneNameGenerator arrays (mirrors Common.cs):
--   Descriptor + ' ' + Noun  [+ optional Suffix ~50% chance]
--
-- ── HEROES ───────────────────────────────────────────────────────────────────
-- 5 heroes per zone, same level as their zone.
-- Strength / Durability = 10 + (Level-1)*2
-- Hp / MaxHp = 1500 + (Level-1)*300   (always 150x Strength see Hero.AttackAt)
-- Types cycle:    warrior → mage → archer → knight → assassin
-- Elements cycle: fire    → water → earth → wind  → lightning
--
-- ── TROOPS ───────────────────────────────────────────────────────────────────
-- One Troop row per zone.
-- Count = MaxCount = 150 + 5*Level, 500 at level 70    (Camp.MaxTroopsAt)
-- Strength = Durability = 7% of the hero's Strength    (Hero.TroopShare)
-- Hp = 60% of the hero's Hp                            (Hero.TroopHpShare)
--
-- Health is much the larger share on purpose: a man is meant to outlast three
-- of a hero's blows rather than a fraction of one, and the damage curve is
-- attack squared over attack plus defence, so a blow a fourteenth the size
-- lands nothing like a fourteenth of the damage. The two are set together and
-- neither means anything alone see Hero.TroopShare and Hero.TroopHpShare,
-- which carry the working.

DO $$
DECLARE
    -- Grid loop
    col             INT;
    row             INT;
    ring            INT;

    -- Shared across both generation passes
    lvl             INT;
    factor          NUMERIC;
    tile_x          NUMERIC(6,2);
    tile_y          NUMERIC(6,2);
    cell_w          NUMERIC := 4000.0 / 13.0;
    cell_h          NUMERIC := 2000.0 / 13.0;

    -- Zone
    zone_id         TEXT;
    zone_name       TEXT;
    zone_suffix     TEXT;
    zone_type       TEXT;

    -- Zone name arrays (mirrors ZoneNameGenerator in Common.cs)
    z_descriptors   TEXT[] := ARRAY[
                        'Shadow','Iron','Storm','Ash','Frost','Blood','Dark','Stone',
                        'Ember','Silver','Crimson','Black','Grim','Wild','Lost','Bleak',
                        'Ancient','Hollow','Doomed','Venom','Bone','Cursed','Fallen','Savage'
                    ];
    z_nouns         TEXT[] := ARRAY[
                        'Keep','Hold','Vale','Reach','Peak','Veil','Mire','Watch',
                        'Forge','Gate','Mark','Fell','Mere','Ridge','Bastion','Haven',
                        'Spire','Citadel','Outpost','Enclave','Expanse','Crossing','Wastes','Hollow'
                    ];
    -- 4 empty strings → ~50% chance of no suffix
    z_suffixes      TEXT[] := ARRAY[
                        '','','','',
                        ' Pass',' Deep',' Ruins',' Depths',' End',' Reach'
                    ];

    -- Resource codes, as Objects.json ResourceTypes spells them. Single
    -- letters, matching what ZoneMutations.CreateZone writes -- the column had
    -- the full words here, which agreed with nothing that reads it.
    resources       TEXT[] := ARRAY['g','m','f','e'];

    -- The two kinds of trouble scattered over the map. Both are real entries in
    -- Objects.json ZoneTypes, unlike the 'mh' and 'bg' this pool used to hold.
    outlaw_types    TEXT[] := ARRAY['bt','br'];
    outlaw_kind     TEXT;
    -- How many to scatter, and how high they go. Every level from 1 to
    -- outlaw_max_lvl is guaranteed to exist for both kinds, so outlaw_total has
    -- to leave room for that -- see the check at the top of PASS 3.
    outlaw_total    INT := 200;
    outlaw_max_lvl  INT := 70;
    -- The roster: one entry per zone, paired index for index. Worked out in
    -- full before anything is inserted, because the guarantee is a property of
    -- the whole set and cannot be decided one zone at a time.
    outlaw_kind_of  TEXT[];
    outlaw_lvl_of   INT[];

    -- Resource zone types, paired index-for-index with res_resources so a
    -- Metal Deposit carries metal, a Forest wood, and so on.
    res_types       TEXT[] := ARRAY['rm','rw','re','rg','rm2','rf','re2','rg2'];
    res_resources   TEXT[] := ARRAY['m','w','e','g','m','f','e','g'];
    res_i           INT;

    -- Level band. Where a resource comes in a pair of nodes, the plain one
    -- takes the shallow half of the range and the deep one -- the cave, the
    -- geyser -- takes the deep half, so which node you have found tells you
    -- roughly what it is worth before you read the level off it.
    --
    -- Wood and food have no pair: one Forest type and one Fishing Pound type
    -- between them serve the whole map, so a band would leave every player
    -- outside it with nowhere to gather. Those draw the full range instead,
    -- which is the same 1..70 the grid settlements run to. The rule is worked
    -- out from res_resources below rather than listed here, so a resource that
    -- is later given a second node stops being full-range on its own.
    res_max         INT := 50;
    res_half        INT := 25;
    res_full        INT := 70;
    -- How many node types yield what this one does. One means it is alone.
    res_siblings    INT;
    -- The stock a resource zone holds of its own resource, and the four column
    -- values that carry it.
    res_stock       INT;
    res_gold        INT;
    res_metal       INT;
    res_food        INT;
    res_wood        INT;
    res_energy      INT;


    -- Hero name arrays (mirrors NameGenerator in Common.cs)
    prefixes        TEXT[] := ARRAY[
                        'Ka','Za','Ra','Lo','Mi','Va','Tor','Zen',
                        'Ar','Bel','Dan','Toe','Lu','Car','Il','Iv','Ton'
                    ];
    middles         TEXT[] := ARRAY[
                        'dor','mir','lan','vash','rin','thal','zor',
                        'vek','nus','us','in','an','it','was','uke'
                    ];
    h_suffixes      TEXT[] := ARRAY[
                        'ion','ar','eth','us','a','or','en','is',
                        'on','in','an','it','was','uke'
                    ];
    hero_name       TEXT;

    -- Hero stats
    hero_id         TEXT;
    hero_num        INT;
    h_strength      NUMERIC(8,2);
    h_durability    NUMERIC(8,2);
    h_hp            INT;

    -- Hero variety
    -- What a hero is built for. Kept in step with Hero.HeroTypes on the server,
    -- which is what a recruit is given; a zone's garrison and a player's own
    -- heroes have to be the same kind of thing.
    --
    -- Drawn at random rather than indexed by hero number, as the five class
    -- names it replaced were: there are three of these and five heroes in a
    -- party, so an index would field the same three in the same order every
    -- time and never give a party two attackers.
    types           TEXT[] := ARRAY['attack','speed','defense'];

    -- What a hero's own kind is worth against the other two, per Hero.Favoured
    -- and Hero.Lesser. The three shares add to three, so a party is worth the
    -- same however its kinds fell -- which is why the zone's Power below is
    -- still worked out from the untilted figure.
    fav             NUMERIC := 1.25;
    les             NUMERIC := 0.875;

    -- One hero's kind and the three stats it tilts. Per hero rather than per
    -- zone: h_strength beside them stays the level's flat figure, because the
    -- zone's Power and its troops are measured off that.
    h_type          TEXT;
    h_str           NUMERIC(8,2);
    h_dur           NUMERIC(8,2);
    h_spd           NUMERIC(8,2);
    elements        TEXT[] := ARRAY['fire','water','earth','wind','lightning'];

    -- Troop stats
    t_count         INT;
    t_strength      NUMERIC(8,2);
    t_durability    NUMERIC(8,2);
    t_hp            INT;

    -- Region. "Id" is a plain integer with no sequence behind it, so the ids
    -- have to be handed out here. It used to start at 1, which meant the script
    -- only ever worked against empty tables: run it a second time and the very
    -- first region collided with the first region of the run before it. Picked
    -- up from whatever is already there instead.
    region_id       INT;

    -- Footprint written into BaseLock, mirroring BaseLockMutations.Footprint:
    -- a resource node is unwalled and about 5 across, a settlement's wall is
    -- its span plus half a unit either side, so 7 up to level 10 and 8 above.
    -- Storing it means the collision check never has to re-derive it.
    foot            DOUBLE PRECISION;

    -- Random zone pass
    rand_i          INT;

    -- Outlaw pass
    outlaw_n        INT;

    -- Totals for NOTICE
    zone_count      INT := 0;
    hero_count      INT := 0;

BEGIN

    -- Carry on from the highest region already on the table, so this can be run
    -- into a database that is not empty. On a fresh one MAX is NULL and the
    -- first region is 1, exactly as before.
    SELECT COALESCE(MAX("Id"), 0) + 1 INTO region_id FROM public."Region";

-- ═══════════════════════════════════════════════════════════════════════════════
-- PASS 1: 13×13 GRID ZONES (169 zones)
-- ═══════════════════════════════════════════════════════════════════════════════

    FOR row IN 0..12 LOOP
        FOR col IN 0..12 LOOP

            ring   := LEAST(col, row, 12 - col, 12 - row);
            lvl    := (ring + 1) * 10;
            factor := lvl::NUMERIC / 10.0;

            -- The whole grid is one type. See the notes at the top.
            zone_type := 'bh';

            tile_x := ROUND((col + 0.5) * cell_w, 2);
            tile_y := ROUND((row + 0.5) * cell_h, 2);
            zone_id := gen_random_uuid()::TEXT;

            -- Generate zone name (ZoneNameGenerator)
            zone_suffix := z_suffixes[(floor(random() * array_length(z_suffixes, 1)) + 1)::INT];
            zone_name   := z_descriptors[(floor(random() * array_length(z_descriptors, 1)) + 1)::INT]
                           || ' '
                           || z_nouns[(floor(random() * array_length(z_nouns, 1)) + 1)::INT]
                           || zone_suffix;

            -- Hero / Troop stats for this level, worked out before the zone row
            -- goes in because its Power column is written from them.
            h_strength   := 10 + (lvl - 1) * 2;
            h_durability := 10 + (lvl - 1) * 2;
            h_hp         := 1500 + (lvl - 1) * 300;
            -- The room a holding of this level has, per Camp.MaxTroopsAt: 150
            -- and five men a level, 500 at level 70. Kept to Camp's own number, because a
            -- zone raised through the API gets it and so does a player's camp:
            -- this was once 100 + (lvl-1)*10 while the server said otherwise,
            -- and the men count on both sides of the power product, which is
            -- how a player whose best hero was level 3 came to outrank a
            -- level-5 camp.
            t_count      := 155  + (lvl - 1) * 5;
            t_strength   := h_strength * 0.07;
            t_durability := h_strength * 0.07;
            t_hp         := ROUND(h_hp * 0.6);

            INSERT INTO public."Zone" (
                "Id","Name","Type","Resource",
                "TentHp","CarrierStrength","Power","Hp",
                "X","Y","Level","Gold","Metal","Food","Energy"
            ) VALUES (
                zone_id, zone_name, zone_type,
                resources[((col + row) % 4) + 1],
                -- The camp, on the one scale everything that fights out of a
                -- tent uses: a full party of five for the zone's level, each
                -- hero worth 100 and 200 more for every level above the first.
                ROUND((5 * (100 + (lvl - 1) * 200))::NUMERIC, 2),
                ROUND(500  * factor, 2),
                -- Power, on the one scale PowerScale.Of uses: what the holding
                -- lands in a round, times everything that has to be taken off
                -- it, over 200.
                --
                -- Written from the very variables the rows below are seeded
                -- from, rather than spelling the curves out a second time. They
                -- were spelled out, and they drifted: the men's count stayed on
                -- a formula the server had stopped using, and because the men
                -- count on both sides of the product a seeded settlement read
                -- under a quarter of what the same zone raised through the API
                -- does.
                ROUND(
                    ((5 * h_strength) + t_strength * t_count)             -- what it lands
                    * ((5 * h_hp)                                         -- heroes' health
                        + t_hp::NUMERIC * t_count                         -- the men's
                        + (5 * (100 + (lvl - 1) * 200)))                  -- the camp
                    / 200
                )::BIGINT,
                (1000  * factor)::INT,
                tile_x, tile_y, lvl,
                (100 * factor)::INT,
                (100 * factor)::INT,
                (100 * factor)::INT,
                (100 * factor)::INT
            );
            zone_count := zone_count + 1;

            -- On the occupancy register, so a player being offered a spot is
            -- checked against this zone without having to look at Zone at all.
            foot := CASE WHEN left(zone_type, 1) = 'r' THEN 5
                         WHEN lvl <= 10 THEN 7 ELSE 8 END;
            INSERT INTO public."BaseLock" ("Id","OwnerId","Kind","Pending","X","Y","Width","Height")
            VALUES (zone_id, zone_id, 'z', FALSE, tile_x, tile_y, foot, foot);

            INSERT INTO public."Region" (
                "Id","ZoneId","Name","IsCapital","AllianceId"
            ) VALUES (
                region_id,
                zone_id,
                'Region ' || zone_name,
                CASE WHEN ring = 6 THEN TRUE ELSE FALSE END,
                NULL
            );
            region_id := region_id + 1;

            -- One body of men for the whole holding, raised before its heroes. It used
            -- to be one row per hero; the men belong to the zone now, and every hero
            -- garrisoning it draws on the same force.
            INSERT INTO public."Troop" (
                "Id","ZoneId","Count","MaxCount","Hp","Level",
                "Strength","Durability","Speed","Experience","UpgradePoints"
            ) VALUES (
                gen_random_uuid()::TEXT, zone_id, t_count, t_count, t_hp, lvl,
                t_strength, t_durability, 2.0, 0, 0
            );

            FOR hero_num IN 1..5 LOOP
                hero_name := prefixes[(floor(random() * array_length(prefixes, 1)) + 1)::INT];
                IF random() > 0.5 THEN
                    hero_name := hero_name
                                 || middles[(floor(random() * array_length(middles, 1)) + 1)::INT];
                END IF;
                hero_name := hero_name
                             || h_suffixes[(floor(random() * array_length(h_suffixes, 1)) + 1)::INT];
                hero_id := gen_random_uuid()::TEXT;

                -- The kind first, because the three stats are read off it.
                h_type := types[(floor(random() * array_length(types, 1)) + 1)::INT];
                h_str  := ROUND(h_strength * (CASE WHEN h_type = 'attack'  THEN fav ELSE les END), 2);
                h_dur  := ROUND(h_strength * (CASE WHEN h_type = 'defense' THEN fav ELSE les END), 2);
                h_spd  := ROUND(2.0        * (CASE WHEN h_type = 'speed'   THEN fav ELSE les END), 2);

                INSERT INTO public."Hero" (
                    "Id","ZoneId","Name","Type","Element","Status",
                    "Hp","HealTime","MaxHp","IsAI","IsRuler","Level","Experience",
                    "Strength","Durability","Speed","SDLUpgradePoints","Position","Rank"
                ) VALUES (
                    hero_id, zone_id, hero_name,
                    h_type,
                    elements[hero_num], 'active',
                    h_hp, 0, h_hp, TRUE,
                    CASE WHEN hero_num = 1 THEN TRUE ELSE FALSE END,
                    lvl, 0,
                    h_str, h_dur, h_spd, 0,
                    hero_num, 0
                );

                hero_count := hero_count + 1;
            END LOOP;

        END LOOP; -- col
    END LOOP; -- row

-- ═══════════════════════════════════════════════════════════════════════════════
-- PASS 2: 500 RANDOM RESOURCE ZONES (running total 669)
-- ═══════════════════════════════════════════════════════════════════════════════
    FOR rand_i IN 1..500 LOOP

        -- Type and Resource are drawn together so they always agree.
        res_i := (floor(random() * array_length(res_types, 1)) + 1)::INT;

        -- Level follows the tier, unless this node is the only one of its
        -- resource see the note beside res_full. Wood and food are gathered
        -- from one type each, so those two draw 1..res_full and a player of any
        -- level can find one worth visiting.
        --
        -- Otherwise: 1..res_half for a plain node, res_half..res_max for a '2'.
        -- Trailing '2' is the marker, so a new deep node needs only to be named
        -- for it and added to the arrays above.
        SELECT count(*) INTO res_siblings
        FROM unnest(res_resources) AS r
        WHERE r = res_resources[res_i];

        IF res_siblings = 1 THEN
            lvl := (floor(random() * res_full) + 1)::INT;
        ELSIF right(res_types[res_i], 1) = '2' THEN
            lvl := (floor(random() * (res_max - res_half + 1)) + res_half)::INT;
        ELSE
            lvl := (floor(random() * res_half) + 1)::INT;
        END IF;
        factor := lvl::NUMERIC / 10.0;

        -- Random tile coords, buffered 4px from map edges
        tile_x := ROUND((floor(random() * 3992) + 4)::NUMERIC, 2);
        tile_y := ROUND((floor(random() * 1992) + 4)::NUMERIC, 2);
        zone_id := gen_random_uuid()::TEXT;

        -- Generate zone name
        zone_suffix := z_suffixes[(floor(random() * array_length(z_suffixes, 1)) + 1)::INT];
        zone_name   := z_descriptors[(floor(random() * array_length(z_descriptors, 1)) + 1)::INT]
                       || ' '
                       || z_nouns[(floor(random() * array_length(z_nouns, 1)) + 1)::INT]
                       || zone_suffix;

        -- Stock of the zone's own resource: scaled by level, then jittered
        -- +/-15%. Two nodes of the same level are worth roughly the same trip
        -- without being interchangeable, which is the point of scouting one
        -- out. At 2000 per level a level-50 node holds ~100k, and GatherZone
        -- takes level*100 a visit (double with a hero), so it is good for
        -- roughly twenty runs before it is worked out.
        res_stock := ROUND(lvl * 2000 * (0.85 + random() * 0.30))::INT;

        -- Only the resource the node is named for. A Metal Deposit holding
        -- gold would be invisible to GatherZone anyway, since that credits the
        -- one resource the type yields.
        res_gold   := CASE WHEN res_resources[res_i] = 'g' THEN res_stock ELSE 0 END;
        res_metal  := CASE WHEN res_resources[res_i] = 'm' THEN res_stock ELSE 0 END;
        res_food   := CASE WHEN res_resources[res_i] = 'f' THEN res_stock ELSE 0 END;
        res_wood   := CASE WHEN res_resources[res_i] = 'w' THEN res_stock ELSE 0 END;
        res_energy := CASE WHEN res_resources[res_i] = 'e' THEN res_stock ELSE 0 END;

        -- As above: worked out first, because Power is written from them.
        h_strength   := 10 + (lvl - 1) * 2;
        h_durability := 10 + (lvl - 1) * 2;
        h_hp         := 1500 + (lvl - 1) * 300;
        t_count      := 155  + (lvl - 1) * 5;
        t_strength   := h_strength * 0.07;
        t_durability := h_strength * 0.07;
        t_hp         := ROUND(h_hp * 0.6);

        INSERT INTO public."Zone" (
            "Id","Name","Type","Resource",
            "TentHp","CarrierStrength","Power","Hp",
            "X","Y","Level","Gold","Metal","Food","Wood","Energy","FullStock"
        ) VALUES (
            zone_id, zone_name,
            res_types[res_i],
            res_resources[res_i],
            -- Same scale as the settlements above.
            ROUND((5 * (100 + (lvl - 1) * 200))::NUMERIC, 2),
            ROUND(500  * factor, 2),
                -- Power, on the one scale PowerScale.Of uses: what the holding
                -- lands in a round, times everything that has to be taken off
                -- it, over 200.
                --
                -- Written from the very variables the rows below are seeded
                -- from, rather than spelling the curves out a second time. They
                -- were spelled out, and they drifted: the men's count stayed on
                -- a formula the server had stopped using, and because the men
                -- count on both sides of the product a seeded settlement read
                -- under a quarter of what the same zone raised through the API
                -- does.
                ROUND(
                    ((5 * h_strength) + t_strength * t_count)             -- what it lands
                    * ((5 * h_hp)                                         -- heroes' health
                        + t_hp::NUMERIC * t_count                         -- the men's
                        + (5 * (100 + (lvl - 1) * 200)))                  -- the camp
                    / 200
                )::BIGINT,
            (1000  * factor)::INT,
            tile_x, tile_y, lvl,
            res_gold, res_metal, res_food, res_wood, res_energy,
            -- And what that stock was, kept so the bar over the node can say
            -- how much of it is left.
            res_stock
        );
        zone_count := zone_count + 1;

        -- Same register row for the resource nodes.
        foot := CASE WHEN left(res_types[res_i], 1) = 'r' THEN 5
                     WHEN lvl <= 10 THEN 7 ELSE 8 END;
        INSERT INTO public."BaseLock" ("Id","OwnerId","Kind","Pending","X","Y","Width","Height")
        VALUES (zone_id, zone_id, 'z', FALSE, tile_x, tile_y, foot, foot);

        INSERT INTO public."Region" (
            "Id","ZoneId","Name","IsCapital","AllianceId"
        ) VALUES (
            region_id,
            zone_id,
            'Region ' || zone_name,
            FALSE,
            NULL
        );
        region_id := region_id + 1;

        -- One body of men for the whole holding, raised before its heroes. It used
        -- to be one row per hero; the men belong to the zone now, and every hero
        -- garrisoning it draws on the same force.
        INSERT INTO public."Troop" (
            "Id","ZoneId","Count","MaxCount","Hp","Level",
            "Strength","Durability","Speed","Experience","UpgradePoints"
        ) VALUES (
            gen_random_uuid()::TEXT, zone_id, t_count, t_count, t_hp, lvl,
            t_strength, t_durability, 2.0, 0, 0
        );

        FOR hero_num IN 1..5 LOOP
            hero_name := prefixes[(floor(random() * array_length(prefixes, 1)) + 1)::INT];
            IF random() > 0.5 THEN
                hero_name := hero_name
                             || middles[(floor(random() * array_length(middles, 1)) + 1)::INT];
            END IF;
            hero_name := hero_name
                         || h_suffixes[(floor(random() * array_length(h_suffixes, 1)) + 1)::INT];
            hero_id := gen_random_uuid()::TEXT;

            h_type := types[(floor(random() * array_length(types, 1)) + 1)::INT];
            h_str  := ROUND(h_strength * (CASE WHEN h_type = 'attack'  THEN fav ELSE les END), 2);
            h_dur  := ROUND(h_strength * (CASE WHEN h_type = 'defense' THEN fav ELSE les END), 2);
            h_spd  := ROUND(2.0        * (CASE WHEN h_type = 'speed'   THEN fav ELSE les END), 2);

            INSERT INTO public."Hero" (
                "Id","ZoneId","Name","Type","Element","Status",
                "Hp","HealTime","MaxHp","IsAI","IsRuler","Level","Experience",
                "Strength","Durability","Speed","SDLUpgradePoints","Position","Rank"
            ) VALUES (
                hero_id, zone_id, hero_name,
                h_type,
                elements[hero_num], 'active',
                h_hp, 0, h_hp, TRUE,
                CASE WHEN hero_num = 1 THEN TRUE ELSE FALSE END,
                lvl, 0,
                h_str, h_dur, h_spd, 0,
                hero_num, 0
            );

            hero_count := hero_count + 1;
        END LOOP;

    END LOOP; -- random zones

-- ═══════════════════════════════════════════════════════════════════════════════
-- PASS 3: 200 OUTLAW ZONES, levels 1-70, every level of both kinds present
-- (running total 869)
-- ═══════════════════════════════════════════════════════════════════════════════
    -- The guarantee has to fit. If somebody raises outlaw_max_lvl or drops
    -- outlaw_total without thinking, say so here rather than quietly leaving a
    -- level the finder can never answer for.
    IF outlaw_total < array_length(outlaw_types, 1) * outlaw_max_lvl THEN
        RAISE EXCEPTION
            'PASS 3: % zones cannot cover levels 1-% of % kinds; need at least %.',
            outlaw_total, outlaw_max_lvl, array_length(outlaw_types, 1),
            array_length(outlaw_types, 1) * outlaw_max_lvl;
    END IF;

    -- One of every level of every kind first, which is the guarantee...
    outlaw_kind_of := ARRAY[]::TEXT[];
    outlaw_lvl_of  := ARRAY[]::INT[];
    FOREACH outlaw_kind IN ARRAY outlaw_types LOOP
        FOR lvl IN 1..outlaw_max_lvl LOOP
            outlaw_kind_of := outlaw_kind_of || outlaw_kind;
            outlaw_lvl_of  := outlaw_lvl_of  || lvl;
        END LOOP;
    END LOOP;

    -- ...then the rest at random, which is what makes some levels commoner
    -- than others rather than the whole map being one of everything.
    WHILE array_length(outlaw_kind_of, 1) < outlaw_total LOOP
        outlaw_kind_of := outlaw_kind_of
            || outlaw_types[(floor(random() * array_length(outlaw_types, 1)) + 1)::INT];
        outlaw_lvl_of := outlaw_lvl_of
            || (floor(random() * outlaw_max_lvl) + 1)::INT;
    END LOOP;

    FOR outlaw_n IN 1..outlaw_total LOOP

        zone_type := outlaw_kind_of[outlaw_n];
        lvl       := outlaw_lvl_of[outlaw_n];
        factor    := lvl::NUMERIC / 10.0;

        -- Anywhere on the map, on the same 4px buffer the resource nodes use.
        -- Where it lands says nothing about how hard it is: these are outlaws
        -- hiding in the country, not part of its gradient.
        tile_x := ROUND((floor(random() * 3992) + 4)::NUMERIC, 2);
        tile_y := ROUND((floor(random() * 1992) + 4)::NUMERIC, 2);

        zone_id := gen_random_uuid()::TEXT;

        zone_suffix := z_suffixes[(floor(random() * array_length(z_suffixes, 1)) + 1)::INT];
        zone_name   := z_descriptors[(floor(random() * array_length(z_descriptors, 1)) + 1)::INT]
                       || ' '
                       || z_nouns[(floor(random() * array_length(z_nouns, 1)) + 1)::INT]
                       || zone_suffix;

        -- As above: worked out first, because Power is written from them.
        h_strength   := 10 + (lvl - 1) * 2;
        h_durability := 10 + (lvl - 1) * 2;
        h_hp         := 1500 + (lvl - 1) * 300;
        t_count      := 155  + (lvl - 1) * 5;
        t_strength   := h_strength * 0.07;
        t_durability := h_strength * 0.07;
        t_hp         := ROUND(h_hp * 0.6);

        INSERT INTO public."Zone" (
            "Id","Name","Type","Resource",
            "TentHp","CarrierStrength","Power","Hp",
            "X","Y","Level","Gold","Metal","Food","Energy"
        ) VALUES (
            zone_id, zone_name, zone_type,
            -- Cycled through the four rather than drawn, so the kinds come out
            -- evenly. PASS 1 does the same with its cell's row and column.
            resources[(outlaw_n % 4) + 1],
            -- Same scale as every other camp: a full party of five for the
            -- level, each hero worth 100 and 200 more per level above the first.
            ROUND((5 * (100 + (lvl - 1) * 200))::NUMERIC, 2),
            ROUND(500  * factor, 2),
                -- Power, on the one scale PowerScale.Of uses: what the holding
                -- lands in a round, times everything that has to be taken off
                -- it, over 200.
                --
                -- Written from the very variables the rows below are seeded
                -- from, rather than spelling the curves out a second time. They
                -- were spelled out, and they drifted: the men's count stayed on
                -- a formula the server had stopped using, and because the men
                -- count on both sides of the product a seeded settlement read
                -- under a quarter of what the same zone raised through the API
                -- does.
                ROUND(
                    ((5 * h_strength) + t_strength * t_count)             -- what it lands
                    * ((5 * h_hp)                                         -- heroes' health
                        + t_hp::NUMERIC * t_count                         -- the men's
                        + (5 * (100 + (lvl - 1) * 200)))                  -- the camp
                    / 200
                )::BIGINT,
            (1000  * factor)::INT,
            tile_x, tile_y, lvl,
            (100 * factor)::INT,
            (100 * factor)::INT,
            (100 * factor)::INT,
            (100 * factor)::INT
        );
        zone_count := zone_count + 1;

        -- The settlement footprint rather than the smaller one a resource node
        -- gets. A camp has no wall round it, but it still holds ground, and the
        -- register is what stops a player dropping a base on top of it.
        foot := CASE WHEN lvl <= 10 THEN 7 ELSE 8 END;
        INSERT INTO public."BaseLock" ("Id","OwnerId","Kind","Pending","X","Y","Width","Height")
        VALUES (zone_id, zone_id, 'z', FALSE, tile_x, tile_y, foot, foot);

        -- Never a capital, whatever its level. The one capital is the grid's
        -- centre cell, and a level-70 camp that happened to drop beside it has
        -- no claim on the title.
        INSERT INTO public."Region" (
            "Id","ZoneId","Name","IsCapital","AllianceId"
        ) VALUES (
            region_id,
            zone_id,
            'Region ' || zone_name,
            FALSE,
            NULL
        );
        region_id := region_id + 1;

        INSERT INTO public."Troop" (
            "Id","ZoneId","Count","MaxCount","Hp","Level",
            "Strength","Durability","Speed","Experience","UpgradePoints"
        ) VALUES (
            gen_random_uuid()::TEXT, zone_id, t_count, t_count, t_hp, lvl,
            t_strength, t_durability, 2.0, 0, 0
        );

        FOR hero_num IN 1..5 LOOP
            hero_name := prefixes[(floor(random() * array_length(prefixes, 1)) + 1)::INT];
            IF random() > 0.5 THEN
                hero_name := hero_name
                             || middles[(floor(random() * array_length(middles, 1)) + 1)::INT];
            END IF;
            hero_name := hero_name
                         || h_suffixes[(floor(random() * array_length(h_suffixes, 1)) + 1)::INT];
            hero_id := gen_random_uuid()::TEXT;

            h_type := types[(floor(random() * array_length(types, 1)) + 1)::INT];
            h_str  := ROUND(h_strength * (CASE WHEN h_type = 'attack'  THEN fav ELSE les END), 2);
            h_dur  := ROUND(h_strength * (CASE WHEN h_type = 'defense' THEN fav ELSE les END), 2);
            h_spd  := ROUND(2.0        * (CASE WHEN h_type = 'speed'   THEN fav ELSE les END), 2);

            INSERT INTO public."Hero" (
                "Id","ZoneId","Name","Type","Element","Status",
                "Hp","HealTime","MaxHp","IsAI","IsRuler","Level","Experience",
                "Strength","Durability","Speed","SDLUpgradePoints","Position","Rank"
            ) VALUES (
                hero_id, zone_id, hero_name,
                h_type,
                elements[hero_num], 'active',
                h_hp, 0, h_hp, TRUE,
                CASE WHEN hero_num = 1 THEN TRUE ELSE FALSE END,
                lvl, 0,
                h_str, h_dur, h_spd, 0,
                hero_num, 0
            );

            hero_count := hero_count + 1;
        END LOOP;

    END LOOP; -- outlaw zones

    RAISE NOTICE 'Done. Inserted % zones (each on the BaseLock register), % regions, % heroes, % troops.',
                 zone_count, zone_count, hero_count, zone_count;

END $$;
