# PostgreSQL Index Testing Parameters

Complete reference for configuring the index testing scripts.

---

## Overview

The `run_complete_analysis.sh` script provides comprehensive PostgreSQL index testing with configurable parameters to control scope and performance.

---

## Command-Line Parameters

### Database Connection

| Parameter | Description | Default | Example |
|-----------|-------------|---------|---------|
| `-h, --host HOST` | Database host | `localhost` | `--host prod-db.example.com` |
| `-p, --port PORT` | Database port | `5432` | `--port 5433` |
| `-d, --database NAME` | Database name | `xnat` | `--database production` |
| `-U, --username USER` | Database user | `postgres` | `--username dbadmin` |
| `-c, --container NAME` | Docker container name | `xnat-db` | `--container my-postgres` |

### Output Options

| Parameter | Description | Default | Example |
|-----------|-------------|---------|---------|
| `-o, --output DIR` | Output directory | `./results` | `--output /tmp/index-tests` |

### Test Selection (Skip Flags)

| Parameter | Description | Impact |
|-----------|-------------|--------|
| `--skip-audit` | Skip database audit report | Skips comprehensive database statistics |
| `--skip-fk` | Skip FK index tests | Skips ~20 foreign key index tests |
| `--skip-non-fk` | Skip non-FK index tests | Skips 4 high-frequency query tests |
| `--skip-schema` | Skip schema-based tests | Skips 7 schema pattern tests |
| `--skip-large-tables` | Skip large table tests | Skips top N largest table tests |
| `--skip-query-based` | Skip query-based tests | Skips top N query pattern tests |

### Test Scope Parameters

| Parameter | Description | Default | Range | Example |
|-----------|-------------|---------|-------|---------|
| `--max-large-tables N` | Number of largest tables to test | `20` | `1-1000` | `--max-large-tables 200` |
| `--max-queries N` | Number of top queries to test | `100` | `1-1000` | `--max-queries 50` |

---

## SQL-Level Parameters

These parameters control filtering criteria within the SQL test scripts. They are **hardcoded** in the scripts but can be modified.

### test_large_tables.sql

Located in: `/Users/james/projects/xnat_misc/postgres-audit/test_large_tables.sql`

| Parameter | Description | Default | Impact |
|-----------|-------------|---------|--------|
| `MAX_TABLES` | Maximum tables to test | `20` | Passed from `--max-large-tables` |
| `MIN_SIZE_MB` | Minimum table size in MB | `1` | Tables < 1MB excluded |
| `MIN_SEQ_SCANS` | Minimum sequential scans | `1` | Tables with ≤1 seq scan excluded |

**Hardcoded minimum:** 100 rows per table (in SQL query)

**To modify thresholds:**
```bash
# Edit the SQL script
vim test_large_tables.sql

# Find line ~175:
WHERE pg_total_relation_size(s.relid) > (min_size_mb * 1024 * 1024)
  AND s.seq_scan > min_seq_scans
  AND s.n_live_tup > 100  # <-- Change this value
```

### test_query_based_indexes.sql

Located in: `/Users/james/projects/xnat_misc/postgres-audit/test_query_based_indexes.sql`

| Parameter | Description | Default | Impact |
|-----------|-------------|---------|--------|
| `MAX_QUERIES` | Maximum queries to analyze | `100` | Passed from `--max-queries` |
| `MIN_CALLS` | Minimum query call count | `50` | Queries called <50 times excluded |
| `MIN_AVG_TIME_MS` | Minimum avg query time (ms) | `0.5` | Queries faster than 0.5ms excluded |

---

## Performance Characteristics

### Test Duration Estimates

| Configuration | Tables Tested | Estimated Time |
|---------------|---------------|----------------|
| Default (all tests) | ~20-30 | 5-10 minutes |
| `--max-large-tables 50` | ~50-60 | 15-20 minutes |
| `--max-large-tables 200` | ~28-200 | 30-60 minutes |
| `--max-large-tables 200 --max-queries 200` | ~50-250 | 60-120 minutes |

**Note:** Actual duration depends on:
- Database size
- Table row counts
- Number of eligible tables
- System load

### Eligibility Criteria Impact

For a database with **923 total tables**, here's how many meet different criteria:

| Criteria | Tables Found | Example Command |
|----------|--------------|-----------------|
| Size > 1MB + seq_scan > 1 | 28 | Default configuration |
| Size > 100KB + seq_scan > 1 | ~50-80 | Modify `MIN_SIZE_MB = 0.1` |
| Size > 10KB + seq_scan > 0 | ~150-200 | Very permissive, slower |
| All tables (no filters) | 923 | Not recommended (hours) |

---

## Usage Examples

### Quick Test (5 minutes)
```bash
./run_complete_analysis.sh \
  --max-large-tables 10 \
  --max-queries 20
```

### Standard Test (10-15 minutes)
```bash
./run_complete_analysis.sh \
  --max-large-tables 20 \
  --max-queries 50
```

### Comprehensive Test (30-60 minutes)
```bash
./run_complete_analysis.sh \
  --max-large-tables 200 \
  --max-queries 100
```

### Skip Time-Intensive Tests
```bash
./run_complete_analysis.sh \
  --skip-large-tables \
  --skip-query-based
```

### Production Database (Minimal Impact)
```bash
./run_complete_analysis.sh \
  --host prod-db.example.com \
  --database production \
  --max-large-tables 5 \
  --skip-audit \
  --skip-query-based
```

### Test Only Large Tables
```bash
./run_complete_analysis.sh \
  --skip-audit \
  --skip-fk \
  --skip-non-fk \
  --skip-schema \
  --skip-query-based \
  --max-large-tables 200
```

---

## Understanding Results

### Summary Output

```
tables_tested | indexes_tested | indexes_kept | indexes_rolled_back | avg_improvement_pct | max_improvement_pct
---------------+----------------+--------------+---------------------+---------------------+---------------------
            29 |             38 |           28 |                  10 |               66.27 |               98.37
```

**What this means:**
- **29 tables tested** - Unique tables that had indexes tested
- **38 indexes tested** - Total indexes created and benchmarked
- **28 indexes kept** - Indexes with ≥5% performance improvement
- **10 indexes rolled back** - Indexes with <5% improvement (automatically dropped)
- **66.27% avg improvement** - Average speedup for kept indexes
- **98.37% max improvement** - Best performing index (fastest query)

### Decision Threshold

**Index kept if:** Query improvement ≥ 5%
**Index rolled back if:** Query improvement < 5%

This threshold is **hardcoded** in the test functions:
```sql
IF v_improvement >= 5.0 THEN
    v_decision := 'KEEP';
ELSE
    v_decision := 'ROLLBACK';
    EXECUTE FORMAT('DROP INDEX %I', p_index_name);
END IF;
```

**To modify threshold:** Edit functions in:
- `test_large_tables.sql` (line ~110)
- `test_non_fk_indexes.sql` (line ~78)
- `test_schema_indexes.sql` (line ~78)
- `test_query_based_indexes.sql` (line ~110)

---

## Advanced Configuration

### Testing Smaller Tables

To test tables smaller than 1MB, modify `test_large_tables.sql`:

```sql
-- Line ~145: Change from
COALESCE(NULLIF(:'MIN_SIZE_MB', ''), '1')::INT,

-- To (for 100KB minimum)
COALESCE(NULLIF(:'MIN_SIZE_MB', ''), '0.1')::INT,
```

Then run:
```bash
./run_complete_analysis.sh --max-large-tables 200
```

### Testing Low-Activity Tables

To test tables with fewer sequential scans, modify `test_large_tables.sql`:

```sql
-- Line ~147: Change from
COALESCE(NULLIF(:'MIN_SEQ_SCANS', ''), '10')::INT;

-- To (for any activity)
COALESCE(NULLIF(:'MIN_SEQ_SCANS', ''), '0')::INT;
```

### Changing Row Count Threshold

To test smaller tables, modify the query in `test_large_tables.sql`:

```sql
-- Line ~177: Change from
AND s.n_live_tup > 100

-- To (for tables with any data)
AND s.n_live_tup > 0
```

---

## Environment Variables

The script uses these environment variables internally:

| Variable | Purpose | Set By |
|----------|---------|--------|
| `MAX_LARGE_TABLES` | Large table test limit | `--max-large-tables` |
| `MAX_QUERIES` | Query test limit | `--max-queries` |
| `SKIP_AUDIT` | Skip audit flag | `--skip-audit` |
| `SKIP_FK` | Skip FK tests flag | `--skip-fk` |
| `SKIP_NON_FK` | Skip non-FK tests flag | `--skip-non-fk` |
| `SKIP_SCHEMA` | Skip schema tests flag | `--skip-schema` |
| `SKIP_LARGE_TABLES` | Skip large table tests flag | `--skip-large-tables` |
| `SKIP_QUERY_BASED` | Skip query tests flag | `--skip-query-based` |
| `DB_HOST` | Database host | `-h, --host` |
| `DB_PORT` | Database port | `-p, --port` |
| `DB_NAME` | Database name | `-d, --database` |
| `DB_USER` | Database user | `-U, --username` |
| `DOCKER_CONTAINER` | Container name | `-c, --container` |
| `OUTPUT_BASE` | Output directory | `-o, --output` |

---

## Troubleshooting

### "Only X tables tested instead of 200"

**Cause:** Not enough tables meet the eligibility criteria.

**Solution:** Check how many tables qualify:
```bash
docker exec xnat-db psql -U xnat -d xnat -c "
SELECT COUNT(*) as eligible_tables
FROM pg_stat_user_tables s
WHERE pg_total_relation_size(s.relid) > (1 * 1024 * 1024)
  AND s.seq_scan > 1
  AND s.n_live_tup > 100;
"
```

**Fix:** Lower thresholds in `test_large_tables.sql` (see Advanced Configuration above)

### "Testing Top <NULL>"

**Cause:** Parameters not passed correctly from shell script.

**Solution:** Parameters are now properly quoted in the script:
```bash
-v MAX_TABLES="$MAX_LARGE_TABLES"
```

### Test takes too long

**Solution:** Reduce scope:
```bash
./run_complete_analysis.sh \
  --max-large-tables 10 \
  --max-queries 20 \
  --skip-query-based
```

### No indexes kept (all rolled back)

**Possible causes:**
1. Tables are already well-indexed
2. Test queries don't benefit from indexes
3. Tables are too small (index overhead > benefit)

**Solution:** Review test results in `results/*/06_large_table_test_results.log`

---

## Best Practices

### Recommendations

1. **Start small**: Test with `--max-large-tables 10` first
2. **Monitor duration**: Check after 5 minutes to estimate full run time
3. **Production databases**: Use `--max-large-tables 5` to minimize impact
4. **Development databases**: Use `--max-large-tables 200` for comprehensive testing
5. **Regular testing**: Run monthly to catch schema/workload changes

### Performance Impact

**Test impact on database:**
- Read-only operations (no data modification)
- Creates temporary test indexes (dropped if not useful)
- Each index test runs 10 queries (5 baseline + 5 with index)
- Minimal CPU/memory impact
- Negligible disk I/O (mostly cached reads)

**Safe for production:** Yes, but recommend off-peak hours for comprehensive tests.

---

## Output Files

All results saved to `./results/YYYY-MM-DD-HH-MM-SS/`:

| File | Description |
|------|-------------|
| `00_README.md` | Summary report with recommendations |
| `01_audit_report.txt` | Full database audit statistics |
| `02_recommendations.sql` | All optimization recommendations |
| `03_fk_test_results.log` | FK index test detailed output |
| `04_non_fk_test_results.log` | Non-FK index test output |
| `05_schema_test_results.log` | Schema-based index test output |
| `06_large_table_test_results.log` | Large table test output |
| `07_query_based_test_results.log` | Query-based test output |
| `06_test_results.csv` | Machine-readable test results |
| `07_summary_stats.txt` | Summary statistics |
| `08_production_fk_indexes.sql` | **Production-ready FK indexes** |
| `09_production_non_fk_indexes.sql` | **Production-ready non-FK indexes** |

---

## See Also

- [README.md](README.md) - Main documentation
- [run_complete_analysis.sh](run_complete_analysis.sh) - Main script
- [test_large_tables.sql](test_large_tables.sql) - Large table test implementation
- [test_query_based_indexes.sql](test_query_based_indexes.sql) - Query-based test implementation
