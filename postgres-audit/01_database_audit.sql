-- PostgreSQL Database Audit Script
-- Purpose: Comprehensive audit of database tables, indexes, and performance
-- Usage: psql -h localhost -U postgres -d your_database -f 01_database_audit.sql
-- Output: Detailed analysis for optimization recommendations

\timing on
\pset border 2

\echo ''
\echo '========================================='
\echo 'PostgreSQL Database Audit'
\echo '========================================='
\echo ''

-- ============================================================================
-- SECTION 1: Database Overview
-- ============================================================================

\echo ''
\echo '--- 1. Database Overview ---'
\echo ''

SELECT
    current_database() AS database_name,
    current_user AS connected_as,
    version() AS postgresql_version;

SELECT
    pg_size_pretty(pg_database_size(current_database())) AS database_size,
    pg_database_size(current_database()) AS size_bytes;

-- ============================================================================
-- SECTION 2: Table Statistics
-- ============================================================================

\echo ''
\echo '--- 2. Table Statistics (Top 20 by size) ---'
\echo ''

SELECT
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS total_size,
    pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) AS table_size,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename) - pg_relation_size(schemaname||'.'||tablename)) AS indexes_size,
    n_live_tup AS row_count,
    n_dead_tup AS dead_rows,
    CASE
        WHEN n_live_tup > 0
        THEN ROUND(100.0 * n_dead_tup / n_live_tup, 2)
        ELSE 0
    END AS dead_row_percent
FROM pg_stat_user_tables
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
LIMIT 20;

-- ============================================================================
-- SECTION 3: Index Analysis
-- ============================================================================

\echo ''
\echo '--- 3. All Indexes (sorted by table and size) ---'
\echo ''

SELECT
    schemaname,
    tablename,
    indexname,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size,
    idx_scan AS scans,
    idx_tup_read AS tuples_read,
    idx_tup_fetch AS tuples_fetched
FROM pg_stat_user_indexes
LEFT JOIN pg_indexes USING (schemaname, tablename, indexname)
ORDER BY schemaname, tablename, pg_relation_size(indexrelid) DESC;

-- ============================================================================
-- SECTION 4: Unused Indexes (Never or Rarely Used)
-- ============================================================================

\echo ''
\echo '--- 4. Potentially Unused Indexes (idx_scan < 100) ---'
\echo ''

SELECT
    schemaname,
    tablename,
    indexname,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size,
    idx_scan AS scans,
    idx_tup_read AS tuples_read
FROM pg_stat_user_indexes
WHERE idx_scan < 100
  AND indexname NOT LIKE '%_pkey'  -- Exclude primary keys
ORDER BY pg_relation_size(indexrelid) DESC;

-- ============================================================================
-- SECTION 5: Missing Indexes (Sequential Scans on Large Tables)
-- ============================================================================

\echo ''
\echo '--- 5. Tables with High Sequential Scans (may need indexes) ---'
\echo ''

SELECT
    schemaname,
    tablename,
    seq_scan AS sequential_scans,
    seq_tup_read AS rows_read_sequentially,
    idx_scan AS index_scans,
    n_live_tup AS row_count,
    CASE
        WHEN seq_scan + idx_scan > 0
        THEN ROUND(100.0 * seq_scan / (seq_scan + idx_scan), 2)
        ELSE 0
    END AS seq_scan_percent,
    pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) AS table_size
FROM pg_stat_user_tables
WHERE seq_scan > 1000  -- High number of sequential scans
  AND n_live_tup > 10000  -- Reasonably large table
ORDER BY seq_scan DESC
LIMIT 20;

-- ============================================================================
-- SECTION 6: Duplicate/Redundant Indexes
-- ============================================================================

\echo ''
\echo '--- 6. Potential Duplicate Indexes (same columns) ---'
\echo ''

SELECT
    a.schemaname,
    a.tablename,
    a.indexname AS index1,
    b.indexname AS index2,
    pg_get_indexdef(a.indexrelid) AS index1_definition,
    pg_get_indexdef(b.indexrelid) AS index2_definition
FROM pg_stat_user_indexes a
JOIN pg_stat_user_indexes b
    ON a.schemaname = b.schemaname
    AND a.tablename = b.tablename
    AND a.indexname < b.indexname
WHERE pg_get_indexdef(a.indexrelid) = pg_get_indexdef(b.indexrelid)
ORDER BY a.schemaname, a.tablename;

-- ============================================================================
-- SECTION 7: Cache Hit Ratio
-- ============================================================================

\echo ''
\echo '--- 7. Cache Hit Ratio (should be > 99%) ---'
\echo ''

SELECT
    'Index Cache Hit Rate' AS metric,
    ROUND(
        100.0 * sum(idx_blks_hit) / NULLIF(sum(idx_blks_hit + idx_blks_read), 0),
        2
    ) AS percentage
FROM pg_statio_user_indexes
UNION ALL
SELECT
    'Table Cache Hit Rate' AS metric,
    ROUND(
        100.0 * sum(heap_blks_hit) / NULLIF(sum(heap_blks_hit + heap_blks_read), 0),
        2
    ) AS percentage
FROM pg_statio_user_tables;

-- ============================================================================
-- SECTION 8: Table Bloat Estimation
-- ============================================================================

\echo ''
\echo '--- 8. Table Bloat Estimation (approximate) ---'
\echo ''

SELECT
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS total_size,
    n_dead_tup AS dead_rows,
    n_live_tup AS live_rows,
    last_vacuum,
    last_autovacuum,
    CASE
        WHEN n_live_tup > 0
        THEN ROUND(100.0 * n_dead_tup / n_live_tup, 2)
        ELSE 0
    END AS bloat_percent
FROM pg_stat_user_tables
WHERE n_dead_tup > 1000
ORDER BY n_dead_tup DESC
LIMIT 20;

-- ============================================================================
-- SECTION 9: Foreign Key Constraints Without Indexes
-- ============================================================================

\echo ''
\echo '--- 9. Foreign Keys Potentially Missing Indexes ---'
\echo ''

SELECT
    c.conrelid::regclass AS table_name,
    string_agg(a.attname, ', ') AS foreign_key_columns,
    c.confrelid::regclass AS references_table
FROM pg_constraint c
JOIN pg_attribute a ON a.attnum = ANY(c.conkey) AND a.attrelid = c.conrelid
WHERE c.contype = 'f'
  AND NOT EXISTS (
      SELECT 1
      FROM pg_index i
      WHERE i.indrelid = c.conrelid
        AND c.conkey[1] = ANY(i.indkey)
  )
GROUP BY c.conrelid, c.confrelid, c.conname
ORDER BY c.conrelid::regclass::text;

-- ============================================================================
-- SECTION 10: Slow Queries (if pg_stat_statements is enabled)
-- ============================================================================

\echo ''
\echo '--- 10. Slow Queries (Top 20 by avg execution time) ---'
\echo ''

SELECT
    ROUND(mean_exec_time::numeric, 2) AS avg_ms,
    calls,
    ROUND(total_exec_time::numeric, 2) AS total_ms,
    LEFT(query, 100) AS query_preview
FROM pg_stat_statements
WHERE mean_exec_time > 100  -- Queries averaging > 100ms
ORDER BY mean_exec_time DESC
LIMIT 20;

-- If pg_stat_statements is not enabled, this will error - that's ok

-- ============================================================================
-- SECTION 11: Index Types Summary
-- ============================================================================

\echo ''
\echo '--- 11. Index Types Summary ---'
\echo ''

SELECT
    am.amname AS index_type,
    COUNT(*) AS count,
    pg_size_pretty(SUM(pg_relation_size(i.indexrelid))) AS total_size
FROM pg_index idx
JOIN pg_class i ON i.oid = idx.indexrelid
JOIN pg_am am ON i.relam = am.oid
JOIN pg_namespace n ON i.relnamespace = n.oid
WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
GROUP BY am.amname
ORDER BY COUNT(*) DESC;

-- ============================================================================
-- SECTION 12: Recommendations Summary
-- ============================================================================

\echo ''
\echo '========================================='
\echo 'Audit Complete - Key Recommendations'
\echo '========================================='
\echo ''
\echo 'Review the following sections for optimization opportunities:'
\echo ''
\echo '1. Section 4: Drop unused indexes to save space and write performance'
\echo '2. Section 5: Add indexes to tables with high sequential scans'
\echo '3. Section 6: Remove duplicate indexes'
\echo '4. Section 7: Investigate if cache hit ratio < 99%'
\echo '5. Section 8: VACUUM tables with high bloat percentage'
\echo '6. Section 9: Add indexes on foreign key columns'
\echo '7. Section 10: Optimize slow queries (if available)'
\echo ''
\echo 'Next Steps:'
\echo '1. Save this output to a file'
\echo '2. Review each section carefully'
\echo '3. Use 02_generate_recommendations.sql to create optimization scripts'
\echo ''
