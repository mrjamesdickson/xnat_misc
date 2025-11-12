-- Test Non-Foreign-Key Index Candidates
-- Based on high sequential scan analysis from pg_stat_statements
-- Duration: ~5-10 minutes

\timing on

\echo ''
\echo '========================================='
\echo 'Testing Non-FK Index Candidates'
\echo '========================================='
\echo ''
\echo 'Based on query analysis:'
\echo '- xnat_imagesessiondata_history: 1,087 calls, 99.86% seq scans'
\echo '- xs_item_cache: 234 calls, 99.99% seq scans'
\echo '- xhbm_xdat_user_auth: 55 calls, 100% seq scans'
\echo '- xdat_user_login: High session_id lookups'
\echo ''

-- Truncate existing log
TRUNCATE TABLE pg_index_test_log;

-- Reuse test function from FK tests
CREATE OR REPLACE FUNCTION test_non_fk_index(
    p_table_name TEXT,
    p_columns TEXT,  -- Can be single or composite: 'col1' or 'col1, col2'
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
    VALUES (p_table_name, p_index_name, 'baseline', v_baseline_ms, NULL, NULL, 'Columns: ' || p_columns);

    INSERT INTO pg_index_test_log (table_name, index_name, test_phase, execution_time_ms, decision, improvement_percent, notes)
    VALUES (p_table_name, p_index_name, 'with_index', v_with_index_ms, NULL, NULL, 'Columns: ' || p_columns);

    INSERT INTO pg_index_test_log (table_name, index_name, test_phase, execution_time_ms, decision, improvement_percent, notes)
    VALUES (p_table_name, p_index_name, 'decision', v_with_index_ms, v_decision, v_improvement, 'Columns: ' || p_columns);

    RETURN QUERY SELECT v_decision, v_baseline_ms, v_with_index_ms, v_improvement;
END;
$$ LANGUAGE plpgsql;

\echo 'Test function created'
\echo ''

-- ============================================================================
-- TEST 1: xnat_imagesessiondata_history (id, change_date)
-- ============================================================================

\echo ''
\echo '========================================='
\echo 'Test 1: xnat_imagesessiondata_history'
\echo '========================================='
\echo 'Query pattern: WHERE id = X AND change_date IS NOT NULL AND change_date <= Y'
\echo 'Calls: 1,087 | Seq scans: 99.86%'
\echo ''

DO $$
DECLARE
    result RECORD;
    sample_id TEXT;
BEGIN
    -- Get a sample ID that has history records
    SELECT id INTO sample_id FROM xnat_imagesessiondata_history LIMIT 1;

    IF sample_id IS NOT NULL THEN
        SELECT * INTO result FROM test_non_fk_index(
            'xnat_imagesessiondata_history',
            'id, change_date',
            'idx_test_imagesession_history_id_date',
            FORMAT('SELECT * FROM xnat_imagesessiondata_history WHERE id = %L AND change_date IS NOT NULL ORDER BY change_date DESC LIMIT 10', sample_id)
        );
    ELSE
        RAISE NOTICE 'No data in xnat_imagesessiondata_history - skipping';
    END IF;
END $$;

-- ============================================================================
-- TEST 2: xs_item_cache (elementName, ids)
-- ============================================================================

\echo ''
\echo '========================================='
\echo 'Test 2: xs_item_cache'
\echo '========================================='
\echo 'Query pattern: WHERE elementName = X AND ids = Y'
\echo 'Calls: 234 | Seq scans: 99.99%'
\echo ''

DO $$
DECLARE
    result RECORD;
    sample_element TEXT;
    sample_ids TEXT;
BEGIN
    -- Get sample values
    SELECT elementName, ids INTO sample_element, sample_ids
    FROM xs_item_cache
    WHERE elementName IS NOT NULL AND ids IS NOT NULL
    LIMIT 1;

    IF sample_element IS NOT NULL THEN
        SELECT * INTO result FROM test_non_fk_index(
            'xs_item_cache',
            'elementName, ids',
            'idx_test_item_cache_element_ids',
            FORMAT('SELECT contents FROM xs_item_cache WHERE elementName = %L AND ids = %L', sample_element, sample_ids)
        );
    ELSE
        RAISE NOTICE 'No data in xs_item_cache - skipping';
    END IF;
END $$;

-- ============================================================================
-- TEST 3: xhbm_xdat_user_auth (id)
-- ============================================================================

\echo ''
\echo '========================================='
\echo 'Test 3: xhbm_xdat_user_auth'
\echo '========================================='
\echo 'Query pattern: WHERE id = X'
\echo 'Calls: 55 | Seq scans: 100%'
\echo ''

DO $$
DECLARE
    result RECORD;
    sample_id BIGINT;
BEGIN
    -- Get sample ID
    SELECT id INTO sample_id FROM xhbm_xdat_user_auth LIMIT 1;

    IF sample_id IS NOT NULL THEN
        SELECT * INTO result FROM test_non_fk_index(
            'xhbm_xdat_user_auth',
            'id',
            'idx_test_xdat_user_auth_id',
            FORMAT('SELECT * FROM xhbm_xdat_user_auth WHERE id = %s', sample_id)
        );
    ELSE
        RAISE NOTICE 'No data in xhbm_xdat_user_auth - skipping';
    END IF;
END $$;

-- ============================================================================
-- TEST 4: xdat_user_login (session_id)
-- ============================================================================

\echo ''
\echo '========================================='
\echo 'Test 4: xdat_user_login'
\echo '========================================='
\echo 'Query pattern: WHERE session_id IN (...)'
\echo 'Calls: 12 | Seq scans: 67.65%'
\echo ''

DO $$
DECLARE
    result RECORD;
    sample_sessions TEXT;
BEGIN
    -- Get sample session IDs
    SELECT string_agg(quote_literal(session_id), ',') INTO sample_sessions
    FROM (SELECT session_id FROM xdat_user_login WHERE session_id IS NOT NULL LIMIT 5) s;

    IF sample_sessions IS NOT NULL THEN
        SELECT * INTO result FROM test_non_fk_index(
            'xdat_user_login',
            'session_id',
            'idx_test_user_login_session',
            FORMAT('SELECT session_id, ip_address FROM xdat_user_login WHERE session_id IN (%s)', sample_sessions)
        );
    ELSE
        RAISE NOTICE 'No sessions in xdat_user_login - skipping';
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
    COUNT(*) FILTER (WHERE decision = 'ERROR') AS errors,
    ROUND(AVG(improvement_percent) FILTER (WHERE decision = 'KEEP'), 2) AS avg_improvement_pct
FROM pg_index_test_log
WHERE test_phase = 'decision';

\echo ''
\echo '--- KEPT INDEXES (>= 5% improvement) ---'
SELECT
    table_name,
    index_name,
    notes AS columns,
    ROUND(improvement_percent, 2) AS improvement_pct
FROM pg_index_test_log
WHERE decision = 'KEEP'
ORDER BY improvement_percent DESC;

\echo ''
\echo '--- ROLLED BACK (<5% improvement) ---'
SELECT
    table_name,
    index_name,
    notes AS columns,
    ROUND(improvement_percent, 2) AS improvement_pct
FROM pg_index_test_log
WHERE decision = 'ROLLBACK'
ORDER BY improvement_percent DESC;

-- Cleanup test indexes
DO $$
DECLARE
    idx RECORD;
BEGIN
    FOR idx IN SELECT DISTINCT indexname FROM pg_indexes WHERE indexname LIKE 'idx_test_%'
    LOOP
        EXECUTE 'DROP INDEX IF EXISTS ' || idx.indexname;
        RAISE NOTICE 'Dropped: %', idx.indexname;
    END LOOP;
END $$;

\echo ''
\echo 'All test indexes cleaned up'
\echo 'Results saved in pg_index_test_log table'
\echo ''
