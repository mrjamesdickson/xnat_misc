# XNAT Query Performance Report

**Date:** 2025-11-12
**Database:** xnat (PostgreSQL 16.9)
**Test Source:** xnat_test_suites E2E tests (134 tests, 123 passed)
**Monitoring Tool:** pg_stat_statements extension

---

## Executive Summary

### Top Performance Issues

1. **Slowest Query:** `get_experiment_list()` function - **144ms average** (7 calls)
2. **Second Slowest:** Complex experiment query with DISTINCT ON - **93ms average** (7 calls)
3. **Third Slowest:** Workflow data query with metadata joins - **89ms average** (3 calls)

### Query Performance Distribution

| Query Type | Avg Time | Calls | Total Time | Priority |
|------------|----------|-------|------------|----------|
| Experiment list queries | 93-144ms | 14 | 1,660ms | **High** |
| Workflow queries | 26-89ms | 14 | 694ms | **Medium** |
| User login queries | 4-15ms | 52 | 369ms | Low |
| Element access queries | 29-37ms | 8 | 263ms | **Medium** |

---

## Top 20 Slowest Queries

### 1. Experiment List Function - 144ms avg ⚠️

**Stats:**
- Calls: 7
- Average: 144.05ms
- Total: 1,008.35ms

**Query:**
```sql
SELECT * FROM get_experiment_list($1)
```

**Recommendation:**
- Investigate `get_experiment_list()` function internals
- Consider materialized view for commonly accessed experiment lists
- Add indexes on filter columns used within function

---

### 2. Complex Experiment Query - 93ms avg ⚠️

**Stats:**
- Calls: 7
- Average: 93.13ms
- Total: 651.89ms

**Query:**
```sql
SELECT *
FROM (
    SELECT DISTINCT ON (expt.id)
        expt.id,
        -- more columns...
    FROM xnat_experimentdata expt
    -- joins...
) AS subquery
```

**Issues:**
- `DISTINCT ON` can be expensive
- Multiple joins without visible WHERE clause filters

**Recommendation:**
- Review if DISTINCT ON is necessary (use GROUP BY or EXISTS instead)
- Add WHERE clause filters early in query
- Ensure all join columns are indexed

---

### 3. Workflow Data Query with Metadata - 89ms avg ⚠️

**Stats:**
- Calls: 3
- Average: 89.17ms
- Min: 62.06ms
- Max: 117.19ms
- Total: 267.52ms

**Query:**
```sql
SELECT
    w.wrk_workflowdata_id AS workflow_pk,
    w.id AS target_id,
    w.externalid AS target_label,
    w.pipeline_name,
    w.launch_time AS workflow_launch_time,
    w.status,
    w.category,
    w.data_type,
    w.details,
    w.comments,
    w.justification,
    w.current_step_id,
    w.current_step_launch_time,
    w.create_user,
    metadata.insert_date AS metadata_insert_date,
    metadata.insert_user_xdat_user_id AS metadata_insert_user_id,
    expt.project AS experiment_project,
    expt.label AS experiment_label,
    subj.id AS subject_id,
    subj.label AS subject_label,
    subj.project AS subject_project
FROM wrk_workflowdata w
LEFT JOIN wrk_workflowdata_meta_data metadata
    ON metadata.meta_data_id = w.workflowdata_info
LEFT JOIN xnat_experimentdata expt
    ON expt.id = w.id
LEFT JOIN xnat_subjectassessordata assessor
    ON assessor.id = w.id
LEFT JOIN xnat_subjectdata subj
    ON subj.id = assessor.subject_id
WHERE $3=$4
ORDER BY workflow_launch_time DESC
LIMIT $1 OFFSET $2
```

**Analysis:**
- **Good:** Uses LIMIT/OFFSET for pagination
- **Issue:** Multiple LEFT JOINs without early filtering
- **Issue:** WHERE clause appears to be dynamic ($3=$4 suggests conditional filtering)

**Related to:** Query optimization work in `xnat_misc/query-optimize/`

**Recommendation:**
1. Apply our recommended indexes:
   ```sql
   CREATE INDEX IF NOT EXISTS idx_xnat_experimentdata_id_project
   ON xnat_experimentdata(id, project) WHERE id IS NOT NULL;

   CREATE INDEX IF NOT EXISTS idx_xnat_subjectassessordata_id_subject
   ON xnat_subjectassessordata(id, subject_id) WHERE id IS NOT NULL;

   CREATE INDEX IF NOT EXISTS idx_xnat_subjectdata_id_project
   ON xnat_subjectdata(id, project) WHERE id IS NOT NULL;
   ```

2. Move dynamic WHERE clause to application logic if possible
3. Consider separate queries for different filter types instead of $3=$4 pattern

**Expected Improvement:** 50-70% faster (89ms → 25-45ms)

---

### 4. Recent Workflow Query - 51ms avg

**Stats:**
- Calls: 7
- Average: 50.93ms
- Min: 35.08ms
- Max: 71.18ms

**Query:**
```sql
SELECT DISTINCT ON (w.id)
    w.id AS workflow_id,
    w.launch_time AS workflow_date,
    CASE w.pipeline_name
        WHEN $2::TEXT THEN $3::TEXT
        ELSE CASE xs_lastposition($4::TEXT, w.pipeline_name::TEXT)
            WHEN $5 THEN w.pipeline_name
            ELSE substring(...)
        END
    END AS pipeline_name,
    w.status AS workflow_status
FROM wrk_workflowdata w
WHERE
    w.category != $13 AND
    w.launch_time > NOW() - make_interval(days := numDays) AND
    w.status != $14 AND
    w.pipeline_name NOT LIKE $15
ORDER BY w.id, w.launch_time DESC
```

**Issues:**
- Complex string manipulation in SELECT (xs_lastposition, substring)
- Date range filter: `launch_time > NOW() - make_interval(days := numDays)`

**Existing Indexes on wrk_workflowdata:**
```
✅ wrk_workflowdata_launch_time_btree (launch_time)
✅ wrk_workflowdata_category_btree (category)
✅ wrk_workflowdata_status_btree (status)
✅ wrk_workflowdata_pipeline_name_btree (pipeline_name)
```

**Recommendation:**
- Consider composite index for common filter combinations:
  ```sql
  CREATE INDEX idx_wrk_workflowdata_filters
  ON wrk_workflowdata(category, status, launch_time DESC, pipeline_name)
  WHERE category != 'system' AND status != 'Complete';
  ```
- Move string manipulation to application code (compute once, not per query)

**Expected Improvement:** 30-40% faster (51ms → 30-35ms)

---

### 5. Project Data Insert - 45ms avg

**Stats:**
- Calls: 1
- Time: 45.38ms

**Query:**
```sql
SELECT i_xnat_projectData($1,$2,$3,$4,$5)
```

**Analysis:**
- Database function for inserting project data
- Only called once (during setup)
- Not a performance concern for read operations

---

### 6-7. Element Access Count Queries - 29-37ms avg

**Stats:**
- Calls: 4 each
- Average: 28.95-36.82ms
- Total: 263ms combined

**Query:**
```sql
SELECT xea.element_name, SUM(expts.SUM) AS ELEMENT_COUNT
FROM xdat_element_access xea
LEFT JOIN ...
```

**Recommendation:**
- Cache element access counts (rarely change)
- Update cache on element access changes
- Potential 90% reduction in query frequency

---

### 8. Workflow Time Bucket Query - 26ms avg

**Stats:**
- Calls: 1
- Time: 26.00ms

**Query:**
```sql
SELECT
    date_trunc($2, w.launch_time) AS bucket,
    COUNT(*) AS total
FROM wrk_workflowdata w
LEFT JOIN xnat_experimentdata expt ON expt.id = w.id
LEFT JOIN xnat_subjectassessordata assessor ON assessor.id = w.id
LEFT JOIN xnat_subjectdata subj ON subj.id = assessor.subject_id
WHERE $3=$4
  AND w.launch_time >= NOW() - ($1 || $5)::interval
GROUP BY bucket
ORDER BY bucket
```

**Issues:**
- Same LEFT JOINs as query #3
- Used for dashboard time series charts

**Recommendation:**
- Apply same indexes as query #3
- Consider materialized view refreshed hourly

---

### 9-20. Faster Queries (< 15ms)

These queries are performing acceptably:
- User login history: 4-15ms
- Session lookups: 4-8ms
- Project searches with CTEs: 8-10ms
- User login inserts: 4.4ms

---

## Index Coverage Analysis

### Well-Indexed Tables ✅

**wrk_workflowdata** - 15 total indexes (excellent coverage)
- Primary key, id, status, category, launch_time, pipeline_name, etc.
- No additional indexes needed

### Tables Needing Indexes ⚠️

Based on query analysis and JOIN patterns:

**xnat_experimentdata**
```sql
-- Missing: Composite index for JOIN + SELECT columns
CREATE INDEX idx_xnat_experimentdata_id_project
ON xnat_experimentdata(id, project)
WHERE id IS NOT NULL;

CREATE INDEX idx_xnat_experimentdata_id_label
ON xnat_experimentdata(id, label)
WHERE id IS NOT NULL;
```

**xnat_subjectassessordata**
```sql
-- Missing: JOIN optimization
CREATE INDEX idx_xnat_subjectassessordata_id_subject
ON xnat_subjectassessordata(id, subject_id)
WHERE id IS NOT NULL;
```

**xnat_subjectdata**
```sql
-- Missing: Subject lookup optimization
CREATE INDEX idx_xnat_subjectdata_id_project
ON xnat_subjectdata(id, project)
WHERE id IS NOT NULL;

CREATE INDEX idx_xnat_subjectdata_id_label
ON xnat_subjectdata(id, label)
WHERE id IS NOT NULL;
```

**xhbm_container_entity_input** (from previous test)
```sql
-- Foreign key index (see TEST_RESULTS.md)
CREATE INDEX idx_container_entity_input_container_entity
ON xhbm_container_entity_input(container_entity);
```

---

## Recommendations by Priority

### High Priority (> 50ms avg)

1. **Investigate get_experiment_list() function** (144ms)
   - Review function code
   - Add indexes on tables used within function
   - Consider materialized view for common queries

2. **Optimize complex experiment DISTINCT ON query** (93ms)
   - Rewrite to use GROUP BY or EXISTS
   - Add early WHERE clause filters
   - Ensure all join columns indexed

3. **Create composite indexes for workflow queries** (89ms)
   - See index recommendations above
   - Test with `/xnat_misc/postgres-audit/03_automated_index_testing.sql`

### Medium Priority (20-50ms)

4. **Optimize workflow string manipulation query** (51ms)
   - Create composite index for filter columns
   - Move string operations to application code

5. **Cache element access counts** (29-37ms)
   - Reduce query frequency by 90%
   - Update cache on access changes

### Low Priority (< 20ms)

6. **Monitor user login queries** (4-15ms)
   - Currently acceptable
   - Review if user base grows significantly

---

## Testing Methodology

### Test Execution
```bash
cd /Users/james/projects/xnat_test_suites
./gradlew test
# 134 tests completed, 123 passed, 11 failed
```

### Query Analysis
```sql
-- Enable query logging (done)
CREATE EXTENSION pg_stat_statements;

-- View top slowest queries
SELECT
    calls,
    ROUND(total_exec_time::numeric, 2) as total_time_ms,
    ROUND(mean_exec_time::numeric, 2) as avg_time_ms,
    query
FROM pg_stat_statements
WHERE query NOT LIKE '%pg_stat_statements%'
ORDER BY mean_exec_time DESC
LIMIT 20;
```

---

## Next Steps

### Immediate Actions

1. **Apply recommended indexes** (30 minutes)
   ```bash
   cd /Users/james/projects/xnat_misc/query-optimize
   psql -h localhost -U postgres -d xnat -f scripts/recommended-indexes.sql
   ```

2. **Run automated index tests** (1 hour)
   ```bash
   cd /Users/james/projects/xnat_misc/postgres-audit
   psql -h localhost -U postgres -d xnat -f 03_automated_index_testing.sql
   ```

3. **Re-run test suite and measure improvement** (5 minutes)
   ```bash
   cd /Users/james/projects/xnat_test_suites
   ./gradlew test

   # Check new query stats
   docker exec xnat-db psql -U postgres -d xnat -c "SELECT pg_stat_statements_reset();"
   ./gradlew test
   docker exec xnat-db psql -U postgres -d xnat -f query_stats.sql
   ```

### Long-Term Improvements

4. **Review get_experiment_list() function** (2-4 hours)
   - Decompile function
   - Identify internal queries
   - Add appropriate indexes

5. **Implement caching strategy** (4-8 hours)
   - Element access counts
   - Dashboard time series data
   - User session data

6. **Query rewrite project** (1-2 days)
   - Complex DISTINCT ON queries
   - String manipulation in SELECT clauses
   - Dynamic WHERE clause patterns

---

## Performance Goals

| Query Type | Current Avg | Target Avg | Expected Improvement |
|------------|-------------|------------|---------------------|
| Experiment list | 93-144ms | 30-50ms | 60-70% |
| Workflow queries | 51-89ms | 20-35ms | 50-60% |
| Element access | 29-37ms | 5-10ms | 80% (via caching) |

**Overall Target:** Reduce P95 query time from 144ms to < 50ms

---

## Tools and Scripts

### Query Logging
- **Location:** xnat-db PostgreSQL container
- **Extension:** pg_stat_statements (enabled)
- **Configuration:** `/var/lib/postgresql/data/postgresql.conf`

### Audit Scripts
- **Location:** `/Users/james/projects/xnat_misc/postgres-audit/`
- **Key Scripts:**
  - `01_database_audit.sql` - 12-section comprehensive analysis
  - `02_generate_recommendations.sql` - Auto-generate optimization SQL
  - `03_automated_index_testing.sql` - A/B testing framework

### Optimization Scripts
- **Location:** `/Users/james/projects/xnat_misc/query-optimize/`
- **Key Scripts:**
  - `scripts/recommended-indexes.sql` - Indexes for workflow query
  - `scripts/workflow-query-optimized.sql` - CTE-based rewrite
  - `scripts/00_run_all_optimizations.sql` - Master execution script

---

## Query Statistics Raw Data

```
 calls | total_time_ms | avg_time_ms | query_preview
-------+---------------+-------------+--------------------------------------------------
     7 |       1008.35 |      144.05 | SELECT * FROM get_experiment_list($1)
     7 |        651.89 |       93.13 | SELECT * FROM (SELECT DISTINCT ON (expt.id) ...
     3 |        267.52 |       89.17 | SELECT w.wrk_workflowdata_id AS workflow_pk ...
     7 |        356.50 |       50.93 | SELECT DISTINCT ON (w.id) w.id AS workflow_id...
     1 |         45.38 |       45.38 | SELECT i_xnat_projectData($1,$2,$3,$4,$5)
     4 |        147.29 |       36.82 | SELECT xea.element_name, SUM(expts.SUM) ...
     4 |        115.81 |       28.95 | SELECT xea.element_name, SUM(expts.SUM) ...
     1 |         26.00 |       26.00 | SELECT date_trunc($2, w.launch_time) AS bucket...
     3 |         45.36 |       15.12 | SELECT l.xdat_user_login_id, l.login_date ...
     1 |         14.75 |       14.75 | SELECT date_trunc($2, l.login_date) AS bucket...
```

---

**Report Generated:** 2025-11-12
**Author:** XNAT Database Performance Analysis
**Status:** Ready for Implementation
