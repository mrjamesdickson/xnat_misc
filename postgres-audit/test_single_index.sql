-- Single Index Performance Test
-- Testing: idx_container_entity_input_container_entity
-- Table: xhbm_container_entity_input
-- Column: container_entity

\timing on

\echo ''
\echo '========================================='
\echo 'Single Index Performance Test'
\echo '========================================='
\echo 'Table: xhbm_container_entity_input'
\echo 'Column: container_entity'
\echo ''

-- Create logging table
CREATE TABLE IF NOT EXISTS pg_index_test_log (
    test_id SERIAL PRIMARY KEY,
    test_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    table_name TEXT,
    index_name TEXT,
    test_phase TEXT,
    execution_time_ms NUMERIC,
    query_plan TEXT,
    decision TEXT,
    improvement_percent NUMERIC,
    notes TEXT
);

-- ============================================================================
-- Step 1: Baseline Test (WITHOUT index)
-- ============================================================================

\echo ''
\echo '--- Step 1: Testing Baseline Performance (No Index) ---'
\echo ''

-- Clear cache for fair test
SELECT pg_stat_reset();

-- Test query with EXPLAIN ANALYZE (run multiple times for accuracy)
\echo 'Run 1...'
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM xhbm_container_entity_input
WHERE container_entity IS NOT NULL
LIMIT 1000;

\echo ''
\echo 'Run 2...'
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM xhbm_container_entity_input
WHERE container_entity IS NOT NULL
LIMIT 1000;

\echo ''
\echo 'Run 3...'
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM xhbm_container_entity_input
WHERE container_entity IS NOT NULL
LIMIT 1000;

-- Log baseline
INSERT INTO pg_index_test_log (
    table_name, index_name, test_phase, notes
) VALUES (
    'xhbm_container_entity_input',
    'idx_container_entity_input_container_entity',
    'baseline',
    'Baseline test without index - see execution times above'
);

-- ============================================================================
-- Step 2: Create Index
-- ============================================================================

\echo ''
\echo '--- Step 2: Creating Index ---'
\echo ''

CREATE INDEX idx_container_entity_input_container_entity
ON xhbm_container_entity_input(container_entity);

\echo 'Index created successfully'
\echo ''

-- Update statistics
ANALYZE xhbm_container_entity_input;

\echo 'Statistics updated'
\echo ''

-- ============================================================================
-- Step 3: Test WITH Index
-- ============================================================================

\echo ''
\echo '--- Step 3: Testing Performance WITH Index ---'
\echo ''

-- Clear cache for fair test
SELECT pg_stat_reset();

-- Test query with EXPLAIN ANALYZE
\echo 'Run 1...'
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM xhbm_container_entity_input
WHERE container_entity IS NOT NULL
LIMIT 1000;

\echo ''
\echo 'Run 2...'
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM xhbm_container_entity_input
WHERE container_entity IS NOT NULL
LIMIT 1000;

\echo ''
\echo 'Run 3...'
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM xhbm_container_entity_input
WHERE container_entity IS NOT NULL
LIMIT 1000;

-- Log with-index test
INSERT INTO pg_index_test_log (
    table_name, index_name, test_phase, notes
) VALUES (
    'xhbm_container_entity_input',
    'idx_container_entity_input_container_entity',
    'with_index',
    'Test with index created - see execution times above'
);

-- ============================================================================
-- Step 4: Show Index Information
-- ============================================================================

\echo ''
\echo '--- Step 4: Index Information ---'
\echo ''

SELECT
    schemaname,
    tablename,
    indexname,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
WHERE indexname = 'idx_container_entity_input_container_entity';

-- ============================================================================
-- Step 5: Decision Point
-- ============================================================================

\echo ''
\echo '========================================='
\echo 'DECISION POINT'
\echo '========================================='
\echo ''
\echo 'Compare the execution times above:'
\echo '1. Baseline (without index) execution time'
\echo '2. With index execution time'
\echo ''
\echo 'If improvement > 10%: Type "keep" to keep the index'
\echo 'If improvement < 10%: Type "rollback" to remove the index'
\echo ''
\echo 'TO KEEP INDEX:'
\echo '  -- Index is already created, no action needed'
\echo '  -- Update log: '
\echo '  UPDATE pg_index_test_log SET decision = ''KEEP'', notes = ''Manual decision: keeping index'' '
\echo '  WHERE index_name = ''idx_container_entity_input_container_entity'' AND test_phase = ''with_index'';'
\echo ''
\echo 'TO ROLLBACK INDEX:'
\echo '  DROP INDEX idx_container_entity_input_container_entity;'
\echo '  UPDATE pg_index_test_log SET decision = ''ROLLBACK'', notes = ''Manual decision: removed index'' '
\echo '  WHERE index_name = ''idx_container_entity_input_container_entity'' AND test_phase = ''with_index'';'
\echo ''

-- Show test log
\echo '--- Test Log ---'
SELECT * FROM pg_index_test_log
WHERE index_name = 'idx_container_entity_input_container_entity'
ORDER BY test_id;

\echo ''
\echo 'Test complete. Review results and make decision.'
\echo ''
