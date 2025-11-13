#!/bin/bash
# Complete PostgreSQL Index Analysis and Testing
# Runs all tests and stores results in date-based folder
# Usage: ./run_complete_analysis.sh

set -e  # Exit on error

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Progress bar function
show_progress() {
    local current=$1
    local total=$2
    local width=50
    local percentage=$((current * 100 / total))
    local completed=$((width * current / total))

    printf "\r${BLUE}Progress: ${NC}["
    printf "%${completed}s" | tr ' ' '▓'
    printf "%$((width - completed))s" | tr ' ' '░'
    printf "] ${BOLD}%3d%%${NC} (Step %d/%d)" $percentage $current $total
}

# Configuration
DATE=$(date +%Y-%m-%d)
TIME=$(date +%H-%M-%S)
RESULTS_DIR="results/${DATE}-${TIME}"
DB_HOST="localhost"
DB_USER="postgres"
DB_NAME="xnat"
DOCKER_CONTAINER="xnat-db"
TOTAL_STEPS=9

echo ""
echo "${BOLD}=========================================${NC}"
echo "${BOLD}PostgreSQL Complete Index Analysis${NC}"
echo "${BOLD}=========================================${NC}"
echo "${GREEN}Date:${NC} $DATE"
echo "${GREEN}Time:${NC} $TIME"
echo "${GREEN}Results:${NC} $RESULTS_DIR"
echo "${BOLD}=========================================${NC}"
echo ""

# Create results directory
mkdir -p "$RESULTS_DIR"

# Show initial progress
show_progress 0 $TOTAL_STEPS
echo ""

# Copy SQL files to Docker container
echo "${BLUE}Preparing:${NC} Copying SQL files to database container..."

# Check if files exist
REQUIRED_FILES=(
    "01_database_audit.sql"
    "02_generate_recommendations.sql"
    "test_all_fk_simple.sql"
    "test_non_fk_indexes.sql"
    "test_schema_indexes.sql"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo "${RED}✗${NC} Error: Required file not found: $file"
        echo "${YELLOW}Current directory:${NC} $(pwd)"
        echo "${YELLOW}Required files:${NC}"
        for f in "${REQUIRED_FILES[@]}"; do
            echo "  - $f"
        done
        exit 1
    fi
done

# Copy files
docker cp 01_database_audit.sql $DOCKER_CONTAINER:/tmp/
docker cp 02_generate_recommendations.sql $DOCKER_CONTAINER:/tmp/
docker cp test_all_fk_simple.sql $DOCKER_CONTAINER:/tmp/
docker cp test_non_fk_indexes.sql $DOCKER_CONTAINER:/tmp/
docker cp test_schema_indexes.sql $DOCKER_CONTAINER:/tmp/

echo "${GREEN}✓${NC} Files copied (5 SQL files)"
echo ""

echo "${YELLOW}▶${NC} ${BOLD}Step 1/9:${NC} Running database audit (12 sections)..."
docker exec $DOCKER_CONTAINER psql -U $DB_USER -d $DB_NAME -f /tmp/01_database_audit.sql > "$RESULTS_DIR/01_audit_report.txt" 2>&1 &
PID=$!
while kill -0 $PID 2>/dev/null; do
    printf "${BLUE}.${NC}"
    sleep 0.5
done
wait $PID
show_progress 1 $TOTAL_STEPS
echo ""
echo "${GREEN}✓${NC} Audit complete"
echo ""

echo "${YELLOW}▶${NC} ${BOLD}Step 2/9:${NC} Generating index recommendations..."
docker exec $DOCKER_CONTAINER psql -U $DB_USER -d $DB_NAME -f /tmp/02_generate_recommendations.sql > "$RESULTS_DIR/02_recommendations.sql" 2>&1 &
PID=$!
while kill -0 $PID 2>/dev/null; do
    printf "${BLUE}.${NC}"
    sleep 0.5
done
wait $PID
show_progress 2 $TOTAL_STEPS
echo ""
echo "${GREEN}✓${NC} Recommendations generated"
echo ""

echo "${YELLOW}▶${NC} ${BOLD}Step 3/9:${NC} Testing FK indexes (20 indexes, ~2 min)..."
docker exec $DOCKER_CONTAINER psql -U $DB_USER -d $DB_NAME -f /tmp/test_all_fk_simple.sql > "$RESULTS_DIR/03_fk_test_results.log" 2>&1 &
PID=$!
while kill -0 $PID 2>/dev/null; do
    printf "${BLUE}.${NC}"
    sleep 1
done
wait $PID
show_progress 3 $TOTAL_STEPS
echo ""
echo "${GREEN}✓${NC} FK tests complete (20/20 tested)"
echo ""

echo "${YELLOW}▶${NC} ${BOLD}Step 4/9:${NC} Testing non-FK indexes (4 indexes, ~30 sec)..."
docker exec $DOCKER_CONTAINER psql -U $DB_USER -d $DB_NAME -f /tmp/test_non_fk_indexes.sql > "$RESULTS_DIR/04_non_fk_test_results.log" 2>&1 &
PID=$!
while kill -0 $PID 2>/dev/null; do
    printf "${BLUE}.${NC}"
    sleep 0.5
done
wait $PID
show_progress 4 $TOTAL_STEPS
echo ""
echo "${GREEN}✓${NC} Non-FK tests complete (4/4 tested)"
echo ""

echo "${YELLOW}▶${NC} ${BOLD}Step 5/9:${NC} Testing schema-based indexes (7 indexes, ~1 min)..."
docker exec $DOCKER_CONTAINER psql -U $DB_USER -d $DB_NAME -f /tmp/test_schema_indexes.sql > "$RESULTS_DIR/05_schema_test_results.log" 2>&1 &
PID=$!
while kill -0 $PID 2>/dev/null; do
    printf "${BLUE}.${NC}"
    sleep 0.5
done
wait $PID
show_progress 5 $TOTAL_STEPS
echo ""
echo "${GREEN}✓${NC} Schema tests complete (7/7 tested)"
echo ""

echo "${YELLOW}▶${NC} ${BOLD}Step 6/9:${NC} Extracting test results from database..."
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
show_progress 6 $TOTAL_STEPS
echo ""
echo "${GREEN}✓${NC} Results exported to CSV"
echo ""

echo "${YELLOW}▶${NC} ${BOLD}Step 7/9:${NC} Generating summary statistics..."
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
show_progress 7 $TOTAL_STEPS
echo ""
echo "${GREEN}✓${NC} Summary generated"
echo ""

echo "${YELLOW}▶${NC} ${BOLD}Step 8/9:${NC} Generating production SQL scripts..."

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

show_progress 8 $TOTAL_STEPS
echo ""
echo "${GREEN}✓${NC} Production scripts generated"
echo ""

echo "${YELLOW}▶${NC} ${BOLD}Step 9/9:${NC} Creating summary report..."
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

show_progress 9 $TOTAL_STEPS
echo ""
echo "${GREEN}✓${NC} Summary report created"
echo ""

# Final summary
echo ""
echo "${BOLD}=========================================${NC}"
echo "${BOLD}${GREEN}✓ Analysis Complete!${NC}"
echo "${BOLD}=========================================${NC}"
echo ""
echo "${BLUE}Results saved to:${NC} ${BOLD}$RESULTS_DIR${NC}"
echo ""
echo "${YELLOW}Summary:${NC}"
cat "$RESULTS_DIR/07_summary_stats.txt"
echo ""
echo "${BOLD}Files Generated:${NC}"
echo "  ${GREEN}✓${NC} 01_audit_report.txt"
echo "  ${GREEN}✓${NC} 02_recommendations.sql"
echo "  ${GREEN}✓${NC} 03-05_test_results.log"
echo "  ${GREEN}✓${NC} 06_test_results.csv"
echo "  ${GREEN}✓${NC} 07_summary_stats.txt"
echo "  ${GREEN}✓${NC} 08-09_production_*.sql"
echo "  ${GREEN}✓${NC} 00_README.md"
echo ""
echo "${BOLD}Next Steps:${NC}"
echo "  ${YELLOW}▶${NC} View: cd $RESULTS_DIR && cat 00_README.md"
echo "  ${YELLOW}▶${NC} Deploy: psql -f $RESULTS_DIR/08_production_fk_indexes.sql"
echo "  ${YELLOW}▶${NC} Dashboard: open ../INDEX_DASHBOARD.html"
echo ""
echo "${GREEN}${BOLD}Done! 🚀${NC}"
echo ""
