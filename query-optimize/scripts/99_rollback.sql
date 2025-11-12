-- Rollback Script - Remove All Optimization Indexes
-- This script safely removes all indexes created by the optimization
--
-- Usage:
--   psql -U xnat -d xnat -f scripts/99_rollback.sql
--
-- When to use:
--   - If indexes are causing issues
--   - If disk space is needed
--   - If rolling back to original state
--
-- Safe to run: Yes - only drops indexes we created, not system indexes

\timing on

\echo ''
\echo '========================================='
\echo 'XNAT Workflow Query Optimization - ROLLBACK'
\echo '========================================='
\echo ''
\echo 'WARNING: This will remove all optimization indexes.'
\echo 'Your query performance will return to original speed.'
\echo ''
\echo 'Press Ctrl+C to cancel within 5 seconds...'
\echo ''

-- Give user time to cancel
SELECT pg_sleep(5);

\echo ''
\echo 'Proceeding with rollback...'
\echo ''

-- ============================================================================
-- Drop Image Assessor Indexes
-- ============================================================================

\echo 'Removing image assessor indexes...'

DROP INDEX IF EXISTS idx_xnat_imageassessordata_imagesession;
DROP INDEX IF EXISTS idx_xnat_imageassessordata_history_imagesession;

-- ============================================================================
-- Drop Experiment Data Indexes
-- ============================================================================

\echo 'Removing experiment data indexes...'

DROP INDEX IF EXISTS idx_xnat_experimentdata_id;
DROP INDEX IF EXISTS idx_xnat_experimentdata_share_experiment;

-- ============================================================================
-- Drop Metadata and User Indexes
-- ============================================================================

\echo 'Removing metadata and user indexes...'

DROP INDEX IF EXISTS idx_wrk_workflowdata_meta_data_id;
DROP INDEX IF EXISTS idx_xdat_user_id;

-- ============================================================================
-- Drop Covering Index (if exists)
-- ============================================================================

\echo 'Removing covering index...'

DROP INDEX IF EXISTS idx_wrk_workflowdata_covering;

-- ============================================================================
-- Verification
-- ============================================================================

\echo ''
\echo 'Verifying removal...'
\echo ''

-- Check if any optimization indexes remain
SELECT COUNT(*) AS "Remaining Optimization Indexes"
FROM pg_indexes
WHERE schemaname = 'public'
  AND indexname LIKE 'idx_%'
  AND tablename IN (
      'xnat_imageassessordata',
      'xnat_imageassessordata_history',
      'xnat_experimentdata',
      'xnat_experimentdata_share',
      'wrk_workflowdata_meta_data',
      'xdat_user',
      'wrk_workflowdata'
  );

-- Show current database size
SELECT pg_size_pretty(pg_database_size(current_database())) AS "Database Size After Rollback";

-- ============================================================================
-- Update Statistics
-- ============================================================================

\echo ''
\echo 'Updating statistics after index removal...'
\echo ''

ANALYZE wrk_workflowdata;
ANALYZE xnat_imageassessordata;
ANALYZE xnat_imageassessordata_history;
ANALYZE xnat_experimentdata;
ANALYZE xnat_experimentdata_share;
ANALYZE wrk_workflowdata_meta_data;
ANALYZE xdat_user;

-- ============================================================================
-- Completion
-- ============================================================================

\echo ''
\echo '========================================='
\echo 'ROLLBACK COMPLETE'
\echo '========================================='
\echo ''
\echo 'Summary:'
\echo '- All optimization indexes removed'
\echo '- Database statistics updated'
\echo '- System returned to original state'
\echo ''
\echo 'Note:'
\echo '- Query performance is now back to original speed'
\echo '- To re-apply optimizations, run:'
\echo '  psql -U xnat -d xnat -f scripts/00_run_all_optimizations.sql'
\echo ''
\echo '========================================='
\echo ''
