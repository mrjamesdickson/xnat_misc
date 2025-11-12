-- Simple Foreign Key Index Testing
-- Tests all foreign keys without indexes using simple WHERE IS NOT NULL queries
-- Duration: ~15-30 minutes

\timing on

\echo ''
\echo '========================================='
\echo 'Simple FK Index Testing'
\echo '========================================='
\echo ''

-- Truncate existing log
TRUNCATE TABLE pg_index_test_log;

-- Create test functions
CREATE OR REPLACE FUNCTION test_fk_index(
    p_table_name TEXT,
    p_column_name TEXT,
    p_index_name TEXT
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
    v_test_query TEXT;
    v_start TIMESTAMP;
    v_end TIMESTAMP;
    i INT;
BEGIN
    -- Build test query
    v_test_query := 'SELECT COUNT(*) FROM ' || p_table_name || ' WHERE ' || p_column_name || ' IS NOT NULL';

    -- Test baseline (5 runs)
    v_baseline_ms := 0;
    FOR i IN 1..5 LOOP
        v_start := clock_timestamp();
        EXECUTE v_test_query;
        v_end := clock_timestamp();
        v_baseline_ms := v_baseline_ms + EXTRACT(MILLISECOND FROM (v_end - v_start));
    END LOOP;
    v_baseline_ms := v_baseline_ms / 5.0;

    RAISE NOTICE 'Baseline: %.2f ms', v_baseline_ms;

    -- Create index
    EXECUTE 'CREATE INDEX ' || p_index_name || ' ON ' || p_table_name || '(' || p_column_name || ')';
    EXECUTE 'ANALYZE ' || p_table_name;

    RAISE NOTICE 'Index created';

    -- Test with index (5 runs)
    v_with_index_ms := 0;
    FOR i IN 1..5 LOOP
        v_start := clock_timestamp();
        EXECUTE v_test_query;
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
    INSERT INTO pg_index_test_log (table_name, index_name, test_phase, execution_time_ms, decision, improvement_percent)
    VALUES (p_table_name, p_index_name, 'baseline', v_baseline_ms, NULL, NULL);

    INSERT INTO pg_index_test_log (table_name, index_name, test_phase, execution_time_ms, decision, improvement_percent)
    VALUES (p_table_name, p_index_name, 'with_index', v_with_index_ms, NULL, NULL);

    INSERT INTO pg_index_test_log (table_name, index_name, test_phase, execution_time_ms, decision, improvement_percent)
    VALUES (p_table_name, p_index_name, 'decision', v_with_index_ms, v_decision, v_improvement);

    RETURN QUERY SELECT v_decision, v_baseline_ms, v_with_index_ms, v_improvement;
END;
$$ LANGUAGE plpgsql;

\echo 'Function created'
\echo ''

-- Test all foreign keys
DO $$
DECLARE
    fk RECORD;
    result RECORD;
    test_num INT := 0;
    total_fks INT;
BEGIN
    -- Count total
    SELECT COUNT(DISTINCT (c.conrelid, a.attname)) INTO total_fks
    FROM pg_constraint c
    JOIN pg_attribute a ON a.attnum = ANY(c.conkey) AND a.attrelid = c.conrelid
    WHERE c.contype = 'f'
      AND NOT EXISTS (
          SELECT 1 FROM pg_index i
          WHERE i.indrelid = c.conrelid AND c.conkey[1] = ANY(i.indkey)
      );

    RAISE NOTICE 'Testing % foreign keys...', total_fks;
    RAISE NOTICE '';

    -- Loop through FKs
    FOR fk IN
        SELECT DISTINCT
            c.conrelid::regclass::text AS table_name,
            a.attname AS column_name,
            pg_size_pretty(pg_relation_size(c.conrelid)) AS size,
            (SELECT reltuples::bigint FROM pg_class WHERE oid = c.conrelid) AS rows,
            pg_relation_size(c.conrelid) AS size_bytes
        FROM pg_constraint c
        JOIN pg_attribute a ON a.attnum = ANY(c.conkey) AND a.attrelid = c.conrelid
        WHERE c.contype = 'f'
          AND NOT EXISTS (
              SELECT 1 FROM pg_index i
              WHERE i.indrelid = c.conrelid AND c.conkey[1] = ANY(i.indkey)
          )
        ORDER BY size_bytes DESC
        LIMIT 20
    LOOP
        test_num := test_num + 1;

        RAISE NOTICE '========================================';
        RAISE NOTICE 'Test %/%: %.% (%)', test_num, total_fks, fk.table_name, fk.column_name, fk.size;
        RAISE NOTICE '========================================';

        BEGIN
            SELECT * INTO result FROM test_fk_index(
                fk.table_name,
                fk.column_name,
                'idx_test_fk_' || test_num
            );
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'ERROR: %', SQLERRM;
            INSERT INTO pg_index_test_log (table_name, index_name, test_phase, decision, notes)
            VALUES (fk.table_name, 'idx_test_fk_' || test_num, 'error', 'ERROR', SQLERRM);
        END;

        RAISE NOTICE '';
    END LOOP;
END $$;

-- Summary report
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
    ROUND(improvement_percent, 2) AS improvement_pct
FROM pg_index_test_log
WHERE decision = 'KEEP'
ORDER BY improvement_percent DESC;

\echo ''
\echo '--- ROLLED BACK (<5% improvement) ---'
SELECT
    table_name,
    index_name,
    ROUND(improvement_percent, 2) AS improvement_pct
FROM pg_index_test_log
WHERE decision = 'ROLLBACK'
ORDER BY improvement_percent DESC;

\echo ''
\echo '--- ERRORS ---'
SELECT
    table_name,
    index_name,
    notes
FROM pg_index_test_log
WHERE decision = 'ERROR';

-- Cleanup remaining test indexes
DO $$
DECLARE
    idx RECORD;
BEGIN
    FOR idx IN SELECT DISTINCT indexname FROM pg_indexes WHERE indexname LIKE 'idx_test_fk_%'
    LOOP
        EXECUTE 'DROP INDEX IF EXISTS ' || idx.indexname;
        RAISE NOTICE 'Dropped: %', idx.indexname;
    END LOOP;
END $$;

\echo ''
\echo 'All test indexes cleaned up'
\echo 'Results saved in pg_index_test_log table'
\echo ''
