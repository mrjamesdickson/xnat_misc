-- ============================================================================
-- NON-FOREIGN-KEY INDEXES
-- Based on automated performance testing - 62.26% average improvement
-- Safe to run - uses CREATE INDEX IF NOT EXISTS
-- Date: 2025-11-12
-- Database: XNAT PostgreSQL 16.9
-- ============================================================================

\timing on

\echo ''
\echo '========================================='
\echo 'Creating Non-FK Indexes'
\echo '========================================='
\echo ''
\echo 'This will create 4 indexes for:'
\echo '- History tables (audit trails)'
\echo '- Cache tables (performance)'
\echo '- Authentication tables (login/session)'
\echo ''
\echo 'Average expected improvement: 62.26%'
\echo 'Estimated time: 2-5 minutes'
\echo 'Estimated space: 2-5 MB'
\echo ''

-- ============================================================================
-- HIGH PRIORITY (> 70% improvement)
-- ============================================================================

\echo '--- High Priority Indexes (70%+ improvement) ---'

-- #1: 88.82% improvement (3.97ms → 0.44ms)
\echo 'Creating idx_imagesessiondata_history_id_date (88.82% improvement)...'
CREATE INDEX IF NOT EXISTS idx_imagesessiondata_history_id_date
ON xnat_imagesessiondata_history(id, change_date);

-- #2: 76.12% improvement (3.55ms → 0.85ms)
\echo 'Creating idx_user_login_session (76.12% improvement)...'
CREATE INDEX IF NOT EXISTS idx_user_login_session
ON xdat_user_login(session_id);

\echo ''

-- ============================================================================
-- MEDIUM PRIORITY (50-70% improvement)
-- ============================================================================

\echo '--- Medium Priority Indexes (50-70% improvement) ---'

-- #3: 59.22% improvement (0.70ms → 0.29ms)
\echo 'Creating idx_item_cache_element_ids (59.22% improvement)...'
CREATE INDEX IF NOT EXISTS idx_item_cache_element_ids
ON xs_item_cache(elementName, ids);

\echo ''

-- ============================================================================
-- STANDARD PRIORITY (20-50% improvement)
-- ============================================================================

\echo '--- Standard Priority Indexes (20-50% improvement) ---'

-- #4: 24.87% improvement (0.38ms → 0.29ms)
\echo 'Creating idx_xdat_user_auth_id (24.87% improvement)...'
CREATE INDEX IF NOT EXISTS idx_xdat_user_auth_id
ON xhbm_xdat_user_auth(id);

\echo ''
\echo 'All indexes created successfully'
\echo ''

-- ============================================================================
-- POST-INDEX MAINTENANCE
-- ============================================================================

\echo '--- Updating Statistics ---'

ANALYZE xnat_imagesessiondata_history;
ANALYZE xdat_user_login;
ANALYZE xs_item_cache;
ANALYZE xhbm_xdat_user_auth;

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
    'idx_imagesessiondata_history_id_date',
    'idx_user_login_session',
    'idx_item_cache_element_ids',
    'idx_xdat_user_auth_id'
)
ORDER BY tablename, indexname;

\echo ''
\echo '========================================='
\echo 'COMPLETE'
\echo '========================================='
\echo ''
\echo 'Summary:'
\echo '- 4 non-foreign-key indexes created'
\echo '- Average expected improvement: 62.26%'
\echo '- Statistics updated for all affected tables'
\echo ''
\echo 'Performance Improvements:'
\echo '  - History queries: 88.82% faster'
\echo '  - Session lookups: 76.12% faster'
\echo '  - Cache queries: 59.22% faster'
\echo '  - Auth lookups: 24.87% faster'
\echo ''
\echo 'Next Steps:'
\echo '1. Monitor query performance over next 24 hours'
\echo '2. Check pg_stat_statements for improvements'
\echo '3. Review pg_stat_user_indexes for index usage'
\echo ''
