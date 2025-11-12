-- Generate Optimization Recommendations
-- Purpose: Based on audit results, generate specific SQL commands
-- Usage: psql -h localhost -U postgres -d your_database -f 02_generate_recommendations.sql
-- Output: SQL commands ready to execute

\timing on

\echo ''
\echo '========================================='
\echo 'PostgreSQL Optimization Recommendations'
\echo '========================================='
\echo ''

-- ============================================================================
-- RECOMMENDATION 1: Indexes for Foreign Keys
-- ============================================================================

\echo ''
\echo '--- RECOMMENDATION 1: Create Indexes on Foreign Keys ---'
\echo ''

SELECT
    'CREATE INDEX idx_' ||
    c.conrelid::regclass::text || '_' ||
    a.attname ||
    ' ON ' || c.conrelid::regclass || '(' || a.attname || ');' AS recommended_sql
FROM pg_constraint c
JOIN pg_attribute a ON a.attnum = ANY(c.conkey) AND a.attrelid = c.conrelid
WHERE c.contype = 'f'
  AND NOT EXISTS (
      SELECT 1
      FROM pg_index i
      WHERE i.indrelid = c.conrelid
        AND c.conkey[1] = ANY(i.indkey)
  )
ORDER BY c.conrelid::regclass::text;

-- ============================================================================
-- RECOMMENDATION 2: Drop Unused Indexes
-- ============================================================================

\echo ''
\echo '--- RECOMMENDATION 2: Drop Unused Indexes (REVIEW FIRST!) ---'
\echo ''
\echo 'WARNING: Only drop after confirming these are truly unused'
\echo ''

SELECT
    'DROP INDEX IF EXISTS ' || schemaname || '.' || indexname || ';  -- Size: ' ||
    pg_size_pretty(pg_relation_size(indexrelid)) || ', Scans: ' || idx_scan AS recommended_sql
FROM pg_stat_user_indexes
WHERE idx_scan < 10
  AND indexname NOT LIKE '%_pkey'
  AND pg_relation_size(indexrelid) > 1024 * 1024  -- Larger than 1MB
ORDER BY pg_relation_size(indexrelid) DESC;

-- ============================================================================
-- RECOMMENDATION 3: VACUUM Bloated Tables
-- ============================================================================

\echo ''
\echo '--- RECOMMENDATION 3: VACUUM Bloated Tables ---'
\echo ''

SELECT
    'VACUUM (FULL, ANALYZE) ' || schemaname || '.' || tablename || ';  -- ' ||
    'Dead rows: ' || n_dead_tup || ' (' ||
    ROUND(100.0 * n_dead_tup / NULLIF(n_live_tup, 0), 2) || '%)' AS recommended_sql
FROM pg_stat_user_tables
WHERE n_dead_tup > 1000
  AND CASE
        WHEN n_live_tup > 0
        THEN (100.0 * n_dead_tup / n_live_tup) > 20
        ELSE false
      END
ORDER BY n_dead_tup DESC
LIMIT 10;

-- ============================================================================
-- RECOMMENDATION 4: Analyze Tables (Update Statistics)
-- ============================================================================

\echo ''
\echo '--- RECOMMENDATION 4: Update Statistics on Large Tables ---'
\echo ''

SELECT
    'ANALYZE ' || schemaname || '.' || tablename || ';  -- ' ||
    'Rows: ' || n_live_tup || ', Size: ' ||
    pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) AS recommended_sql
FROM pg_stat_user_tables
WHERE n_live_tup > 100000
  OR pg_relation_size(schemaname||'.'||tablename) > 100 * 1024 * 1024  -- > 100MB
ORDER BY pg_relation_size(schemaname||'.'||tablename) DESC
LIMIT 20;

-- ============================================================================
-- RECOMMENDATION 5: Composite Indexes for High Sequential Scans
-- ============================================================================

\echo ''
\echo '--- RECOMMENDATION 5: Consider Composite Indexes ---'
\echo ''
\echo 'Tables with high sequential scans may benefit from indexes'
\echo 'Analyze queries on these tables to determine which columns to index'
\echo ''

SELECT
    '-- ' || schemaname || '.' || tablename ||
    ' has ' || seq_scan || ' seq scans, ' || n_live_tup || ' rows' ||
    chr(10) ||
    '-- CREATE INDEX idx_' || tablename || '_COLUMN_NAME ON ' ||
    schemaname || '.' || tablename || '(COLUMN_NAME);' AS recommended_sql
FROM pg_stat_user_tables
WHERE seq_scan > 5000
  AND n_live_tup > 10000
  AND seq_scan > idx_scan  -- More sequential than index scans
ORDER BY seq_scan DESC
LIMIT 10;

-- ============================================================================
-- RECOMMENDATION 6: Remove Duplicate Indexes
-- ============================================================================

\echo ''
\echo '--- RECOMMENDATION 6: Remove Duplicate Indexes (if found) ---'
\echo ''

SELECT
    'DROP INDEX IF EXISTS ' || b.schemaname || '.' || b.indexname || ';  -- Duplicate of ' || a.indexname AS recommended_sql
FROM pg_stat_user_indexes a
JOIN pg_stat_user_indexes b
    ON a.schemaname = b.schemaname
    AND a.tablename = b.tablename
    AND a.indexname < b.indexname
WHERE pg_get_indexdef(a.indexrelid) = pg_get_indexdef(b.indexrelid)
ORDER BY a.schemaname, a.tablename;

-- ============================================================================
-- SUMMARY
-- ============================================================================

\echo ''
\echo '========================================='
\echo 'Recommendations Generated'
\echo '========================================='
\echo ''
\echo 'IMPORTANT:'
\echo '1. Review all recommendations before executing'
\echo '2. Test in a development environment first'
\echo '3. Create a backup before making changes'
\echo '4. Run ANALYZE after creating new indexes'
\echo '5. Monitor performance after changes'
\echo ''
\echo 'Save recommendations to a file:'
\echo 'psql -h localhost -U postgres -d your_db -f 02_generate_recommendations.sql > recommendations.sql'
\echo ''
