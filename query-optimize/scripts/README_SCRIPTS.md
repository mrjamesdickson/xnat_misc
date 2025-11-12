# SQL Scripts Directory

This directory contains all SQL scripts for XNAT workflow query optimization.

## Quick Start

### One-Command Optimization (Recommended)
```bash
psql -U xnat -d xnat -f scripts/00_run_all_optimizations.sql
```

This master script will:
1. Run pre-flight checks
2. Create all recommended indexes
3. Update database statistics
4. Verify index creation
5. Display performance summary

**Time:** ~5 minutes
**Expected Result:** 3-4x faster queries

---

## Script Inventory

### Master Scripts

| Script | Purpose | Usage |
|--------|---------|-------|
| **00_run_all_optimizations.sql** | One-command complete optimization | Run first |
| **99_rollback.sql** | Remove all optimization indexes | Use if needed to rollback |

### Individual Scripts

| Script | Purpose | When to Use |
|--------|---------|-------------|
| **recommended-indexes.sql** | Create database indexes | Standalone index creation |
| **performance-test.sql** | Benchmark before/after | Verify improvements |
| **workflow-query-optimized.sql** | Optimized query version | Phase 2: Code updates |
| **workflow-query-original.sql** | Original slow query | Reference only |
| **schema-wrk_workflowdata.sql** | Table schema documentation | Reference only |

---

## Execution Order

### Standard Workflow
```bash
# 1. Run complete optimization (recommended)
psql -U xnat -d xnat -f scripts/00_run_all_optimizations.sql

# 2. Test performance
psql -U xnat -d xnat -f scripts/performance-test.sql

# 3. (Optional) If issues occur, rollback
psql -U xnat -d xnat -f scripts/99_rollback.sql
```

### Manual Workflow (Advanced)
```bash
# 1. Create indexes manually
psql -U xnat -d xnat -f scripts/recommended-indexes.sql

# 2. Test specific query
psql -U xnat -d xnat -c "EXPLAIN (ANALYZE) SELECT ..."

# 3. Update statistics
psql -U xnat -d xnat -c "ANALYZE xnat_imageassessordata;"
```

---

## Script Details

### 00_run_all_optimizations.sql
**Master orchestration script**

Sections:
1. Pre-flight checks (permissions, disk space)
2. Index creation (calls recommended-indexes.sql)
3. Statistics update (ANALYZE tables)
4. Verification (check new indexes)
5. Performance summary (sizes and next steps)

Features:
- Progress reporting
- Error handling
- Timing information
- Verification checks
- Next steps guidance

### 99_rollback.sql
**Safe removal of optimization indexes**

Features:
- 5-second warning before execution
- Only drops optimization indexes (not system indexes)
- Updates statistics after removal
- Verification checks
- Returns database to original state

Safe to run: Yes - idempotent, only drops indexes we created

### recommended-indexes.sql
**Creates 6 optimization indexes**

Indexes created:
1. `idx_xnat_imageassessordata_imagesession` - Critical
2. `idx_xnat_imageassessordata_history_imagesession` - Critical
3. `idx_xnat_experimentdata_id` - Important
4. `idx_xnat_experimentdata_share_experiment` - Supporting
5. `idx_wrk_workflowdata_meta_data_id` - Supporting
6. `idx_xdat_user_id` - Supporting

Note: Includes notes about existing indexes on wrk_workflowdata table

### performance-test.sql
**Automated before/after benchmarking**

Tests:
1. Original query without indexes
2. Original query with indexes
3. Optimized query with indexes

Provides:
- Execution time comparison
- Query plan analysis
- Buffer usage statistics
- Index usage verification
- Table statistics

Replace `'XNAT_E00001'` with actual experiment ID before running.

### workflow-query-optimized.sql
**Optimized query for Phase 2**

Improvements:
- Uses CTEs (Common Table Expressions)
- UNION ALL instead of UNION
- Reduced nesting levels
- Better index utilization
- Includes alternative approaches

Use this to replace the query in your Java/application code.

### workflow-query-original.sql
**Original XNAT query (reference)**

Shows the baseline query with performance issues.
For reference only - do not use in production.

### schema-wrk_workflowdata.sql
**Complete table schema**

Documents:
- All table columns and types
- All 15 existing indexes
- Foreign key constraints
- Triggers
- Index analysis and recommendations

For understanding and reference only.

---

## Safety Notes

### Safe to Run
✅ All scripts are safe to run multiple times (idempotent)
✅ Index creation does not modify data
✅ Rollback script only drops indexes we created
✅ No data is deleted or modified

### Considerations
⚠️ Index creation may briefly lock tables (~30 seconds)
⚠️ Use `CREATE INDEX CONCURRENTLY` for zero-downtime (slower)
⚠️ Indexes require disk space (~50-100MB total)
⚠️ Best to run during low-usage periods

### Rollback
If anything goes wrong:
```bash
psql -U xnat -d xnat -f scripts/99_rollback.sql
```

---

## Troubleshooting

### Permission errors
```
ERROR: permission denied for table xnat_imageassessordata
```
**Solution:** Ensure your database user has CREATE privileges:
```sql
GRANT CREATE ON DATABASE xnat TO your_user;
```

### Disk space issues
```
ERROR: could not extend file: No space left on device
```
**Solution:** Free up space or use smaller indexes (skip covering index)

### Table locked
```
ERROR: deadlock detected
```
**Solution:** Use `CREATE INDEX CONCURRENTLY` or retry during low-usage period

### Index not being used
**Solution:**
```sql
-- Update statistics
ANALYZE xnat_imageassessordata;

-- Verify index exists
\d xnat_imageassessordata

-- Check query plan
EXPLAIN (ANALYZE) SELECT ...
```

---

## Monitoring

### Check index usage
```sql
SELECT indexname, idx_scan, idx_tup_read
FROM pg_stat_user_indexes
WHERE tablename = 'xnat_imageassessordata'
ORDER BY idx_scan DESC;
```

### Check index sizes
```sql
SELECT indexname, pg_size_pretty(pg_relation_size(indexrelid))
FROM pg_indexes
LEFT JOIN pg_class ON indexname = relname
WHERE tablename = 'xnat_imageassessordata';
```

### Identify slow queries
```sql
SELECT query, mean_exec_time, calls
FROM pg_stat_statements
WHERE query LIKE '%wrk_workflowdata%'
ORDER BY mean_exec_time DESC
LIMIT 10;
```

---

## Best Practices

1. **Always run 00_run_all_optimizations.sql first**
   - It includes all checks and verifications
   - Provides progress reporting
   - Gives next steps guidance

2. **Test with performance-test.sql**
   - Verifies improvement
   - Documents baseline metrics
   - Helps troubleshoot issues

3. **Keep 99_rollback.sql ready**
   - Safety net if issues occur
   - Quick revert to original state
   - No data loss

4. **Monitor index usage**
   - Check pg_stat_user_indexes regularly
   - Drop unused indexes to save space
   - Update statistics weekly

5. **Document baseline metrics**
   - Query execution time before optimization
   - Table row counts
   - Current disk usage
   - Helps measure ROI

---

## Support

For issues or questions:
- See parent directory's EXECUTIVE_SUMMARY.md for business context
- See parent directory's README.md for technical details
- See parent directory's QUICK_REFERENCE.md for quick commands

---

**Last Updated:** 2025-11-12
**PostgreSQL Version:** 12+
**XNAT Version:** 1.8+
