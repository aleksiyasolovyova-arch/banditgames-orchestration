-- Connect4 Database Schema
-- PostgreSQL Schema for persistent game storage
-- Database: postgres (shared with other services)
-- Schema: connect4_backend (isolated namespace)

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create dedicated schema for Connect4 backend
DROP SCHEMA IF EXISTS connect4_backend CASCADE;
CREATE SCHEMA connect4_backend;

-- Set search path to use the new schema
SET search_path TO connect4_backend, public;


-- Players table - stores player information
CREATE TABLE connect4_backend.players (
                                          player_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- Player information
                                          name VARCHAR(255) NOT NULL,

    -- Timestamps
                                          created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                                          updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Games table - stores game state and metadata
CREATE TABLE connect4_backend.games (
                                        game_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- Board configuration
                                        rows INTEGER NOT NULL DEFAULT 6 CHECK (rows >= 4 AND rows <= 10),
    cols INTEGER NOT NULL DEFAULT 7 CHECK (cols >= 4 AND cols <= 10),

    -- Board state (stored as 2D array of strings: 'X', 'O', '.')
    grid JSONB NOT NULL,

    -- Players (foreign keys to players table)
    player_one_id UUID NOT NULL REFERENCES connect4_backend.players(player_id) ON DELETE RESTRICT,
    player_one_name VARCHAR(255) NOT NULL,
    player_two_id UUID NOT NULL REFERENCES connect4_backend.players(player_id) ON DELETE RESTRICT,
    player_two_name VARCHAR(255) NOT NULL,

    -- Game state
    current_token VARCHAR(1) NOT NULL CHECK (current_token IN ('X', 'O')),
    phase VARCHAR(20) NOT NULL CHECK (phase IN ('NOT_STARTED', 'IN_PROGRESS', 'FINISHED')),

    -- Winner (nullable - null means draw or game in progress)
    winner_id UUID REFERENCES connect4_backend.players(player_id) ON DELETE RESTRICT,
    winner_name VARCHAR(255),

    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    started_at TIMESTAMPTZ,
    finished_at TIMESTAMPTZ,
    turn_started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Constraints
    CONSTRAINT different_players CHECK (player_one_id != player_two_id),
    CONSTRAINT winner_is_player CHECK (
        winner_id IS NULL OR
        winner_id = player_one_id OR
        winner_id = player_two_id
    )
);

-- Moves table - stores move history for each game
CREATE TABLE connect4_backend.moves (
                                        move_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
                                        game_id UUID NOT NULL REFERENCES connect4_backend.games(game_id) ON DELETE CASCADE,

    -- Move details
                                        move_index INTEGER NOT NULL,
                                        col INTEGER NOT NULL,  -- Renamed from 'column' (reserved keyword)

    -- Landing position
                                        landed_row INTEGER NOT NULL,
                                        landed_col INTEGER NOT NULL,

    -- Token placed
                                        token VARCHAR(1) NOT NULL CHECK (token IN ('X', 'O')),

    -- Player who made the move (foreign key to players table)
                                        player_id UUID NOT NULL REFERENCES connect4_backend.players(player_id) ON DELETE RESTRICT,

    -- Timing
                                        timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                                        thinking_time_ms DOUBLE PRECISION NOT NULL DEFAULT 0,

    -- Constraints
                                        CONSTRAINT unique_move_index_per_game UNIQUE (game_id, move_index),
                                        CHECK (col >= 0),
                                        CHECK (landed_row >= 0),
                                        CHECK (landed_col >= 0),
                                        CHECK (move_index >= 0),
                                        CHECK (thinking_time_ms >= 0)
);

-- Achievement Unlocked table - stores which achievements were unlocked per player
-- Prevents the same player from unlocking the same achievement twice
CREATE TABLE connect4_backend.achievement_unlocked (
                                                       achievement_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- Player who unlocked the achievement
                                                       player_id UUID NOT NULL REFERENCES connect4_backend.players(player_id) ON DELETE CASCADE,

    -- Achievement type (e.g., 'FIRST_MOVE', 'DIAGONAL_WINNER', etc.)
                                                       achievement_type VARCHAR(64) NOT NULL,

    -- When the achievement was unlocked
                                                       unlocked_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Optional: which game caused the unlock
                                                       game_id UUID REFERENCES connect4_backend.games(game_id) ON DELETE SET NULL,

    -- Guarantee: achievement is unlocked only once per player
                                                       CONSTRAINT uq_player_achievement UNIQUE (player_id, achievement_type)
);

-- Indexes for query performance

-- Players indexes
CREATE INDEX idx_players_created_at ON connect4_backend.players(created_at DESC);
CREATE INDEX idx_players_name ON connect4_backend.players(name);

-- Index for finding games by players
CREATE INDEX idx_games_player_one ON connect4_backend.games(player_one_id);
CREATE INDEX idx_games_player_two ON connect4_backend.games(player_two_id);

-- Index for finding active/finished games
CREATE INDEX idx_games_phase ON connect4_backend.games(phase);
CREATE INDEX idx_games_finished_at ON connect4_backend.games(finished_at) WHERE finished_at IS NOT NULL;

-- Index for game timeline queries
CREATE INDEX idx_games_created_at ON connect4_backend.games(created_at DESC);
CREATE INDEX idx_games_updated_at ON connect4_backend.games(updated_at DESC);

-- Index for move queries
CREATE INDEX idx_moves_game_id ON connect4_backend.moves(game_id);
CREATE INDEX idx_moves_game_move_index ON connect4_backend.moves(game_id, move_index);
CREATE INDEX idx_moves_timestamp ON connect4_backend.moves(timestamp);
CREATE INDEX idx_moves_player_id ON connect4_backend.moves(player_id);

-- Achievement unlocked indexes
CREATE INDEX idx_achievement_unlocked_player ON connect4_backend.achievement_unlocked(player_id);
CREATE INDEX idx_achievement_unlocked_type ON connect4_backend.achievement_unlocked(achievement_type);
CREATE INDEX idx_achievement_unlocked_game ON connect4_backend.achievement_unlocked(game_id);
CREATE INDEX idx_achievement_unlocked_at ON connect4_backend.achievement_unlocked(unlocked_at DESC);

-- Views for common queries

-- Active games view
CREATE VIEW connect4_backend.active_games AS
SELECT
    g.*,
    COUNT(m.move_id) as move_count,
    MAX(m.timestamp) as last_move_at
FROM connect4_backend.games g
         LEFT JOIN connect4_backend.moves m ON g.game_id = m.game_id
WHERE g.phase IN ('NOT_STARTED', 'IN_PROGRESS')
GROUP BY g.game_id;

-- Finished games view with statistics
CREATE VIEW connect4_backend.finished_games AS
SELECT
    g.*,
    COUNT(m.move_id) as total_moves,
    EXTRACT(EPOCH FROM (g.finished_at - g.started_at)) as duration_seconds,
    MIN(m.timestamp) as first_move_at,
    MAX(m.timestamp) as last_move_at
FROM connect4_backend.games g
         LEFT JOIN connect4_backend.moves m ON g.game_id = m.game_id
WHERE g.phase = 'FINISHED'
GROUP BY g.game_id;

-- Reset search path
RESET search_path;

-- Schemas for the platform backend
CREATE SCHEMA IF NOT EXISTS player_schema;
CREATE SCHEMA IF NOT EXISTS content_schema;
CREATE SCHEMA IF NOT EXISTS read_model_schema;
CREATE SCHEMA IF NOT EXISTS mlflow;
