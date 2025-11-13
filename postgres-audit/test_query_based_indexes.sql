-- Test Indexes Based on Top Queries
-- Dynamically tests indexes for the most frequent queries
-- Duration: ~15-30 minutes depending on MAX_QUERIES parameter

\timing on

-- Configuration parameters
\set MAX_QUERIES 100
\set MIN_CALLS 50
\set MIN_AVG_TIME_MS 0.5

\echo ''
\echo '========================================='
\echo 'Testing Query-Based Indexes'
\echo '========================================='
\echo 'Configuration:'
\echo '  MAX_QUERIES: ' :MAX_QUERIES
\echo '  MIN_CALLS: ' :MIN_CALLS
\echo '  MIN_AVG_TIME_MS: ' :MIN_AVG_TIME_MS
\echo ''

-- Test log table already exists (created by earlier tests)
-- Just ensure we have the required columns

-- Show top queries
\echo ''
\echo '--- Top Queries by Call Count ---'
SELECT
    calls,
    ROUND(mean_exec_time::numeric, 2) AS avg_ms,
    ROUND(total_exec_time::numeric, 2) AS total_ms,
    LEFT(query, 80) AS query_preview
FROM pg_stat_statements
WHERE query NOT LIKE '<insufficient privilege>%'
  AND query NOT LIKE 'SET %'
  AND query NOT LIKE 'BEGIN%'
  AND query NOT LIKE 'COMMIT%'
  AND calls >= :MIN_CALLS
  AND mean_exec_time >= :MIN_AVG_TIME_MS
ORDER BY calls DESC
LIMIT 20;

\echo ''
\echo '--- Top Queries by Total Time ---'
SELECT
    calls,
    ROUND(mean_exec_time::numeric, 2) AS avg_ms,
    ROUND(total_exec_time::numeric, 2) AS total_ms,
    LEFT(query, 80) AS query_preview
FROM pg_stat_statements
WHERE query NOT LIKE '<insufficient privilege>%'
  AND query NOT LIKE 'SET %'
  AND query NOT LIKE 'BEGIN%'
  AND query NOT LIKE 'COMMIT%'
  AND calls >= :MIN_CALLS
  AND mean_exec_time >= :MIN_AVG_TIME_MS
ORDER BY total_exec_time DESC
LIMIT 20;

\echo ''
\echo '========================================='
\echo 'Testing Specific Query Patterns'
\echo '========================================='
\echo ''

-- Test function
CREATE OR REPLACE FUNCTION test_query_index(
    p_table_name TEXT,
    p_columns TEXT,
    p_index_name TEXT,
    p_test_query TEXT
)
RETURNS TABLE (
    decision TEXT,
    baseline_ms NUMERIC,
    with_index_ms NUMERIC,
    improvement_pct NUMERIC
) AS $$
DECLARE
    v_baseline_ms NUMERIC;
    v_with_index_ms NUMERIC;
    v_improvement NUMERIC;
    v_decision TEXT;
    v_start TIMESTAMP;
    v_end TIMESTAMP;
    i INT;
BEGIN
    -- Test baseline (5 runs)
    v_baseline_ms := 0;
    FOR i IN 1..5 LOOP
        v_start := clock_timestamp();
        EXECUTE p_test_query;
        v_end := clock_timestamp();
        v_baseline_ms := v_baseline_ms + EXTRACT(MILLISECOND FROM (v_end - v_start));
    END LOOP;
    v_baseline_ms := v_baseline_ms / 5.0;

    RAISE NOTICE 'Baseline: %.2f ms', v_baseline_ms;

    -- Create index
    EXECUTE 'CREATE INDEX ' || p_index_name || ' ON ' || p_table_name || '(' || p_columns || ')';
    EXECUTE 'ANALYZE ' || p_table_name;

    RAISE NOTICE 'Index created: %(%)', p_index_name, p_columns;

    -- Test with index (5 runs)
    v_with_index_ms := 0;
    FOR i IN 1..5 LOOP
        v_start := clock_timestamp();
        EXECUTE p_test_query;
        v_end := clock_timestamp();
        v_with_index_ms := v_with_index_ms + EXTRACT(MILLISECOND FROM (v_end - v_start));
    END LOOP;
    v_with_index_ms := v_with_index_ms / 5.0;

    RAISE NOTICE 'With index: %.2f ms', v_with_index_ms;

    -- Calculate improvement
    v_improvement := ROUND(100.0 * (v_baseline_ms - v_with_index_ms) / NULLIF(v_baseline_ms, 0), 2);

    -- Decide
    IF v_improvement >= 5.0 THEN
        v_decision := 'KEEP';
        RAISE NOTICE 'KEEP - improved by %.2f%%', v_improvement;
    ELSE
        v_decision := 'ROLLBACK';
        EXECUTE 'DROP INDEX ' || p_index_name;
        RAISE NOTICE 'ROLLBACK - only improved by %.2f%%', v_improvement;
    END IF;

    -- Log
    INSERT INTO pg_index_test_log (table_name, index_name, test_phase, execution_time_ms, decision, improvement_percent, notes)
    VALUES (p_table_name, p_index_name, 'baseline', v_baseline_ms, NULL, NULL, 'Query-based: ' || p_columns);

    INSERT INTO pg_index_test_log (table_name, index_name, test_phase, execution_time_ms, decision, improvement_percent, notes)
    VALUES (p_table_name, p_index_name, 'with_index', v_with_index_ms, NULL, NULL, 'Query-based: ' || p_columns);

    INSERT INTO pg_index_test_log (table_name, index_name, test_phase, execution_time_ms, decision, improvement_percent, notes)
    VALUES (p_table_name, p_index_name, 'decision', v_with_index_ms, v_decision, v_improvement, 'Query-based: ' || p_columns);

    RETURN QUERY SELECT v_decision, v_baseline_ms, v_with_index_ms, v_improvement;
END;
$$ LANGUAGE plpgsql;

\echo 'Test function created'
\echo ''

-- ============================================================================
-- TEST 1: xs_item_cache (elementName, ids) - Most frequent slow query
-- ============================================================================

\echo ''
\echo '========================================='
\echo 'Test 1: xs_item_cache (elementName, ids)'
\echo '========================================='
\echo 'Query pattern: SELECT contents FROM xs_item_cache WHERE elementName=$1 AND ids=$2'
\echo 'Calls: 1,284 | Avg: 1.63ms'
\echo ''

DO $$
DECLARE
    result RECORD;
    sample_element TEXT;
    sample_ids TEXT;
BEGIN
    SELECT elementName, ids INTO sample_element, sample_ids
    FROM xs_item_cache
    WHERE elementName IS NOT NULL AND ids IS NOT NULL
    LIMIT 1;

    IF sample_element IS NOT NULL THEN
        SELECT * INTO result FROM test_query_index(
            'xs_item_cache',
            'elementName, ids',
            'idx_test_query_item_cache_element_ids',
            FORMAT('SELECT contents FROM xs_item_cache WHERE elementName = %L AND ids = %L', sample_element, sample_ids)
        );
    END IF;
END $$;

-- ============================================================================
-- TEST 2: xnat_imagesessiondata_history (id, change_date)
-- ============================================================================

\echo ''
\echo '========================================='
\echo 'Test 2: xnat_imagesessiondata_history'
\echo '========================================='
\echo 'Query pattern: WHERE id = $1 AND change_date IS NOT NULL'
\echo 'Calls: 1,107 | Avg: 0.09ms'
\echo ''

DO $$
DECLARE
    result RECORD;
    sample_id TEXT;
BEGIN
    SELECT id INTO sample_id FROM xnat_imagesessiondata_history LIMIT 1;

    IF sample_id IS NOT NULL THEN
        SELECT * INTO result FROM test_query_index(
            'xnat_imagesessiondata_history',
            'id, change_date',
            'idx_test_query_imagesession_history',
            FORMAT('SELECT * FROM xnat_imagesessiondata_history WHERE id = %L AND change_date IS NOT NULL ORDER BY change_date DESC LIMIT 10', sample_id)
        );
    END IF;
END $$;

-- ============================================================================
-- TEST 3: xhbm_preference (multiple patterns)
-- ============================================================================

\echo ''
\echo '========================================='
\echo 'Test 3: xhbm_preference'
\echo '========================================='
\echo 'Query pattern: Complex WHERE clauses'
\echo 'Calls: 7,162 | Avg: 0.08ms'
\echo ''

DO $$
DECLARE
    result RECORD;
    sample_tool TEXT;
BEGIN
    SELECT tool INTO sample_tool FROM xhbm_preference WHERE tool IS NOT NULL LIMIT 1;

    IF sample_tool IS NOT NULL THEN
        SELECT * INTO result FROM test_query_index(
            'xhbm_preference',
            'tool, name',
            'idx_test_query_preference_tool_name',
            FORMAT('SELECT * FROM xhbm_preference WHERE tool = %L LIMIT 100', sample_tool)
        );
    END IF;
END $$;

-- ============================================================================
-- TEST 4: xdat_user_login (session_id)
-- ============================================================================

\echo ''
\echo '========================================='
\echo 'Test 4: xdat_user_login (session_id)'
\echo '========================================='
\echo 'Query pattern: WHERE session_id IN (...)'
\echo ''

DO $$
DECLARE
    result RECORD;
    sample_sessions TEXT;
BEGIN
    SELECT string_agg(quote_literal(session_id), ',') INTO sample_sessions
    FROM (SELECT session_id FROM xdat_user_login WHERE session_id IS NOT NULL LIMIT 5) s;

    IF sample_sessions IS NOT NULL THEN
        SELECT * INTO result FROM test_query_index(
            'xdat_user_login',
            'session_id',
            'idx_test_query_user_login_session',
            FORMAT('SELECT * FROM xdat_user_login WHERE session_id IN (%s)', sample_sessions)
        );
    END IF;
END $$;

-- ============================================================================
-- SUMMARY REPORT
-- ============================================================================

\echo ''
\echo '========================================='
\echo 'SUMMARY'
\echo '========================================='
\echo ''

SELECT
    COUNT(DISTINCT table_name) AS tables_tested,
    COUNT(DISTINCT index_name) AS indexes_tested,
    COUNT(*) FILTER (WHERE decision = 'KEEP') AS kept,
    COUNT(*) FILTER (WHERE decision = 'ROLLBACK') AS rolled_back,
    ROUND(AVG(improvement_percent) FILTER (WHERE decision = 'KEEP'), 2) AS avg_improvement_pct
FROM pg_index_test_log
WHERE test_phase = 'decision'
  AND index_name LIKE 'idx_test_query_%';

\echo ''
\echo '--- KEPT INDEXES (>= 5% improvement) ---'
SELECT
    table_name,
    index_name,
    notes AS columns,
    ROUND(improvement_percent, 2) AS improvement_pct
FROM pg_index_test_log
WHERE decision = 'KEEP'
  AND index_name LIKE 'idx_test_query_%'
ORDER BY improvement_percent DESC;

\echo ''
\echo 'Results saved in pg_index_test_log table'
\echo ''
