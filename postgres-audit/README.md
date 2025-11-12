# PostgreSQL Database Audit and Optimization Toolkit

Comprehensive PostgreSQL database audit and automated index testing suite.

## Overview

This toolkit provides three powerful scripts for database optimization:

1. **01_database_audit.sql** - Complete database analysis
2. **02_generate_recommendations.sql** - Generate optimization SQL
3. **03_automated_index_testing.sql** - Automated A/B testing of indexes

## Quick Start

```bash
# Connect to your database
psql -h localhost -U postgres -d your_database

# Run complete audit
\i 01_database_audit.sql

# Generate recommendations
\i 02_generate_recommendations.sql

# Run automated tests (creates, tests, keeps good/rolls back bad indexes)
\i 03_automated_index_testing.sql
```

---

## Script 1: Database Audit

**File:** `01_database_audit.sql`

### What It Does

Comprehensive 12-section analysis of your PostgreSQL database:

1. **Database Overview** - Version, size, connection info
2. **Table Statistics** - Size, row counts, dead rows
3. **Index Analysis** - All indexes with usage statistics
4. **Unused Indexes** - Indexes with < 100 scans
5. **Missing Indexes** - Tables with high sequential scans
6. **Duplicate Indexes** - Redundant index detection
7. **Cache Hit Ratio** - Should be > 99%
8. **Table Bloat** - Tables needing VACUUM
9. **Foreign Keys Without Indexes** - Common performance issue
10. **Slow Queries** - Top 20 by execution time
11. **Index Types** - btree, hash, gin, gist summary
12. **Recommendations Summary** - Key findings

### Usage

```bash
# Interactive mode
psql -h localhost -U postgres -d your_db -f 01_database_audit.sql

# Save to file
psql -h localhost -U postgres -d your_db -f 01_database_audit.sql > audit_report.txt

# Pipe to less for easy viewing
psql -h localhost -U postgres -d your_db -f 01_database_audit.sql | less
```

### Output Example

```
--- 4. Potentially Unused Indexes (idx_scan < 100) ---

 schemaname |    tablename    |      indexname       | index_size | scans
------------+-----------------+---------------------+------------+-------
 public     | large_table     | idx_rarely_used_col | 45 MB      | 3
 public     | another_table   | idx_old_index       | 23 MB      | 0
```

---

## Script 2: Generate Recommendations

**File:** `02_generate_recommendations.sql`

### What It Does

Generates ready-to-execute SQL commands for:

1. **Create Indexes on Foreign Keys** - Missing FK indexes
2. **Drop Unused Indexes** - Save space and write performance
3. **VACUUM Bloated Tables** - Reclaim disk space
4. **Update Statistics** - ANALYZE large tables
5. **Composite Indexes** - For tables with high sequential scans
6. **Remove Duplicate Indexes** - Eliminate redundancy

### Usage

```bash
# Generate recommendations
psql -h localhost -U postgres -d your_db -f 02_generate_recommendations.sql

# Save to executable SQL file
psql -h localhost -U postgres -d your_db -f 02_generate_recommendations.sql > optimizations.sql

# Review and execute
less optimizations.sql
psql -h localhost -U postgres -d your_db -f optimizations.sql
```

### Output Example

```sql
--- RECOMMENDATION 1: Create Indexes on Foreign Keys ---

CREATE INDEX idx_orders_customer_id ON orders(customer_id);
CREATE INDEX idx_order_items_order_id ON order_items(order_id);

--- RECOMMENDATION 2: Drop Unused Indexes ---

DROP INDEX IF EXISTS public.idx_old_column;  -- Size: 45 MB, Scans: 0
```

---

## Script 3: Automated Index Testing

**File:** `03_automated_index_testing.sql`

### What It Does

**Automated A/B testing framework for indexes:**

1. ✅ Tests baseline query performance (5 iterations)
2. ✅ Creates candidate index
3. ✅ Tests performance with index (5 iterations)
4. ✅ Compares results
5. ✅ **Keeps index if improvement > threshold** (default 10%)
6. ✅ **Rolls back index if improvement < threshold**
7. ✅ Logs all results to `pg_index_test_log` table
8. ✅ Generates detailed performance report
9. ✅ Reverts all test changes at end

### Key Features

- **Fully automated** - No manual intervention required
- **Safe** - All changes reverted unless proven beneficial
- **Logged** - Every test recorded in database
- **Configurable** - Adjustable improvement thresholds
- **Iterative** - Multiple test runs for accuracy

### Usage

```bash
# Run full automated test suite
psql -h localhost -U postgres -d your_db -f 03_automated_index_testing.sql

# Test specific index manually
psql -h localhost -U postgres -d your_db << 'EOF'
SELECT * FROM test_index_candidate(
    'my_table',
    'idx_my_table_column',
    'CREATE INDEX idx_my_table_column ON my_table(column_name)',
    'SELECT * FROM my_table WHERE column_name = ''value''',
    10.0  -- minimum 10% improvement required
);
EOF
```

### Example Output

```
========================================
Testing: idx_test_orders_customer_id on orders(customer_id)
========================================
NOTICE:  Testing baseline performance for orders...
NOTICE:  Baseline: 245.32ms (avg of 5 runs)
NOTICE:  Creating index: idx_test_orders_customer_id
NOTICE:  Index created successfully
NOTICE:  Testing performance with index...
NOTICE:  With index: 12.45ms (avg of 5 runs)
NOTICE:  Index improved performance by 94.92% (245.32ms -> 12.45ms). KEEPING index.

--- Summary Statistics ---
 tables_tested | indexes_tested | indexes_kept | indexes_rolled_back | avg_improvement_percent
---------------+----------------+--------------+---------------------+------------------------
             3 |              5 |            3 |                   2 |                   67.23

--- Kept Indexes (Performance Improved) ---
      table_name       |        index_name         | improvement_pct |           notes
-----------------------+---------------------------+-----------------+---------------------------
 orders                | idx_test_orders_cust_id   |           94.92 | Kept - 94.92% improvement
 order_items           | idx_test_order_items_oid  |           78.34 | Kept - 78.34% improvement
```

### Report Review

After running, review the test log:

```sql
-- View all tests
SELECT * FROM pg_index_test_log ORDER BY test_id;

-- View only kept indexes
SELECT * FROM pg_index_test_log
WHERE test_phase = 'decision' AND decision = 'KEEP';

-- Export to CSV
\copy (SELECT * FROM pg_index_test_log ORDER BY test_id) TO 'index_test_report.csv' CSV HEADER;
```

---

## Workflow

### Standard Workflow

```bash
# Step 1: Audit
psql -h localhost -U postgres -d your_db -f 01_database_audit.sql > audit.txt

# Step 2: Generate recommendations
psql -h localhost -U postgres -d your_db -f 02_generate_recommendations.sql > recommendations.sql

# Step 3: Automated testing
psql -h localhost -U postgres -d your_db -f 03_automated_index_testing.sql > test_results.txt

# Step 4: Review results
cat test_results.txt
psql -h localhost -U postgres -d your_db -c "SELECT * FROM pg_index_test_log WHERE decision = 'KEEP';"

# Step 5: Implement proven indexes
# (Script 3 already rolled back all test indexes)
# Manually create the indexes that showed improvement
```

### Quick Test Workflow

```bash
# Run automated testing only (fastest)
psql -h localhost -U postgres -d your_db -f 03_automated_index_testing.sql
```

---

## Safety

### What's Safe

✅ All scripts are **read-only** except Script 3
✅ Script 3 creates test indexes but **reverts everything** at the end
✅ Original database state is **fully restored**
✅ All tests are **logged** for review
✅ No production indexes are **modified or dropped**

### What to Watch

⚠️ Script 3 creates temporary indexes (may take time on large tables)
⚠️ Test queries run multiple times (may cause brief load)
⚠️ `pg_index_test_log` table is created and **kept** for review

### Cleanup

```sql
-- Drop test log table when done reviewing
DROP TABLE IF EXISTS pg_index_test_log;
```

---

## Customization

### Adjust Test Parameters

Edit `03_automated_index_testing.sql`:

```sql
-- Change minimum improvement threshold (default 10%)
test_index_candidate(..., 5.0)  -- Accept 5% improvement

-- Change number of test iterations (default 5)
test_query_performance(..., 10)  -- Run 10 iterations for more accuracy

-- Limit number of indexes tested
LIMIT 5  -- Test only first 5 candidates
```

### Add Custom Test Queries

```sql
SELECT * FROM test_index_candidate(
    'your_table',
    'idx_your_table_custom',
    'CREATE INDEX idx_your_table_custom ON your_table(col1, col2)',
    'SELECT * FROM your_table WHERE col1 = ''val'' AND col2 > 100',
    15.0  -- Require 15% improvement
);
```

---

## Requirements

- PostgreSQL 12+
- `pg_stat_statements` extension (optional, for slow query analysis)
- Database user with CREATE INDEX privilege
- Sufficient disk space for temporary indexes

---

## Troubleshooting

### "permission denied for table"

```sql
-- Grant necessary permissions
GRANT CREATE ON DATABASE your_db TO your_user;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO your_user;
```

### "pg_stat_statements must be loaded"

```sql
-- Add to postgresql.conf
shared_preload_libraries = 'pg_stat_statements'

-- Restart PostgreSQL
-- Create extension
CREATE EXTENSION pg_stat_statements;
```

### "out of memory" during testing

Reduce test iterations:
```sql
-- In test_query_performance function
test_query_performance(p_table_name, p_query, 3)  -- Reduce from 5 to 3
```

---

## Performance Impact

### Script 1 (Audit)
- **Impact:** Minimal - read-only queries
- **Time:** 1-5 minutes depending on database size

### Script 2 (Recommendations)
- **Impact:** Minimal - generates SQL only
- **Time:** < 1 minute

### Script 3 (Automated Testing)
- **Impact:** Moderate - creates/drops indexes, runs test queries
- **Time:** 5-30 minutes depending on:
  - Number of indexes tested
  - Table sizes
  - Test iterations
- **Best run during:** Low-usage periods

---

## Best Practices

1. ✅ Run Script 1 first to understand your database
2. ✅ Review Script 2 output before executing
3. ✅ Run Script 3 during low-usage periods
4. ✅ Save all output for documentation
5. ✅ Test in development before production
6. ✅ Monitor after implementing changes
7. ✅ Keep `pg_index_test_log` for future reference

---

## Example: Complete Session

```bash
# Connect
psql -h localhost -U postgres -d production_db

# Audit
\i 01_database_audit.sql
\o audit_report.txt
\i 01_database_audit.sql
\o

# Generate recommendations
\o recommendations.sql
\i 02_generate_recommendations.sql
\o

# Automated testing
\o test_results.txt
\i 03_automated_index_testing.sql
\o

# Review
\! cat test_results.txt
SELECT * FROM pg_index_test_log WHERE decision = 'KEEP';

# Cleanup
DROP TABLE pg_index_test_log;
\q
```

---

## Support

- See examples in each script file
- Check PostgreSQL logs for detailed errors
- Review `pg_index_test_log` table for test history

---

**Created:** 2025-11-12
**PostgreSQL Version:** 12+
**Status:** Production Ready ✅
