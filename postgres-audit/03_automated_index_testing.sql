-- Automated Index Testing and Optimization
-- Purpose: Test index performance, keep if better, rollback if worse
-- Usage: psql -h localhost -U postgres -d your_database -f 03_automated_index_testing.sql
-- Output: Detailed performance report with recommendations

\timing on
\set ECHO all

-- ============================================================================
-- SETUP: Create logging table and test framework
-- ============================================================================

\echo ''
\echo '========================================='
\echo 'Automated Index Performance Testing'
\echo '========================================='
\echo ''

-- Create logging table if it doesn't exist
CREATE TABLE IF NOT EXISTS pg_index_test_log (
    test_id SERIAL PRIMARY KEY,
    test_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    table_name TEXT,
    index_name TEXT,
    test_phase TEXT,  -- 'baseline', 'with_index', 'decision'
    execution_time_ms NUMERIC,
    query_plan TEXT,
    decision TEXT,  -- 'keep', 'rollback', 'pending'
    improvement_percent NUMERIC,
    notes TEXT
);

\echo 'Created logging table: pg_index_test_log'
\echo ''

-- ============================================================================
-- FUNCTION: Test Query Performance
-- ============================================================================

CREATE OR REPLACE FUNCTION test_query_performance(
    p_table_name TEXT,
    p_query TEXT,
    p_iterations INT DEFAULT 5
)
RETURNS NUMERIC AS $$
DECLARE
    v_start TIMESTAMP;
    v_end TIMESTAMP;
    v_total_ms NUMERIC := 0;
    v_avg_ms NUMERIC;
    i INT;
BEGIN
    -- Warm up (discard first run)
    EXECUTE p_query;

    -- Run multiple iterations
    FOR i IN 1..p_iterations LOOP
        v_start := clock_timestamp();
        EXECUTE p_query;
        v_end := clock_timestamp();
        v_total_ms := v_total_ms + EXTRACT(MILLISECOND FROM (v_end - v_start));
    END LOOP;

    v_avg_ms := v_total_ms / p_iterations;
    RETURN v_avg_ms;
END;
$$ LANGUAGE plpgsql;

\echo 'Created function: test_query_performance()'
\echo ''

-- ============================================================================
-- FUNCTION: Test Index Candidate
-- ============================================================================

CREATE OR REPLACE FUNCTION test_index_candidate(
    p_table_name TEXT,
    p_index_name TEXT,
    p_index_definition TEXT,
    p_test_query TEXT,
    p_improvement_threshold NUMERIC DEFAULT 10.0
)
RETURNS TABLE (
    decision TEXT,
    baseline_ms NUMERIC,
    with_index_ms NUMERIC,
    improvement_percent NUMERIC,
    recommendation TEXT
) AS $$
DECLARE
    v_baseline_ms NUMERIC;
    v_with_index_ms NUMERIC;
    v_improvement_percent NUMERIC;
    v_decision TEXT;
    v_recommendation TEXT;
    v_baseline_plan TEXT;
    v_index_plan TEXT;
BEGIN
    -- Step 1: Test baseline (without index)
    RAISE NOTICE 'Testing baseline performance for %...', p_table_name;
    v_baseline_ms := test_query_performance(p_table_name, p_test_query, 5);

    -- Get baseline query plan
    EXECUTE 'EXPLAIN (FORMAT TEXT) ' || p_test_query INTO v_baseline_plan;

    -- Log baseline
    INSERT INTO pg_index_test_log (
        table_name, index_name, test_phase, execution_time_ms, query_plan, notes
    ) VALUES (
        p_table_name, p_index_name, 'baseline', v_baseline_ms, v_baseline_plan,
        'Baseline test without index'
    );

    -- Step 2: Create index
    RAISE NOTICE 'Creating index: %', p_index_name;
    BEGIN
        EXECUTE p_index_definition;
        RAISE NOTICE 'Index created successfully';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Failed to create index: %', SQLERRM;
        v_decision := 'error';
        v_recommendation := 'Failed to create index: ' || SQLERRM;
        RETURN QUERY SELECT v_decision, v_baseline_ms, NULL::NUMERIC, NULL::NUMERIC, v_recommendation;
        RETURN;
    END;

    -- Update statistics
    EXECUTE 'ANALYZE ' || p_table_name;

    -- Step 3: Test with index
    RAISE NOTICE 'Testing performance with index...';
    v_with_index_ms := test_query_performance(p_table_name, p_test_query, 5);

    -- Get index query plan
    EXECUTE 'EXPLAIN (FORMAT TEXT) ' || p_test_query INTO v_index_plan;

    -- Log with-index test
    INSERT INTO pg_index_test_log (
        table_name, index_name, test_phase, execution_time_ms, query_plan, notes
    ) VALUES (
        p_table_name, p_index_name, 'with_index', v_with_index_ms, v_index_plan,
        'Test with index created'
    );

    -- Step 4: Calculate improvement
    v_improvement_percent := ROUND(
        100.0 * (v_baseline_ms - v_with_index_ms) / NULLIF(v_baseline_ms, 0),
        2
    );

    -- Step 5: Make decision
    IF v_improvement_percent >= p_improvement_threshold THEN
        v_decision := 'KEEP';
        v_recommendation := FORMAT(
            'Index improved performance by %s%% (%.2fms -> %.2fms). KEEPING index.',
            v_improvement_percent, v_baseline_ms, v_with_index_ms
        );
        RAISE NOTICE '%', v_recommendation;
    ELSE
        v_decision := 'ROLLBACK';
        v_recommendation := FORMAT(
            'Index only improved by %s%% (%.2fms -> %.2fms). ROLLING BACK.',
            COALESCE(v_improvement_percent, 0), v_baseline_ms, v_with_index_ms
        );
        RAISE NOTICE '%', v_recommendation;

        -- Drop the index
        EXECUTE 'DROP INDEX IF EXISTS ' || p_index_name;
        RAISE NOTICE 'Index dropped';
    END IF;

    -- Log decision
    INSERT INTO pg_index_test_log (
        table_name, index_name, test_phase, execution_time_ms,
        decision, improvement_percent, notes
    ) VALUES (
        p_table_name, p_index_name, 'decision', v_with_index_ms,
        v_decision, v_improvement_percent, v_recommendation
    );

    -- Return results
    RETURN QUERY SELECT
        v_decision,
        v_baseline_ms,
        v_with_index_ms,
        v_improvement_percent,
        v_recommendation;
END;
$$ LANGUAGE plpgsql;

\echo 'Created function: test_index_candidate()'
\echo ''

-- ============================================================================
-- EXAMPLE USAGE
-- ============================================================================

\echo ''
\echo '--- Example: Test an Index Candidate ---'
\echo ''
\echo 'Usage:'
\echo 'SELECT * FROM test_index_candidate('
\echo '    ''my_table'','
\echo '    ''idx_my_table_column'','
\echo '    ''CREATE INDEX idx_my_table_column ON my_table(column_name)'','
\echo '    ''SELECT * FROM my_table WHERE column_name = ''''value'''''' ,'
\echo '    10.0  -- minimum 10% improvement required'
\echo ');'
\echo ''

-- ============================================================================
-- AUTOMATED TEST SUITE: Test All Foreign Key Indexes
-- ============================================================================

\echo ''
\echo '--- Running Automated Test Suite ---'
\echo 'Testing index candidates for foreign keys...'
\echo ''

DO $$
DECLARE
    fk_rec RECORD;
    test_result RECORD;
    test_query TEXT;
    index_name TEXT;
    index_def TEXT;
BEGIN
    -- Loop through foreign keys without indexes
    FOR fk_rec IN
        SELECT DISTINCT
            c.conrelid::regclass::text AS table_name,
            a.attname AS column_name,
            c.confrelid::regclass::text AS ref_table
        FROM pg_constraint c
        JOIN pg_attribute a ON a.attnum = ANY(c.conkey) AND a.attrelid = c.conrelid
        WHERE c.contype = 'f'
          AND NOT EXISTS (
              SELECT 1
              FROM pg_index i
              WHERE i.indrelid = c.conrelid
                AND c.conkey[1] = ANY(i.indkey)
          )
        LIMIT 5  -- Test first 5 candidates
    LOOP
        -- Generate index name and definition
        index_name := 'idx_test_' || replace(fk_rec.table_name, '.', '_') || '_' || fk_rec.column_name;
        index_def := FORMAT('CREATE INDEX %s ON %s(%s)', index_name, fk_rec.table_name, fk_rec.column_name);

        -- Generate test query (simple WHERE clause on FK column)
        test_query := FORMAT(
            'SELECT * FROM %s WHERE %s IS NOT NULL LIMIT 1000',
            fk_rec.table_name, fk_rec.column_name
        );

        RAISE NOTICE '';
        RAISE NOTICE '========================================';
        RAISE NOTICE 'Testing: % on %(%)', index_name, fk_rec.table_name, fk_rec.column_name;
        RAISE NOTICE '========================================';

        -- Test the index
        SELECT * INTO test_result
        FROM test_index_candidate(
            fk_rec.table_name,
            index_name,
            index_def,
            test_query,
            5.0  -- 5% minimum improvement
        );

        -- Log result
        RAISE NOTICE 'Result: %', test_result.recommendation;
    END LOOP;
END $$;

-- ============================================================================
-- GENERATE FINAL REPORT
-- ============================================================================

\echo ''
\echo '========================================='
\echo 'FINAL PERFORMANCE TEST REPORT'
\echo '========================================='
\echo ''

\echo '--- Summary Statistics ---'
SELECT
    COUNT(DISTINCT table_name) AS tables_tested,
    COUNT(DISTINCT index_name) AS indexes_tested,
    COUNT(*) FILTER (WHERE decision = 'KEEP') AS indexes_kept,
    COUNT(*) FILTER (WHERE decision = 'ROLLBACK') AS indexes_rolled_back,
    ROUND(AVG(improvement_percent) FILTER (WHERE decision = 'KEEP'), 2) AS avg_improvement_percent
FROM pg_index_test_log
WHERE test_phase = 'decision';

\echo ''
\echo '--- Kept Indexes (Performance Improved) ---'
SELECT
    table_name,
    index_name,
    ROUND(improvement_percent, 2) AS improvement_pct,
    notes
FROM pg_index_test_log
WHERE test_phase = 'decision'
  AND decision = 'KEEP'
ORDER BY improvement_percent DESC;

\echo ''
\echo '--- Rolled Back Indexes (Not Worth Keeping) ---'
SELECT
    table_name,
    index_name,
    ROUND(COALESCE(improvement_percent, 0), 2) AS improvement_pct,
    notes
FROM pg_index_test_log
WHERE test_phase = 'decision'
  AND decision = 'ROLLBACK'
ORDER BY improvement_percent DESC NULLS LAST;

\echo ''
\echo '--- Performance Comparison Details ---'
SELECT
    l.table_name,
    l.index_name,
    b.execution_time_ms AS baseline_ms,
    i.execution_time_ms AS with_index_ms,
    l.improvement_percent,
    l.decision
FROM pg_index_test_log l
LEFT JOIN pg_index_test_log b
    ON l.table_name = b.table_name
    AND l.index_name = b.index_name
    AND b.test_phase = 'baseline'
LEFT JOIN pg_index_test_log i
    ON l.table_name = i.table_name
    AND l.index_name = i.index_name
    AND i.test_phase = 'with_index'
WHERE l.test_phase = 'decision'
ORDER BY l.improvement_percent DESC NULLS LAST;

-- ============================================================================
-- CLEANUP: Revert All Changes
-- ============================================================================

\echo ''
\echo '--- Cleanup: Reverting All Test Changes ---'
\echo ''

-- Drop any remaining test indexes
DO $$
DECLARE
    idx_rec RECORD;
BEGIN
    FOR idx_rec IN
        SELECT DISTINCT indexname
        FROM pg_indexes
        WHERE indexname LIKE 'idx_test_%'
    LOOP
        EXECUTE 'DROP INDEX IF EXISTS ' || idx_rec.indexname;
        RAISE NOTICE 'Dropped test index: %', idx_rec.indexname;
    END LOOP;
END $$;

-- Drop test functions
DROP FUNCTION IF EXISTS test_index_candidate(TEXT, TEXT, TEXT, TEXT, NUMERIC);
DROP FUNCTION IF EXISTS test_query_performance(TEXT, TEXT, INT);

\echo ''
\echo 'Test functions dropped'
\echo ''

-- Keep log table for review
\echo ''
\echo 'NOTE: Keeping pg_index_test_log table for review'
\echo 'To view full test log: SELECT * FROM pg_index_test_log ORDER BY test_id;'
\echo 'To drop log table: DROP TABLE pg_index_test_log;'
\echo ''

-- ============================================================================
-- FINAL SUMMARY
-- ============================================================================

\echo '========================================='
\echo 'AUTOMATED INDEX TESTING COMPLETE'
\echo '========================================='
\echo ''
\echo 'Summary:'
\echo '- All test indexes have been reverted'
\echo '- Test log preserved in pg_index_test_log table'
\echo '- Review report above for recommendations'
\echo ''
\echo 'Next Steps:'
\echo '1. Review indexes that were KEPT (showed improvement)'
\echo '2. Manually create those indexes in production'
\echo '3. Monitor performance after implementation'
\echo ''
\echo 'To export full report:'
\echo 'psql -d your_db -c "SELECT * FROM pg_index_test_log" > index_test_report.csv'
\echo ''
