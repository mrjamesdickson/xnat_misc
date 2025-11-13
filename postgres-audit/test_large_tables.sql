-- Test Indexes for Large Tables
-- Dynamically tests top N largest tables based on size and activity
-- Duration: ~20-60 minutes depending on MAX_TABLES parameter

\timing on

-- Configuration parameters (can be overridden with -v flag)
-- Remove \set commands to allow command-line overrides
-- Defaults: MAX_TABLES=20, MIN_SIZE_MB=1, MIN_SEQ_SCANS=10

\echo ''
\echo '========================================='
\echo 'Testing Indexes for Large Tables'
\echo '========================================='
\echo 'Configuration:'
\echo '  MAX_TABLES: ' :MAX_TABLES
\echo '  MIN_SIZE_MB: ' :MIN_SIZE_MB
\echo '  MIN_SEQ_SCANS: ' :MIN_SEQ_SCANS
\echo ''

-- Test function
CREATE OR REPLACE FUNCTION test_large_table_index(
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
    v_start TIMESTAMP;
    v_end TIMESTAMP;
    v_test_query TEXT;
    v_sample_value TEXT;
    i INT;
BEGIN
    -- Get a sample value from the column
    BEGIN
        EXECUTE FORMAT('SELECT %I::TEXT FROM %I WHERE %I IS NOT NULL LIMIT 1',
                      p_column_name, p_table_name, p_column_name)
        INTO v_sample_value;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Skipped % - cannot sample column %: %', p_table_name, p_column_name, SQLERRM;
        RETURN;
    END;

    IF v_sample_value IS NULL THEN
        RAISE NOTICE 'Skipped % - no data in column %', p_table_name, p_column_name;
        RETURN;
    END IF;

    -- Build test query
    v_test_query := FORMAT('SELECT * FROM %I WHERE %I = %L LIMIT 100',
                          p_table_name, p_column_name, v_sample_value);

    RAISE NOTICE 'Testing % on %.%', p_index_name, p_table_name, p_column_name;

    -- Test baseline (5 runs)
    v_baseline_ms := 0;
    FOR i IN 1..5 LOOP
        v_start := clock_timestamp();
        BEGIN
            EXECUTE v_test_query;
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'Skipped % - query error: %', p_table_name, SQLERRM;
            RETURN;
        END;
        v_end := clock_timestamp();
        v_baseline_ms := v_baseline_ms + EXTRACT(MILLISECOND FROM (v_end - v_start));
    END LOOP;
    v_baseline_ms := v_baseline_ms / 5.0;

    RAISE NOTICE 'Baseline: %.2f ms', v_baseline_ms;

    -- Create index
    BEGIN
        EXECUTE FORMAT('CREATE INDEX %I ON %I(%I)', p_index_name, p_table_name, p_column_name);
        EXECUTE FORMAT('ANALYZE %I', p_table_name);
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Skipped % - index creation error: %', p_table_name, SQLERRM;
        RETURN;
    END;

    RAISE NOTICE 'Index created: %', p_index_name;

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
        EXECUTE FORMAT('DROP INDEX %I', p_index_name);
        RAISE NOTICE 'ROLLBACK - only improved by %.2f%%', v_improvement;
    END IF;

    -- Log results
    INSERT INTO pg_index_test_log (table_name, index_name, test_phase, execution_time_ms, decision, improvement_percent, notes)
    VALUES (p_table_name, p_index_name, 'baseline', v_baseline_ms, NULL, NULL, 'Column: ' || p_column_name);

    INSERT INTO pg_index_test_log (table_name, index_name, test_phase, execution_time_ms, decision, improvement_percent, notes)
    VALUES (p_table_name, p_index_name, 'with_index', v_with_index_ms, NULL, NULL, 'Column: ' || p_column_name);

    INSERT INTO pg_index_test_log (table_name, index_name, test_phase, execution_time_ms, decision, improvement_percent, notes)
    VALUES (p_table_name, p_index_name, 'decision', v_with_index_ms, v_decision, v_improvement, 'Column: ' || p_column_name);

    RETURN QUERY SELECT v_decision, v_baseline_ms, v_with_index_ms, v_improvement;
END;
$$ LANGUAGE plpgsql;

\echo 'Test function created'
\echo ''

-- Create temp table to hold configuration
CREATE TEMP TABLE IF NOT EXISTS test_config (
    max_tables INT DEFAULT 20,
    min_size_mb INT DEFAULT 1,
    min_seq_scans INT DEFAULT 10
);

-- Insert config values (use defaults if not provided via -v)
INSERT INTO test_config
SELECT
    COALESCE(NULLIF(:'MAX_TABLES', ''), '20')::INT,
    COALESCE(NULLIF(:'MIN_SIZE_MB', ''), '1')::INT,
    COALESCE(NULLIF(:'MIN_SEQ_SCANS', ''), '10')::INT;

-- Generate and execute tests for top N largest tables
DO $$
DECLARE
    r RECORD;
    col_rec RECORD;
    test_count INT := 0;
    max_tables INT;
    min_size_mb INT;
    min_seq_scans INT;
    result RECORD;
BEGIN
    -- Get configuration from temp table
    SELECT t.max_tables, t.min_size_mb, t.min_seq_scans
    INTO max_tables, min_size_mb, min_seq_scans
    FROM test_config t;

    RAISE NOTICE '';
    RAISE NOTICE '=========================================';
    RAISE NOTICE 'Testing Top % Largest Tables', max_tables;
    RAISE NOTICE '=========================================';
    RAISE NOTICE '';

    -- Iterate through top N largest tables
    FOR r IN
        SELECT
            s.relname AS table_name,
            pg_size_pretty(pg_total_relation_size(s.relid)) AS size,
            s.n_live_tup AS row_count,
            s.seq_scan
        FROM pg_stat_user_tables s
        WHERE pg_total_relation_size(s.relid) > (min_size_mb * 1024 * 1024)
          AND s.seq_scan > min_seq_scans
          AND s.n_live_tup > 100
        ORDER BY pg_total_relation_size(s.relid) DESC
        LIMIT max_tables
    LOOP
        test_count := test_count + 1;

        RAISE NOTICE '';
        RAISE NOTICE '=========================================';
        RAISE NOTICE 'Test %/%: % (%, % rows, % seq scans)',
            test_count, max_tables, r.table_name, r.size, r.row_count, r.seq_scan;
        RAISE NOTICE '=========================================';

        -- Find the best column to index (first non-PK column with data)
        FOR col_rec IN
            SELECT column_name
            FROM information_schema.columns
            WHERE table_schema = 'public'
              AND table_name = r.table_name
              AND column_name NOT IN (
                  SELECT a.attname
                  FROM pg_index i
                  JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
                  WHERE i.indrelid = r.table_name::regclass
                    AND i.indisprimary
              )
            ORDER BY ordinal_position
            LIMIT 3  -- Try up to 3 columns per table
        LOOP
            BEGIN
                -- Test this column
                SELECT * INTO result
                FROM test_large_table_index(
                    r.table_name,
                    col_rec.column_name,
                    'idx_test_large_' || r.table_name || '_' || col_rec.column_name
                );

                -- If we got a result, we tested successfully
                IF FOUND THEN
                    EXIT;  -- Move to next table after first successful test
                END IF;

            EXCEPTION WHEN OTHERS THEN
                RAISE NOTICE 'Error testing %.%: %', r.table_name, col_rec.column_name, SQLERRM;
            END;
        END LOOP;

    END LOOP;

    RAISE NOTICE '';
    RAISE NOTICE 'Completed testing % tables', test_count;
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
    ROUND(AVG(improvement_percent) FILTER (WHERE decision = 'KEEP'), 2) AS avg_improvement_pct,
    ROUND(MAX(improvement_percent) FILTER (WHERE decision = 'KEEP'), 2) AS max_improvement_pct
FROM pg_index_test_log
WHERE test_phase = 'decision'
  AND index_name LIKE 'idx_test_large_%';

\echo ''
\echo '--- KEPT INDEXES (>= 5% improvement) ---'
SELECT
    table_name,
    index_name,
    notes AS column_indexed,
    ROUND(improvement_percent, 2) AS improvement_pct
FROM pg_index_test_log
WHERE decision = 'KEEP'
  AND index_name LIKE 'idx_test_large_%'
ORDER BY improvement_percent DESC;

\echo ''
\echo '--- ROLLED BACK (<5% improvement) ---'
SELECT
    table_name,
    index_name,
    notes AS column_indexed,
    ROUND(improvement_percent, 2) AS improvement_pct
FROM pg_index_test_log
WHERE decision = 'ROLLBACK'
  AND index_name LIKE 'idx_test_large_%'
ORDER BY improvement_percent DESC;

\echo ''
\echo 'Results saved in pg_index_test_log table'
\echo ''
