-- The main database main the directory every world shares: the
-- accounts that sign in, the device tokens that let them back in without a
-- password, and for each the world their player lives in (Player.Server, a
-- game database by name such as game_0) and the id they were given there
-- (Player.UserId). The API reads it over the Accounts connection in
-- appsettings and builds it from this file where it is empty see Setup.
-- Run this against an empty database only; it drops and rebuilds every
-- table.

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

-- An account: who can sign in, and which world their player lives in. The
-- player is a "User" row in the world "Server" names a database, by its
-- name, such as game_0 so there is no foreign key from here to it, and
-- "UserId" is the id it was given there. A player made through Apple or
-- Google has no password at all, and "PasswordHash" is blank for them.

---- Table: public.Player

DROP TABLE IF EXISTS public."Player" CASCADE;

CREATE TABLE IF NOT EXISTS public."Player"
(
    "Id" character(36) COLLATE pg_catalog."default" NOT NULL,
    "UserId" character(36) COLLATE pg_catalog."default" NOT NULL,
    "Server" text COLLATE pg_catalog."default" NOT NULL DEFAULT '',
    "Name" text COLLATE pg_catalog."default" NOT NULL,
    "PasswordHash" character(60) COLLATE pg_catalog."default" NOT NULL,
    "Email" text COLLATE pg_catalog."default",
    "Gender" text COLLATE pg_catalog."default",
    "Dob" timestamp without time zone,
    created timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT player_pkey PRIMARY KEY ("Id"),
    CONSTRAINT player_email_key UNIQUE ("Email"),
    CONSTRAINT player_name_key UNIQUE ("Name")
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public."Player"
    OWNER to postgres;

-- Trigger: player_updated_at

DROP TRIGGER IF EXISTS player_updated_at ON public."Player" CASCADE;

CREATE OR REPLACE TRIGGER player_updated_at
    BEFORE UPDATE
    ON public."Player"
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_column();

-- A way into a player's account through Apple's or Google's door: the
-- provider and what it calls the person, tied to the player it opens. A
-- player may hold one a provider beside the password they may or may not
-- have.

---- Table: public.Login

DROP TABLE IF EXISTS public."Login" CASCADE;

CREATE TABLE IF NOT EXISTS public."Login"
(
    "Provider" text COLLATE pg_catalog."default" NOT NULL,
    "Subject" text COLLATE pg_catalog."default" NOT NULL,
    "PlayerId" character(36) COLLATE pg_catalog."default" NOT NULL,
    "Email" text COLLATE pg_catalog."default",
    "Created" timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT login_pkey PRIMARY KEY ("Provider", "Subject"),
    CONSTRAINT login_player_fkey FOREIGN KEY ("PlayerId")
        REFERENCES public."Player" ("Id") ON DELETE CASCADE
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public."Login"
    OWNER to postgres;

-- A device's standing way back in: the long-lived half of a session, kept
-- as a hash and spent on use see RefreshToken.cs.

---- Table: public.RefreshToken

DROP TABLE IF EXISTS public."RefreshToken" CASCADE;

CREATE TABLE IF NOT EXISTS public."RefreshToken"
(
    "Hash" character(64) COLLATE pg_catalog."default" NOT NULL,
    "PlayerId" character(36) COLLATE pg_catalog."default" NOT NULL,
    "ExpiresAt" timestamp without time zone NOT NULL,
    "Created" timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "Revoked" boolean NOT NULL DEFAULT false,
    CONSTRAINT refreshtoken_pkey PRIMARY KEY ("Hash"),
    CONSTRAINT refreshtoken_player_fkey FOREIGN KEY ("PlayerId")
        REFERENCES public."Player" ("Id") ON DELETE CASCADE
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public."RefreshToken"
    OWNER to postgres;

---- Table: public.BlacklistedToken

DROP TABLE IF EXISTS public."BlacklistedToken" CASCADE;

CREATE TABLE IF NOT EXISTS public."BlacklistedToken"
(
    "Jti" text COLLATE pg_catalog."default" NOT NULL,
    "ExpiresAt" timestamp without time zone NOT NULL,
    "Created" timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT blacklistedtokens_pkey PRIMARY KEY ("Jti")
)
TABLESPACE pg_default;

ALTER TABLE IF EXISTS public."BlacklistedToken"
    OWNER to postgres;

-- ********************** Indexes **********************

CREATE INDEX IF NOT EXISTS idx_login_player ON public."Login" ("PlayerId");
CREATE INDEX IF NOT EXISTS idx_refreshtoken_player ON public."RefreshToken" ("PlayerId");
-- Signing in finds the account by its world and name, and the worlds answer
-- for their players by the User id the account carries.
CREATE INDEX IF NOT EXISTS idx_player_userid ON public."Player" ("UserId");
