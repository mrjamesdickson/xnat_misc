# XNAT Workflow Query Optimization - Complete Package

**Purpose:** Optimize XNAT workflow queries for 10x better performance
**Impact:** Reduce query time from 1500ms to 150ms
**Risk:** Low - reversible, well-documented
**Time:** 30 minutes to implement Phase 1

---

## Start Here

### 🚀 Quick Start (Choose One Path)

#### Path 1: Executive/Manager
👉 Read **[EXECUTIVE_SUMMARY.md](EXECUTIVE_SUMMARY.md)**
- Business case and ROI
- 3-phase implementation plan
- Resource requirements
- Risk assessment

#### Path 2: DBA/DevOps (Just Do It)
👉 Run **[scripts/00_run_all_optimizations.sql](scripts/00_run_all_optimizations.sql)**
```bash
cd query-optimize
psql -U xnat -d xnat -f scripts/00_run_all_optimizations.sql
```
- One command, ~5 minutes
- Creates all indexes
- 3-4x faster queries immediately

#### Path 3: Developer (I Need Details)
👉 Read **[README.md](README.md)** → **[scripts/README_SCRIPTS.md](scripts/README_SCRIPTS.md)**
- Complete technical documentation
- Understanding the problem
- How the solution works
- Code examples

#### Path 4: Command Line Power User
👉 Use **[QUICK_REFERENCE.md](QUICK_REFERENCE.md)**
- Quick commands cheat sheet
- Decision tree
- Troubleshooting guide
- One-liners

---

## Documentation Structure

```
query-optimize/
├── INDEX.md (you are here) ⭐ Start here
├── EXECUTIVE_SUMMARY.md    📊 Business case, ROI, implementation plan
├── QUICK_REFERENCE.md      ⚡ Quick start, cheat sheet, troubleshooting
├── README.md               📚 Complete technical documentation
└── scripts/                🔧 SQL implementation scripts
    ├── README_SCRIPTS.md          Script documentation
    ├── 00_run_all_optimizations.sql   Master script (run this!)
    ├── 99_rollback.sql                 Rollback script
    ├── recommended-indexes.sql         Index creation
    ├── workflow-query-optimized.sql    Improved query
    ├── workflow-query-original.sql     Original query
    ├── schema-wrk_workflowdata.sql     Table schema
    └── performance-test.sql            Benchmarking
```

---

## Document Quick Reference

### EXECUTIVE_SUMMARY.md
**Who:** Managers, DBAs making decisions
**What:** Business case for optimization
**Contains:**
- Problem statement with metrics
- 3-phase implementation plan
- Risk assessment
- ROI calculation
- Resource requirements
- Success criteria

### README.md
**Who:** Technical implementers
**What:** Complete technical guide
**Contains:**
- Problem analysis
- Index recommendations (prioritized)
- Query optimization strategies
- Performance benchmarks
- Monitoring and maintenance
- Best practices

### QUICK_REFERENCE.md
**Who:** Anyone needing fast answers
**What:** Cheat sheet and quick start
**Contains:**
- TL;DR commands
- File guide
- Command cheat sheet
- Decision tree
- Troubleshooting
- Priority matrix

### scripts/README_SCRIPTS.md
**Who:** Users running SQL scripts
**What:** Script execution guide
**Contains:**
- Script inventory
- Execution order
- Usage examples
- Safety notes
- Troubleshooting
- Monitoring queries

---

## Implementation Workflows

### Workflow 1: Fastest (5 minutes)
For: "Just make it faster"
```bash
cd query-optimize
psql -U xnat -d xnat -f scripts/00_run_all_optimizations.sql
# Done! 3-4x faster
```

### Workflow 2: Cautious (30 minutes)
For: "I want to understand first"
```bash
# 1. Read executive summary
cat EXECUTIVE_SUMMARY.md | less

# 2. Review scripts
cat scripts/00_run_all_optimizations.sql

# 3. Run with monitoring
psql -U xnat -d xnat -f scripts/00_run_all_optimizations.sql

# 4. Verify
psql -U xnat -d xnat -f scripts/performance-test.sql
```

### Workflow 3: Complete (2-4 hours)
For: "I'm doing this properly"
```bash
# Phase 1: Indexes (30 min)
1. Read EXECUTIVE_SUMMARY.md
2. Read README.md
3. Run scripts/00_run_all_optimizations.sql
4. Run scripts/performance-test.sql
5. Document baseline metrics
6. Monitor for issues (1 day)

# Phase 2: Query Optimization (2-4 hours)
7. Review scripts/workflow-query-optimized.sql
8. Update application code
9. Test thoroughly
10. Deploy and monitor
```

---

## Key Files by Use Case

### "I need to show this to my boss"
📄 EXECUTIVE_SUMMARY.md

### "I need to run this now"
🔧 scripts/00_run_all_optimizations.sql

### "I need to understand the problem"
📚 README.md → Problem Statement section

### "I need to test if it worked"
🧪 scripts/performance-test.sql

### "I need to undo this"
↩️ scripts/99_rollback.sql

### "I need quick commands"
⚡ QUICK_REFERENCE.md

### "I need to understand the schema"
📋 scripts/schema-wrk_workflowdata.sql

### "I need the new query code"
💻 scripts/workflow-query-optimized.sql

---

## Expected Results

### Phase 1: Index Creation (5 minutes)
**Before:**
- Query time: 1500-2000ms
- Full table scans
- Nested loop joins

**After:**
- Query time: 300-500ms
- Index scans
- Hash joins
- **3-4x faster** ✅

### Phase 2: Query Optimization (2-4 hours)
**After Phase 1 + Phase 2:**
- Query time: 150-200ms
- Efficient CTEs
- Better query plan
- **10x faster total** ✅

---

## Safety Checklist

Before running optimization:
- [ ] Read EXECUTIVE_SUMMARY.md or README.md
- [ ] Have database backup (or verify automatic backups)
- [ ] Check disk space (need ~100MB free)
- [ ] Verify database credentials
- [ ] Review scripts/00_run_all_optimizations.sql
- [ ] Know how to rollback (scripts/99_rollback.sql)
- [ ] Plan low-usage time window (optional but recommended)

✅ Safe to proceed if all checked

---

## Success Criteria

You'll know it worked when:
- ✅ All 6 indexes created without errors
- ✅ Query execution time < 500ms (Phase 1)
- ✅ Query execution time < 200ms (Phase 1 + Phase 2)
- ✅ No increase in error rates
- ✅ No user-visible changes in behavior
- ✅ Index usage statistics show scans > 1000/day

---

## Support & Resources

### Getting Help
1. Check QUICK_REFERENCE.md → Troubleshooting section
2. Check scripts/README_SCRIPTS.md → Troubleshooting
3. Check README.md → Monitoring section
4. Review EXECUTIVE_SUMMARY.md → Risk Assessment

### Rollback
If anything goes wrong:
```bash
psql -U xnat -d xnat -f scripts/99_rollback.sql
```

### Verification
After running optimization:
```sql
-- Check indexes exist
\d xnat_imageassessordata

-- Verify usage
SELECT * FROM pg_stat_user_indexes WHERE indexname LIKE 'idx_%';

-- Test query performance
EXPLAIN (ANALYZE) SELECT ...
```

---

## Summary

| Document | Purpose | Time to Read | Action Required |
|----------|---------|--------------|-----------------|
| INDEX.md (this file) | Navigate the package | 5 min | Choose your path |
| EXECUTIVE_SUMMARY.md | Business case | 10 min | Get approval |
| QUICK_REFERENCE.md | Quick start | 2 min | Execute commands |
| README.md | Technical details | 20 min | Understand solution |
| scripts/00_run_all_optimizations.sql | Execute optimization | 5 min | Run it |
| scripts/99_rollback.sql | Undo changes | 2 min | Safety net |

**Total time investment:** 30 minutes reading + 5 minutes executing = 35 minutes
**Expected benefit:** 10x faster queries forever

---

## Next Steps

1. **Read** EXECUTIVE_SUMMARY.md (if showing to management)
   OR **Read** QUICK_REFERENCE.md (if implementing now)

2. **Run** scripts/00_run_all_optimizations.sql

3. **Verify** with scripts/performance-test.sql

4. **Monitor** for 1-2 days

5. **Plan** Phase 2 (query optimization) if Phase 1 successful

---

**Version:** 1.0
**Created:** 2025-11-12
**PostgreSQL:** 12+
**XNAT:** 1.8+
**Status:** Production Ready ✅
