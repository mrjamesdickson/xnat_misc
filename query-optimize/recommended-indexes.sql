-- Recommended Indexes for XNAT Workflow Query Optimization
-- Purpose: Improve performance of workflow data retrieval queries

-- ============================================================================
-- PRIMARY INDEXES - Most Important for Query Performance
-- ============================================================================

-- 1. Index on wrk_workflowdata.id (primary key lookup)
-- Used in: WHERE w.id = $1 OR w.id IN (...)
CREATE INDEX IF NOT EXISTS idx_wrk_workflowdata_id
ON wrk_workflowdata(id);

-- 2. Composite index for image assessor lookups
-- Used in: JOIN from workflow data to image assessor data
CREATE INDEX IF NOT EXISTS idx_xnat_imageassessordata_imagesession
ON xnat_imageassessordata(imagesession_id, id)
WHERE id IS NOT NULL;

-- 3. Composite index for image assessor history lookups
-- Used in: UNION query for historical assessor data
CREATE INDEX IF NOT EXISTS idx_xnat_imageassessordata_history_imagesession
ON xnat_imageassessordata_history(imagesession_id, id)
WHERE id IS NOT NULL;

-- ============================================================================
-- SECONDARY INDEXES - JOIN Optimization
-- ============================================================================

-- 4. Index for experiment data joins
-- Used in: INNER JOIN xnat_experimentdata e ON w.id = e.id
CREATE INDEX IF NOT EXISTS idx_xnat_experimentdata_id
ON xnat_experimentdata(id);

-- 5. Index for experiment share lookups
-- Used in: LEFT JOIN xnat_experimentdata_share s ON e.id = s.sharing_share_xnat_experimentda_id
CREATE INDEX IF NOT EXISTS idx_xnat_experimentdata_share_experiment
ON xnat_experimentdata_share(sharing_share_xnat_experimentda_id);

-- 6. Index for workflow metadata joins
-- Used in: LEFT JOIN wrk_workflowdata_meta_data m ON w.workflowdata_info = m.meta_data_id
CREATE INDEX IF NOT EXISTS idx_wrk_workflowdata_meta_data_id
ON wrk_workflowdata_meta_data(meta_data_id);

-- 7. Index for user lookups
-- Used in: LEFT JOIN xdat_user u ON m.insert_user_xdat_user_id = u.xdat_user_id
CREATE INDEX IF NOT EXISTS idx_xdat_user_id
ON xdat_user(xdat_user_id);

-- ============================================================================
-- COVERING INDEXES - Reduce Table Scans
-- ============================================================================

-- 8. Covering index for workflow data common queries
-- Includes most frequently accessed columns to avoid table lookups
CREATE INDEX IF NOT EXISTS idx_wrk_workflowdata_covering
ON wrk_workflowdata(
    id,
    wrk_workflowdata_id,
    status,
    launch_time,
    last_modified
) INCLUDE (
    externalid,
    pipeline_name,
    data_type,
    step_description,
    percentagecomplete
);

-- ============================================================================
-- ORDERING INDEX - Improve Sort Performance
-- ============================================================================

-- 9. Index for ORDER BY clause
-- Used in: ORDER BY q.wrk_workflowdata_id DESC
CREATE INDEX IF NOT EXISTS idx_wrk_workflowdata_id_desc
ON wrk_workflowdata(wrk_workflowdata_id DESC);

-- ============================================================================
-- STATISTICS UPDATE
-- ============================================================================

-- Update table statistics for query planner
ANALYZE wrk_workflowdata;
ANALYZE xnat_imageassessordata;
ANALYZE xnat_imageassessordata_history;
ANALYZE xnat_experimentdata;
ANALYZE xnat_experimentdata_share;
ANALYZE wrk_workflowdata_meta_data;
ANALYZE xdat_user;

-- ============================================================================
-- INDEX USAGE VERIFICATION
-- ============================================================================

-- Query to check if indexes are being used
-- Run this after creating indexes:
/*
EXPLAIN (ANALYZE, BUFFERS)
SELECT ... [your full query here] ...;
*/

-- Check index sizes
SELECT
    schemaname,
    tablename,
    indexname,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_indexes
LEFT JOIN pg_class ON indexname = relname
WHERE schemaname = 'public'
  AND tablename IN (
      'wrk_workflowdata',
      'xnat_imageassessordata',
      'xnat_imageassessordata_history',
      'xnat_experimentdata',
      'xnat_experimentdata_share',
      'wrk_workflowdata_meta_data',
      'xdat_user'
  )
ORDER BY tablename, indexname;

-- ============================================================================
-- EXPECTED PERFORMANCE IMPROVEMENTS
-- ============================================================================

/*
Without Indexes:
- Full table scans on wrk_workflowdata
- Sequential scans on image assessor tables
- Nested loop joins on every query
- Estimated query time: 500ms - 2000ms for large datasets

With Indexes:
- Index seeks instead of table scans
- Efficient bitmap index scans for UNION operations
- Hash joins instead of nested loops
- Estimated query time: 50ms - 200ms for large datasets

Expected Improvement: 5-10x faster query execution
*/

-- ============================================================================
-- MAINTENANCE NOTES
-- ============================================================================

/*
1. Indexes will automatically be maintained by PostgreSQL during INSERT/UPDATE/DELETE
2. Consider REINDEX if index bloat becomes an issue over time
3. Monitor index usage with pg_stat_user_indexes view
4. Drop unused indexes to save disk space and write performance

To check index usage:
SELECT
    schemaname,
    tablename,
    indexname,
    idx_scan,
    idx_tup_read,
    idx_tup_fetch
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
ORDER BY idx_scan DESC;
*/
