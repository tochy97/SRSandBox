-- A world: one game database game_0 with everything in it: the
-- players as "User" rows, their heroes, buildings, troops, the map's zones
-- and the rest. Who may sign in is not here but in the main database
-- (main.sql), which names this world for each account and the "User" id it
-- holds here. Each world has a chat database of its own beside it chat_0,
-- from SRMessage's chat.sql. The API builds a world from this file where it
-- is empty see Setup. Run this against an empty database only; it drops
-- and rebuilds every table.

-- ********************** Functions **********************

-- FUNCTION: public.update_updated_column()

DROP FUNCTION IF EXISTS public.update_updated_column() CASCADE;

CREATE OR REPLACE FUNCTION public.update_updated_column()
    RETURNS trigger
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE NOT LEAKPROOF
AS $BODY$
BEGIN
    NEW.updated = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$BODY$;

ALTER FUNCTION public.update_updated_column()
    OWNER TO postgres;

-- ********************** Tables **********************

---- Table: public.Alliance

DROP TABLE IF EXISTS public."Alliance" CASCADE;

CREATE TABLE IF NOT EXISTS public."Alliance"
(
    "Id" character(36) COLLATE pg_catalog."default" NOT NULL,
    "Name" text COLLATE pg_catalog."default",
    -- The badge in front of a member's name, and the colours the hall flies.
    -- Both are picked by whoever founds the alliance.
    "ShortName" text COLLATE pg_catalog."default",
    "Color" text COLLATE pg_catalog."default",
    -- What the name is written in over those colours. A banner can be any
    -- colour in the spectrum, and no rule picks readable lettering for all of
    -- them only the alliance can say. Null on one founded before there was
    -- one to pick, which every screen reads as white.
    "TextColor" text COLLATE pg_catalog."default",
    "X" numeric(6,2) NOT NULL,
    "Y" numeric(6,2) NOT NULL,
    "Level" integer NOT NULL,
    "Power" numeric(12,0) NOT NULL,
    -- The oil members have given in, and what skills are bought with. Bigint
    -- because a skill costs a million and a full tree is eight of them.
    "Donated" bigint NOT NULL DEFAULT 0,
    "Rank" text COLLATE pg_catalog."default",
    created timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT alliance_name_key UNIQUE ("Name"),
    CONSTRAINT alliance_pkey PRIMARY KEY ("Id")
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public."Alliance"
    OWNER to postgres;

-- Trigger: alliance_updated_at

DROP TRIGGER IF EXISTS alliance_updated_at ON public."Alliance" CASCADE;

CREATE OR REPLACE TRIGGER alliance_updated_at
    BEFORE UPDATE
    ON public."Alliance"
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_column();

-- The skills an alliance has taken. One row is the whole of it: a skill is
-- either taken or it is not, so the pair is both the identity and what stops
-- the same one being taken twice.
--
-- "Type" is a code out of Objects.json's AllianceSkillTypes and carries no
-- foreign key: the definitions are a file the server reads, not a table, so
-- there is nothing for the database to point at. The alliance is the only thing
-- a row references, and disbanding takes its skills with it.
--
-- An alliance's "Level" is the number of rows it has here.

---- Table: public.AllianceSkill

DROP TABLE IF EXISTS public."AllianceSkill" CASCADE;

CREATE TABLE IF NOT EXISTS public."AllianceSkill"
(
    "AllianceId" character(36) COLLATE pg_catalog."default" NOT NULL,
    "Type" text COLLATE pg_catalog."default" NOT NULL,
    "Unlocked" timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT allianceskill_pkey PRIMARY KEY ("AllianceId", "Type"),
    CONSTRAINT allianceskill_alliance_fkey FOREIGN KEY ("AllianceId")
        REFERENCES public."Alliance" ("Id") ON DELETE CASCADE
)
TABLESPACE pg_default;

ALTER TABLE IF EXISTS public."AllianceSkill"
    OWNER to postgres;

---- Table: public.User

DROP TABLE IF EXISTS public."User" CASCADE;

CREATE TABLE IF NOT EXISTS public."User"
(
    "Id" character(36) COLLATE pg_catalog."default" NOT NULL,
    "Name" text COLLATE pg_catalog."default",
    "X" numeric(6,2) NOT NULL,
    "Y" numeric(6,2) NOT NULL,
    "Level" integer NOT NULL,
    "TentHp" numeric(10,2) NOT NULL,
    "CarrierStrength" numeric(10,2) NOT NULL,
    "Power" numeric(12,0) NOT NULL,
    "WallLevel" integer NOT NULL DEFAULT 1,
    -- The palisade's own clock: the same three a "Building" row carries, kept
    -- here because the wall is not a building and has no row to keep them on.
    -- It waits on the capital's scale now, where it used to go up at once.
    "WallUpgrading" boolean NOT NULL DEFAULT false,
    "WallStartTime" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "WallSeconds" integer NOT NULL DEFAULT 0,
    -- The player's picture: the file's name in the picture store on the
    -- server's disk, served under /pictures. Empty for the default.
    "Picture" text COLLATE pg_catalog."default" NOT NULL DEFAULT '',
    -- What has been knocked off the holding since it last stood whole. Its
    -- health is ten times its power less this, worked out rather than stored
    -- see User.Health and every raid on it that succeeds adds the
    -- attacker's base power here; attacking costs nothing. At the ceiling the
    -- base is moved and this goes back to nothing.
    "HealthLost" bigint NOT NULL DEFAULT 0,
    -- How far the player has got on the steal run: the highest bridge crossed,
    -- which is also the run's ranking see BridgeMutations.RunBoard.
    "StealRun" integer NOT NULL DEFAULT 0,
    -- The duelling ring: the hero who stands for this player, and how that
    -- champion has fared. A drawn pass is neither a win nor a loss, so the
    -- two counts are the whole of the ranking see DuelMutations.
    "ChampionId" character(36) COLLATE pg_catalog."default",
    "DuelWins" integer NOT NULL DEFAULT 0,
    "DuelLosses" integer NOT NULL DEFAULT 0,
    -- The match standing in front of them: the player they were drawn against,
    -- or 'ai' for the tower's own champion, and nothing while they are not in
    -- a pass. Text rather than a player's id, since 'ai' is not one.
    "DuelOpponentId" text COLLATE pg_catalog."default",
    -- The rounds of that match, won and lost: best of three, the first to two
    -- takes it, and both back to nothing when it is decided or left.
    "DuelRoundsWon" integer NOT NULL DEFAULT 0,
    "DuelRoundsLost" integer NOT NULL DEFAULT 0,
    -- The day's allowance: five passes against the tower and five against other
    -- players, and the day the two counts belong to. A stamp from an older day
    -- is a fresh allowance see DuelMutations.MostADay.
    "DuelTowerPasses" integer NOT NULL DEFAULT 0,
    "DuelPlayerPasses" integer NOT NULL DEFAULT 0,
    "DuelPassesDay" timestamp with time zone,
    -- The camp standing at the gate: the zone whose company has come looking
    -- for this player, and nothing while none has. One at a time, and nothing
    -- may be sent out on the map while it stands -- see ChallengeMutations.
    "ChallengeZoneId" character(36) COLLATE pg_catalog."default",
    -- When a camp last came, which is two things: while the id above stands it
    -- is that camp's arrival, and once the challenge is answered it is left as
    -- the stamp the next draw is held off (ChallengeMutations.RestMinutes).
    "ChallengeAt" timestamp with time zone,
    -- The colours the player dresses their own army in, each 0xRRGGBB: armour,
    -- clothing, shield, and the plume on their heroes' helmets. Null is "never
    -- chosen", and the client draws its own defaults. Only ever seen by this
    -- player -- see PreferenceMutations.
    "ArmyArmour" integer,
    "ArmyCloth" integer,
    "ArmyShield" integer,
    "ArmyPlume" integer,
    -- Where the player is in the tutorial guide: the steps done, by the guide's
    -- own ids, and whether they asked it to stop. Kept here so a new device
    -- takes up where the old one left off.
    "GuideDone" text[] NOT NULL DEFAULT '{}',
    "GuideOptedOut" boolean NOT NULL DEFAULT false,
    "Hp" integer NOT NULL,
    "Rank" text COLLATE pg_catalog."default",
    "Gold" integer NOT NULL,
    "Energy" integer NOT NULL,
    "Metal" integer NOT NULL,
    "Food" integer NOT NULL,
    -- Timber. A store like the four above and nothing more yet: nothing is
    -- priced in it and no collector produces it, so it defaults to none and
    -- every existing player starts from there.
    "Wood" integer NOT NULL DEFAULT 0,
    "Diamond" integer NOT NULL,
    "ExpUpgradePoints" bigint NOT NULL,
    "EquipShards" integer,
    "AllianceId" character(36) COLLATE pg_catalog."default",
    "AlliancePosition" text COLLATE pg_catalog."default",
    created timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT user_name_key UNIQUE ("Name"),
    CONSTRAINT user_pkey PRIMARY KEY ("Id")
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public."User"
    OWNER to postgres;

-- Trigger: user_updated_at

DROP TRIGGER IF EXISTS user_updated_at ON public."User" CASCADE;

CREATE OR REPLACE TRIGGER user_updated_at
    BEFORE UPDATE
    ON public."User"
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_column();

---- Table: public.Zone

DROP TABLE IF EXISTS public."Zone" CASCADE;

CREATE TABLE IF NOT EXISTS public."Zone"
(
    "Id" character(36) COLLATE pg_catalog."default" NOT NULL,
    "Name" text COLLATE pg_catalog."default" NOT NULL,
    "Type" text COLLATE pg_catalog."default",
    "Resource" text COLLATE pg_catalog."default",
    "TentHp" numeric(10,2) NOT NULL,
    "CarrierStrength" numeric(10,2) NOT NULL,
    "Power" bigint NOT NULL,
    -- Its siege health once war is declared on it: twenty-five times its
    -- power see WarMutations.SiegeHpPerPower in long, since the
    -- strongest places' power is most of what an integer holds on its own.
    "Hp" bigint NOT NULL,
    "X" numeric(6,2) NOT NULL,
    "Y" numeric(6,2) NOT NULL,
    "Level" integer NOT NULL,
    "Gold" integer NOT NULL,
    "Metal" integer NOT NULL,
    "Food" integer NOT NULL,
    "Energy" integer NOT NULL,
    -- Timber. Nothing yields it yet there is no wood zone type so it is
    -- carried at none until there is.
    "Wood" integer NOT NULL DEFAULT 0,
    -- What a resource node held when it was laid down, so a screen can show
    -- how much of it is left against how much has been taken. Set with the
    -- stock at generation and again each time a worked-out node is laid
    -- down fresh (Zone.Restock); nothing for a settlement or a camp.
    "FullStock" integer NOT NULL DEFAULT 0,
    created timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT zone_pkey PRIMARY KEY ("Id")
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public."Zone"
    OWNER to postgres;

-- Trigger: zone_updated_at

DROP TRIGGER IF EXISTS zone_updated_at ON public."Zone" CASCADE;

CREATE OR REPLACE TRIGGER zone_updated_at
    BEFORE UPDATE
    ON public."Zone"
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_column();

---- Table: public.Region

DROP TABLE IF EXISTS public."Region" CASCADE;

CREATE TABLE IF NOT EXISTS public."Region"
(
    "Id" integer NOT NULL,
    "ZoneId" character(36) COLLATE pg_catalog."default" NOT NULL,
    "Name" text COLLATE pg_catalog."default" NOT NULL,
    "IsCapital" boolean NOT NULL,
    "AllianceId" character(36) COLLATE pg_catalog."default",
    -- Mapped by Region.Type and never declared here, so a database built from
    -- this file came up without it and every read of a region -- the alliance
    -- roster, its halls, the war that takes one -- failed on the missing
    -- column. Nothing sets it or reads it yet; it is here because the model
    -- maps it, and a model that maps a column the schema does not have is a
    -- table nobody can select from.
    "Type" text COLLATE pg_catalog."default" NOT NULL DEFAULT '',
    created timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT region_pkey PRIMARY KEY ("Id")
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public."Region"
    OWNER to postgres;

-- Trigger: region_updated_at

DROP TRIGGER IF EXISTS region_updated_at ON public."Region" CASCADE;

CREATE OR REPLACE TRIGGER region_updated_at
    BEFORE UPDATE
    ON public."Region"
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_column();

---- Table: public.Hero

DROP TABLE IF EXISTS public."Hero" CASCADE;

CREATE TABLE IF NOT EXISTS public."Hero"
(
    "Id" character(36) COLLATE pg_catalog."default" NOT NULL,
    "UserId" character(36) COLLATE pg_catalog."default" NULL,
    "ZoneId" character(36) COLLATE pg_catalog."default" NULL,
    "Name" text COLLATE pg_catalog."default" NOT NULL,
    "Type" text COLLATE pg_catalog."default" NOT NULL,
    "Element" text COLLATE pg_catalog."default" NOT NULL,
    "Status" text COLLATE pg_catalog."default" NOT NULL,
    "Hp" integer NOT NULL,
    "HealTime" integer NOT NULL,
    "HealStart" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "MaxHp" integer NOT NULL,
    "IsAI" boolean NOT NULL,
    "IsRuler" boolean NOT NULL,
    "Level" integer NOT NULL,
    "Experience" integer,
    "Strength" numeric(8,2) NOT NULL,
    "Durability" numeric(8,2) NOT NULL,
    "Speed" numeric(8,2) NOT NULL,
    "SDLUpgradePoints" integer NOT NULL,
    "Position" integer NOT NULL DEFAULT 0,
    "ImageIndex" integer NOT NULL DEFAULT 0,
    -- How far the hero has been decorated, 0 through 7. Raised with
    -- Phalerae -- see Hero.RankCost, which is the rank cubed -- and paid
    -- for a handful at a time, with what has gone in so far banked in
    -- "RankProgress" until it covers the next one.
    "Rank" integer NOT NULL DEFAULT 0,
    "RankProgress" integer NOT NULL DEFAULT 0,
    created timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT hero_pkey PRIMARY KEY ("Id"),
    CONSTRAINT hero_user_fkey FOREIGN KEY ("UserId")
        REFERENCES public."User" ("Id"),
    CONSTRAINT hero_zone_fkey FOREIGN KEY ("ZoneId")
        REFERENCES public."Zone" ("Id")
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public."Hero"
    OWNER to postgres;

-- Trigger: hero_updated_at

DROP TRIGGER IF EXISTS hero_updated_at ON public."Hero" CASCADE;

CREATE OR REPLACE TRIGGER hero_updated_at
    BEFORE UPDATE
    ON public."Hero"
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_column();

---- Table: public.Skill

DROP TABLE IF EXISTS public."Skill" CASCADE;

CREATE TABLE IF NOT EXISTS public."Skill"
(
    "Id" integer NOT NULL,
    "Level" integer NOT NULL,
    -- Which skill it is: the code of the usable spent to give it "msk",
    -- "cat", "arc". See Models/Shared/SkillUsable.cs.
    "Type" text COLLATE pg_catalog."default" NOT NULL DEFAULT '',
    "HeroId" text COLLATE pg_catalog."default" NULL,
    "UserId" text COLLATE pg_catalog."default" NOT NULL,
    created timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT skill_pkey PRIMARY KEY ("UserId","Id"),
    CONSTRAINT skill_user_fkey FOREIGN KEY ("UserId")
        REFERENCES public."User" ("Id"),
    CONSTRAINT skill_hero_fkey FOREIGN KEY ("HeroId")
        REFERENCES public."Hero" ("Id")
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public."Skill"
    OWNER to postgres;

-- Trigger: skill_updated_at

DROP TRIGGER IF EXISTS skill_updated_at ON public."Skill" CASCADE;

CREATE OR REPLACE TRIGGER skill_updated_at
    BEFORE UPDATE
    ON public."Skill"
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_column();

---- Table: public.Troop

DROP TABLE IF EXISTS public."Troop" CASCADE;

-- The men a side fields, one body per holding rather than one per hero.
-- Exactly one of "UserId" and "ZoneId" is set, and each holding has at most one
-- row, which the unique indexes at the end of the file are what actually enforce.
CREATE TABLE IF NOT EXISTS public."Troop"
(
    "Id" character(36) COLLATE pg_catalog."default" NOT NULL,
    "UserId" character(36) COLLATE pg_catalog."default",
    "ZoneId" character(36) COLLATE pg_catalog."default",
    "Count" integer NOT NULL,
    "MaxCount" integer NOT NULL,
    -- The batch in training: how many were bought, how long they were quoted,
    -- and when the clock started. RecruitCount is 0 when nobody is training.
    "RecruitCount" integer NOT NULL DEFAULT 0,
    "RecruitSeconds" integer NOT NULL DEFAULT 0,
    -- With the zone, matching Building."StartTime". EF maps a DateTime to
    -- timestamptz by default, and a column declared without one hands values
    -- back with an unspecified Kind that it then refuses to write again.
    "RecruitStart" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "Hp" integer NOT NULL,
    "Level" integer NOT NULL,
    "Strength" numeric(8,2) NOT NULL,
    "Durability" numeric(8,2) NOT NULL,
    "Speed" numeric(8,2) NOT NULL,
    "Experience" integer NOT NULL,
    "UpgradePoints" integer NOT NULL,
    created timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT troop_pkey PRIMARY KEY ("Id"),
    CONSTRAINT troop_owner_chk CHECK (("UserId" IS NULL) <> ("ZoneId" IS NULL)),
    CONSTRAINT troop_user_fkey FOREIGN KEY ("UserId")
        REFERENCES public."User" ("Id") ON DELETE CASCADE,
    CONSTRAINT troop_zone_fkey FOREIGN KEY ("ZoneId")
        REFERENCES public."Zone" ("Id") ON DELETE CASCADE
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public."Troop"
    OWNER to postgres;

-- Trigger: troop_updated_at

DROP TRIGGER IF EXISTS troop_updated_at ON public."Troop" CASCADE;

CREATE OR REPLACE TRIGGER troop_updated_at
    BEFORE UPDATE
    ON public."Troop"
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_column();

---- Table: public.Equip

DROP TABLE IF EXISTS public."Equip" CASCADE;

CREATE TABLE IF NOT EXISTS public."Equip"
(
    "Id" integer NOT NULL,
    "UserId" character(36) NULL,
    "HeroId" character(36) NULL,
    "Level" integer NOT NULL,
    "Name" text NOT NULL,
    "Type" text COLLATE pg_catalog."default" NOT NULL,
    "Tier" text COLLATE pg_catalog."default" NOT NULL,
    "WeaponType" character varying(5) COLLATE pg_catalog."default",
    "ShardsRequired" integer,
    "ShardsConsumed" integer,
    -- The pins on the piece, out of seven, and what has been put towards the
    -- next one. The same Phalerae a hero wears see Gear.
    "Rank" integer NOT NULL DEFAULT 0,
    "RankProgress" integer NOT NULL DEFAULT 0,
    "BuffAmount" integer NOT NULL,
    "BuffType" character varying(5) COLLATE pg_catalog."default" NOT NULL,
    created timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT equip_pkey PRIMARY KEY ("Id"),
    CONSTRAINT equip_hero_fkey FOREIGN KEY ("HeroId")
        REFERENCES public."Hero" ("Id"),
    CONSTRAINT equip_user_fkey FOREIGN KEY ("UserId")
        REFERENCES public."User" ("Id")
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public."Equip"
    OWNER to postgres;

-- Trigger: equip_updated_at

DROP TRIGGER IF EXISTS equip_updated_at ON public."Equip" CASCADE;

CREATE OR REPLACE TRIGGER equip_updated_at
    BEFORE UPDATE
    ON public."Equip"
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_column();

---- Table: public.Building

DROP TABLE IF EXISTS public."Building" CASCADE;

CREATE TABLE IF NOT EXISTS public."Building"
(
    "UserId" character(36) COLLATE pg_catalog."default" NOT NULL,
    "Id" integer NOT NULL,
    "Type" text COLLATE pg_catalog."default" NOT NULL,
    "Upgrading" boolean,
    "Level" integer NOT NULL,
    "StartTime" timestamp with time zone,
    "PreviousMinRequired" integer,
    "MinRequired" integer NOT NULL,
    "BuffAmount" integer,
    "BuffType" text COLLATE pg_catalog."default",
    "X" numeric(6,2),
    "Y" numeric(6,2),
    created timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT building_pkey PRIMARY KEY ("UserId", "Id"),
    CONSTRAINT building_user_fkey FOREIGN KEY ("UserId")
        REFERENCES public."User" ("Id")
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public."Building"
    OWNER to postgres;

-- Trigger: building_updated_at

DROP TRIGGER IF EXISTS building_updated_at ON public."Building" CASCADE;

CREATE OR REPLACE TRIGGER building_updated_at
    BEFORE UPDATE
    ON public."Building"
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_column();

---- Table: public.Buff

DROP TABLE IF EXISTS public."Buff" CASCADE;

CREATE TABLE IF NOT EXISTS public."Buff"
(
    "Id" integer NOT NULL,
    "UserId" character(36) COLLATE pg_catalog."default" NOT NULL,
    "Amount" integer,
    "Type" text COLLATE pg_catalog."default",
    "EndTime" timestamp with time zone,
    "ApplyType" text COLLATE pg_catalog."default",
    created timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT buff_pkey PRIMARY KEY ("UserId", "Id"),
    CONSTRAINT buff_user_fkey FOREIGN KEY ("UserId")
        REFERENCES public."User" ("Id")
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public."Buff"
    OWNER to postgres;

-- Trigger: buff_updated_at

DROP TRIGGER IF EXISTS buff_updated_at ON public."Buff" CASCADE;

CREATE OR REPLACE TRIGGER buff_updated_at
    BEFORE UPDATE
    ON public."Buff"
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_column();

---- Table: public.Collector

DROP TABLE IF EXISTS public."Collector" CASCADE;

CREATE TABLE IF NOT EXISTS public."Collector"
(
    "UserId" character(36) COLLATE pg_catalog."default" NOT NULL,
    "Id" integer NOT NULL,
    "Type" text COLLATE pg_catalog."default" NOT NULL,
    "LastCollect" timestamp with time zone,
    "Max" integer NOT NULL,
    "Base" numeric(6,2),
    "Level" integer,
    created timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT collector_pkey PRIMARY KEY ("UserId", "Id"),
    CONSTRAINT collector_user_fkey FOREIGN KEY ("UserId")
        REFERENCES public."User" ("Id")
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public."Collector"
    OWNER to postgres;

-- Trigger: collector_updated_at

DROP TRIGGER IF EXISTS collector_updated_at ON public."Collector" CASCADE;

CREATE OR REPLACE TRIGGER collector_updated_at
    BEFORE UPDATE
    ON public."Collector"
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_column();

---- Table: public.Research

DROP TABLE IF EXISTS public."Research" CASCADE;

CREATE TABLE IF NOT EXISTS public."Research"
(
    "UserId" character(36) COLLATE pg_catalog."default" NOT NULL,
    "Id" integer NOT NULL,
    "Type" text COLLATE pg_catalog."default" NOT NULL,
    "Upgrading" boolean NOT NULL,
    "Level" integer NOT NULL,
    "StartTime" timestamp with time zone,
    "PreviousMinRequired" integer NOT NULL,
    "MinRequired" integer NOT NULL,
    "BuffAmount" integer NOT NULL,
    "BuffType" text COLLATE pg_catalog."default" NOT NULL,
    "Increment" integer NOT NULL,
    created timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT research_pkey PRIMARY KEY ("UserId", "Id"),
    CONSTRAINT research_user_fkey FOREIGN KEY ("UserId")
        REFERENCES public."User" ("Id")
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public."Research"
    OWNER to postgres;

-- Trigger: research_updated_at

DROP TRIGGER IF EXISTS research_updated_at ON public."Research" CASCADE;

CREATE OR REPLACE TRIGGER research_updated_at
    BEFORE UPDATE
    ON public."Research"
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_column();

---- Table: public.Usable

DROP TABLE IF EXISTS public."Usable" CASCADE;

CREATE TABLE IF NOT EXISTS public."Usable"
(
    "Id" integer NOT NULL,
    "UserId" character(36) COLLATE pg_catalog."default" NOT NULL,
    "Type" text COLLATE pg_catalog."default" NOT NULL,
    "Category" text COLLATE pg_catalog."default" NOT NULL,
    "Amount" integer NOT NULL,
    "IsActive" boolean NOT NULL,
    "BuffAmount" integer NOT NULL,
    "BuffType" text COLLATE pg_catalog."default" NOT NULL,
    "ApplyType" text COLLATE pg_catalog."default",
    created timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT usable_pkey PRIMARY KEY ("UserId", "Id"),
    CONSTRAINT usable_user_fkey FOREIGN KEY ("UserId")
        REFERENCES public."User" ("Id")
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public."Usable"
    OWNER to postgres;

-- Trigger: usable_updated_at

DROP TRIGGER IF EXISTS usable_updated_at ON public."Usable" CASCADE;

CREATE OR REPLACE TRIGGER usable_updated_at
    BEFORE UPDATE
    ON public."Usable"
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_column();

---- Table: public.ArmyCombatStats

DROP TABLE IF EXISTS public."ArmyCombatStats" CASCADE;

CREATE TABLE IF NOT EXISTS public."ArmyCombatStats"
(
    "Id" serial PRIMARY KEY,
    "UserId" character(36) COLLATE pg_catalog."default" NOT NULL,
    "Winner" boolean NOT NULL,
    "WinnerId" text NOT NULL,
    "WinnerName" text NOT NULL,
    "WinnerNewHp" integer NOT NULL,
    "LooserId" text NOT NULL,
    "LooserName" text NOT NULL,
    "LooserNewHp" integer NOT NULL,
    "FirstUserId" text NOT NULL,
    "SecondUserId" text NOT NULL,
    "Count" integer NOT NULL,
    "UserWallHp" integer NOT NULL DEFAULT -1,
    "EnemyWallHp" integer NOT NULL DEFAULT -1,
    "EnemyName" text NOT NULL DEFAULT '',
    "EnemyType" text NOT NULL DEFAULT '',
    -- Whether the player has looked at this record. False only on the copy
    -- filed for a player who was raided, until they open their history.
    "Seen" boolean NOT NULL DEFAULT true,
    -- Whether this fight took the last of the loser's health and moved their
    -- base. On both sides' copies.
    "Overrun" boolean NOT NULL DEFAULT false,
    created timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT armyCombatStats_user_fkey FOREIGN KEY ("UserId")
        REFERENCES public."User" ("Id")
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public."ArmyCombatStats"
    OWNER to postgres;

-- Trigger: armyCombatStats_updated_at

DROP TRIGGER IF EXISTS armyCombatStats_updated_at ON public."ArmyCombatStats" CASCADE;

CREATE OR REPLACE TRIGGER armyCombatStats_updated_at
    BEFORE UPDATE
    ON public."ArmyCombatStats"
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_column();

---- Table: public.SingleCombatStats

DROP TABLE IF EXISTS public."SingleCombatStats" CASCADE;

CREATE TABLE IF NOT EXISTS public."SingleCombatStats"
(
    "Id" serial PRIMARY KEY,
    "ArmyCombatStatsId" integer NOT NULL,
    "Index" integer NOT NULL,
    "UserId" text NOT NULL DEFAULT ''::text,
    "HeroId" character(36) NOT NULL,
    "HeroName" text NOT NULL,
    "HeroMaxHp" integer NOT NULL,
    "HeroLevel" integer NOT NULL,
    "HeroElement" text NOT NULL,
    "NewHeroHp" integer NOT NULL,
    "HeroDamageTaken" integer NOT NULL,
    "HeroHitCount" double PRECISION NOT NULL,
    "HeroDamageCaused" integer NOT NULL,
    "NewTroopCount" integer NOT NULL,
    "HurtTroopCount" integer NOT NULL,
    "DeadTroopCount" integer NOT NULL,
    "TroopLevel" integer NOT NULL,
    "TroopDamageCaused" integer NOT NULL,
    "TroopsWallDamage" integer NOT NULL,
    "Winner" boolean NOT NULL,
    "Count" integer NOT NULL,
    created timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT singleCombatStat_armycombatstats_fkey FOREIGN KEY ("ArmyCombatStatsId")
        REFERENCES "ArmyCombatStats"("Id")
        ON DELETE CASCADE
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public."SingleCombatStats"
    OWNER to postgres;

-- Trigger: singleCombatStats_updated_at

DROP TRIGGER IF EXISTS singleCombatStats_updated_at ON public."SingleCombatStats" CASCADE;

CREATE OR REPLACE TRIGGER singleCombatStats_updated_at
    BEFORE UPDATE
    ON public."SingleCombatStats"
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_column();

---- Table: public.Story

DROP TABLE IF EXISTS public."Story" CASCADE;

CREATE TABLE IF NOT EXISTS public."Story"
(
    "Id" integer NOT NULL,
    "UserId" text NOT NULL,
    "Type" text NOT NULL,
    "Rating" integer NOT NULL,
    created timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT story_pkey PRIMARY KEY ("UserId", "Id"),
    CONSTRAINT story_user_fkey FOREIGN KEY ("UserId")
        REFERENCES "User"("Id")
        ON DELETE CASCADE
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public."Story"
    OWNER to postgres;

-- Trigger: story_updated_at

DROP TRIGGER IF EXISTS story_updated_at ON public."Story" CASCADE;

CREATE OR REPLACE TRIGGER story_updated_at
    BEFORE UPDATE
    ON public."Story"
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_column();

-- How far a player has got on one AI base's bridge. Progress is per base, not
-- per player: every settlement has its own set of ten crossings. An absent row
-- means level zero, so nothing has to be seeded.

---- Table: public.BridgeProgress

DROP TABLE IF EXISTS public."BridgeProgress" CASCADE;

CREATE TABLE IF NOT EXISTS public."BridgeProgress"
(
    "UserId" text COLLATE pg_catalog."default" NOT NULL,
    "ZoneId" text COLLATE pg_catalog."default" NOT NULL,
    "Level" integer NOT NULL DEFAULT 0,
    "Updated" timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT bridgeprogress_pkey PRIMARY KEY ("UserId", "ZoneId")
)
TABLESPACE pg_default;

ALTER TABLE IF EXISTS public."BridgeProgress"
    OWNER to postgres;

-- Every campaign an alliance has declared against a settlement, and how far
-- that settlement was worn down while it lasted.
--
-- A war belongs to the alliance, not to whoever pressed the button, so the
-- player is nowhere in this table: every member sees the same war, and the
-- record outlives any of them. A war stamped with its declarer would leave the
-- history reading as a list of individuals, and a member who left would take
-- their part of it with them.
--
-- A row is never deleted. Standing down stamps "Ended" and leaves the row where
-- it is, which is what makes this a history as well as a state: an alliance's
-- record is every row it ever declared, and a war that could be deleted would
-- take that record with it. The war an alliance is currently waging is its row
-- with no "Ended" on it, and the partial unique index at the end of the file is
-- what holds it to one at a time.
--
-- "StartHp" is what the place stood at the day war was declared and never moves
-- again; "Hp" is what it was last seen at. The pair is the progress of the war,
-- which neither figure could tell on its own. Nothing pushes the second one
-- a raid writes the zone and knows nothing about who is campaigning against it
-- so it is brought up to date whenever the war is read.
--
-- The settlement is referenced and not copied, so its name, level and
-- coordinates are always the current ones.

---- Table: public.War

DROP TABLE IF EXISTS public."War" CASCADE;

CREATE TABLE IF NOT EXISTS public."War"
(
    -- character(36), not text: these carry foreign keys, and the ids they point
    -- at are declared that way. A guid is exactly thirty-six characters, so
    -- nothing is padded.
    "Id" character(36) COLLATE pg_catalog."default" NOT NULL,
    "ZoneId" character(36) COLLATE pg_catalog."default" NOT NULL,
    "AllianceId" character(36) COLLATE pg_catalog."default" NOT NULL,
    "StartHp" bigint NOT NULL DEFAULT 0,
    "Hp" bigint NOT NULL DEFAULT 0,
    "Declared" timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "Updated" timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    -- When it finished and how, and the two move together: 'c' called off, 'w'
    -- carried, 'r' carried and let go see War.Outcome. A record that only
    -- said a war had finished would be a list of dates which of them an
    -- alliance won is the whole of what it is for. The check used to know
    -- only 'c' and 'w', so releasing a fallen settlement fell over on it.
    "Ended" timestamp without time zone,
    "Outcome" text COLLATE pg_catalog."default",
    CONSTRAINT war_outcome_chk CHECK (
        ("Ended" IS NULL AND "Outcome" IS NULL)
        OR ("Ended" IS NOT NULL AND "Outcome" IN ('c', 'w', 'r'))),
    CONSTRAINT war_pkey PRIMARY KEY ("Id"),
    -- Disbanding takes the alliance's wars with it: there is nobody left to be
    -- waging them, and a record belonging to an alliance that no longer exists
    -- is a record nothing can read.
    CONSTRAINT war_alliance_fkey FOREIGN KEY ("AllianceId")
        REFERENCES public."Alliance" ("Id") ON DELETE CASCADE,
    CONSTRAINT war_zone_fkey FOREIGN KEY ("ZoneId")
        REFERENCES public."Zone" ("Id") ON DELETE CASCADE
)
TABLESPACE pg_default;

ALTER TABLE IF EXISTS public."War"
    OWNER to postgres;

-- Where everything stands on the world map, and how much ground it covers.
-- Every player and every zone has a row, so "is this spot free" is one query
-- against one table rather than a walk over Users and Zones working out each
-- footprint on the way past.
--
-- Pending = false is where the owner is now, and never lapses.
-- Pending = true  is a spot held while they decide whether to move there;
--                 ExpiresAt is the safety net for a client that never answers.
-- An owner may hold both at once, which is why the key is "Id" (the owner id,
-- or the owner id + ':p' for a pending row) rather than the owner.

---- Table: public.BaseLock

DROP TABLE IF EXISTS public."BaseLock" CASCADE;

CREATE TABLE IF NOT EXISTS public."BaseLock"
(
    "Id" text COLLATE pg_catalog."default" NOT NULL,
    "OwnerId" text COLLATE pg_catalog."default" NOT NULL,
    "Kind" text COLLATE pg_catalog."default" NOT NULL,
    "Pending" boolean NOT NULL DEFAULT false,
    "X" double precision NOT NULL,
    "Y" double precision NOT NULL,
    "Width" double precision NOT NULL,
    "Height" double precision NOT NULL,
    "ExpiresAt" timestamp without time zone,
    "Created" timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT baselock_pkey PRIMARY KEY ("Id")
)
TABLESPACE pg_default;

ALTER TABLE IF EXISTS public."BaseLock"
    OWNER to postgres;

---- Table: public.March
--
-- The army -- or one hero -- out on the world map.
--
-- The key is the player and the hero, which is the lock: the army's attack
-- names no hero ('' in "HeroId"), so a player has one; a gathering run names the
-- hero digging, so a hero has one road and a player may have several out. A row
-- exists only while somebody is out; coming home deletes it.
--
-- Out and back are one row, not two. Both legs are the same distance, so
-- "Seconds" is what a leg takes and "Phase" says which stretch is being walked
-- -- 'o' out, 'w' working the node, 'b' back -- and each stretch restamps
-- "StartTime" rather than laying a second row, so there is never a moment where
-- a journey has two rows or none. "WorkSeconds" is the middle stretch, set when
-- a gathering run arrives and is put to work, and zero on an attack.
--
-- The destination is a kind and an id rather than a foreign key, because it may
-- be a player's holding or a settlement and those are different tables. Nothing
-- else about it is copied in: a place that is worn down or moved while the army
-- walks is met as it is on arrival.
--
-- Kept in step with march.sql, which is the same table for a database that is
-- already up.

DROP TABLE IF EXISTS public."March" CASCADE;

CREATE TABLE IF NOT EXISTS public."March"
(
    "UserId" character(36) COLLATE pg_catalog."default" NOT NULL,
    -- What it went to do: 'a' attack, 'g' gather.
    "Errand" text COLLATE pg_catalog."default" NOT NULL,
    -- Where: 'u' a player's holding, 'z' a settlement or node.
    "TargetType" text COLLATE pg_catalog."default" NOT NULL,
    "TargetId" text COLLATE pg_catalog."default" NOT NULL,
    -- The one hero sent to gather. Empty on an attack, which takes the lot.
    "HeroId" text COLLATE pg_catalog."default" NOT NULL DEFAULT '',
    -- Which stretch is being walked: 'o' out, 'w' working the node, 'b' back.
    "Phase" character(1) COLLATE pg_catalog."default" NOT NULL,
    "StartTime" timestamp with time zone NOT NULL,
    -- One leg, in seconds. An hour is the longest there is, corner to corner.
    "Seconds" integer NOT NULL,
    -- The work at the node, in seconds. Zero until a gather arrives; zero on an attack.
    "WorkSeconds" integer NOT NULL DEFAULT 0,
    created timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT march_pkey PRIMARY KEY ("UserId", "HeroId"),
    CONSTRAINT march_user_fkey FOREIGN KEY ("UserId")
        REFERENCES public."User" ("Id")
        ON DELETE CASCADE
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public."March"
    OWNER to postgres;

-- Trigger: march_updated_at

DROP TRIGGER IF EXISTS march_updated_at ON public."March" CASCADE;

CREATE OR REPLACE TRIGGER march_updated_at
    BEFORE UPDATE
    ON public."March"
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_column();

---- Table: public.Craft
--
-- Work on the Crafter's bench.
--
-- One row to a player, which is the lock: one bench, one thing on it. A row
-- exists only while something is being made, and taking the work off the bench
-- deletes it.
--
-- What is being made is a kind and a code rather than a half-built row in
-- "Equip". Nothing exists until it is collected: a piece whose tier were rolled
-- at the press would be one the player could see the tier of before deciding to
-- wait for it, and one banked in "Equip" would have to be marked somehow as not
-- yet theirs.
--
-- The price is taken at the press rather than at the collection, or a bench
-- could be filled for nothing and emptied when the shards finally arrived.

DROP TABLE IF EXISTS public."Craft" CASCADE;

CREATE TABLE IF NOT EXISTS public."Craft"
(
    "UserId" character(36) COLLATE pg_catalog."default" NOT NULL,
    -- Which Crafter the work is on: the building's own id on that base. One
    -- order to a bench, and a base may raise more than one bench.
    "Id" integer NOT NULL DEFAULT 0,
    -- Which bench: 'e' equipment, 's' a skill.
    "Kind" text COLLATE pg_catalog."default" NOT NULL,
    -- What was ordered: a slot code on the one bench, a skill's code on the
    -- other.
    "Type" text COLLATE pg_catalog."default" NOT NULL,
    -- Which arm, where the order is for the weapon slot.
    "WeaponType" text COLLATE pg_catalog."default" NOT NULL DEFAULT '',
    -- The crafter's level when the order was placed, which is what decides how
    -- good a tier can be rolled. Kept, so a building raised while the work sat
    -- there does not improve work it had no hand in.
    "Level" integer NOT NULL DEFAULT 1,
    "StartTime" timestamp with time zone NOT NULL,
    -- A day at the first level, a quarter hour less at every one above it.
    "Seconds" integer NOT NULL,
    created timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT craft_pkey PRIMARY KEY ("UserId", "Id"),
    CONSTRAINT craft_user_fkey FOREIGN KEY ("UserId")
        REFERENCES public."User" ("Id")
        ON DELETE CASCADE
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public."Craft"
    OWNER to postgres;

-- Trigger: craft_updated_at

DROP TRIGGER IF EXISTS craft_updated_at ON public."Craft" CASCADE;

CREATE OR REPLACE TRIGGER craft_updated_at
    BEFORE UPDATE
    ON public."Craft"
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_column();

---- Table: public.Gift
--
-- The day's tribute from the settlements an alliance took in war, and when one
-- member last took it.
--
-- One row to a player, which is the lock: the gift belongs to the member rather
-- than to any settlement, so holding four places is four places to collect the
-- same one gift from and not four gifts.
--
-- What was given is not kept, and neither is which settlement decided anything.
-- The clock is the whole of the state -- the item is drawn at the moment of
-- collection, and one decided in advance would be one the player could see
-- before choosing whether to take it.

DROP TABLE IF EXISTS public."Gift" CASCADE;

CREATE TABLE IF NOT EXISTS public."Gift"
(
    "UserId" character(36) COLLATE pg_catalog."default" NOT NULL,
    -- Which settlement gave it. Kept so the screen can say where today's went;
    -- nothing reads it to decide anything.
    "ZoneId" character(36) COLLATE pg_catalog."default" NOT NULL,
    -- When this member last took a gift, from anywhere. The next is due at the
    -- midnight ending that day, not a rolling twenty-four hours after it.
    "Taken" timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT gift_pkey PRIMARY KEY ("UserId"),
    CONSTRAINT gift_user_fkey FOREIGN KEY ("UserId")
        REFERENCES public."User" ("Id")
        ON DELETE CASCADE
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public."Gift"
    OWNER to postgres;

-- Trigger: gift_updated_at

DROP TRIGGER IF EXISTS gift_updated_at ON public."Gift" CASCADE;

CREATE OR REPLACE TRIGGER gift_updated_at
    BEFORE UPDATE
    ON public."Gift"
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_column();

---- Table: public.Haul
--
-- What a gathering run brought home: which hero, from which node, how much of
-- what, and when. A record rather than a state -- the march is the state of a
-- run and is gone when the hero is back in; this is written the moment the
-- haul goes into the stores and never touched again, so the battle history can
-- list a dig beside a fight.
--
-- The names are copied in rather than joined: a node moves, is worked out and
-- renamed, and a hero is dismissed. The record keeps the names things had when
-- it happened, the way a battle record keeps the enemy's.

DROP TABLE IF EXISTS public."Haul" CASCADE;

CREATE TABLE IF NOT EXISTS public."Haul"
(
    "Id" integer NOT NULL GENERATED BY DEFAULT AS IDENTITY,
    "UserId" character(36) COLLATE pg_catalog."default" NOT NULL,
    "HeroId" text COLLATE pg_catalog."default" NOT NULL,
    "HeroName" text COLLATE pg_catalog."default" NOT NULL DEFAULT '',
    "ZoneId" text COLLATE pg_catalog."default" NOT NULL,
    -- The node's kind as shown -- "Metal Ore" -- not its generated place name.
    "ZoneName" text COLLATE pg_catalog."default" NOT NULL DEFAULT '',
    -- What was dug, as the resource's ApplyType code: m, f, w, e, g.
    "Resource" text COLLATE pg_catalog."default" NOT NULL,
    "Amount" integer NOT NULL,
    created timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT haul_pkey PRIMARY KEY ("Id"),
    CONSTRAINT haul_user_fkey FOREIGN KEY ("UserId")
        REFERENCES public."User" ("Id")
        ON DELETE CASCADE
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public."Haul"
    OWNER to postgres;

-- A scout sent at a holding: who sent them, at what, whether they got a look
-- and what they saw -- the defence as the pre-battle screen draws it, at the
-- moment of the look, kept as text since a report is a picture of a moment.
-- For "Seconds" after it was sent the row is also a scout away from home,
-- which is what holds a player to the scouts they have. See Scout.cs and
-- ScoutMutations.

---- Table: public.Scout

DROP TABLE IF EXISTS public."Scout" CASCADE;

CREATE TABLE IF NOT EXISTS public."Scout"
(
    "Id" character(36) COLLATE pg_catalog."default" NOT NULL,
    "UserId" character(36) COLLATE pg_catalog."default" NOT NULL,
    "UserName" text COLLATE pg_catalog."default" NOT NULL DEFAULT '',
    -- "u" for a player's base, "z" for a settlement.
    "TargetType" text COLLATE pg_catalog."default" NOT NULL,
    "TargetId" text COLLATE pg_catalog."default" NOT NULL,
    "TargetName" text COLLATE pg_catalog."default" NOT NULL DEFAULT '',
    -- The chance the scout had, in percent: the sender's Watch Tower level, capped.
    "Chance" integer NOT NULL,
    "Success" boolean NOT NULL,
    "Report" text COLLATE pg_catalog."default" NOT NULL DEFAULT '',
    -- How long the scout is away: the walk there and home.
    "Seconds" integer NOT NULL,
    created timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT scout_pkey PRIMARY KEY ("Id"),
    CONSTRAINT scout_user_fkey FOREIGN KEY ("UserId")
        REFERENCES public."User" ("Id")
        ON DELETE CASCADE
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public."Scout"
    OWNER to postgres;

---- Table: public.Sack

-- Stores taken off a player: who came for them, and how much of each was
-- carried off. The other direction from "Haul", and kept the same way -- a
-- record written the moment the stores come down and never touched again,
-- because it is the only thing that tells a player what a raid on them
-- actually cost; a battle record says they were attacked and says nothing
-- about the warehouse.
--
-- Three things file one: a camp at the gate given up, a camp at the gate that
-- won, and another player carrying the holding in a raid. All three are one
-- thing from the player's side -- a defence that was not made -- and all three
-- cost a twentieth of every store. See Sack.cs and ChallengeMutations.Sacked,
-- which is the one place any of it is worked out.
--
-- The amounts are what was taken, and they are a loss rather than a transfer:
-- nothing is credited to whoever came, whose own spoils are a separate
-- reckoning (UserMutations.GenerateRewards).

DROP TABLE IF EXISTS public."Sack" CASCADE;

CREATE TABLE IF NOT EXISTS public."Sack"
(
    "Id" integer NOT NULL GENERATED BY DEFAULT AS IDENTITY,
    "UserId" character(36) COLLATE pg_catalog."default" NOT NULL,
    -- Who came: "z" a camp off the world map, "u" another player.
    "ByType" text COLLATE pg_catalog."default" NOT NULL,
    "ById" text COLLATE pg_catalog."default" NOT NULL,
    -- Their name at the time.
    "ByName" text COLLATE pg_catalog."default" NOT NULL DEFAULT '',
    -- Where they came from -- the camp's tents or the raider's base -- as they
    -- stood when the stores came down. Kept, like the name, because neither
    -- stays put. Null on a row filed before this was kept.
    "FromX" double precision,
    "FromY" double precision,
    -- Whether it was given up rather than fought out. Only a camp's challenge
    -- can be given up, so this is false for every "u".
    "GaveUp" boolean NOT NULL DEFAULT false,
    "Gold" integer NOT NULL DEFAULT 0,
    "Metal" integer NOT NULL DEFAULT 0,
    "Food" integer NOT NULL DEFAULT 0,
    "Wood" integer NOT NULL DEFAULT 0,
    "Energy" integer NOT NULL DEFAULT 0,
    created timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT sack_pkey PRIMARY KEY ("Id"),
    CONSTRAINT sack_user_fkey FOREIGN KEY ("UserId")
        REFERENCES public."User" ("Id")
        ON DELETE CASCADE
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public."Sack"
    OWNER to postgres;

-- ********************** Indexes **********************

-- Index: fki_Hero_ArmyId_fkey

CREATE INDEX IF NOT EXISTS "fki_Hero_ArmyId_fkey"
    ON public."Hero" USING btree
    ("Id" COLLATE pg_catalog."default" ASC NULLS LAST)
    WITH (fillfactor=100, deduplicate_items=True)
    TABLESPACE pg_default;

-- Each holding has at most one body of men see the note over "Troop".
CREATE UNIQUE INDEX IF NOT EXISTS troop_user_uniq ON public."Troop" ("UserId") WHERE "UserId" IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS troop_zone_uniq ON public."Troop" ("ZoneId") WHERE "ZoneId" IS NOT NULL;

-- One war at a time, held where it cannot be forgotten and it is the alliance
-- that is held to one, not the member who happened to declare it. Partial, so
-- it means one *unfinished* war rather than one ever: the finished ones are the
-- record, and there is no limit on how many of those an alliance may have.
CREATE UNIQUE INDEX IF NOT EXISTS war_active_uniq
    ON public."War" ("AllianceId") WHERE "Ended" IS NULL;

-- Every settlement is a candidate for a siege by several players at once, so
-- the other direction "who is at war with this place" is worth an index.
CREATE INDEX IF NOT EXISTS idx_war_zoneid ON public."War" ("ZoneId");

-- Every lookup is "what is near here", so the coordinates carry the index.
CREATE INDEX IF NOT EXISTS idx_baselock_xy ON public."BaseLock" ("X", "Y");

CREATE INDEX IF NOT EXISTS idx_haul_userid ON public."Haul" ("UserId");

-- A player's own scouts, and the scouts sent at them.
CREATE INDEX IF NOT EXISTS idx_scout_userid ON public."Scout" ("UserId");
CREATE INDEX IF NOT EXISTS idx_scout_target ON public."Scout" ("TargetType", "TargetId");

-- What has been taken off one player's stores, which is the only way this is
-- ever read: their own history, newest first.
CREATE INDEX IF NOT EXISTS idx_sack_userid ON public."Sack" ("UserId");

CREATE INDEX IF NOT EXISTS idx_zone_level  ON public."Zone"  ("Level");
CREATE INDEX IF NOT EXISTS idx_hero_zoneid ON public."Hero"  ("ZoneId");
CREATE INDEX IF NOT EXISTS idx_region_zoneid ON public."Region" ("ZoneId");
-- "Gift" had an idx_gift_userid here. The player is the primary key now -- one
-- gift a day belongs to the member, not to a settlement -- so the index it
-- would have added is the one Postgres already builds for that key.
-- Troop had an idx_troop_heroid here. The men belong to the holding now, not to
-- a hero, and there has been no "HeroId" column since -- so the last statement
-- in the file was one that could only fail, taking the whole script with it.
-- What it was for is covered by troop_user_uniq and troop_zone_uniq above.


---- One special a hero, and no ballista

-- The same block as onespecial.sql, which is what a world built before either
-- change is put through. On a world this file has just built there is nothing
-- for it to find every table above is new and empty so it runs and changes
-- nothing; it is here so this file holds every rule the data is held to, and
-- the two cannot drift apart unseen. See onespecial.sql for the why of each
-- step. One DO is one statement, and all or nothing on its own.
--
-- 1. Every ballista becomes a catapult, on a hero and in a pack alike.
-- 2. A hero carrying more than one special keeps the first he was given, and
--    the rest go back into his player's pack, one item each.
-- 3. Stacks of the same special in one pack are put together, the way the
--    server stacks them (UsableMutations.CreateUsable).

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

---- Troop camps

-- The same block as troopcap.sql, which is what a world built before the
-- change is put through: every camp brought to 150 and five men a level
-- (155 at level 1, 500 at level 70), and each settlement's stored power
-- written again to match. On a world this file has just built there is
-- nothing for it to find the settlements are GenerateServer.sql's, run
-- after this file, and they are generated with these numbers so it runs
-- and changes nothing; it is here so this file holds every rule the data is
-- held to. See troopcap.sql for the why of each step.

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
