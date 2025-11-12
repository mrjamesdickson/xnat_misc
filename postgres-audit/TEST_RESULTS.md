# XNAT Database Index Test Results

**Date:** 2025-11-12
**Database:** xnat (PostgreSQL 16.9)
**Table:** xhbm_container_entity_input
**Rows:** 122,564
**Table Size:** 10 MB

---

## Test Summary

### Index Tested
- **Index Name:** `idx_container_entity_input_container_entity`
- **Column:** `container_entity`
- **Index Size:** 1.2 MB
- **Reason:** Foreign key without index

---

## Performance Results

### Test Query
```sql
SELECT * FROM xhbm_container_entity_input
WHERE container_entity IS NOT NULL
LIMIT 1000;
```

### Baseline (No Index)
**Note:** We don't have baseline measurements because the test output was truncated,
but we can see the WITH-index performance below.

### With Index
| Run | Execution Time | Query Plan |
|-----|----------------|------------|
| 1 | 30.3 ms | Sequential Scan |
| 2 | 30.4 ms | Sequential Scan |
| 3 | 31.7 ms | Sequential Scan |
| **Average** | **30.8 ms** | - |

---

## Analysis

### ⚠️ Index NOT Being Used

**Why:**
The query `WHERE container_entity IS NOT NULL` matches nearly all rows in the table (122,564 rows), so PostgreSQL's query planner correctly chose **Sequential Scan** as more efficient than an index scan.

**Query Plan shows:**
```
Seq Scan on xhbm_container_entity_input
  Filter: (container_entity IS NOT NULL)
  Buffers: shared hit=11
```

### When Would This Index Help?

This index WOULD be beneficial for:

1. **JOIN operations:**
```sql
SELECT * FROM xhbm_container_entity_input i
JOIN xhbm_container_entity e ON i.container_entity = e.xhbm_container_entity_id
WHERE e.status = 'RUNNING';
```

2. **Selective WHERE clauses:**
```sql
SELECT * FROM xhbm_container_entity_input
WHERE container_entity = 12345;  -- Specific value
```

3. **Foreign key constraint enforcement:**
   - Prevents locking issues during DELETE/UPDATE on parent table
   - Improves referential integrity check performance

---

## Recommendation

### ✅ **KEEP THE INDEX**

**Reasoning:**

1. **Foreign Key Performance**
   - Even though our test query doesn't use it, this index is critical for foreign key operations
   - Without it, deletes/updates on `xhbm_container_entity` table will cause table scans
   - Prevents lock contention on the parent table

2. **JOIN Performance**
   - Container queries likely join to parent `xhbm_container_entity` table
   - Index will significantly speed up these joins

3. **Small Size**
   - Only 1.2 MB (very small overhead)
   - Minimal impact on write performance

4. **Best Practice**
   - Standard database optimization: **ALWAYS index foreign keys**
   - PostgreSQL doesn't automatically index foreign keys (unlike some other databases)

### Better Test Query

To see the actual benefit, we should test with a JOIN:

```sql
-- This would show significant improvement
EXPLAIN (ANALYZE, BUFFERS)
SELECT i.*, e.*
FROM xhbm_container_entity_input i
JOIN xhbm_container_entity e
  ON i.container_entity = e.xhbm_container_entity_id
LIMIT 1000;
```

---

## Decision

**Status:** ✅ **INDEX KEPT**

**Action Taken:**
```sql
-- Index already exists, no further action needed
-- idx_container_entity_input_container_entity (1.2 MB)
```

**Log Update:**
```sql
UPDATE pg_index_test_log
SET decision = 'KEEP',
    notes = 'Foreign key index - critical for FK operations and JOINs even though not used by simple WHERE IS NOT NULL query'
WHERE index_name = 'idx_container_entity_input_container_entity'
  AND test_phase = 'with_index';
```

---

## Lessons Learned

### Test Query Selection Matters

1. **Bad test query:** `WHERE foreign_key_column IS NOT NULL` (returns most rows)
2. **Good test queries:**
   - `WHERE foreign_key_column = specific_value` (selective)
   - `JOIN parent_table ON foreign_key_column = parent.id` (common use case)
   - `DELETE FROM parent_table WHERE id = X` (FK constraint check)

### Foreign Key Indexes Are Special

Unlike regular indexes, foreign key indexes provide benefits even when not used in SELECT queries:
- Prevent full table scans during parent DELETE/UPDATE
- Avoid long-running locks on child tables
- Improve referential integrity performance
- Standard best practice in all relational databases

---

## Next Steps

### Recommended: Test Other Foreign Keys

Based on our earlier scan, these tables also have foreign keys without indexes:

| Table | Column | Rows | Size | Priority |
|-------|--------|------|------|----------|
| xhbm_container_entity_history | container_entity | 96,133 | 12 MB | High |
| xhbm_container_entity | parent_container_entity | 14,682 | 5.8 MB | Medium |
| xhbm_container_entity_mount | container_entity | 27,953 | 5 MB | Medium |
| xhbm_container_entity_output | container_entity | 16,326 | 2.4 MB | Medium |

### Command to Create All Recommended Indexes

```sql
-- These should all be created (standard best practice)
CREATE INDEX idx_container_entity_history_ce ON xhbm_container_entity_history(container_entity);
CREATE INDEX idx_container_entity_parent ON xhbm_container_entity(parent_container_entity);
CREATE INDEX idx_container_entity_mount_ce ON xhbm_container_entity_mount(container_entity);
CREATE INDEX idx_container_entity_output_ce ON xhbm_container_entity_output(container_entity);

-- Update statistics
ANALYZE xhbm_container_entity_history;
ANALYZE xhbm_container_entity;
ANALYZE xhbm_container_entity_mount;
ANALYZE xhbm_container_entity_output;
```

**Total additional space needed:** ~5-10 MB
**Expected benefit:** Improved container operations, reduced locking, faster deletes/updates

---

## Conclusion

The test successfully demonstrated:
1. ✅ How to create and test an index
2. ✅ How to analyze query plans
3. ✅ Understanding when indexes are (and aren't) used
4. ✅ Why foreign key indexes are important beyond SELECT performance

**Final Result:** Index kept - correct decision for foreign key optimization.

---

**Test Log Location:** `pg_index_test_log` table in XNAT database
**Index Location:** XNAT database, public schema
**Production Ready:** Yes - safe to keep
