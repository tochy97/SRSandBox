-- Five of every piece into every player's stores: five Heads, five Chests,
-- five Legs, five Shields and five Swords apiece, twenty-five a player. Bare
-- and unranked, at level 1 and tier C, worth what the Crafter's own pieces
-- are worth: the slot decides what a piece lifts (see Gear.StatFor) and every
-- piece is a tenth of it; a shield lifts nothing, and only the weapon is an
-- arm. In the stores rather than on anybody (no hero), so each player puts
-- them on from a hero's card. Ids carry on from the last piece in the table.
--
-- Run against a world (game_0), as often as you like: it always adds.
--
--     psql -U postgres -d game_0 -f database/userequips.sql

INSERT INTO public."Equip"
    ("Id", "UserId", "HeroId", "Level", "Name", "Type", "Tier", "WeaponType",
     "Rank", "RankProgress", "BuffAmount", "BuffType")
SELECT
    (SELECT COALESCE(MAX("Id"), 0) FROM public."Equip")
        + ROW_NUMBER() OVER (ORDER BY u."Id", piece.slot, copy.n),
    u."Id",
    NULL,
    1,
    piece.name,
    piece.slot,
    'C',
    piece.weapon,
    0,
    0,
    10,
    piece.buff
FROM public."User" AS u
CROSS JOIN (VALUES
    ('a', 'Head',   '',   'hdu'),
    ('c', 'Chest',  '',   'hdu'),
    ('l', 'Legs',   '',   'hsp'),
    ('s', 'Shield', '',   ''),
    ('w', 'Sword',  'sw', 'hst')
) AS piece(slot, name, weapon, buff)
CROSS JOIN generate_series(1, 5) AS copy(n);
