#!/bin/bash
# Complete PostgreSQL Index Analysis and Testing
# Runs all tests and stores results in date-based folder
# Usage: ./run_complete_analysis.sh

set -e  # Exit on error

# Configuration
DATE=$(date +%Y-%m-%d)
TIME=$(date +%H-%M-%S)
RESULTS_DIR="results/${DATE}-${TIME}"
DB_HOST="localhost"
DB_USER="postgres"
DB_NAME="xnat"
DOCKER_CONTAINER="xnat-db"

echo "========================================="
echo "PostgreSQL Complete Index Analysis"
echo "========================================="
echo "Date: $DATE"
echo "Time: $TIME"
echo "Results will be saved to: $RESULTS_DIR"
echo ""

# Create results directory
mkdir -p "$RESULTS_DIR"

echo "Step 1: Running database audit..."
docker exec $DOCKER_CONTAINER psql -U $DB_USER -d $DB_NAME -f /tmp/01_database_audit.sql > "$RESULTS_DIR/01_audit_report.txt" 2>&1
echo "✓ Audit complete"

echo ""
echo "Step 2: Generating recommendations..."
docker exec $DOCKER_CONTAINER psql -U $DB_USER -d $DB_NAME -f /tmp/02_generate_recommendations.sql > "$RESULTS_DIR/02_recommendations.sql" 2>&1
echo "✓ Recommendations generated"

echo ""
echo "Step 3: Testing FK indexes (20 indexes, ~2 min)..."
docker exec $DOCKER_CONTAINER psql -U $DB_USER -d $DB_NAME -f /tmp/test_all_fk_simple.sql > "$RESULTS_DIR/03_fk_test_results.log" 2>&1
echo "✓ FK tests complete"

echo ""
echo "Step 4: Testing non-FK indexes (4 indexes, ~30 sec)..."
docker exec $DOCKER_CONTAINER psql -U $DB_USER -d $DB_NAME -f /tmp/test_non_fk_indexes.sql > "$RESULTS_DIR/04_non_fk_test_results.log" 2>&1
echo "✓ Non-FK tests complete"

echo ""
echo "Step 5: Testing schema-based indexes (7 indexes, ~1 min)..."
docker exec $DOCKER_CONTAINER psql -U $DB_USER -d $DB_NAME -f /tmp/test_schema_indexes.sql > "$RESULTS_DIR/05_schema_test_results.log" 2>&1
echo "✓ Schema tests complete"

echo ""
echo "Step 6: Extracting test results from database..."
docker exec $DOCKER_CONTAINER psql -U $DB_USER -d $DB_NAME -c "
COPY (
    SELECT
        test_timestamp,
        table_name,
        index_name,
        test_phase,
        execution_time_ms,
        decision,
        improvement_percent,
        notes
    FROM pg_index_test_log
    ORDER BY test_id
) TO STDOUT CSV HEADER
" > "$RESULTS_DIR/06_test_results.csv" 2>&1
echo "✓ Results exported to CSV"

echo ""
echo "Step 7: Generating summary statistics..."
docker exec $DOCKER_CONTAINER psql -U $DB_USER -d $DB_NAME -c "
SELECT
    COUNT(DISTINCT table_name) as tables_tested,
    COUNT(DISTINCT index_name) FILTER (WHERE test_phase = 'decision') as indexes_tested,
    COUNT(*) FILTER (WHERE decision = 'KEEP') as indexes_kept,
    COUNT(*) FILTER (WHERE decision = 'ROLLBACK') as indexes_rolled_back,
    ROUND(AVG(improvement_percent) FILTER (WHERE decision = 'KEEP'), 2) as avg_improvement_pct,
    ROUND(MAX(improvement_percent), 2) as max_improvement_pct
FROM pg_index_test_log
WHERE test_phase = 'decision';
" > "$RESULTS_DIR/07_summary_stats.txt" 2>&1
echo "✓ Summary generated"

echo ""
echo "Step 8: Generating production SQL scripts..."

# FK indexes
echo "-- FK Indexes (from test results)" > "$RESULTS_DIR/08_production_fk_indexes.sql"
docker exec $DOCKER_CONTAINER psql -U $DB_USER -d $DB_NAME -t -c "
SELECT DISTINCT
    'CREATE INDEX IF NOT EXISTS ' ||
    REPLACE(index_name, 'idx_test_', 'idx_') ||
    ' ON ' || table_name || '(...);  -- ' ||
    ROUND(improvement_percent, 2) || '% improvement'
FROM pg_index_test_log
WHERE decision = 'KEEP'
  AND index_name LIKE 'idx_test_fk_%'
ORDER BY improvement_percent DESC;
" >> "$RESULTS_DIR/08_production_fk_indexes.sql" 2>&1

# Non-FK indexes
echo "-- Non-FK Indexes (from test results)" > "$RESULTS_DIR/09_production_non_fk_indexes.sql"
docker exec $DOCKER_CONTAINER psql -U $DB_USER -d $DB_NAME -t -c "
SELECT DISTINCT
    'CREATE INDEX IF NOT EXISTS ' ||
    REPLACE(index_name, 'idx_test_', 'idx_') ||
    ' ON ' || table_name || '(...);  -- ' ||
    ROUND(improvement_percent, 2) || '% improvement (' || notes || ')'
FROM pg_index_test_log
WHERE decision = 'KEEP'
  AND index_name NOT LIKE 'idx_test_fk_%'
ORDER BY improvement_percent DESC;
" >> "$RESULTS_DIR/09_production_non_fk_indexes.sql" 2>&1

echo "✓ Production scripts generated"

echo ""
echo "Step 9: Creating summary report..."
cat > "$RESULTS_DIR/00_README.md" <<EOF
# PostgreSQL Index Analysis Results

**Date:** $DATE $TIME
**Database:** $DB_NAME
**Duration:** ~5 minutes

## Summary

$(cat "$RESULTS_DIR/07_summary_stats.txt")

## Files Generated

1. **01_audit_report.txt** - Complete 12-section database audit
2. **02_recommendations.sql** - Auto-generated optimization SQL
3. **03_fk_test_results.log** - FK index A/B test results
4. **04_non_fk_test_results.log** - Non-FK index test results
5. **05_schema_test_results.log** - Schema-based index test results
6. **06_test_results.csv** - All test data in CSV format
7. **07_summary_stats.txt** - Statistical summary
8. **08_production_fk_indexes.sql** - FK indexes ready to deploy
9. **09_production_non_fk_indexes.sql** - Non-FK indexes ready to deploy

## Next Steps

1. Review test results in CSV or log files
2. Deploy proven indexes using production SQL scripts
3. Monitor performance after deployment
4. Re-run analysis in 1 week to identify new opportunities

## Quick Deploy

\`\`\`bash
# Deploy all proven indexes
psql -h $DB_HOST -U $DB_USER -d $DB_NAME -f 08_production_fk_indexes.sql
psql -h $DB_HOST -U $DB_USER -d $DB_NAME -f 09_production_non_fk_indexes.sql
\`\`\`

---

Generated by: run_complete_analysis.sh
EOF

echo "✓ Summary report created"

echo ""
echo "========================================="
echo "Analysis Complete!"
echo "========================================="
echo ""
echo "Results saved to: $RESULTS_DIR"
echo ""
echo "Summary:"
cat "$RESULTS_DIR/07_summary_stats.txt"
echo ""
echo "To view results:"
echo "  cd $RESULTS_DIR"
echo "  cat 00_README.md"
echo ""
echo "To deploy indexes:"
echo "  psql -h $DB_HOST -U $DB_USER -d $DB_NAME -f $RESULTS_DIR/08_production_fk_indexes.sql"
echo "  psql -h $DB_HOST -U $DB_USER -d $DB_NAME -f $RESULTS_DIR/09_production_non_fk_indexes.sql"
echo ""
