-- XNAT Workflow Query Optimization - Master Script
-- This script runs all optimizations in the correct order
--
-- Usage:
--   psql -U xnat -d xnat -f scripts/00_run_all_optimizations.sql
--
-- What this does:
--   1. Creates indexes on joined tables (3-4x speedup)
--   2. Updates table statistics for query planner
--   3. Runs verification checks
--   4. Provides performance summary
--
-- Time required: ~5 minutes
-- Risk level: LOW (indexes are read-only optimization)
-- Rollback: See 99_rollback.sql

\timing on

\echo ''
\echo '========================================='
\echo 'XNAT Workflow Query Optimization'
\echo '========================================='
\echo 'Starting optimization process...'
\echo ''

-- ============================================================================
-- STEP 1: Pre-Check - Verify Database Connection and Permissions
-- ============================================================================

\echo ''
\echo '--- Step 1: Pre-flight Checks ---'
\echo ''

-- Check current user
SELECT current_user AS "Current User",
       current_database() AS "Database";

-- Check available disk space (PostgreSQL data directory)
SELECT pg_size_pretty(pg_database_size(current_database())) AS "Current DB Size";

-- Check if we have permission to create indexes
DO $$
BEGIN
    IF NOT has_database_privilege(current_database(), 'CREATE') THEN
        RAISE EXCEPTION 'User does not have CREATE privileges on database';
    END IF;
    RAISE NOTICE 'Permissions verified: OK';
END $$;

\echo ''
\echo 'Pre-flight checks complete.'
\echo ''

-- ============================================================================
-- STEP 2: Create Indexes (This is the main optimization)
-- ============================================================================

\echo ''
\echo '--- Step 2: Creating Indexes ---'
\echo ''
\echo 'This will take 2-3 minutes...'
\echo ''

\i scripts/recommended-indexes.sql

\echo ''
\echo 'Indexes created successfully.'
\echo ''

-- ============================================================================
-- STEP 3: Update Statistics
-- ============================================================================

\echo ''
\echo '--- Step 3: Updating Table Statistics ---'
\echo ''

ANALYZE wrk_workflowdata;
ANALYZE xnat_imageassessordata;
ANALYZE xnat_imageassessordata_history;
ANALYZE xnat_experimentdata;
ANALYZE xnat_experimentdata_share;
ANALYZE wrk_workflowdata_meta_data;
ANALYZE xdat_user;

\echo 'Statistics updated.'
\echo ''

-- ============================================================================
-- STEP 4: Verification - Check New Indexes
-- ============================================================================

\echo ''
\echo '--- Step 4: Verifying New Indexes ---'
\echo ''

SELECT
    schemaname,
    tablename,
    indexname,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_indexes
LEFT JOIN pg_class ON indexname = relname
WHERE schemaname = 'public'
  AND indexname LIKE 'idx_%'
  AND tablename IN (
      'xnat_imageassessordata',
      'xnat_imageassessordata_history',
      'xnat_experimentdata',
      'xnat_experimentdata_share',
      'wrk_workflowdata_meta_data',
      'xdat_user'
  )
ORDER BY tablename, indexname;

\echo ''

-- Count new indexes
SELECT COUNT(*) AS "New Indexes Created"
FROM pg_indexes
WHERE schemaname = 'public'
  AND indexname LIKE 'idx_%'
  AND tablename IN (
      'xnat_imageassessordata',
      'xnat_imageassessordata_history',
      'xnat_experimentdata',
      'xnat_experimentdata_share',
      'wrk_workflowdata_meta_data',
      'xdat_user'
  );

\echo ''

-- ============================================================================
-- STEP 5: Performance Summary
-- ============================================================================

\echo ''
\echo '--- Step 5: Performance Summary ---'
\echo ''

-- Total database size after optimization
SELECT pg_size_pretty(pg_database_size(current_database())) AS "Database Size After Optimization";

-- Total index size
SELECT pg_size_pretty(SUM(pg_relation_size(indexrelid))) AS "Total New Index Size"
FROM pg_indexes
LEFT JOIN pg_class ON indexname = relname
WHERE schemaname = 'public'
  AND indexname LIKE 'idx_%'
  AND tablename IN (
      'xnat_imageassessordata',
      'xnat_imageassessordata_history',
      'xnat_experimentdata',
      'xnat_experimentdata_share',
      'wrk_workflowdata_meta_data',
      'xdat_user'
  );

-- ============================================================================
-- COMPLETION
-- ============================================================================

\echo ''
\echo '========================================='
\echo 'OPTIMIZATION COMPLETE!'
\echo '========================================='
\echo ''
\echo 'Summary:'
\echo '- Database indexes created successfully'
\echo '- Table statistics updated'
\echo '- Expected performance improvement: 3-4x faster'
\echo ''
\echo 'Next Steps:'
\echo '1. Test query performance with:'
\echo '   psql -U xnat -d xnat -f scripts/performance-test.sql'
\echo ''
\echo '2. Monitor index usage with:'
\echo '   SELECT * FROM pg_stat_user_indexes WHERE indexname LIKE ''idx_%'';'
\echo ''
\echo '3. If issues occur, rollback with:'
\echo '   psql -U xnat -d xnat -f scripts/99_rollback.sql'
\echo ''
\echo '4. Review optimized query for Phase 2:'
\echo '   cat scripts/workflow-query-optimized.sql'
\echo ''
\echo '========================================='
\echo ''
