-- =============================================================================
-- SRMessage -- the messaging database
--
-- Its own database, apart from the game's: "chat_0", the chat half of the
-- game's world game_0 (built from ShadowRuler's game.sql), on the same
-- server. Nothing in here refers to a table in the game's database and nothing
-- there refers to one in here -- the two meet only at the game's user id, which
-- the game hands over on every contact and this side writes down verbatim.
--
-- There is no login on this side. The game has already done that, and a second
-- sign-in to talk inside it would be a second door to the same room. So there
-- is no password, no email, no token table: a user here is an id the game
-- vouches for and a name it currently uses.
--
-- Run on an empty database:
--
--     psql -U postgres -d postgres   -c 'CREATE DATABASE chat_0'
--     psql -U postgres -d chat_0     -f database/chat.sql
--
-- Or run nothing: the API does both on its first start if the tables are not
-- there -- see SRMessage.Infrastructure/Data/Schema.cs, which carries this file
-- inside it. This drops and rebuilds; on a database with talk in it, run only
-- the ALTERs you need.
-- =============================================================================

-- Table: public.users
--
-- Who has spoken, under the game's own id. Written the first time a player
-- connects and restamped every time after, so it is a record of contact rather
-- than a register anybody has to be on first.

DROP TABLE IF EXISTS public.users CASCADE;

CREATE TABLE IF NOT EXISTS public.users
(
    -- The game's user id, verbatim: a GUID, as the game writes it.
    id          character(36) COLLATE pg_catalog."default" NOT NULL,
    -- What the game called them at their last contact.
    name        text COLLATE pg_catalog."default" NOT NULL,
    first_seen  timestamp with time zone NOT NULL DEFAULT NOW(),
    last_seen   timestamp with time zone NOT NULL DEFAULT NOW(),
    CONSTRAINT users_pkey PRIMARY KEY (id)
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.users
    OWNER to postgres;

-- Table: public.rooms
--
-- A place messages go, named by a slug the game builds for itself and this
-- side makes on first use:
--
--     world                          everyone
--     alliance:{allianceId}          an alliance's members
--     alliance:{allianceId}:leaders  its leader and officers
--     dm:{idA}:{idB}                 two players, ids in sorted order
--
-- The slug is the whole identity and the whole rule. Nothing here checks that
-- a player is in the alliance they name -- the game is the authority on that,
-- and this is the game's own client asking. The one thing enforced is that a
-- dm room admits the two ids in its slug and nobody else.

DROP TABLE IF EXISTS public.rooms CASCADE;

CREATE TABLE IF NOT EXISTS public.rooms
(
    slug        text COLLATE pg_catalog."default" NOT NULL,
    -- 'world', 'alliance', 'leaders' or 'dm': the first word of the slug,
    -- kept as a column so the inbox query can ask for one kind.
    kind        text COLLATE pg_catalog."default" NOT NULL,
    created_at  timestamp with time zone NOT NULL DEFAULT NOW(),
    CONSTRAINT rooms_pkey PRIMARY KEY (slug),
    CONSTRAINT rooms_kind_chk CHECK (kind IN ('world', 'alliance', 'leaders', 'dm'))
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.rooms
    OWNER to postgres;

-- Table: public.room_members
--
-- Who is in a direct room -- the two ids its slug already names, written down
-- so "everyone I have talked to" is one join rather than a scan of every dm
-- slug for a name. Only dm rooms have rows here: the world and an alliance are
-- open to whoever asks, and have no list to keep.

DROP TABLE IF EXISTS public.room_members CASCADE;

CREATE TABLE IF NOT EXISTS public.room_members
(
    room_slug   text COLLATE pg_catalog."default" NOT NULL,
    user_id     character(36) COLLATE pg_catalog."default" NOT NULL,
    CONSTRAINT room_members_pkey PRIMARY KEY (room_slug, user_id),
    CONSTRAINT room_members_room_fkey FOREIGN KEY (room_slug)
        REFERENCES public.rooms (slug)
        ON DELETE CASCADE
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.room_members
    OWNER to postgres;

-- Table: public.messages
--
-- One thing somebody said, in one room. The sender's name is written on it as
-- it was at the time rather than joined back on every read: a player who
-- renames keeps their old words under their old name, which is what a record
-- of a conversation is.

DROP TABLE IF EXISTS public.messages CASCADE;

CREATE TABLE IF NOT EXISTS public.messages
(
    id          uuid NOT NULL,
    room_slug   text COLLATE pg_catalog."default" NOT NULL,
    sender_id   character(36) COLLATE pg_catalog."default" NOT NULL,
    sender_name text COLLATE pg_catalog."default" NOT NULL,
    -- Capped at Message.MaxLength on the way in; the column is the backstop.
    content     text COLLATE pg_catalog."default" NOT NULL,
    sent_at     timestamp with time zone NOT NULL DEFAULT NOW(),
    CONSTRAINT messages_pkey PRIMARY KEY (id),
    CONSTRAINT messages_room_fkey FOREIGN KEY (room_slug)
        REFERENCES public.rooms (slug)
        ON DELETE CASCADE,
    CONSTRAINT messages_content_chk CHECK (char_length(content) BETWEEN 1 AND 1000)
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.messages
    OWNER to postgres;

-- Table: public.read_marks
--
-- How far into a room a player has read: the moment they last had it open.
-- What was said in the room by somebody else after that moment is what they
-- have waiting -- the count on the inbox row, and the badges the game shows
-- before the room is opened. One row a player a room, written when the room
-- opens and restamped every time after. No row means a conversation has not
-- been read at all, and an alliance's room is counted from when the player
-- first came to the chat.
--
-- Direct rooms and an alliance's are marked. The world is a stream, not a
-- letterbox, and nobody is owed a count of what they missed there.

DROP TABLE IF EXISTS public.read_marks CASCADE;

CREATE TABLE IF NOT EXISTS public.read_marks
(
    user_id     character(36) COLLATE pg_catalog."default" NOT NULL,
    room_slug   text COLLATE pg_catalog."default" NOT NULL,
    read_at     timestamp with time zone NOT NULL DEFAULT NOW(),
    CONSTRAINT read_marks_pkey PRIMARY KEY (user_id, room_slug),
    CONSTRAINT read_marks_room_fkey FOREIGN KEY (room_slug)
        REFERENCES public.rooms (slug)
        ON DELETE CASCADE
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.read_marks
    OWNER to postgres;

-- Indexes
-- A room's history is read newest first and scrolled back from a moment, which
-- is the one query the table exists to answer.
CREATE INDEX IF NOT EXISTS idx_messages_room_sent ON public.messages (room_slug, sent_at DESC);
-- And a player's inbox is every dm room they are a member of.
CREATE INDEX IF NOT EXISTS idx_room_members_user ON public.room_members (user_id);

-- =============================================================================
-- Standing
--
-- Everything above runs once, on a database with no tables -- see Schema.cs.
-- Everything below runs on every start, so a database made before a table
-- existed gets it without being rebuilt. Nothing here drops anything.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.read_marks
(
    user_id     character(36) COLLATE pg_catalog."default" NOT NULL,
    room_slug   text COLLATE pg_catalog."default" NOT NULL,
    read_at     timestamp with time zone NOT NULL DEFAULT NOW(),
    CONSTRAINT read_marks_pkey PRIMARY KEY (user_id, room_slug),
    CONSTRAINT read_marks_room_fkey FOREIGN KEY (room_slug)
        REFERENCES public.rooms (slug)
        ON DELETE CASCADE
);

-- A message taken back by whoever said it. Kept rather than dropped, so a
-- report made against it still points at something, but never shown again:
-- every read of the room, the inbox and the counts passes it over.
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS deleted_at timestamp with time zone;

-- Where a message was said from: the sender's address and the socket it came
-- in on ('http' for the plain call). Never handed to a client; written into
-- Reported.log when somebody reports it -- see ChatLog.
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS sender_ip text;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS sender_connection text;

-- The bubble a player's words are drawn in: 'hearts', 'roses', 'skulls',
-- 'gold' or 'silver', or empty for the plain one. Theirs, so every message
-- they have said is drawn in whichever they wear now -- see ChatActions.
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS bubble text NOT NULL DEFAULT '';

-- Table: public.message_likes
--
-- Who has liked what: one row a player a message, taken away again by
-- unliking it. Gone with the message.
CREATE TABLE IF NOT EXISTS public.message_likes
(
    message_id  uuid NOT NULL,
    user_id     character(36) COLLATE pg_catalog."default" NOT NULL,
    liked_at    timestamp with time zone NOT NULL DEFAULT NOW(),
    CONSTRAINT message_likes_pkey PRIMARY KEY (message_id, user_id),
    CONSTRAINT message_likes_message_fkey FOREIGN KEY (message_id)
        REFERENCES public.messages (id)
        ON DELETE CASCADE
);

