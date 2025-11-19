#!/bin/bash

# Test script for HTML report generation
# Verifies all data files are created correctly and contain expected data

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0

# Test function
test_assert() {
    local description="$1"
    local command="$2"

    if eval "$command"; then
        echo -e "${GREEN}✓${NC} $description"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}✗${NC} $description"
        ((TESTS_FAILED++))
        return 1
    fi
}

echo "=== Testing HTML Report Generation ==="
echo ""

# Run a quick test (5 workflows) with report generation
echo -e "${YELLOW}Running test batch submission (5 workflows)...${NC}"
yes | ./batch_test_csv.sh -h http://demo02.xnatworks.io -u admin -p admin \
    -f admin_11_18_2025_19_15_12.csv -c 70 -m 5 -r test2 > /tmp/test_run.log 2>&1

# Extract the log file name
LOG_FILE=$(grep "Full log saved to:" /tmp/test_run.log | sed 's/.*Full log saved to: //' | tr -d '\033' | sed 's/\[[0-9;]*m//g')
echo "Log file: $LOG_FILE"

BASE_NAME="${LOG_FILE%.log}"
HTML_FILE="${BASE_NAME}.html"
JSON_FILE="${BASE_NAME}_data.json"
CSV_FILE="${BASE_NAME}_workflow_metrics.csv"

echo ""
echo "=== File Existence Tests ==="

test_assert "Log file exists" "[ -f '$LOG_FILE' ]"
test_assert "HTML file exists" "[ -f '$HTML_FILE' ]"
test_assert "JSON data file exists" "[ -f '$JSON_FILE' ]"
test_assert "Workflow CSV file exists" "[ -f '$CSV_FILE' ]"

echo ""
echo "=== Log File Content Tests ==="

test_assert "Log contains query timing data" "grep -q 'query:.*s' '$LOG_FILE'"
test_assert "Log contains host information" "grep -q '^Host:' '$LOG_FILE'"
test_assert "Log contains jobs submitted count" "grep -q 'Jobs Submitted:' '$LOG_FILE'"
test_assert "Log contains execution time" "grep -q 'Execution Time:' '$LOG_FILE'"

echo ""
echo "=== JSON Validation Tests ==="

test_assert "JSON is valid (parses without errors)" "python3 -m json.tool '$JSON_FILE' > /dev/null 2>&1"
test_assert "JSON contains test_info section" "jq -e '.test_info' '$JSON_FILE' > /dev/null"
test_assert "JSON contains results section" "jq -e '.results' '$JSON_FILE' > /dev/null"
test_assert "JSON contains query_performance array" "jq -e '.query_performance' '$JSON_FILE' > /dev/null"
test_assert "JSON has numeric jobs_submitted" "jq -e '.results.jobs_submitted | type == \"number\"' '$JSON_FILE' > /dev/null"
test_assert "JSON has numeric successful count" "jq -e '.results.successful | type == \"number\"' '$JSON_FILE' > /dev/null"
test_assert "JSON has numeric failed count" "jq -e '.results.failed | type == \"number\"' '$JSON_FILE' > /dev/null"
test_assert "JSON query_performance has data" "[ \$(jq '.query_performance | length' '$JSON_FILE') -gt 0 ]"

echo ""
echo "=== Workflow CSV Tests ==="

test_assert "CSV file has header row" "head -1 '$CSV_FILE' | grep -q 'WorkflowID'"
test_assert "CSV has data rows (>1 line)" "[ \$(wc -l < '$CSV_FILE') -gt 1 ]"
test_assert "CSV has expected 10 columns" "[ \$(head -1 '$CSV_FILE' | tr ',' '\n' | wc -l) -eq 10 ]"
test_assert "CSV contains workflow IDs" "grep -q '[0-9]\+,' '$CSV_FILE'"
test_assert "CSV contains experiment IDs" "grep -q 'XNAT_E[0-9]\+' '$CSV_FILE'"

echo ""
echo "=== HTML File Tests ==="

test_assert "HTML contains Chart.js library" "grep -q 'chart.js' '$HTML_FILE'"
test_assert "HTML contains query performance chart" "grep -q 'queryPerfChart' '$HTML_FILE'"
test_assert "HTML contains workflow timing chart" "grep -q 'workflowTimingChart' '$HTML_FILE'"
test_assert "HTML dynamically constructs data JSON filename" "grep -q '_data.json' '$HTML_FILE'"
test_assert "HTML dynamically constructs workflow CSV filename" "grep -q '_workflow_metrics.csv' '$HTML_FILE'"

echo ""
echo "=== Data Consistency Tests ==="

JOBS_IN_LOG=$(grep "Jobs Submitted:" "$LOG_FILE" | sed -E 's/.*Jobs Submitted: ([0-9]+).*/\1/')
JOBS_IN_JSON=$(jq -r '.results.jobs_submitted' "$JSON_FILE")
test_assert "Jobs count matches (log=$JOBS_IN_LOG, json=$JOBS_IN_JSON)" "[ '$JOBS_IN_LOG' = '$JOBS_IN_JSON' ]"

CSV_ROWS=$(($(wc -l < "$CSV_FILE") - 1))  # Subtract header
test_assert "CSV workflow count matches jobs ($CSV_ROWS workflows)" "[ $CSV_ROWS -eq $JOBS_IN_JSON ]"

echo ""
echo "=== Test Summary ==="
echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}✗ Some tests failed${NC}"
    exit 1
fi
