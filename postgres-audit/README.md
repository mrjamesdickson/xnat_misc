# PostgreSQL Index Testing Suite

Comprehensive PostgreSQL index performance testing with automatic benchmarking, intelligent filtering, and production-ready recommendations.

## Features

- ✅ **Automated A/B Testing** - Compares query performance with and without indexes
- ✅ **Intelligent Filtering** - Only keeps indexes with ≥5% improvement
- ✅ **Multiple Test Strategies** - FK indexes, large tables, high-frequency queries, schema patterns
- ✅ **Production-Ready SQL** - Generates deployment scripts for proven indexes
- ✅ **Interactive HTML Reports** - Beautiful dashboard with drill-down details
- ✅ **Configurable Parameters** - Test 10-200+ tables based on your needs
- ✅ **Safe for Production** - Read-only analysis, automatically drops underperforming indexes
- ✅ **Complete Cleanup** - ALL test indexes are removed after analysis (zero database impact)

## Quick Start

```bash
# Run comprehensive analysis (tests ~20-30 tables, 5-10 minutes)
./run_complete_analysis.sh

# Quick test (10 tables, 5 minutes)
./run_complete_analysis.sh --max-large-tables 10 --max-queries 20

# Comprehensive test (200 tables, 30-60 minutes)
./run_complete_analysis.sh --max-large-tables 200 --max-queries 100
```

## Output Files

Results saved to `./results/YYYY-MM-DD-HH-MM-SS/`:

| File | Description |
|------|-------------|
| **index_test_report.html** | 📊 Interactive HTML dashboard (open in browser) |
| **00_README.md** | Summary report with recommendations |
| **08_production_fk_indexes.sql** | Production-ready FK indexes to deploy |
| **09_production_non_fk_indexes.sql** | Production-ready non-FK indexes to deploy |
| **07_summary_stats.txt** | Summary statistics and table list |
| **06_test_results.csv** | Machine-readable test data |
| 01-05_*.log | Detailed test output logs |

## Example Results

```
tables_tested | indexes_tested | indexes_kept | indexes_rolled_back | avg_improvement_pct
--------------+----------------+--------------+---------------------+--------------------
           29 |             38 |           28 |                  10 |               66.27

Tables Tested:
-------------
xdat_change_info                   | 2 indexes | 2 kept | 0 rolled | 98.43% avg
xhbm_dicom_spatial_data            | 2 indexes | 2 kept | 0 rolled | 88.06% avg
xdat_user_login                    | 3 indexes | 3 kept | 0 rolled | 60.38% avg
```

## Configuration

See [PARAMETERS.md](PARAMETERS.md) for complete documentation on all parameters.

### Common Options

```bash
# Database connection
./run_complete_analysis.sh --host localhost --database xnat --username postgres

# Test scope
./run_complete_analysis.sh --max-large-tables 50 --max-queries 100

# Skip tests
./run_complete_analysis.sh --skip-audit --skip-large-tables

# Custom output directory
./run_complete_analysis.sh --output /tmp/index-tests
```

## How It Works

1. **Audit Database** - Analyzes table sizes, row counts, sequential scans
2. **Identify Candidates** - Finds tables that need indexes based on activity
3. **Benchmark Tests** - For each candidate:
   - Run 5 queries WITHOUT index (baseline)
   - Create test index
   - Run 5 queries WITH index (test)
   - Calculate improvement percentage
   - Keep if ≥5% improvement, otherwise rollback
4. **Generate Reports** - Creates SQL scripts, CSV data, and interactive HTML dashboard
5. **Production Deploy** - Review and deploy proven indexes

## Interactive HTML Report

The HTML report provides:

- 📊 **Summary Cards** - Key metrics at a glance
- 📋 **Tables List** - All tested tables with results
- 🔍 **Drill-Down Details** - Click any table to see index details
- 🔎 **Filtering** - Search by table name, filter by status
- 📄 **SQL Preview** - Production-ready CREATE INDEX statements
- 🚀 **Quick Actions** - Links to deploy scripts and CSV data

**Open the report:**
```bash
open ./results/YYYY-MM-DD-HH-MM-SS/index_test_report.html
```

## Deployment

After reviewing results:

```bash
cd ./results/YYYY-MM-DD-HH-MM-SS

# Deploy FK indexes
psql -h localhost -U postgres -d xnat -f 08_production_fk_indexes.sql

# Deploy non-FK indexes
psql -h localhost -U postgres -d xnat -f 09_production_non_fk_indexes.sql

# Or deploy all at once
cat 08_production_fk_indexes.sql 09_production_non_fk_indexes.sql | psql -h localhost -U postgres -d xnat
```

## Best Practices

1. **Start small** - Test with `--max-large-tables 10` first
2. **Review before deploying** - Check HTML report and SQL scripts
3. **Test in dev first** - Deploy to development environment before production
4. **Monitor performance** - Track query times after deployment
5. **Re-run periodically** - Run monthly to catch workload changes

## Performance Impact

- **Read-only operations** - No data modification
- **Minimal overhead** - Mostly cached reads, low CPU/memory
- **Safe for production** - Can run during business hours
- **Duration** - 5-60 minutes depending on scope

## Requirements

- PostgreSQL 9.6+
- Docker (for containerized databases)
- bash, bc (for calculations)
- Modern web browser (for HTML reports)

## Troubleshooting

**"Only X tables tested instead of 200"**

Only tables meeting eligibility criteria are tested:
- Size > 1MB
- Sequential scans > 1
- Rows > 100

Check eligible tables:
```bash
docker exec xnat-db psql -U xnat -d xnat -c "
SELECT COUNT(*) FROM pg_stat_user_tables s
WHERE pg_total_relation_size(s.relid) > 1024*1024
  AND s.seq_scan > 1 AND s.n_live_tup > 100;"
```

To test smaller tables, modify `test_large_tables.sql` (see [PARAMETERS.md](PARAMETERS.md)).

## Files

- `run_complete_analysis.sh` - Main script
- `generate_html_report.sh` - HTML report generator
- `test_large_tables.sql` - Large table tests
- `test_query_based_indexes.sql` - Query-based tests
- `test_non_fk_indexes.sql` - Non-FK pattern tests
- `test_schema_indexes.sql` - Schema-based tests
- `PARAMETERS.md` - Complete parameter documentation

## License

MIT License - See LICENSE file for details

## Author

Generated for XNAT PostgreSQL optimization
