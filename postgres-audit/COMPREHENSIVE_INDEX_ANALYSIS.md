# Comprehensive Index Analysis

**Date:** 2025-11-12
**Source:** pg_stat_statements (live query data from E2E tests)
**Scope:** ALL slow queries > 5ms with > 3 calls

---

## Summary

**What we tested so far:** 20 foreign key indexes only
**What we found:** Many more optimization opportunities beyond foreign keys

###Current Status:
- ✅ Foreign keys tested: 20/20 (55.23% avg improvement)
- ⏳ Non-FK indexes tested: 0
- 📊 Additional candidates identified: 15+

---

## Query Categories Needing Indexes

### 1. History/Audit Tables (High Priority)

**xnat_imagesessiondata_history** - 1,087 calls, 99.86% seq scans
```sql
-- Query pattern:
SELECT * FROM xnat_imagesessiondata_history
WHERE id = $1 AND change_date IS NOT NULL AND change_date <= $2
ORDER BY change_date DESC;
```

**Recommendation:**
```sql
CREATE INDEX idx_imagesessiondata_history_id_date
ON xnat_imagesessiondata_history(id, change_date DESC);
```

**Expected improvement:** 70-90% (similar to other history tables)

---

### 2. Cache Tables (High Priority)

**xs_item_cache** - 234 calls, 99.99% seq scans, 0.98ms avg
```sql
-- Query pattern:
SELECT contents FROM xs_item_cache
WHERE elementName=$1 AND ids=$2;
```

**Recommendation:**
```sql
CREATE INDEX idx_item_cache_element_ids
ON xs_item_cache(elementName, ids);
```

**Expected improvement:** 60-80%

---

### 3. Authentication Tables (Medium Priority)

**xdat_user_login** - 12 calls, 67.65% seq scans, 6.02ms avg
```sql
-- Query pattern:
SELECT session_id, ip_address FROM xdat_user_login
WHERE session_id IN ($1,$2,$3,$4,$5,$6,$7,$8);

-- Also:
SELECT login_date FROM xdat_user_login
WHERE user_xdat_user_id=$1 AND login_date < (SELECT MAX(...))
ORDER BY login_date DESC;
```

**Recommendation:**
```sql
CREATE INDEX idx_user_login_session
ON xdat_user_login(session_id);

CREATE INDEX idx_user_login_user_date
ON xdat_user_login(user_xdat_user_id, login_date DESC);
```

**Expected improvement:** 40-60%

---

### 4. Experiment Queries (High Priority - CRITICAL)

**get_experiment_list()** - 9 calls, 144.57ms avg (SLOWEST!)

This is a function but the slow part is likely:
```sql
-- Inside get_experiment_list():
SELECT * FROM (
    SELECT DISTINCT ON (expt.id)
        expt.id, perm.label, perm.project, expt.date,
        emd.status, W.workflow_status, xme.element_name, ...
    FROM xnat_experimentData expt
        LEFT JOIN xdat_meta_element xme ON expt.extension = xme.xdat_meta_element_id
        LEFT JOIN xnat_experimentData_meta_data emd ON expt.experimentData_info = emd.meta_data_id
        LEFT JOIN xdat_element_security es ON xme.element_name = es.element_name
        LEFT JOIN get_open_workflows(numDays) W ON expt.id = W.workflow_id
        RIGHT JOIN get_accessible_image_sessions(username) perm ON expt.id = perm.id
        RIGHT JOIN xnat_imageSessionData isd ON perm.id = isd.id
    WHERE emd.status != $22
      AND (emd.insert_date > idleInterval
       OR emd.activation_date > idleInterval
       OR emd.last_modified > idleInterval
       OR W.workflow_date > idleInterval)
) SEARCH
ORDER BY SEARCH.action_date DESC
LIMIT numResults;
```

**Problem:** Multiple LEFT/RIGHT JOINs without proper indexes

**Recommendations:**
```sql
-- Composite indexes for JOIN optimization
CREATE INDEX idx_experimentdata_extension_id
ON xnat_experimentData(extension, id);

CREATE INDEX idx_meta_element_id_name
ON xdat_meta_element(xdat_meta_element_id, element_name);

CREATE INDEX idx_element_security_name
ON xdat_element_security(element_name);

-- Date filters (WHERE clause)
CREATE INDEX idx_experimentdata_meta_dates
ON xnat_experimentData_meta_data(status, insert_date DESC, activation_date DESC, last_modified DESC);
```

**Expected improvement:** 50-70% (144ms → 40-60ms)

---

### 5. Element Access Queries (Medium Priority)

**Complex permission queries** - 8 calls, 26-57ms avg

```sql
-- Pattern involves multiple tables:
SELECT xea.element_name, SUM(expts.SUM) AS ELEMENT_COUNT
FROM xdat_element_access xea
    LEFT JOIN xdat_usergroup grp ON xea.xdat_usergroup_xdat_usergroup_id = grp.xdat_usergroup_id
    LEFT JOIN xdat_user_groupid gid ON grp.id = gid.groupid
    LEFT JOIN xdat_field_mapping_set fms ON xea.xdat_element_access_id = fms.permissions_allow_set_xdat_elem_xdat_element_access_id
    LEFT JOIN xdat_field_mapping xfm ON fms.xdat_field_mapping_set_id = xfm.xdat_field_mapping_set_xdat_field_mapping_set_id
-- Complex joins and aggregations
```

**Recommendations:**
```sql
CREATE INDEX idx_element_access_usergroup
ON xdat_element_access(xdat_usergroup_xdat_usergroup_id, element_name);

CREATE INDEX idx_user_groupid_composite
ON xdat_user_groupid(groupid, groups_groupid_xdat_user_xdat_user_id);

CREATE INDEX idx_field_mapping_set_composite
ON xdat_field_mapping_set(permissions_allow_set_xdat_elem_xdat_element_access_id, xdat_field_mapping_set_id);
```

**Expected improvement:** 30-50%

---

### 6. Project Data Queries (Medium Priority)

**Complex CTE queries** - 19 calls, 8-18ms avg

```sql
WITH S_xnat_projectData AS (...)
SELECT ... FROM S_xnat_projectData xnat_projectData
    LEFT JOIN xnat_projectData_meta_data table10 ON xnat_projectData.projectData_info=table10.meta_data_id
    LEFT JOIN xnat_investigatorData table20 ON xnat_projectData.pi_xnat_investigatordata_id=table20.xnat_investigatordata_id
    -- More joins...
WHERE ...
ORDER BY ...
```

**Recommendations:**
```sql
CREATE INDEX idx_projectdata_meta_status
ON xnat_projectData_meta_data(meta_data_id, status, insert_date);

CREATE INDEX idx_projectdata_investigator
ON xnat_projectData(pi_xnat_investigatordata_id, id);
```

**Expected improvement:** 20-40%

---

## Complete Testing Plan

### Phase 1: Critical (Do First)
1. ✅ **Foreign keys** (DONE - 55% improvement)
2. **Experiment list function** (144ms → 40-60ms target)
3. **History tables** (xnat_imagesessiondata_history)
4. **Cache tables** (xs_item_cache)

### Phase 2: High Value
5. **Authentication** (xdat_user_login - session_id, user_date)
6. **Element access** (permission check optimization)

### Phase 3: Incremental
7. **Project data** (CTE optimization)
8. **Workflow queries** (already fast, but can improve)

---

## Testing Script Status

| Script | Status | Coverage |
|--------|--------|----------|
| test_all_fk_simple.sql | ✅ Complete | Foreign keys only |
| test_non_fk_indexes.sql | ⏳ Ready | 4 non-FK candidates |
| **NEEDED:** test_experiment_indexes.sql | ❌ Not created | Experiment optimization |
| **NEEDED:** test_all_candidates.sql | ❌ Not created | Comprehensive (all above) |

---

## Implementation Strategy

**Option A: Incremental (Recommended)**
1. Apply FK indexes now (ready to run)
2. Test non-FK candidates (4 indexes)
3. Apply proven non-FK indexes
4. Attack experiment function (complex, needs analysis)
5. Monitor and iterate

**Option B: Comprehensive**
1. Create master testing script for ALL candidates
2. Run overnight (may take 1-2 hours)
3. Review results
4. Apply all proven indexes at once

---

## Expected Total Impact

**Foreign Keys (Done):**
- 20 indexes
- 55.23% avg improvement
- ~10-15 MB disk space

**Non-FK Candidates (Estimated):**
- 15+ indexes
- 40-60% avg improvement
- ~20-30 MB disk space

**Combined:**
- 35+ total indexes
- 50%+ overall query improvement
- ~30-45 MB total disk space
- **Massive** performance boost

---

## Next Steps

1. **Immediate:** Apply FK indexes (already tested, ready)
   ```bash
   psql -f create_fk_indexes.sql
   ```

2. **Today:** Test non-FK candidates
   ```bash
   psql -f test_non_fk_indexes.sql
   ```

3. **This Week:** Deep-dive experiment list optimization
   - Analyze get_experiment_list() function
   - Create targeted indexes
   - Test with real workload

4. **Monitor:** Track improvements
   ```sql
   SELECT * FROM pg_stat_statements WHERE mean_exec_time > 5 ORDER BY mean_exec_time DESC;
   ```

---

## Tools Available

- ✅ `01_database_audit.sql` - Comprehensive analysis
- ✅ `02_generate_recommendations.sql` - Auto-generate SQL
- ✅ `03_automated_index_testing.sql` - Full testing framework
- ✅ `test_all_fk_simple.sql` - FK testing (used)
- ✅ `test_non_fk_indexes.sql` - Non-FK testing (ready)
- ✅ `create_fk_indexes.sql` - Production FK script (ready)
- ⏳ Need: `create_non_fk_indexes.sql` (after testing)

---

**Bottom Line:**

**We've only scratched the surface.** FK indexes are just 20 out of 35+ needed indexes. Testing non-FK candidates will likely reveal another 40-60% average improvement opportunity.

**Total potential:** ~50-60% overall query performance improvement across the board.

---

**Generated:** 2025-11-12
**Status:** Analysis Complete, Testing Partially Done
**Next:** Run test_non_fk_indexes.sql
