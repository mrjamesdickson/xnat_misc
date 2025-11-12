-- Test Schema-Based Index Recommendations
-- Tests most critical indexes identified from schema analysis
-- Duration: ~10-20 minutes

\timing on

\echo ''
\echo '========================================='
\echo 'Testing Schema-Based Index Recommendations'
\echo '========================================='
\echo ''
\echo 'This will test 15 high-priority indexes based on schema analysis'
\echo ''

-- Truncate existing log
TRUNCATE TABLE pg_index_test_log;

-- Reuse test function
CREATE OR REPLACE FUNCTION test_schema_index(
    p_table_name TEXT,
    p_columns TEXT,
    p_index_name TEXT,
    p_test_query TEXT,
    p_where_clause TEXT DEFAULT NULL
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
    v_index_def TEXT;
    i INT;
BEGIN
    -- Build index definition
    v_index_def := 'CREATE INDEX ' || p_index_name || ' ON ' || p_table_name || '(' || p_columns || ')';
    IF p_where_clause IS NOT NULL THEN
        v_index_def := v_index_def || ' WHERE ' || p_where_clause;
    END IF;

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
    EXECUTE v_index_def;
    EXECUTE 'ANALYZE ' || p_table_name;

    RAISE NOTICE 'Index created: %', p_index_name;

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
    VALUES
        (p_table_name, p_index_name, 'baseline', v_baseline_ms, NULL, NULL, 'Columns: ' || p_columns),
        (p_table_name, p_index_name, 'with_index', v_with_index_ms, NULL, NULL, 'Columns: ' || p_columns),
        (p_table_name, p_index_name, 'decision', v_with_index_ms, v_decision, v_improvement, 'Schema-based index');

    RETURN QUERY SELECT v_decision, v_baseline_ms, v_with_index_ms, v_improvement;
END;
$$ LANGUAGE plpgsql;

\echo 'Test function created'
\echo ''

-- ============================================================================
-- TEST 1: xdat_change_info - Date-based audit queries
-- ============================================================================

\echo ''
\echo '========================================='
\echo 'Test 1: xdat_change_info - change_date'
\echo '========================================='
\echo 'Audit logs queried by date range'
\echo ''

DO $$
DECLARE
    result RECORD;
BEGIN
    SELECT * INTO result FROM test_schema_index(
        'xdat_change_info',
        'change_date DESC',
        'idx_test_change_info_date',
        'SELECT * FROM xdat_change_info WHERE change_date > NOW() - INTERVAL ''30 days'' ORDER BY change_date DESC LIMIT 100',
        NULL
    );
END $$;

-- ============================================================================
-- TEST 2: xhbm_container_entity_log_paths - CRITICAL (no indexes!)
-- ============================================================================

\echo ''
\echo '========================================='
\echo 'Test 2: xhbm_container_entity_log_paths'
\echo '========================================='
\echo '⚠️ CRITICAL: This table has NO indexes!'
\echo ''

DO $$
DECLARE
    result RECORD;
    sample_container BIGINT;
BEGIN
    SELECT container_entity INTO sample_container
    FROM xhbm_container_entity_log_paths
    LIMIT 1;

    IF sample_container IS NOT NULL THEN
        SELECT * INTO result FROM test_schema_index(
            'xhbm_container_entity_log_paths',
            'container_entity',
            'idx_test_log_paths_container',
            FORMAT('SELECT * FROM xhbm_container_entity_log_paths WHERE container_entity = %s', sample_container),
            NULL
        );
    END IF;
END $$;

-- ============================================================================
-- TEST 3: xhbm_dicom_spatial_data - Frame lookup
-- ============================================================================

\echo ''
\echo '========================================='
\echo 'Test 3: xhbm_dicom_spatial_data - frame_number'
\echo '========================================='
\echo 'DICOM viewer frame navigation'
\echo ''

DO $$
DECLARE
    result RECORD;
BEGIN
    SELECT * INTO result FROM test_schema_index(
        'xhbm_dicom_spatial_data',
        'frame_number',
        'idx_test_dicom_frame',
        'SELECT * FROM xhbm_dicom_spatial_data WHERE frame_number BETWEEN 1 AND 100 AND NOT disabled',
        'NOT disabled'
    );
END $$;

-- ============================================================================
-- TEST 4: xhbm_dicom_spatial_data - Series UID
-- ============================================================================

\echo ''
\echo '========================================='
\echo 'Test 4: xhbm_dicom_spatial_data - series_uid'
\echo '========================================='
\echo 'DICOM series retrieval'
\echo ''

DO $$
DECLARE
    result RECORD;
    sample_series TEXT;
BEGIN
    SELECT series_uid INTO sample_series
    FROM xhbm_dicom_spatial_data
    WHERE series_uid IS NOT NULL
    LIMIT 1;

    IF sample_series IS NOT NULL THEN
        SELECT * INTO result FROM test_schema_index(
            'xhbm_dicom_spatial_data',
            'series_uid, frame_number',
            'idx_test_dicom_series',
            FORMAT('SELECT * FROM xhbm_dicom_spatial_data WHERE series_uid = %L ORDER BY frame_number', sample_series),
            NULL
        );
    END IF;
END $$;

-- ============================================================================
-- TEST 5: xhbm_container_entity - Status monitoring
-- ============================================================================

\echo ''
\echo '========================================='
\echo 'Test 5: xhbm_container_entity - status, status_time'
\echo '========================================='
\echo 'Container status monitoring'
\echo ''

DO $$
DECLARE
    result RECORD;
BEGIN
    SELECT * INTO result FROM test_schema_index(
        'xhbm_container_entity',
        'status, status_time DESC',
        'idx_test_container_status',
        'SELECT * FROM xhbm_container_entity WHERE status IN (''Running'', ''Failed'') AND NOT disabled ORDER BY status_time DESC LIMIT 50',
        'NOT disabled'
    );
END $$;

-- ============================================================================
-- TEST 6: xhbm_container_entity - Project queries
-- ============================================================================

\echo ''
\echo '========================================='
\echo 'Test 6: xhbm_container_entity - project, created'
\echo '========================================='
\echo 'Project-based container queries'
\echo ''

DO $$
DECLARE
    result RECORD;
    sample_project TEXT;
BEGIN
    SELECT project INTO sample_project
    FROM xhbm_container_entity
    WHERE project IS NOT NULL
    LIMIT 1;

    IF sample_project IS NOT NULL THEN
        SELECT * INTO result FROM test_schema_index(
            'xhbm_container_entity',
            'project, created DESC',
            'idx_test_container_project',
            FORMAT('SELECT * FROM xhbm_container_entity WHERE project = %L AND NOT disabled ORDER BY created DESC LIMIT 50', sample_project),
            'NOT disabled'
        );
    END IF;
END $$;

-- ============================================================================
-- TEST 7: xdat_user_login - Active sessions
-- ============================================================================

\echo ''
\echo '========================================='
\echo 'Test 7: xdat_user_login - active sessions'
\echo '========================================='
\echo 'Active session monitoring'
\echo ''

DO $$
DECLARE
    result RECORD;
BEGIN
    SELECT * INTO result FROM test_schema_index(
        'xdat_user_login',
        'user_xdat_user_id, login_date DESC',
        'idx_test_user_login_active',
        'SELECT * FROM xdat_user_login WHERE logout_date IS NULL ORDER BY login_date DESC LIMIT 100',
        'logout_date IS NULL'
    );
END $$;

-- ============================================================================
-- TEST 8: xnat_resource - Format queries
-- ============================================================================

\echo ''
\echo '========================================='
\echo 'Test 8: xnat_resource - format'
\echo '========================================='
\echo 'Resource format filtering'
\echo ''

DO $$
DECLARE
    result RECORD;
BEGIN
    SELECT * INTO result FROM test_schema_index(
        'xnat_resource',
        'format',
        'idx_test_resource_format',
        'SELECT * FROM xnat_resource WHERE format = ''DICOM'' LIMIT 100',
        NULL
    );
END $$;

-- ============================================================================
-- TEST 9: xnat_imagescandata - Modality queries
-- ============================================================================

\echo ''
\echo '========================================='
\echo 'Test 9: xnat_imagescandata - modality'
\echo '========================================='
\echo 'Scan modality filtering'
\echo ''

DO $$
DECLARE
    result RECORD;
BEGIN
    SELECT * INTO result FROM test_schema_index(
        'xnat_imagescandata',
        'modality',
        'idx_test_imagescan_modality',
        'SELECT * FROM xnat_imagescandata WHERE modality = ''MR'' LIMIT 100',
        NULL
    );
END $$;

-- ============================================================================
-- TEST 10: xnat_imagescandata - UID lookup
-- ============================================================================

\echo ''
\echo '========================================='
\echo 'Test 10: xnat_imagescandata - uid'
\echo '========================================='
\echo 'DICOM UID lookup'
\echo ''

DO $$
DECLARE
    result RECORD;
    sample_uid TEXT;
BEGIN
    SELECT uid INTO sample_uid
    FROM xnat_imagescandata
    WHERE uid IS NOT NULL
    LIMIT 1;

    IF sample_uid IS NOT NULL THEN
        SELECT * INTO result FROM test_schema_index(
            'xnat_imagescandata',
            'uid',
            'idx_test_imagescan_uid',
            FORMAT('SELECT * FROM xnat_imagescandata WHERE uid = %L', sample_uid),
            NULL
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
