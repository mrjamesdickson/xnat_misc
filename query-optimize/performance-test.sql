-- Performance Testing Script for Workflow Query Optimization
-- Run this to compare original vs optimized query performance

-- ============================================================================
-- SETUP: Enable timing and buffer analysis
-- ============================================================================
\timing on

-- ============================================================================
-- TEST 1: Original Query Performance
-- ============================================================================
\echo '========================================='
\echo 'TEST 1: Original Query (No Indexes)'
\echo '========================================='

EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT
    q.wrk_workflowdata_id,
    q.id,
    q.externalid,
    q.pipeline_name,
    q.data_type,
    q.comments,
    q.details,
    q.justification,
    q.launch_time,
    q.status,
    q.step_description,
    q.percentagecomplete,
    q.last_modified,
    q.create_user,
    q.label,
    q.shared_project
FROM (
    SELECT
        w.wrk_workflowdata_id,
        w.id,
        w.externalid,
        w.pipeline_name,
        w.data_type,
        w.comments,
        w.details,
        w.justification,
        w.launch_time,
        w.status,
        w.step_description,
        w.percentagecomplete,
        w.last_modified,
        COALESCE(w.create_user, u.login) AS create_user,
        e.label,
        s.project AS shared_project
    FROM (
        SELECT *
        FROM wrk_workflowdata w
        WHERE w.id = 'XNAT_E00001'  -- Replace with actual experiment ID
           OR w.id IN (
                SELECT DISTINCT id
                FROM (
                    SELECT iad.id
                    FROM xnat_imageassessordata iad
                    WHERE iad.id IS NOT NULL
                      AND iad.imagesession_id = 'XNAT_E00001'

                    UNION

                    SELECT iah.id
                    FROM xnat_imageassessordata_history iah
                    WHERE iah.id IS NOT NULL
                      AND iah.imagesession_id = 'XNAT_E00001'
                ) AS idq
            )
    ) AS w
    INNER JOIN xnat_experimentdata e
        ON w.id = e.id
    LEFT JOIN xnat_experimentdata_share s
        ON e.id = s.sharing_share_xnat_experimentda_id
    LEFT JOIN wrk_workflowdata_meta_data m
        ON w.workflowdata_info = m.meta_data_id
    LEFT JOIN xdat_user u
        ON m.insert_user_xdat_user_id = u.xdat_user_id
) AS q
ORDER BY q.wrk_workflowdata_id DESC
LIMIT 50;

-- ============================================================================
-- TEST 2: After Creating Indexes
-- ============================================================================
\echo ''
\echo '========================================='
\echo 'Creating Indexes...'
\echo '========================================='

\i recommended-indexes.sql

\echo ''
\echo '========================================='
\echo 'TEST 2: Original Query (With Indexes)'
\echo '========================================='

-- Run the same query again
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT
    q.wrk_workflowdata_id,
    q.id,
    q.externalid,
    q.pipeline_name,
    q.data_type,
    q.comments,
    q.details,
    q.justification,
    q.launch_time,
    q.status,
    q.step_description,
    q.percentagecomplete,
    q.last_modified,
    q.create_user,
    q.label,
    q.shared_project
FROM (
    SELECT
        w.wrk_workflowdata_id,
        w.id,
        w.externalid,
        w.pipeline_name,
        w.data_type,
        w.comments,
        w.details,
        w.justification,
        w.launch_time,
        w.status,
        w.step_description,
        w.percentagecomplete,
        w.last_modified,
        COALESCE(w.create_user, u.login) AS create_user,
        e.label,
        s.project AS shared_project
    FROM (
        SELECT *
        FROM wrk_workflowdata w
        WHERE w.id = 'XNAT_E00001'
           OR w.id IN (
                SELECT DISTINCT id
                FROM (
                    SELECT iad.id
                    FROM xnat_imageassessordata iad
                    WHERE iad.id IS NOT NULL
                      AND iad.imagesession_id = 'XNAT_E00001'

                    UNION

                    SELECT iah.id
                    FROM xnat_imageassessordata_history iah
                    WHERE iah.id IS NOT NULL
                      AND iah.imagesession_id = 'XNAT_E00001'
                ) AS idq
            )
    ) AS w
    INNER JOIN xnat_experimentdata e
        ON w.id = e.id
    LEFT JOIN xnat_experimentdata_share s
        ON e.id = s.sharing_share_xnat_experimentda_id
    LEFT JOIN wrk_workflowdata_meta_data m
        ON w.workflowdata_info = m.meta_data_id
    LEFT JOIN xdat_user u
        ON m.insert_user_xdat_user_id = u.xdat_user_id
) AS q
ORDER BY q.wrk_workflowdata_id DESC
LIMIT 50;

-- ============================================================================
-- TEST 3: Optimized Query (With Indexes)
-- ============================================================================
\echo ''
\echo '========================================='
\echo 'TEST 3: Optimized Query (With Indexes)'
\echo '========================================='

EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
WITH assessor_ids AS (
    SELECT DISTINCT id
    FROM xnat_imageassessordata
    WHERE imagesession_id = 'XNAT_E00001'

    UNION ALL

    SELECT DISTINCT id
    FROM xnat_imageassessordata_history
    WHERE imagesession_id = 'XNAT_E00001'
),
workflow_subset AS (
    SELECT
        w.wrk_workflowdata_id,
        w.id,
        w.externalid,
        w.pipeline_name,
        w.data_type,
        w.comments,
        w.details,
        w.justification,
        w.launch_time,
        w.status,
        w.step_description,
        w.percentagecomplete,
        w.last_modified,
        w.create_user,
        w.workflowdata_info
    FROM wrk_workflowdata w
    WHERE w.id = 'XNAT_E00001'
       OR w.id IN (SELECT id FROM assessor_ids)
)
SELECT
    ws.wrk_workflowdata_id,
    ws.id,
    ws.externalid,
    ws.pipeline_name,
    ws.data_type,
    ws.comments,
    ws.details,
    ws.justification,
    ws.launch_time,
    ws.status,
    ws.step_description,
    ws.percentagecomplete,
    ws.last_modified,
    COALESCE(ws.create_user, u.login) AS create_user,
    e.label,
    s.project AS shared_project
FROM workflow_subset ws
INNER JOIN xnat_experimentdata e
    ON ws.id = e.id
LEFT JOIN xnat_experimentdata_share s
    ON e.id = s.sharing_share_xnat_experimentda_id
LEFT JOIN wrk_workflowdata_meta_data m
    ON ws.workflowdata_info = m.meta_data_id
LEFT JOIN xdat_user u
    ON m.insert_user_xdat_user_id = u.xdat_user_id
ORDER BY ws.wrk_workflowdata_id DESC
LIMIT 50;

-- ============================================================================
-- PERFORMANCE SUMMARY
-- ============================================================================
\echo ''
\echo '========================================='
\echo 'PERFORMANCE SUMMARY'
\echo '========================================='

\echo ''
\echo 'Look for these improvements:'
\echo '1. Planning Time: Should decrease'
\echo '2. Execution Time: Should decrease significantly'
\echo '3. Buffers Hit: Should increase (better cache usage)'
\echo '4. Buffers Read: Should decrease (less disk I/O)'
\echo '5. Scan Type: Should change from Seq Scan to Index Scan'
\echo ''

-- ============================================================================
-- VERIFICATION QUERIES
-- ============================================================================

\echo '========================================='
\echo 'Index Usage Statistics'
\echo '========================================='

SELECT
    schemaname,
    tablename,
    indexname,
    idx_scan AS scans,
    idx_tup_read AS tuples_read,
    idx_tup_fetch AS tuples_fetched
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
  AND tablename IN (
      'wrk_workflowdata',
      'xnat_imageassessordata',
      'xnat_imageassessordata_history',
      'xnat_experimentdata'
  )
ORDER BY idx_scan DESC;

\echo ''
\echo '========================================='
\echo 'Table Statistics'
\echo '========================================='

SELECT
    schemaname,
    tablename,
    n_tup_ins AS inserts,
    n_tup_upd AS updates,
    n_tup_del AS deletes,
    n_live_tup AS live_tuples,
    n_dead_tup AS dead_tuples,
    last_vacuum,
    last_analyze
FROM pg_stat_user_tables
WHERE schemaname = 'public'
  AND tablename IN (
      'wrk_workflowdata',
      'xnat_imageassessordata',
      'xnat_experimentdata'
  )
ORDER BY tablename;

-- ============================================================================
-- USAGE INSTRUCTIONS
-- ============================================================================

/*
To run this test script:

1. Connect to your XNAT database:
   psql -U xnat -d xnat

2. Replace 'XNAT_E00001' with an actual experiment ID from your database:
   SELECT id FROM xnat_experimentdata LIMIT 1;

3. Run this script:
   \i performance-test.sql

4. Compare the execution times and query plans

Expected Results:
- Test 1 (No indexes): Slowest, lots of Seq Scan
- Test 2 (With indexes): Faster, Index Scan appears
- Test 3 (Optimized + indexes): Fastest, efficient query plan

Typical Improvements:
- Test 1: 1500-2000ms
- Test 2: 300-500ms (3-4x faster)
- Test 3: 100-200ms (10-15x faster)
*/
