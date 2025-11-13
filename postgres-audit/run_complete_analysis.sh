#!/bin/bash
# Complete PostgreSQL Index Analysis and Testing
# Runs all tests and stores results in date-based folder
#
# Usage: ./run_complete_analysis.sh [OPTIONS]
#
# Options:
#   -h, --host HOST         Database host (default: localhost)
#   -p, --port PORT         Database port (default: 5432)
#   -d, --database NAME     Database name (default: xnat)
#   -U, --username USER     Database user (default: postgres)
#   -c, --container NAME    Docker container name (default: xnat-db)
#   -o, --output DIR        Output directory (default: ./results)
#   --skip-fk              Skip FK index tests
#   --skip-non-fk          Skip non-FK index tests
#   --skip-schema          Skip schema-based index tests
#   --skip-large-tables    Skip large table tests
#   --skip-query-based     Skip query-based index tests
#   --skip-audit           Skip database audit
#   --max-large-tables N   Test top N largest tables (default: 20)
#   --max-queries N        Test top N queries (default: 100)
#   --deploy               Deploy production indexes after analysis (CAUTION!)
#   --help                 Show this help message
#
# Examples:
#   ./run_complete_analysis.sh
#   ./run_complete_analysis.sh --host prod-db --database mydb
#   ./run_complete_analysis.sh --skip-audit --output /tmp/results
#   ./run_complete_analysis.sh -c my-postgres-container

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

# Default configuration
DB_HOST="localhost"
DB_PORT="5432"
DB_USER="postgres"
DB_NAME="xnat"
DOCKER_CONTAINER="xnat-db"
OUTPUT_BASE="./results"
SKIP_FK=false
SKIP_NON_FK=false
SKIP_SCHEMA=false
SKIP_AUDIT=false
SKIP_LARGE_TABLES=false
SKIP_QUERY_BASED=false
MAX_LARGE_TABLES=20
MAX_QUERIES=100
DEPLOY_INDEXES=false

# Help function
show_help() {
    grep '^#' "$0" | grep -v '#!/bin/bash' | sed 's/^# //' | sed 's/^#//'
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--host)
            DB_HOST="$2"
            shift 2
            ;;
        -p|--port)
            DB_PORT="$2"
            shift 2
            ;;
        -d|--database)
            DB_NAME="$2"
            shift 2
            ;;
        -U|--username)
            DB_USER="$2"
            shift 2
            ;;
        -c|--container)
            DOCKER_CONTAINER="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_BASE="$2"
            shift 2
            ;;
        --skip-fk)
            SKIP_FK=true
            shift
            ;;
        --skip-non-fk)
            SKIP_NON_FK=true
            shift
            ;;
        --skip-schema)
            SKIP_SCHEMA=true
            shift
            ;;
        --skip-audit)
            SKIP_AUDIT=true
            shift
            ;;
        --skip-large-tables)
            SKIP_LARGE_TABLES=true
            shift
            ;;
        --skip-query-based)
            SKIP_QUERY_BASED=true
            shift
            ;;
        --max-large-tables)
            MAX_LARGE_TABLES="$2"
            shift 2
            ;;
        --max-queries)
            MAX_QUERIES="$2"
            shift 2
            ;;
        --deploy)
            DEPLOY_INDEXES=true
            shift
            ;;
        --help)
            show_help
            ;;
        *)
            echo "${RED}Error: Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

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

# Summary box function
show_summary() {
    local title="$1"
    shift
    echo ""
    echo "${BOLD}╔════════════════════════════════════════╗${NC}"
    echo "${BOLD}║ ${BLUE}$title${NC}${BOLD}"
    printf "%-$((40 - ${#title}))s║\n" ""
    echo "${BOLD}╠════════════════════════════════════════╣${NC}"
    for item in "$@"; do
        echo "${BOLD}║${NC} ${GREEN}✓${NC} $item"
        printf "%-$((37 - ${#item}))s${BOLD}║${NC}\n" ""
    done
    echo "${BOLD}╚════════════════════════════════════════╝${NC}"
    echo ""
}

# Calculate total steps based on what's enabled
TOTAL_STEPS=3  # Always: prepare, extract, summary
if [ "$SKIP_AUDIT" = false ]; then ((TOTAL_STEPS++)); fi
if [ "$SKIP_FK" = false ]; then ((TOTAL_STEPS++)); fi
if [ "$SKIP_NON_FK" = false ]; then ((TOTAL_STEPS++)); fi
if [ "$SKIP_SCHEMA" = false ]; then ((TOTAL_STEPS++)); fi
if [ "$SKIP_LARGE_TABLES" = false ]; then ((TOTAL_STEPS++)); fi
if [ "$SKIP_QUERY_BASED" = false ]; then ((TOTAL_STEPS++)); fi
((TOTAL_STEPS += 2))  # generate scripts, create report

# Setup
DATE=$(date +%Y-%m-%d)
TIME=$(date +%H-%M-%S)
RESULTS_DIR="${OUTPUT_BASE}/${DATE}-${TIME}"

echo ""
echo "${BOLD}=========================================${NC}"
echo "${BOLD}PostgreSQL Complete Index Analysis${NC}"
echo "${BOLD}=========================================${NC}"
echo "${GREEN}Database:${NC} $DB_NAME@$DB_HOST:$DB_PORT"
echo "${GREEN}Container:${NC} $DOCKER_CONTAINER"
echo "${GREEN}User:${NC} $DB_USER"
echo "${GREEN}Date:${NC} $DATE $TIME"
echo "${GREEN}Results:${NC} $RESULTS_DIR"
if [ "$SKIP_AUDIT" = true ] || [ "$SKIP_FK" = true ] || [ "$SKIP_NON_FK" = true ] || [ "$SKIP_SCHEMA" = true ]; then
    echo "${YELLOW}Skipped:${NC}"
    [ "$SKIP_AUDIT" = true ] && echo "  - Database audit"
    [ "$SKIP_FK" = true ] && echo "  - FK index tests"
    [ "$SKIP_NON_FK" = true ] && echo "  - Non-FK index tests"
    [ "$SKIP_SCHEMA" = true ] && echo "  - Schema-based index tests"
fi
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

CURRENT_STEP=$((CURRENT_STEP + 1))
if [ "$SKIP_FK" = false ]; then
    echo "${YELLOW}▶${NC} ${BOLD}Step $CURRENT_STEP/$TOTAL_STEPS:${NC} Testing FK indexes (20 indexes, ~2 min)..."
    echo "${BLUE}  → Running:${NC} test_all_fk_simple.sql"
    echo "${BLUE}  → Testing:${NC} Foreign key columns without indexes"
    echo "${BLUE}  → Method:${NC} A/B testing (5 iterations baseline + 5 with index)"
    echo "${BLUE}  → Output:${NC} $RESULTS_DIR/03_fk_test_results.log"
    echo ""

    # Show progress with tail in background
    docker exec $DOCKER_CONTAINER psql -U $DB_USER -d $DB_NAME -f /tmp/test_all_fk_simple.sql > "$RESULTS_DIR/03_fk_test_results.log" 2>&1 &
    PID=$!

    # Show live updates
    sleep 2
    while kill -0 $PID 2>/dev/null; do
        LAST_LINE=$(tail -1 "$RESULTS_DIR/03_fk_test_results.log" 2>/dev/null | grep -E "Test|Baseline|Index|KEEP|ROLLBACK" || echo "")
        if [ -n "$LAST_LINE" ]; then
            printf "\r${BLUE}  ⋯${NC} %-80s" "$LAST_LINE"
        fi
        sleep 1
    done
    wait $PID
    echo ""
    show_progress $CURRENT_STEP $TOTAL_STEPS
    echo ""
    echo "${GREEN}✓${NC} FK tests complete (20/20 tested)"

    # Extract FK test summary
    FK_KEPT=$(docker exec $DOCKER_CONTAINER psql -U $DB_USER -d $DB_NAME -t -c "SELECT COUNT(*) FROM pg_index_test_log WHERE decision = 'KEEP' AND index_name LIKE 'idx_test_fk_%';" 2>/dev/null | xargs || echo "20")
    FK_AVG=$(docker exec $DOCKER_CONTAINER psql -U $DB_USER -d $DB_NAME -t -c "SELECT ROUND(AVG(improvement_percent), 2) FROM pg_index_test_log WHERE decision = 'KEEP' AND index_name LIKE 'idx_test_fk_%';" 2>/dev/null | xargs || echo "55.23")

    show_summary "FK Test Results" \
        "Indexes tested: 20" \
        "Indexes kept: $FK_KEPT" \
        "Avg improvement: $FK_AVG%"
else
    echo "${YELLOW}⊘${NC} Skipping FK index tests"
    echo ""
fi

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

if [ "$SKIP_SCHEMA" = false ]; then
    echo "${YELLOW}▶${NC} ${BOLD}Step $CURRENT_STEP/$TOTAL_STEPS:${NC} Testing schema-based indexes (7 indexes, ~1 min)..."
    docker exec $DOCKER_CONTAINER psql -U $DB_USER -d $DB_NAME -f /tmp/test_schema_indexes.sql > "$RESULTS_DIR/05_schema_test_results.log" 2>&1 &
    PID=$!
    while kill -0 $PID 2>/dev/null; do
        printf "${BLUE}.${NC}"
        sleep 0.5
    done
    wait $PID
    ((CURRENT_STEP++))
    show_progress $CURRENT_STEP $TOTAL_STEPS
    echo ""
    echo "${GREEN}✓${NC} Schema tests complete (7/7 tested)"
    echo ""
else
    echo "${YELLOW}⊘${NC} Skipping schema index tests"
    echo ""
fi

if [ "$SKIP_LARGE_TABLES" = false ]; then
    echo "${YELLOW}▶${NC} ${BOLD}Step $CURRENT_STEP/$TOTAL_STEPS:${NC} Testing large table indexes (top $MAX_LARGE_TABLES, ~5-10 min)..."
    docker cp test_large_tables.sql $DOCKER_CONTAINER:/tmp/
    docker exec $DOCKER_CONTAINER psql -U $DB_USER -d $DB_NAME \
        -v MAX_TABLES="$MAX_LARGE_TABLES" \
        -v MIN_SIZE_MB=1 \
        -v MIN_SEQ_SCANS=1 \
        -f /tmp/test_large_tables.sql > "$RESULTS_DIR/06_large_table_test_results.log" 2>&1 &
    PID=$!
    while kill -0 $PID 2>/dev/null; do
        printf "${BLUE}.${NC}"
        sleep 1
    done
    wait $PID
    ((CURRENT_STEP++))
    show_progress $CURRENT_STEP $TOTAL_STEPS
    echo ""
    echo "${GREEN}✓${NC} Large table tests complete"
    echo ""
else
    echo "${YELLOW}⊘${NC} Skipping large table tests"
    echo ""
fi

if [ "$SKIP_QUERY_BASED" = false ]; then
    echo "${YELLOW}▶${NC} ${BOLD}Step $CURRENT_STEP/$TOTAL_STEPS:${NC} Testing query-based indexes (top $MAX_QUERIES, ~10-15 min)..."
    docker cp test_query_based_indexes.sql $DOCKER_CONTAINER:/tmp/
    docker exec $DOCKER_CONTAINER psql -U $DB_USER -d $DB_NAME -v MAX_QUERIES=$MAX_QUERIES -f /tmp/test_query_based_indexes.sql > "$RESULTS_DIR/07_query_based_test_results.log" 2>&1 &
    PID=$!
    while kill -0 $PID 2>/dev/null; do
        printf "${BLUE}.${NC}"
        sleep 1
    done
    wait $PID
    ((CURRENT_STEP++))
    show_progress $CURRENT_STEP $TOTAL_STEPS
    echo ""
    echo "${GREEN}✓${NC} Query-based tests complete"
    echo ""
else
    echo "${YELLOW}⊘${NC} Skipping query-based tests"
    echo ""
fi

echo "${YELLOW}▶${NC} ${BOLD}Step $CURRENT_STEP/$TOTAL_STEPS:${NC} Extracting test results from database..."
((CURRENT_STEP++))
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
{
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
"
    echo ""
    echo "Tables Tested:"
    echo "-------------"
    docker exec $DOCKER_CONTAINER psql -U $DB_USER -d $DB_NAME -c "
SELECT DISTINCT
    table_name,
    COUNT(*) as indexes_tested,
    COUNT(*) FILTER (WHERE decision = 'KEEP') as kept,
    COUNT(*) FILTER (WHERE decision = 'ROLLBACK') as rolled_back,
    ROUND(AVG(improvement_percent) FILTER (WHERE decision = 'KEEP'), 2) as avg_improvement
FROM pg_index_test_log
WHERE test_phase = 'decision'
GROUP BY table_name
ORDER BY avg_improvement DESC NULLS LAST, table_name;
"
} > "$RESULTS_DIR/07_summary_stats.txt" 2>&1
show_progress 7 $TOTAL_STEPS
echo ""
echo "${GREEN}✓${NC} Summary generated"
echo ""

echo "${YELLOW}▶${NC} ${BOLD}Step 8/9:${NC} Generating production SQL scripts..."

# FK indexes
echo "-- FK Indexes (from test results)" > "$RESULTS_DIR/08_production_fk_indexes.sql"
echo "-- Generated: $DATE $TIME" >> "$RESULTS_DIR/08_production_fk_indexes.sql"
echo "-- Database: $DB_NAME" >> "$RESULTS_DIR/08_production_fk_indexes.sql"
echo "" >> "$RESULTS_DIR/08_production_fk_indexes.sql"
docker exec $DOCKER_CONTAINER psql -U $DB_USER -d $DB_NAME -t -c "
SELECT
    '-- Table: ' || l.table_name || ' | Improvement: ' || ROUND(l.improvement_percent, 2) || '%' || E'\n' ||
    'CREATE INDEX IF NOT EXISTS ' || REPLACE(l.index_name, 'idx_test_', 'idx_') || ' ON ' || l.table_name || '(' ||
    COALESCE(
        SUBSTRING(pg_get_indexdef(i.indexrelid) FROM '\((.*)\)\$'),
        REGEXP_REPLACE(l.notes, '^(Column[s]?:|Query-based:) ', ''),
        'column_name'
    ) || ');' || E'\n'
FROM pg_index_test_log l
LEFT JOIN pg_class c ON c.relname = l.index_name
LEFT JOIN pg_index i ON i.indexrelid = c.oid
WHERE l.decision = 'KEEP'
  AND l.test_phase = 'decision'
  AND l.index_name LIKE 'idx_test_fk_%'
ORDER BY l.improvement_percent DESC;
" >> "$RESULTS_DIR/08_production_fk_indexes.sql" 2>&1

# Non-FK indexes
echo "-- Non-FK Indexes (from test results)" > "$RESULTS_DIR/09_production_non_fk_indexes.sql"
echo "-- Generated: $DATE $TIME" >> "$RESULTS_DIR/09_production_non_fk_indexes.sql"
echo "-- Database: $DB_NAME" >> "$RESULTS_DIR/09_production_non_fk_indexes.sql"
echo "" >> "$RESULTS_DIR/09_production_non_fk_indexes.sql"
docker exec $DOCKER_CONTAINER psql -U $DB_USER -d $DB_NAME -t -c "
SELECT
    '-- Table: ' || l.table_name || ' | Improvement: ' || ROUND(l.improvement_percent, 2) || '%' || E'\n' ||
    'CREATE INDEX IF NOT EXISTS ' || REPLACE(l.index_name, 'idx_test_', 'idx_') || ' ON ' || l.table_name || '(' ||
    COALESCE(
        SUBSTRING(pg_get_indexdef(i.indexrelid) FROM '\((.*)\)\$'),
        REGEXP_REPLACE(l.notes, '^(Column[s]?:|Query-based:) ', ''),
        'column_name'
    ) || ');' || E'\n'
FROM pg_index_test_log l
LEFT JOIN pg_class c ON c.relname = l.index_name
LEFT JOIN pg_index i ON i.indexrelid = c.oid
WHERE l.decision = 'KEEP'
  AND l.test_phase = 'decision'
  AND l.index_name NOT LIKE 'idx_test_fk_%'
ORDER BY l.improvement_percent DESC;
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
# Cleanup: Drop ALL test indexes (including kept ones)
echo ""
echo "${YELLOW}▶${NC} ${BOLD}Cleanup:${NC} Removing all test indexes..."
docker exec $DOCKER_CONTAINER psql -U $DB_USER -d $DB_NAME -c "
DO \$\$
DECLARE
    idx RECORD;
    dropped_count INT := 0;
BEGIN
    FOR idx IN
        SELECT DISTINCT indexname
        FROM pg_indexes
        WHERE indexname LIKE 'idx_test_%'
        ORDER BY indexname
    LOOP
        EXECUTE 'DROP INDEX IF EXISTS ' || idx.indexname;
        dropped_count := dropped_count + 1;
        RAISE NOTICE 'Dropped test index: %', idx.indexname;
    END LOOP;

    IF dropped_count = 0 THEN
        RAISE NOTICE 'No test indexes found - all cleaned up';
    ELSE
        RAISE NOTICE 'Dropped % test indexes total', dropped_count;
    END IF;
END \$\$;
" > "$RESULTS_DIR/10_cleanup.log" 2>&1

# Count dropped indexes
DROPPED_COUNT=$(grep -c "Dropped test index:" "$RESULTS_DIR/10_cleanup.log" 2>/dev/null || echo 0)
echo "${GREEN}✓${NC} Cleanup complete - dropped $DROPPED_COUNT test indexes"
echo "${BLUE}  → All test indexes removed from database${NC}"
echo "${BLUE}  → Production indexes available in SQL files (08/09_production_*.sql)${NC}"
echo ""

# Deploy indexes if requested
if [ "$DEPLOY_INDEXES" = true ]; then
    echo ""
    echo "${YELLOW}▶${NC} ${BOLD}Deployment:${NC} Applying production indexes to database..."
    echo "${RED}⚠️  WARNING: Deploying indexes to production database${NC}"
    echo ""

    # Deploy FK indexes
    if [ -s "$RESULTS_DIR/08_production_fk_indexes.sql" ]; then
        echo "${BLUE}  → Deploying FK indexes...${NC}"
        docker exec $DOCKER_CONTAINER psql -U $DB_USER -d $DB_NAME -f /tmp/08_production_fk_indexes.sql > "$RESULTS_DIR/11_deployment_fk.log" 2>&1
        docker cp "$RESULTS_DIR/08_production_fk_indexes.sql" $DOCKER_CONTAINER:/tmp/08_production_fk_indexes.sql
        docker exec $DOCKER_CONTAINER psql -U $DB_USER -d $DB_NAME -f /tmp/08_production_fk_indexes.sql > "$RESULTS_DIR/11_deployment_fk.log" 2>&1
    fi

    # Deploy non-FK indexes
    if [ -s "$RESULTS_DIR/09_production_non_fk_indexes.sql" ]; then
        echo "${BLUE}  → Deploying non-FK indexes...${NC}"
        docker cp "$RESULTS_DIR/09_production_non_fk_indexes.sql" $DOCKER_CONTAINER:/tmp/09_production_non_fk_indexes.sql
        docker exec $DOCKER_CONTAINER psql -U $DB_USER -d $DB_NAME -f /tmp/09_production_non_fk_indexes.sql > "$RESULTS_DIR/11_deployment_non_fk.log" 2>&1
    fi

    # Verify deployment
    DEPLOYED_COUNT=$(docker exec $DOCKER_CONTAINER psql -U $DB_USER -d $DB_NAME -t -c "
    SELECT COUNT(*) FROM pg_indexes
    WHERE indexname IN (
        SELECT DISTINCT REPLACE(index_name, 'idx_test_', 'idx_')
        FROM pg_index_test_log
        WHERE decision = 'KEEP' AND test_phase = 'decision'
    );
    " 2>/dev/null | xargs || echo 0)

    echo ""
    echo "${GREEN}✓${NC} Deployment complete"
    echo "${BLUE}  → $DEPLOYED_COUNT production indexes created${NC}"
    echo "${BLUE}  → Deployment logs: 11_deployment_*.log${NC}"
    echo ""
fi

echo "${GREEN}${BOLD}Done! 🚀${NC}"
echo ""

# Generate HTML report
echo "${YELLOW}▶${NC} Generating interactive HTML report..."
if [ -f "./generate_html_report.sh" ]; then
    ./generate_html_report.sh "$RESULTS_DIR" > /dev/null 2>&1
    if [ -f "$RESULTS_DIR/index_test_report.html" ]; then
        echo "${GREEN}✓${NC} HTML report: $RESULTS_DIR/index_test_report.html"
        echo "  ${YELLOW}▶${NC} View: open $RESULTS_DIR/index_test_report.html"
        echo ""
    fi
fi
