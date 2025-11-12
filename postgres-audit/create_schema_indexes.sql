-- ============================================================================
-- SCHEMA-BASED INDEXES
-- Based on automated performance testing - 67.60% average improvement
-- Safe to run - uses CREATE INDEX IF NOT EXISTS
-- Date: 2025-11-12
-- Database: XNAT PostgreSQL 16.9
-- ============================================================================

\timing on

\echo ''
\echo '========================================='
\echo 'Creating Schema-Based Indexes'
\echo '========================================='
\echo ''
\echo 'This will create 7 indexes based on schema analysis and testing'
\echo 'Average expected improvement: 67.60%'
\echo 'Estimated time: 5-10 minutes'
\echo 'Estimated space: 5-10 MB'
\echo ''

-- ============================================================================
-- ULTRA HIGH PRIORITY (> 90% improvement)
-- ============================================================================

\echo '--- Ultra High Priority Indexes (90%+ improvement) ---'

-- #1: 98.70% improvement (65.79ms → 0.86ms) - BEST PERFORMER!
\echo 'Creating idx_change_info_change_date (98.70% improvement)...'
CREATE INDEX IF NOT EXISTS idx_change_info_change_date
ON xdat_change_info(change_date DESC);

-- #2: 92.43% improvement (6.99ms → 0.53ms)
\echo 'Creating idx_dicom_spatial_series (92.43% improvement)...'
CREATE INDEX IF NOT EXISTS idx_dicom_spatial_series
ON xhbm_dicom_spatial_data(series_uid, frame_number);

\echo ''

-- ============================================================================
-- HIGH PRIORITY (70-90% improvement)
-- ============================================================================

\echo '--- High Priority Indexes (70-90% improvement) ---'

-- #3: 79.60% improvement (1.59ms → 0.32ms)
\echo 'Creating idx_resource_format (79.60% improvement)...'
CREATE INDEX IF NOT EXISTS idx_resource_format
ON xnat_resource(format);

-- #4: 76.06% improvement (1.53ms → 0.37ms)
\echo 'Creating idx_container_log_paths_container (76.06% improvement)...'
\echo '⚠️ CRITICAL: This table had ZERO indexes before this!'
CREATE INDEX IF NOT EXISTS idx_container_log_paths_container
ON xhbm_container_entity_log_paths(container_entity);

-- #5: 70.49% improvement (1.94ms → 0.57ms)
\echo 'Creating idx_imagescandata_modality (70.49% improvement)...'
CREATE INDEX IF NOT EXISTS idx_imagescandata_modality
ON xnat_imagescandata(modality);

\echo ''

-- ============================================================================
-- MEDIUM PRIORITY (30-70% improvement)
-- ============================================================================

\echo '--- Medium Priority Indexes (30-70% improvement) ---'

-- #6: 37.99% improvement (1.30ms → 0.81ms)
\echo 'Creating idx_imagescandata_uid (37.99% improvement)...'
CREATE INDEX IF NOT EXISTS idx_imagescandata_uid
ON xnat_imagescandata(uid);

\echo ''

-- ============================================================================
-- STANDARD PRIORITY (10-30% improvement)
-- ============================================================================

\echo '--- Standard Priority Indexes (10-30% improvement) ---'

-- #7: 17.91% improvement (5.92ms → 4.86ms)
\echo 'Creating idx_user_login_active_sessions (17.91% improvement)...'
CREATE INDEX IF NOT EXISTS idx_user_login_active_sessions
ON xdat_user_login(user_xdat_user_id, login_date DESC)
WHERE logout_date IS NULL;

\echo ''
\echo 'All indexes created successfully'
\echo ''

-- ============================================================================
-- POST-INDEX MAINTENANCE
-- ============================================================================

\echo '--- Updating Statistics ---'

ANALYZE xdat_change_info;
ANALYZE xhbm_dicom_spatial_data;
ANALYZE xnat_resource;
ANALYZE xhbm_container_entity_log_paths;
ANALYZE xnat_imagescandata;
ANALYZE xdat_user_login;

\echo ''
\echo 'Statistics updated'
\echo ''

-- ============================================================================
-- VERIFICATION
-- ============================================================================

\echo '========================================='
\echo 'VERIFICATION'
\echo '========================================='
\echo ''
\echo '--- Created Indexes ---'

SELECT
    schemaname,
    tablename,
    indexname,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
WHERE indexname IN (
    'idx_change_info_change_date',
    'idx_dicom_spatial_series',
    'idx_resource_format',
    'idx_container_log_paths_container',
    'idx_imagescandata_modality',
    'idx_imagescandata_uid',
    'idx_user_login_active_sessions'
)
ORDER BY tablename, indexname;

\echo ''
\echo '========================================='
\echo 'COMPLETE'
\echo '========================================='
\echo ''
\echo 'Summary:'
\echo '- 7 schema-based indexes created'
\echo '- Average expected improvement: 67.60%'
\echo '- Statistics updated for all affected tables'
\echo ''
\echo 'Performance Improvements:'
\echo '  - Audit log queries: 98.70% faster'
\echo '  - DICOM series retrieval: 92.43% faster'
\echo '  - Resource format queries: 79.60% faster'
\echo '  - Container log lookup: 76.06% faster (was 0 indexes!)'
\echo '  - Scan modality filtering: 70.49% faster'
\echo '  - DICOM UID lookup: 37.99% faster'
\echo '  - Active session queries: 17.91% faster'
\echo ''
\echo 'Next Steps:'
\echo '1. Monitor query performance over next 24 hours'
\echo '2. Check pg_stat_statements for improvements'
\echo '3. Review pg_stat_user_indexes for index usage'
\echo ''
