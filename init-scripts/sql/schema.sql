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

-- Drop tables if they exist (for clean redeployment)
DROP TABLE IF EXISTS connect4_backend.moves CASCADE;
DROP TABLE IF EXISTS connect4_backend.games CASCADE;

-- Games table - stores game state and metadata
CREATE TABLE connect4_backend.games (
                                        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- Board configuration
                                        rows INTEGER NOT NULL DEFAULT 6 CHECK (rows >= 4 AND rows <= 10),
    cols INTEGER NOT NULL DEFAULT 7 CHECK (cols >= 4 AND cols <= 10),

    -- Board state (stored as 2D array of strings: 'X', 'O', '.')
    grid JSONB NOT NULL,

    -- Players
    player_one_id VARCHAR(255) NOT NULL,
    player_one_name VARCHAR(255) NOT NULL,
    player_two_id VARCHAR(255) NOT NULL,
    player_two_name VARCHAR(255) NOT NULL,

    -- Game state
    current_token VARCHAR(1) NOT NULL CHECK (current_token IN ('X', 'O')),
    phase VARCHAR(20) NOT NULL CHECK (phase IN ('NOT_STARTED', 'IN_PROGRESS', 'FINISHED')),

    -- Winner (nullable - null means draw or game in progress)
    winner_id VARCHAR(255),
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
                                        id BIGSERIAL PRIMARY KEY,
                                        game_id UUID NOT NULL REFERENCES connect4_backend.games(id) ON DELETE CASCADE,

    -- Move details
                                        move_index INTEGER NOT NULL,
                                        column INTEGER NOT NULL,

    -- Landing position
                                        landed_row INTEGER NOT NULL,
                                        landed_col INTEGER NOT NULL,

    -- Token placed
                                        token VARCHAR(1) NOT NULL CHECK (token IN ('X', 'O')),

    -- Player who made the move
                                        player_id VARCHAR(255) NOT NULL,

    -- Timing
                                        timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                                        thinking_time_ms DOUBLE PRECISION NOT NULL DEFAULT 0,

    -- Constraints
                                        CONSTRAINT unique_move_index_per_game UNIQUE (game_id, move_index),
                                        CHECK (column >= 0),
    CHECK (landed_row >= 0),
    CHECK (landed_col >= 0),
    CHECK (move_index >= 0),
    CHECK (thinking_time_ms >= 0)
);

-- Indexes for query performance

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

-- Views for common queries

-- Active games view
CREATE VIEW connect4_backend.active_games AS
SELECT
    g.*,
    COUNT(m.id) as move_count,
    MAX(m.timestamp) as last_move_at
FROM connect4_backend.games g
         LEFT JOIN connect4_backend.moves m ON g.id = m.game_id
WHERE g.phase IN ('NOT_STARTED', 'IN_PROGRESS')
GROUP BY g.id;

-- Finished games view with statistics
CREATE VIEW connect4_backend.finished_games AS
SELECT
    g.*,
    COUNT(m.id) as total_moves,
    EXTRACT(EPOCH FROM (g.finished_at - g.started_at)) as duration_seconds,
    MIN(m.timestamp) as first_move_at,
    MAX(m.timestamp) as last_move_at
FROM connect4_backend.games g
         LEFT JOIN connect4_backend.moves m ON g.id = m.game_id
WHERE g.phase = 'FINISHED'
GROUP BY g.id;


-- Reset search path
RESET search_path;