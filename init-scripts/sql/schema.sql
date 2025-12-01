-- ============================================================================
-- Connect4 Gameplay Logging Database Schema

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================================
-- CREATE SCHEMAS
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS connect4;
CREATE SCHEMA IF NOT EXISTS game_schema;
CREATE SCHEMA IF NOT EXISTS gamelobby_schema;
CREATE SCHEMA IF NOT EXISTS player_schema;
-- For now I will leave these last 3 here ( should not be here ) THIS IS FOR RADU ALSO
-- ============================================================================
-- CORE TABLES
-- ============================================================================

-- Players table (for tracking individual players/agents)
CREATE TABLE IF NOT EXISTS connect4.players (
                                                player_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    player_type VARCHAR(20) NOT NULL CHECK (player_type IN ('human', 'cpu', 'mcts_agent')),
    skill_level VARCHAR(20) CHECK (skill_level IN ('easy', 'medium', 'hard', 'expert', NULL)),
    display_name VARCHAR(100),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
                             metadata JSONB DEFAULT '{}'::jsonb
                             );

-- Games table (master record for each game)
CREATE TABLE IF NOT EXISTS connect4.games (
                                              game_id UUID PRIMARY KEY,
                                              player1_id UUID REFERENCES connect4.players(player_id),
    player2_id UUID REFERENCES connect4.players(player_id),
    player1_type VARCHAR(20) NOT NULL CHECK (player1_type IN ('human', 'cpu')),
    player2_type VARCHAR(20) NOT NULL CHECK (player2_type IN ('human', 'cpu')),
    player1_skill_level VARCHAR(20),
    player2_skill_level VARCHAR(20),

    -- Game configuration
    rows INTEGER NOT NULL DEFAULT 6,
    cols INTEGER NOT NULL DEFAULT 7,
    connect INTEGER NOT NULL DEFAULT 4,
    empty_token VARCHAR(5) NOT NULL DEFAULT '.',
    player1_token VARCHAR(5) NOT NULL DEFAULT 'X',
    player2_token VARCHAR(5) NOT NULL DEFAULT 'O',
    starting_player VARCHAR(20) NOT NULL DEFAULT 'player1',

    -- Game outcome
    status VARCHAR(20) NOT NULL DEFAULT 'in_progress' CHECK (status IN ('in_progress', 'win', 'draw', 'abandoned')),
    winner VARCHAR(20) CHECK (winner IN ('player1', 'player2', NULL)),
    total_moves INTEGER DEFAULT 0,

    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    started_at TIMESTAMP WITH TIME ZONE,
    ended_at TIMESTAMP WITH TIME ZONE,
                           duration_seconds FLOAT,

                           -- Final state
                           final_board JSONB,
                           final_utilities JSONB,

                           -- Metadata for ML
                           game_metadata JSONB DEFAULT '{}'::jsonb
                           );

-- Game states table (snapshot of game state at each move)
CREATE TABLE IF NOT EXISTS connect4.game_states (
                                                    state_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    game_id UUID NOT NULL REFERENCES connect4.games(game_id) ON DELETE CASCADE,
    move_index INTEGER NOT NULL,

    -- Board state (2D array as JSON)
    board JSONB NOT NULL,

    -- Turn information
    current_player VARCHAR(20) NOT NULL,
    legal_actions JSONB NOT NULL,

    -- Game status at this state
    status VARCHAR(20) NOT NULL,

    -- Heuristic evaluation (utility values)
    utility_player1 FLOAT DEFAULT 0,
    utility_player2 FLOAT DEFAULT 0,

    -- State hash for deduplication/lookup
    state_hash VARCHAR(128),

    -- Timestamp
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

                                                                 UNIQUE(game_id, move_index)
    );

-- Moves table (detailed move information)
CREATE TABLE IF NOT EXISTS connect4.moves (
                                              move_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    game_id UUID NOT NULL REFERENCES connect4.games(game_id) ON DELETE CASCADE,
    state_id UUID REFERENCES connect4.game_states(state_id),

    -- Move details
    move_index INTEGER NOT NULL,
    player VARCHAR(20) NOT NULL,
    column_played INTEGER NOT NULL,
    row_placed INTEGER NOT NULL,

    -- Timing
    move_timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
                                                                 thinking_time_ms INTEGER,

                                                                 -- Pre-move state reference
                                                                 board_before JSONB,
                                                                 board_after JSONB,

                                                                 -- Heuristic evaluation
                                                                 utility_before JSONB,
                                                                 utility_after JSONB,

                                                                 UNIQUE(game_id, move_index)
    );

-- MCTS statistics table (for AI move analysis)
CREATE TABLE IF NOT EXISTS connect4.mcts_statistics (
                                                        stat_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    move_id UUID REFERENCES connect4.moves(move_id) ON DELETE CASCADE,
    game_id UUID NOT NULL REFERENCES connect4.games(game_id) ON DELETE CASCADE,
    move_index INTEGER NOT NULL,

    -- MCTS search statistics
    skill_level VARCHAR(20),
    time_limit_seconds FLOAT,
    actual_search_time_seconds FLOAT,
    num_rollouts INTEGER,
    nodes_explored INTEGER,

    -- Move selection data
    best_move INTEGER,
    move_probabilities JSONB,
    visit_counts JSONB,
    q_values JSONB,

    -- Exploration vs exploitation
    exploration_constant FLOAT,

    -- Dynamic difficulty adjustment
    time_adjustment_factor FLOAT,
    base_skill_level VARCHAR(20),

    -- Additional metadata
    metadata JSONB DEFAULT '{}'::jsonb,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
                                                        );

-- Player performance metrics (for DDA tracking)
CREATE TABLE IF NOT EXISTS connect4.player_performance (
                                                           performance_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    player_id UUID REFERENCES connect4.players(player_id),
    game_id UUID REFERENCES connect4.games(game_id) ON DELETE CASCADE,

    -- Session tracking
    session_id UUID,

    -- Performance metrics
    games_played INTEGER DEFAULT 0,
    games_won INTEGER DEFAULT 0,
    games_lost INTEGER DEFAULT 0,
    games_drawn INTEGER DEFAULT 0,

    -- Recent performance (for DDA)
    recent_win_rate FLOAT,
    consecutive_wins INTEGER DEFAULT 0,
    consecutive_losses INTEGER DEFAULT 0,

    -- Timing metrics
    avg_response_time_seconds FLOAT,
    total_thinking_time_seconds FLOAT,

    -- Skill progression
    current_opponent_skill VARCHAR(20),
    difficulty_adjustments INTEGER DEFAULT 0,

    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
                                                        );

-- Self-play sessions (for dataset generation)
CREATE TABLE IF NOT EXISTS connect4.self_play_sessions (
                                                           session_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- Session configuration
    agent1_skill VARCHAR(20) NOT NULL,
    agent2_skill VARCHAR(20) NOT NULL,
    noise_level FLOAT DEFAULT 0.0,
    randomness_temperature FLOAT DEFAULT 0.0,

    -- Session stats
    total_games INTEGER DEFAULT 0,
    agent1_wins INTEGER DEFAULT 0,
    agent2_wins INTEGER DEFAULT 0,
    draws INTEGER DEFAULT 0,

    -- Timing
    started_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    ended_at TIMESTAMP WITH TIME ZONE,

                           -- Export tracking
                           exported_to_parquet BOOLEAN DEFAULT FALSE,
                           parquet_file_path VARCHAR(500),
    dvc_version VARCHAR(50),

    metadata JSONB DEFAULT '{}'::jsonb
    );

-- Dataset exports tracking
CREATE TABLE IF NOT EXISTS connect4.dataset_exports (
                                                        export_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- Export details
    version VARCHAR(50) NOT NULL,
    num_games INTEGER NOT NULL,
    num_moves INTEGER NOT NULL,

    -- File information
    file_path VARCHAR(500) NOT NULL,
    file_size_bytes BIGINT,
    checksum VARCHAR(128),

    -- DVC tracking
    dvc_tracked BOOLEAN DEFAULT FALSE,
    dvc_file_path VARCHAR(500),
    minio_bucket VARCHAR(100),
    minio_key VARCHAR(500),

    -- Generation parameters
    skill_levels_included JSONB,
    date_range_start TIMESTAMP WITH TIME ZONE,
    date_range_end TIMESTAMP WITH TIME ZONE,

    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

                             metadata JSONB DEFAULT '{}'::jsonb
                             );

-- ============================================================================
-- INDEXES FOR PERFORMANCE
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_games_status ON connect4.games(status);
CREATE INDEX IF NOT EXISTS idx_games_created_at ON connect4.games(created_at);
CREATE INDEX IF NOT EXISTS idx_games_player1 ON connect4.games(player1_id);
CREATE INDEX IF NOT EXISTS idx_games_player2 ON connect4.games(player2_id);
CREATE INDEX IF NOT EXISTS idx_games_winner ON connect4.games(winner);

CREATE INDEX IF NOT EXISTS idx_game_states_game_id ON connect4.game_states(game_id);
CREATE INDEX IF NOT EXISTS idx_game_states_move_index ON connect4.game_states(game_id, move_index);
CREATE INDEX IF NOT EXISTS idx_game_states_hash ON connect4.game_states(state_hash);

CREATE INDEX IF NOT EXISTS idx_moves_game_id ON connect4.moves(game_id);
CREATE INDEX IF NOT EXISTS idx_moves_player ON connect4.moves(player);
CREATE INDEX IF NOT EXISTS idx_moves_timestamp ON connect4.moves(move_timestamp);

CREATE INDEX IF NOT EXISTS idx_mcts_stats_game_id ON connect4.mcts_statistics(game_id);
CREATE INDEX IF NOT EXISTS idx_mcts_stats_move_id ON connect4.mcts_statistics(move_id);
CREATE INDEX IF NOT EXISTS idx_mcts_stats_skill ON connect4.mcts_statistics(skill_level);

CREATE INDEX IF NOT EXISTS idx_self_play_sessions ON connect4.self_play_sessions(started_at);

-- ============================================================================
-- VIEWS FOR ANALYTICS
-- ============================================================================

-- Complete game summary view
CREATE OR REPLACE VIEW connect4.game_summary AS
SELECT
    g.game_id,
    g.player1_type,
    g.player2_type,
    g.player1_skill_level,
    g.player2_skill_level,
    g.status,
    g.winner,
    g.total_moves,
    g.duration_seconds,
    g.created_at,
    g.ended_at,
    COUNT(DISTINCT m.move_id) as move_count,
    AVG(m.thinking_time_ms) as avg_thinking_time_ms
FROM connect4.games g
         LEFT JOIN connect4.moves m ON g.game_id = m.game_id
GROUP BY g.game_id;

-- Move analysis view (for ML training)
CREATE OR REPLACE VIEW connect4.move_analysis AS
SELECT
    m.move_id,
    m.game_id,
    m.move_index,
    m.player,
    m.column_played,
    m.row_placed,
    m.board_before,
    m.board_after,
    m.utility_before,
    m.utility_after,
    ms.best_move,
    ms.visit_counts,
    ms.q_values,
    ms.num_rollouts,
    ms.skill_level as ai_skill_level,
    g.winner,
    g.status as game_status
FROM connect4.moves m
         LEFT JOIN connect4.mcts_statistics ms ON m.move_id = ms.move_id
         JOIN connect4.games g ON m.game_id = g.game_id;

-- Dataset generation view
CREATE OR REPLACE VIEW connect4.training_data AS
SELECT
    m.game_id,
    m.move_index,
    m.player,
    m.column_played as action,
    m.board_before as state,
    gs.legal_actions,
    ms.visit_counts,
    ms.q_values,
    ms.num_rollouts,
    ms.best_move,
    g.winner,
    CASE
        WHEN g.winner = m.player THEN 1.0
        WHEN g.winner IS NULL THEN 0.0
        ELSE -1.0
END as outcome_reward,
    g.player1_skill_level,
    g.player2_skill_level,
    m.thinking_time_ms
FROM connect4.moves m
JOIN connect4.games g ON m.game_id = g.game_id
LEFT JOIN connect4.game_states gs ON m.state_id = gs.state_id
LEFT JOIN connect4.mcts_statistics ms ON m.move_id = ms.move_id
WHERE g.status IN ('win', 'draw');

-- ============================================================================
-- FUNCTIONS FOR REPLAY
-- ============================================================================

-- Function to get complete game replay data
CREATE OR REPLACE FUNCTION connect4.get_game_replay(p_game_id UUID)
RETURNS TABLE (
    move_index INTEGER,
    player VARCHAR(20),
    column_played INTEGER,
    row_placed INTEGER,
    board_after JSONB,
    thinking_time_ms INTEGER,
    move_timestamp TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
RETURN QUERY
SELECT
    m.move_index,
    m.player,
    m.column_played,
    m.row_placed,
    m.board_after,
    m.thinking_time_ms,
    m.move_timestamp
FROM connect4.moves m
WHERE m.game_id = p_game_id
ORDER BY m.move_index;
END;
$$ LANGUAGE plpgsql;

-- Function to get game state at specific move
CREATE OR REPLACE FUNCTION connect4.get_game_state_at_move(p_game_id UUID, p_move_index INTEGER)
RETURNS JSONB AS $$
DECLARE
result JSONB;
BEGIN
SELECT jsonb_build_object(
               'game_id', gs.game_id,
               'move_index', gs.move_index,
               'board', gs.board,
               'current_player', gs.current_player,
               'legal_actions', gs.legal_actions,
               'status', gs.status,
               'utility_player1', gs.utility_player1,
               'utility_player2', gs.utility_player2
       ) INTO result
FROM connect4.game_states gs
WHERE gs.game_id = p_game_id AND gs.move_index = p_move_index;

RETURN result;
END;
$$ LANGUAGE plpgsql;
