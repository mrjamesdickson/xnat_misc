#!/bin/bash

# HTML Report Generator for Batch Performance Testing
# Converts log files to interactive HTML reports

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Upload/retry configuration (override via env vars if needed)
UPLOAD_MAX_TIME=${UPLOAD_MAX_TIME:-600}
UPLOAD_CONNECT_TIMEOUT=${UPLOAD_CONNECT_TIMEOUT:-30}
UPLOAD_RETRY_COUNT=${UPLOAD_RETRY_COUNT:-5}
UPLOAD_RETRY_DELAY=${UPLOAD_RETRY_DELAY:-20}

# Usage
usage() {
    echo "Usage: $0 [-l <LOG_FILE>] [-o <OUTPUT_FILE>] [-a] [-h <XNAT_HOST>] [-u <USERNAME>] [-p <PASSWORD>] [-r <REPORT_PROJECT>]"
    echo "  -l  Log file to convert (optional - will list if not provided)"
    echo "  -o  Output HTML file (optional - defaults to <log_name>.html)"
    echo "  -a  Generate report for all logs in logs/ directory"
    echo "  -h  XNAT host (required for upload)"
    echo "  -u  Username (required for upload)"
    echo "  -p  Password (required for upload)"
    echo "  -r  Report project ID to upload to (creates BATCH_TESTS resource)"
    exit 1
}

# Parse arguments
ALL_LOGS=false
while getopts "l:o:ah:u:p:r:" opt; do
    case $opt in
        l) LOG_FILE="$OPTARG" ;;
        o) OUTPUT_FILE="$OPTARG" ;;
        a) ALL_LOGS=true ;;
        h) XNAT_HOST="$OPTARG" ;;
        u) USERNAME="$OPTARG" ;;
        p) PASSWORD="$OPTARG" ;;
        r) REPORT_PROJECT="$OPTARG" ;;
        *) usage ;;
    esac
done

# Remove trailing slash from host
XNAT_HOST="${XNAT_HOST%/}"

# Historical database
HISTORY_DB=".cache/performance_history.json"
mkdir -p "$(dirname "$HISTORY_DB")"

# Initialize history database if it doesn't exist
if [ ! -f "$HISTORY_DB" ]; then
    echo '{}' > "$HISTORY_DB"
fi

echo -e "${GREEN}=== HTML Report Generator ===${NC}"
echo ""

# Function to record metrics in history database
record_metrics() {
    local host="$1"
    local project="$2"
    local container="$3"
    local timestamp="$4"
    local submission_time="$5"
    local execution_time="$6"
    local throughput="$7"
    local success_count="$8"
    local fail_count="$9"
    local total_jobs="${10}"

    # Create unique key: host|project|container
    local key="${host}|${project}|${container}"

    # Extract numeric values
    local sub_seconds=$(echo "$submission_time" | awk '{print $1}' | sed 's/s$//')
    local exec_seconds=$(echo "$execution_time" | awk '{print $1}' | sed 's/s$//')
    local throughput_num=$(echo "$throughput" | awk '{print $1}')

    # Build new entry
    local new_entry=$(cat <<ENTRY
{
  "timestamp": "$timestamp",
  "submission_time": $sub_seconds,
  "execution_time": ${exec_seconds:-0},
  "throughput": ${throughput_num:-0},
  "success_count": $success_count,
  "fail_count": $fail_count,
  "total_jobs": $total_jobs
}
ENTRY
)

    # Update history database using jq
    local temp_file=$(mktemp)
    jq --arg key "$key" --argjson entry "$new_entry" '
        .[$key] = (.[$key] // []) + [$entry] |
        .[$key] |= (sort_by(.timestamp) | .[-50:])
    ' "$HISTORY_DB" > "$temp_file" && mv "$temp_file" "$HISTORY_DB"
}

# Function to get historical data
get_history() {
    local host="$1"
    local project="$2"
    local container="$3"

    local key="${host}|${project}|${container}"

    jq -r --arg key "$key" '.[$key] // []' "$HISTORY_DB"
}

# Upload helper with retry logic
upload_with_retry() {
    local file_path="$1"
    local content_type="$2"
    local upload_path="$3"
    local content_label="$4"
    local resource_label="$5"

    if [ ! -f "$file_path" ]; then
        echo -e "  ${YELLOW}⚠ Skipping ${resource_label} upload; file not found (${file_path})${NC}"
        return 1
    fi

    local attempt=1
    while [ $attempt -le $UPLOAD_RETRY_COUNT ]; do
        echo -e "  Attempt ${attempt}/${UPLOAD_RETRY_COUNT}..."
        local response http_code body
        response=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X PUT \
            -b "JSESSIONID=$JSESSION" \
            -H "Content-Type: $content_type" \
            --connect-timeout "$UPLOAD_CONNECT_TIMEOUT" \
            --max-time "$UPLOAD_MAX_TIME" \
            --data-binary "@${file_path}" \
            "${XNAT_HOST}/data/projects/${REPORT_PROJECT}/resources/BATCH_TESTS/files/${upload_path}?format=json&content=${content_label}&inbody=true")

        http_code=$(echo "$response" | grep "HTTP_CODE:" | sed 's/HTTP_CODE://')
        body=$(echo "$response" | grep -v "HTTP_CODE:")

        if [ "$http_code" = "200" ] || [ "$http_code" = "201" ]; then
            echo -e "  ${GREEN}✓ ${resource_label} uploaded${NC}"
            return 0
        fi

        echo -e "  ${YELLOW}⚠ ${resource_label} upload failed (HTTP ${http_code})${NC}"
        [ -n "$body" ] && echo "    $body"

        if [ $attempt -lt $UPLOAD_RETRY_COUNT ]; then
            echo "  Retrying in ${UPLOAD_RETRY_DELAY}s..."
            sleep "$UPLOAD_RETRY_DELAY"
        fi
        attempt=$((attempt + 1))
    done

    echo -e "  ${RED}✗ Failed to upload ${resource_label} after ${UPLOAD_RETRY_COUNT} attempts${NC}"
    return 1
}

# If -a flag is set, process all logs
if [ "$ALL_LOGS" = true ]; then
    if [ ! -d "logs" ]; then
        echo -e "${RED}No logs directory found${NC}"
        exit 1
    fi

    LOG_FILES=$(find logs -name "*.log" -type f | sort -r)
    LOG_COUNT=$(echo "$LOG_FILES" | wc -l | tr -d ' ')

    if [ "$LOG_COUNT" -eq 0 ]; then
        echo -e "${RED}No log files found in logs/ directory${NC}"
        exit 1
    fi

    echo -e "${YELLOW}Processing $LOG_COUNT log files...${NC}"
    echo ""

    # Create reports directory
    REPORTS_DIR="reports"
    mkdir -p "$REPORTS_DIR"

    # Process each log file
    echo "$LOG_FILES" | while read -r log_file; do
        base_name=$(basename "$log_file" .log)
        output_html="$REPORTS_DIR/${base_name}.html"

        echo -ne "  Processing: $log_file -> $output_html ... "

        # Call this script recursively for each log (without -a flag)
        bash "$0" -l "$log_file" -o "$output_html" > /dev/null 2>&1

        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓${NC}"
        else
            echo -e "${RED}✗${NC}"
        fi
    done

    # Generate index.html
    INDEX_FILE="$REPORTS_DIR/index.html"
    echo ""
    echo -e "${YELLOW}Generating index.html...${NC}"

    # Create HTML index
    cat > "$INDEX_FILE" <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>XNAT Batch Performance Test Reports</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
            line-height: 1.6;
            color: #333;
            background: #f5f5f5;
            padding: 20px;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            padding: 40px;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        h1 {
            color: #2c3e50;
            margin-bottom: 10px;
            font-size: 2em;
        }
        .subtitle {
            color: #7f8c8d;
            margin-bottom: 30px;
            font-size: 1.1em;
        }
        .report-list {
            list-style: none;
        }
        .report-item {
            margin-bottom: 15px;
            padding: 20px;
            background: #f8f9fa;
            border-left: 4px solid #3498db;
            border-radius: 4px;
            transition: all 0.3s ease;
        }
        .report-item:hover {
            background: #e9ecef;
            transform: translateX(5px);
            box-shadow: 0 2px 8px rgba(0,0,0,0.1);
        }
        .report-link {
            text-decoration: none;
            color: #2c3e50;
            font-weight: 600;
            font-size: 1.1em;
            display: block;
        }
        .report-date {
            color: #7f8c8d;
            font-size: 0.9em;
            margin-top: 5px;
        }
        .no-reports {
            padding: 40px;
            text-align: center;
            color: #7f8c8d;
            font-style: italic;
        }
        footer {
            margin-top: 40px;
            padding-top: 20px;
            border-top: 1px solid #dee2e6;
            text-align: center;
            color: #7f8c8d;
            font-size: 0.9em;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>📊 XNAT Batch Performance Test Reports</h1>
        <p class="subtitle">All batch performance test results</p>

        <ul class="report-list">
EOF

    # Add report links
    find "$REPORTS_DIR" -name "*.html" -not -name "index.html" -type f | sort -r | while read -r html_file; do
        base_name=$(basename "$html_file" .html)

        # Try to extract date from filename (format: batch_test_HHMMSS)
        if [[ "$base_name" =~ batch_test_([0-9]{6}) ]]; then
            time_str="${BASH_REMATCH[1]}"
            hour="${time_str:0:2}"
            min="${time_str:2:2}"
            sec="${time_str:4:2}"
            formatted_time="${hour}:${min}:${sec}"
        else
            formatted_time="Unknown time"
        fi

        # Extract parent directory (date) from path
        parent_dir=$(dirname "$html_file" | xargs basename)

        cat >> "$INDEX_FILE" <<EOF
            <li class="report-item">
                <a href="$(basename "$html_file")" class="report-link">$base_name</a>
                <div class="report-date">Date: $parent_dir | Time: $formatted_time</div>
            </li>
EOF
    done

    cat >> "$INDEX_FILE" <<'EOF'
        </ul>

        <footer>
            Generated on <span id="gen-date"></span>
        </footer>
    </div>
    <script>
        document.getElementById('gen-date').textContent = new Date().toLocaleString();
    </script>
</body>
</html>
EOF

    echo -e "${GREEN}✓ Index generated: $INDEX_FILE${NC}"
    echo ""
    echo -e "${GREEN}=== REPORT GENERATION COMPLETE ===${NC}"
    echo ""
    echo "Reports saved to: $REPORTS_DIR/"
    echo "Open index.html to view all reports: $INDEX_FILE"
    echo ""

    exit 0
fi

# If no log file specified, list available logs
if [ -z "$LOG_FILE" ]; then
    if [ ! -d "logs" ]; then
        echo -e "${RED}No logs directory found${NC}"
        echo "Run batch_test.sh first to generate logs"
        exit 1
    fi

    LOG_FILES=$(find logs -name "*.log" -type f | sort -r)
    LOG_COUNT=$(echo "$LOG_FILES" | wc -l | tr -d ' ')

    if [ "$LOG_COUNT" -eq 0 ]; then
        echo -e "${RED}No log files found${NC}"
        echo "Run batch_test.sh first to generate logs"
        exit 1
    fi

    echo "Available log files:"
    echo ""
    echo "$LOG_FILES" | nl -w 3 -s '. '
    echo ""
    read -p "Enter log file number (or 'a' for all): " selection

    if [ "$selection" = "a" ] || [ "$selection" = "A" ]; then
        # Re-run with -a flag
        exec bash "$0" -a
    fi

    LOG_FILE=$(echo "$LOG_FILES" | sed -n "${selection}p")

    if [ -z "$LOG_FILE" ]; then
        echo -e "${RED}Invalid selection${NC}"
        exit 1
    fi
fi

# Check log file exists
if [ ! -f "$LOG_FILE" ]; then
    echo -e "${RED}Log file not found: $LOG_FILE${NC}"
    exit 1
fi

# Generate output filename if not specified
if [ -z "$OUTPUT_FILE" ]; then
    OUTPUT_FILE="${LOG_FILE%.log}.html"
fi

HISTORY_JSON_FILE="${OUTPUT_FILE%.html}_history.json"

echo "Log file: $LOG_FILE"
echo "Output: $OUTPUT_FILE"
echo ""

# Parse log file
echo -e "${YELLOW}Parsing log file...${NC}"

# Extract metadata
TEST_STARTED=$(grep "Test Started:" "$LOG_FILE" | sed 's/Test Started: //')
TEST_COMPLETED=$(grep "Test Completed:" "$LOG_FILE" | sed 's/Test Completed: //')
HOST=$(grep "^Host:" "$LOG_FILE" | head -1 | sed 's/Host: //')
USER=$(grep "^User:" "$LOG_FILE" | head -1 | sed 's/User: //')
PROJECT=$(grep "^  Project:" "$LOG_FILE" | tail -1 | sed 's/  Project: //')
CONTAINER=$(grep "^  Container:" "$LOG_FILE" | tail -1 | sed 's/  Container: //')
MAX_JOBS=$(grep "^  Max Jobs Limit:" "$LOG_FILE" | tail -1 | sed 's/  Max Jobs Limit: //')
JOBS_SUBMITTED=$(grep "^  Jobs Submitted:" "$LOG_FILE" | sed 's/  Jobs Submitted: //')
SUCCESSFUL=$(grep "^  Successful:" "$LOG_FILE" | sed 's/  Successful: //')
FAILED=$(grep "^  Failed:" "$LOG_FILE" | sed 's/  Failed: //')
TOTAL_DURATION=$(grep "^  Total Duration:" "$LOG_FILE" | sed 's/  Total Duration: //')
AVG_TIME=$(grep "^  Average Job Submission Time:" "$LOG_FILE" | sed 's/  Average Job Submission Time: //')
FASTEST=$(grep "^  Fastest Submission:" "$LOG_FILE" | sed 's/  Fastest Submission: //')
SLOWEST=$(grep "^  Slowest Submission:" "$LOG_FILE" | sed 's/  Slowest Submission: //')
THROUGHPUT=$(grep "^  Throughput:" "$LOG_FILE" | sed 's/  Throughput: //')

# Extract execution monitoring data if available
EXECUTION_TIME=$(grep "^Execution Time:" "$LOG_FILE" | tail -1 | sed 's/Execution Time: //')
TOTAL_WITH_EXECUTION=$(grep "^Total Time (Submission + Execution):" "$LOG_FILE" | tail -1 | sed 's/Total Time (Submission + Execution): //')
FINAL_STATUS=$(grep "^Final Status:" "$LOG_FILE" | tail -1 | sed 's/Final Status: //')

# Extract success/fail counts for chart
SUCCESS_COUNT=$(echo "$SUCCESSFUL" | sed -E 's/^([0-9]+).*/\1/' || echo "0")
FAIL_COUNT=$(echo "$FAILED" | sed -E 's/^([0-9]+).*/\1/' || echo "0")

# Record metrics to history database
if [ -n "$HOST" ] && [ -n "$PROJECT" ] && [ -n "$CONTAINER" ] && [ -n "$TEST_STARTED" ]; then
    echo -e "${YELLOW}Recording metrics to history database...${NC}"
    record_metrics "$HOST" "$PROJECT" "$CONTAINER" "$TEST_STARTED" "$TOTAL_DURATION" "$EXECUTION_TIME" "$THROUGHPUT" "$SUCCESS_COUNT" "$FAIL_COUNT" "$JOBS_SUBMITTED"
fi

# Get historical data for this container
HISTORICAL_DATA="[]"
if [ -n "$HOST" ] && [ -n "$PROJECT" ] && [ -n "$CONTAINER" ]; then
    HISTORICAL_DATA=$(get_history "$HOST" "$PROJECT" "$CONTAINER")
fi

# Generate HTML report
echo -e "${YELLOW}Generating HTML report...${NC}"

cat > "$OUTPUT_FILE" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>XNAT Batch Performance Test Report</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
            line-height: 1.6;
            color: #333;
            background: #f5f5f5;
            padding: 20px;
        }

        .container {
            max-width: 1400px;
            margin: 0 auto;
            background: white;
            padding: 40px;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }

        header {
            border-bottom: 3px solid #3498db;
            padding-bottom: 20px;
            margin-bottom: 30px;
        }

        h1 {
            color: #2c3e50;
            margin-bottom: 10px;
            font-size: 2.5em;
        }

        .subtitle {
            color: #7f8c8d;
            font-size: 1.1em;
        }

        .metadata {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }

        .metadata-item {
            padding: 15px;
            background: #f8f9fa;
            border-radius: 4px;
            border-left: 4px solid #3498db;
        }

        .metadata-label {
            font-weight: 600;
            color: #7f8c8d;
            font-size: 0.9em;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }

        .metadata-value {
            color: #2c3e50;
            font-size: 1.1em;
            margin-top: 5px;
        }

        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }

        .stat-card {
            padding: 20px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border-radius: 8px;
            text-align: center;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
        }

        .stat-card.success {
            background: linear-gradient(135deg, #11998e 0%, #38ef7d 100%);
        }

        .stat-card.fail {
            background: linear-gradient(135deg, #eb3349 0%, #f45c43 100%);
        }

        .stat-card.performance {
            background: linear-gradient(135deg, #FFD89B 0%, #19547B 100%);
        }

        .stat-label {
            font-size: 0.9em;
            opacity: 0.9;
            text-transform: uppercase;
            letter-spacing: 1px;
        }

        .stat-value {
            font-size: 2.5em;
            font-weight: bold;
            margin: 10px 0;
        }

        .stat-sublabel {
            font-size: 0.85em;
            opacity: 0.8;
        }

        .section {
            margin-bottom: 40px;
        }

        .section-title {
            color: #2c3e50;
            font-size: 1.8em;
            margin-bottom: 20px;
            padding-bottom: 10px;
            border-bottom: 2px solid #ecf0f1;
        }

        .chart-container {
            margin: 30px 0;
            padding: 20px;
            background: #f8f9fa;
            border-radius: 8px;
        }

        .trend-charts {
            display: grid;
            grid-template-columns: 1fr;
            gap: 30px;
            margin: 30px 0;
        }

        .chart-wrapper {
            background: white;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 2px 8px rgba(0,0,0,0.05);
        }

        .chart-wrapper h3 {
            color: #2c3e50;
            margin-bottom: 15px;
            font-size: 1.2em;
        }

        .chart-wrapper canvas {
            max-height: 300px;
        }

        .svg-chart {
            width: 100%;
            height: 250px;
            border: 1px solid #ecf0f1;
            border-radius: 4px;
        }

        .chart-data-table {
            width: 100%;
            margin-top: 15px;
            border-collapse: collapse;
            font-size: 0.9em;
        }

        .chart-data-table th {
            background: #ecf0f1;
            padding: 8px;
            text-align: left;
            font-weight: 600;
            color: #2c3e50;
        }

        .chart-data-table td {
            padding: 8px;
            border-bottom: 1px solid #ecf0f1;
        }

        .chart-data-table tr:hover {
            background: #f8f9fa;
        }

        .sortable-table th {
            cursor: pointer;
            user-select: none;
            position: relative;
        }

        .sortable-table th:hover {
            background: #d5dce0;
        }

        .sortable-table th.sort-asc::after {
            content: ' ▲';
            font-size: 0.8em;
            color: #3498db;
        }

        .sortable-table th.sort-desc::after {
            content: ' ▼';
            font-size: 0.8em;
            color: #3498db;
        }

        .workflow-summary {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px;
            margin: 20px 0;
        }

        .workflow-stat {
            padding: 15px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border-radius: 6px;
            text-align: center;
        }

        .workflow-stat .label {
            font-size: 0.9em;
            opacity: 0.9;
            margin-bottom: 5px;
        }

        .workflow-stat .value {
            font-size: 1.5em;
            font-weight: 600;
        }

        .trend-up {
            color: #e74c3c;
        }

        .trend-down {
            color: #27ae60;
        }

        .trend-stable {
            color: #95a5a6;
        }

        .progress-bar-container {
            background: #ecf0f1;
            border-radius: 10px;
            overflow: hidden;
            height: 40px;
            display: flex;
            margin: 20px 0;
        }

        .progress-bar-success {
            background: linear-gradient(90deg, #11998e 0%, #38ef7d 100%);
            height: 100%;
            display: flex;
            align-items: center;
            justify-content: center;
            color: white;
            font-weight: 600;
            transition: width 1s ease;
        }

        .progress-bar-fail {
            background: linear-gradient(90deg, #eb3349 0%, #f45c43 100%);
            height: 100%;
            display: flex;
            align-items: center;
            justify-content: center;
            color: white;
            font-weight: 600;
            transition: width 1s ease;
        }

        .log-entries {
            max-height: 600px;
            overflow-y: auto;
            background: #2c3e50;
            color: #ecf0f1;
            padding: 20px;
            border-radius: 8px;
            font-family: "Courier New", monospace;
            font-size: 0.9em;
        }

        .log-entry {
            margin-bottom: 15px;
            padding: 10px;
            border-radius: 4px;
            border-left: 3px solid transparent;
        }

        .log-entry.success {
            background: rgba(56, 239, 125, 0.1);
            border-left-color: #38ef7d;
        }

        .log-entry.fail {
            background: rgba(235, 51, 73, 0.1);
            border-left-color: #eb3349;
        }

        .log-timestamp {
            color: #95a5a6;
            font-size: 0.85em;
        }

        .log-status {
            font-weight: 600;
            margin: 0 10px;
        }

        .log-status.success {
            color: #38ef7d;
        }

        .log-status.fail {
            color: #f45c43;
        }

        .log-details {
            margin-top: 5px;
            padding-left: 20px;
            color: #bdc3c7;
        }

        .filter-controls {
            margin-bottom: 20px;
            display: flex;
            gap: 10px;
            flex-wrap: wrap;
        }

        .filter-btn {
            padding: 10px 20px;
            border: 2px solid #3498db;
            background: white;
            color: #3498db;
            border-radius: 4px;
            cursor: pointer;
            font-weight: 600;
            transition: all 0.3s ease;
        }

        .filter-btn:hover {
            background: #3498db;
            color: white;
        }

        .filter-btn.active {
            background: #3498db;
            color: white;
        }

        footer {
            margin-top: 40px;
            padding-top: 20px;
            border-top: 1px solid #ecf0f1;
            text-align: center;
            color: #7f8c8d;
            font-size: 0.9em;
        }

        @media print {
            body {
                background: white;
                padding: 0;
            }
            .container {
                box-shadow: none;
            }
            .log-entries {
                max-height: none;
            }
            .filter-controls {
                display: none;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>📊 XNAT Batch Performance Test Report</h1>
            <p class="subtitle">Container batch submission performance analysis</p>
        </header>

        <div class="section">
            <h2 class="section-title">Test Configuration</h2>
            <div class="metadata">
                <div class="metadata-item">
                    <div class="metadata-label">Test Started</div>
                    <div class="metadata-value">$TEST_STARTED</div>
                </div>
                <div class="metadata-item">
                    <div class="metadata-label">Test Completed</div>
                    <div class="metadata-value">$TEST_COMPLETED</div>
                </div>
                <div class="metadata-item">
                    <div class="metadata-label">XNAT Host</div>
                    <div class="metadata-value">$HOST</div>
                </div>
                <div class="metadata-item">
                    <div class="metadata-label">User</div>
                    <div class="metadata-value">$USER</div>
                </div>
                <div class="metadata-item">
                    <div class="metadata-label">Project</div>
                    <div class="metadata-value">$PROJECT</div>
                </div>
                <div class="metadata-item">
                    <div class="metadata-label">Container</div>
                    <div class="metadata-value">$CONTAINER</div>
                </div>
                <div class="metadata-item">
                    <div class="metadata-label">Max Jobs Limit</div>
                    <div class="metadata-value">$MAX_JOBS</div>
                </div>
                <div class="metadata-item">
                    <div class="metadata-label">Jobs Submitted</div>
                    <div class="metadata-value">$JOBS_SUBMITTED</div>
                </div>
            </div>
        </div>

        <div class="section">
            <h2 class="section-title">Results Summary</h2>
            <div class="stats-grid">
                <div class="stat-card success">
                    <div class="stat-label">Successful</div>
                    <div class="stat-value">$SUCCESS_COUNT</div>
                    <div class="stat-sublabel">$SUCCESSFUL</div>
                </div>
                <div class="stat-card fail">
                    <div class="stat-label">Failed</div>
                    <div class="stat-value">$FAIL_COUNT</div>
                    <div class="stat-sublabel">$FAILED</div>
                </div>
                <div class="stat-card performance">
                    <div class="stat-label">Submission Time</div>
                    <div class="stat-value">$(echo "$TOTAL_DURATION" | awk '{print $1}' | sed 's/s$//')</div>
                    <div class="stat-sublabel">$TOTAL_DURATION</div>
                </div>
EOF

# Add execution time card if available
if [ -n "$EXECUTION_TIME" ]; then
    cat >> "$OUTPUT_FILE" <<EOF
                <div class="stat-card performance">
                    <div class="stat-label">Execution Time</div>
                    <div class="stat-value">$(echo "$EXECUTION_TIME" | awk '{print $1}' | sed 's/s$//')</div>
                    <div class="stat-sublabel">$EXECUTION_TIME</div>
                </div>
                <div class="stat-card performance">
                    <div class="stat-label">Total Time</div>
                    <div class="stat-value">$(echo "$TOTAL_WITH_EXECUTION" | awk '{print $1}' | sed 's/s$//')</div>
                    <div class="stat-sublabel">$TOTAL_WITH_EXECUTION</div>
                </div>
EOF
else
    cat >> "$OUTPUT_FILE" <<EOF
                <div class="stat-card performance">
                    <div class="stat-label">Throughput</div>
                    <div class="stat-value">$(echo "$THROUGHPUT" | awk '{print $1}')</div>
                    <div class="stat-sublabel">$THROUGHPUT</div>
                </div>
EOF
fi

cat >> "$OUTPUT_FILE" <<EOF
            </div>

            <div class="chart-container">
                <h3>Success Rate</h3>
                <div class="progress-bar-container">
                    <div class="progress-bar-success" style="width: $(awk "BEGIN {if ($JOBS_SUBMITTED > 0) printf \"%.0f\", ($SUCCESS_COUNT/$JOBS_SUBMITTED)*100; else print 0}")%">
                        $SUCCESS_COUNT successful
                    </div>
                    <div class="progress-bar-fail" style="width: $(awk "BEGIN {if ($JOBS_SUBMITTED > 0) printf \"%.0f\", ($FAIL_COUNT/$JOBS_SUBMITTED)*100; else print 0}")%">
                        $FAIL_COUNT failed
                    </div>
                </div>
            </div>
        </div>

EOF

# Generate trend charts if we have historical data
HISTORY_COUNT=$(echo "$HISTORICAL_DATA" | jq 'length' 2>/dev/null || echo "0")

if [ "$HISTORY_COUNT" -gt 0 ]; then
    cat >> "$OUTPUT_FILE" <<'EOF'
        <div class="section" id="trend-section">
            <h2 class="section-title">Performance Trends</h2>
            <p class="subtitle">Historical performance data for this container (last 50 runs)</p>

            <div class="trend-charts">
                <div class="chart-wrapper">
                    <h3>⏱️ Submission Time Trend</h3>
                    <svg id="submissionChart" class="svg-chart"></svg>
                    <div id="submissionStats"></div>
                </div>
                <div class="chart-wrapper">
                    <h3>⚡ Execution Time Trend</h3>
                    <svg id="executionChart" class="svg-chart"></svg>
                    <div id="executionStats"></div>
                </div>
                <div class="chart-wrapper">
                    <h3>📊 Throughput Trend</h3>
                    <svg id="throughputChart" class="svg-chart"></svg>
                    <div id="throughputStats"></div>
                </div>
                <div class="chart-wrapper">
                    <h3>✅ Success Rate Trend</h3>
                    <svg id="successRateChart" class="svg-chart"></svg>
                    <div id="successStats"></div>
                </div>
            </div>

            <h3 style="margin-top: 30px; color: #2c3e50;">Recent Performance History</h3>
EOF

    # Generate table with last 10 runs
    cat >> "$OUTPUT_FILE" <<'EOF'
            <table class="chart-data-table">
                <thead>
                    <tr>
                        <th>Timestamp</th>
                        <th>Submission (s)</th>
                        <th>Execution (s)</th>
                        <th>Throughput</th>
                        <th>Success Rate</th>
                    </tr>
                </thead>
                <tbody>
EOF

    # Add last 10 rows from historical data
    echo "$HISTORICAL_DATA" | jq -r '.[-10:] | reverse | .[] |
        @json' | while IFS= read -r row; do
        timestamp=$(echo "$row" | jq -r '.timestamp')
        submission=$(echo "$row" | jq -r '.submission_time')
        execution=$(echo "$row" | jq -r '.execution_time')
        throughput=$(echo "$row" | jq -r '.throughput')
        success_count=$(echo "$row" | jq -r '.success_count')
        total_jobs=$(echo "$row" | jq -r '.total_jobs')

        success_rate=$(awk "BEGIN {printf \"%.1f\", ($success_count/$total_jobs)*100}")

        cat >> "$OUTPUT_FILE" <<TABLEROW
                    <tr>
                        <td>$timestamp</td>
                        <td>${submission}s</td>
                        <td>${execution}s</td>
                        <td>${throughput} jobs/s</td>
                        <td>${success_rate}%</td>
                    </tr>
TABLEROW
    done

    cat >> "$OUTPUT_FILE" <<'EOF'
                </tbody>
            </table>
        </div>
EOF
fi

cat >> "$OUTPUT_FILE" <<EOF

        <div class="section">
            <h2 class="section-title">Performance Metrics</h2>
            <div class="metadata">
                <div class="metadata-item">
                    <div class="metadata-label">Submission Duration</div>
                    <div class="metadata-value">$TOTAL_DURATION</div>
                </div>
EOF

# Add execution time if available
if [ -n "$EXECUTION_TIME" ]; then
    cat >> "$OUTPUT_FILE" <<EOF
                <div class="metadata-item">
                    <div class="metadata-label">Execution Duration</div>
                    <div class="metadata-value">$EXECUTION_TIME</div>
                </div>
                <div class="metadata-item">
                    <div class="metadata-label">Total Time (Submission + Execution)</div>
                    <div class="metadata-value">$TOTAL_WITH_EXECUTION</div>
                </div>
EOF
fi

cat >> "$OUTPUT_FILE" <<EOF
                <div class="metadata-item">
                    <div class="metadata-label">Average Submission Time</div>
                    <div class="metadata-value">$AVG_TIME</div>
                </div>
                <div class="metadata-item">
                    <div class="metadata-label">Fastest Submission</div>
                    <div class="metadata-value">$FASTEST</div>
                </div>
                <div class="metadata-item">
                    <div class="metadata-label">Slowest Submission</div>
                    <div class="metadata-value">$SLOWEST</div>
                </div>
                <div class="metadata-item">
                    <div class="metadata-label">Throughput</div>
                    <div class="metadata-value">$THROUGHPUT</div>
                </div>
            </div>
        </div>
EOF

# Check for per-workflow metrics CSV
WORKFLOW_METRICS_CSV="${LOG_FILE%.log}_workflow_metrics.csv"
if [ -f "$WORKFLOW_METRICS_CSV" ]; then
    echo "   Found workflow metrics: $WORKFLOW_METRICS_CSV"

    # Calculate summary statistics using awk
    WORKFLOW_STATS=$(tail -n +2 "$WORKFLOW_METRICS_CSV" | awk -F',' '
    BEGIN {
        count = 0
        total_queued = 0
        total_running = 0
        total_total = 0
        min_queued = 999999
        max_queued = 0
        min_running = 999999
        max_running = 0
        complete = 0
        failed = 0
    }
    {
        count++
        queued = $7
        running = $8
        total = $9
        status = $3

        total_queued += queued
        total_running += running
        total_total += total

        if (queued < min_queued) min_queued = queued
        if (queued > max_queued) max_queued = queued
        if (running < min_running) min_running = running
        if (running > max_running) max_running = running

        if (tolower(status) ~ /complete/) complete++
        else if (tolower(status) ~ /fail/) failed++
    }
    END {
        if (count > 0) {
            printf "%d|%.1f|%.1f|%.1f|%.1f|%.1f|%.1f|%.1f|%d|%d",
                count,
                total_queued/count,
                min_queued,
                max_queued,
                total_running/count,
                min_running,
                max_running,
                total_total/count,
                complete,
                failed
        }
    }
    ')

    if [ -n "$WORKFLOW_STATS" ]; then
        WF_COUNT=$(echo "$WORKFLOW_STATS" | cut -d'|' -f1)
        WF_AVG_QUEUE=$(echo "$WORKFLOW_STATS" | cut -d'|' -f2)
        WF_MIN_QUEUE=$(echo "$WORKFLOW_STATS" | cut -d'|' -f3)
        WF_MAX_QUEUE=$(echo "$WORKFLOW_STATS" | cut -d'|' -f4)
        WF_AVG_RUN=$(echo "$WORKFLOW_STATS" | cut -d'|' -f5)
        WF_MIN_RUN=$(echo "$WORKFLOW_STATS" | cut -d'|' -f6)
        WF_MAX_RUN=$(echo "$WORKFLOW_STATS" | cut -d'|' -f7)
        WF_AVG_TOTAL=$(echo "$WORKFLOW_STATS" | cut -d'|' -f8)
        WF_COMPLETE=$(echo "$WORKFLOW_STATS" | cut -d'|' -f9)
        WF_FAILED=$(echo "$WORKFLOW_STATS" | cut -d'|' -f10)

        cat >> "$OUTPUT_FILE" <<'WFEOF'

        <div class="section">
            <h2 class="section-title">⏱️ Per-Workflow Metrics</h2>
            <p class="subtitle">Individual workflow timing breakdown (queue time, execution time, total duration)</p>

            <div class="workflow-summary">
WFEOF

        cat >> "$OUTPUT_FILE" <<WFEOF
                <div class="workflow-stat">
                    <div class="label">Workflows Tracked</div>
                    <div class="value">$WF_COUNT</div>
                </div>
                <div class="workflow-stat">
                    <div class="label">Avg Queue Time</div>
                    <div class="value">${WF_AVG_QUEUE}s</div>
                </div>
                <div class="workflow-stat">
                    <div class="label">Avg Run Time</div>
                    <div class="value">${WF_AVG_RUN}s</div>
                </div>
                <div class="workflow-stat">
                    <div class="label">Avg Total Time</div>
                    <div class="value">${WF_AVG_TOTAL}s</div>
                </div>
WFEOF

        cat >> "$OUTPUT_FILE" <<'WFEOF'
            </div>

            <h3 style="margin-top: 20px; color: #2c3e50;">Workflow Details</h3>
            <p style="font-size: 0.9em; color: #7f8c8d; margin-bottom: 10px;">Click column headers to sort. Showing all workflows from this test run.</p>

            <table class="chart-data-table sortable-table" id="workflowTable">
                <thead>
                    <tr>
                        <th onclick="sortTable(0)">Workflow ID</th>
                        <th onclick="sortTable(1)">Experiment ID</th>
                        <th onclick="sortTable(2)">Status</th>
                        <th onclick="sortTable(3)">Queue Time (s)</th>
                        <th onclick="sortTable(4)">Run Time (s)</th>
                        <th onclick="sortTable(5)">Total Time (s)</th>
                    </tr>
                </thead>
                <tbody>
WFEOF

        # Add workflow data rows (skip header, limit to first 100 for performance)
        tail -n +2 "$WORKFLOW_METRICS_CSV" | head -100 | while IFS=',' read -r wf_id exp_id status launch first last queued running total; do
            cat >> "$OUTPUT_FILE" <<WFEOF
                    <tr>
                        <td>$wf_id</td>
                        <td>$exp_id</td>
                        <td>$status</td>
                        <td>$queued</td>
                        <td>$running</td>
                        <td>$total</td>
                    </tr>
WFEOF
        done

        cat >> "$OUTPUT_FILE" <<'WFEOF'
                </tbody>
            </table>
        </div>

        <script>
        // Table sorting functionality
        function sortTable(columnIndex) {
            const table = document.getElementById('workflowTable');
            const tbody = table.querySelector('tbody');
            const rows = Array.from(tbody.querySelectorAll('tr'));
            const header = table.querySelectorAll('th')[columnIndex];
            const isNumeric = columnIndex >= 3; // Columns 3+ are numeric

            // Determine sort direction
            const currentSort = header.className;
            const isAscending = currentSort !== 'sort-asc';

            // Clear all sort indicators
            table.querySelectorAll('th').forEach(th => th.className = '');

            // Set new sort indicator
            header.className = isAscending ? 'sort-asc' : 'sort-desc';

            // Sort rows
            rows.sort((a, b) => {
                const aValue = a.cells[columnIndex].textContent.trim();
                const bValue = b.cells[columnIndex].textContent.trim();

                let comparison = 0;
                if (isNumeric) {
                    comparison = parseFloat(aValue) - parseFloat(bValue);
                } else {
                    comparison = aValue.localeCompare(bValue);
                }

                return isAscending ? comparison : -comparison;
            });

            // Re-append sorted rows
            rows.forEach(row => tbody.appendChild(row));
        }
        </script>
WFEOF
    fi
fi

cat >> "$OUTPUT_FILE" <<EOF

        <div class="section">
            <h2 class="section-title">Detailed Job Log</h2>
            <div class="filter-controls">
                <button class="filter-btn active" onclick="filterLogs('all')">All ($JOBS_SUBMITTED)</button>
                <button class="filter-btn" onclick="filterLogs('success')">Success ($SUCCESS_COUNT)</button>
                <button class="filter-btn" onclick="filterLogs('fail')">Failed ($FAIL_COUNT)</button>
            </div>
            <div class="log-entries" id="log-entries">
EOF

# Parse log entries and add to HTML
grep -E "^\[.*\] (SUCCESS|FAIL)" "$LOG_FILE" | while IFS= read -r line; do
    # Extract timestamp, status, and experiment ID using awk for reliability
    timestamp=$(echo "$line" | awk '{print $1, $2}')
    exp_id=$(echo "$line" | awk -F' - ' '{print $2}')

    # Determine status by checking if line contains SUCCESS or FAIL
    if echo "$line" | grep -q "SUCCESS"; then
        status="SUCCESS"
        status_class="success"
        status_symbol="✓"
    else
        status="FAIL"
        status_class="fail"
        status_symbol="✗"
    fi

    # Read next 2-3 lines for details
    log_section=$(grep -F -A 3 "$line" "$LOG_FILE" 2>/dev/null | tail -n +2)

    cat >> "$OUTPUT_FILE" <<LOGENTRY
                <div class="log-entry $status_class" data-status="$status_class">
                    <div>
                        <span class="log-timestamp">$timestamp</span>
                        <span class="log-status $status_class">$status_symbol $status</span>
                        <span>$exp_id</span>
                    </div>
                    <div class="log-details">
LOGENTRY

    # Add details from next lines
    echo "$log_section" | sed 's/^/                        /' >> "$OUTPUT_FILE"

    cat >> "$OUTPUT_FILE" <<LOGENTRY
                    </div>
                </div>
LOGENTRY
done

cat >> "$OUTPUT_FILE" <<'EOF'
            </div>
        </div>

        <footer>
            <p>Report generated on <span id="gen-date"></span></p>
            <p>XNAT Batch Performance Testing Tool</p>
        </footer>
    </div>
EOF

cat >> "$OUTPUT_FILE" <<EOF
    <script id="history-source" type="application/json" data-history-url="$(basename "$HISTORY_JSON_FILE")">
EOF
echo "$HISTORICAL_DATA" >> "$OUTPUT_FILE"
cat >> "$OUTPUT_FILE" <<'EOF'
    </script>
EOF

cat >> "$OUTPUT_FILE" <<'EOF'
    <script>
        let historicalData = [];

        async function loadHistoricalData() {
            const sourceEl = document.getElementById('history-source');
            if (!sourceEl) {
                return [];
            }

            const inlinePayload = (sourceEl.textContent || '').trim();
            const historyUrl = sourceEl.dataset.historyUrl;

            if (historyUrl) {
                try {
                    const response = await fetch(historyUrl, { cache: 'no-store' });
                    if (response.ok) {
                        const remoteData = await response.json();
                        return Array.isArray(remoteData) ? remoteData : [];
                    }
                } catch (error) {
                    console.warn('Unable to fetch historical data', error);
                }
            }

            if (inlinePayload) {
                try {
                    const inlineData = JSON.parse(inlinePayload);
                    return Array.isArray(inlineData) ? inlineData : [];
                } catch (error) {
                    console.warn('Unable to parse inline historical data', error);
                }
            }

            return [];
        }

        // Set generation date
        const genDateEl = document.getElementById('gen-date');
        if (genDateEl) {
            genDateEl.textContent = new Date().toLocaleString();
        }

        // Function to create SVG line chart
        function createLineChart(svgId, data, color, label, maxY = null) {
            const svg = document.getElementById(svgId);
            if (!svg || !data || data.length === 0) return;

            const width = svg.clientWidth || 800;
            const height = svg.clientHeight || 250;
            const padding = {top: 20, right: 30, bottom: 30, left: 60};
            const chartWidth = width - padding.left - padding.right;
            const chartHeight = height - padding.top - padding.bottom;

            svg.setAttribute('viewBox', `0 0 ${width} ${height}`);

            // Calculate scales
            const minVal = Math.min(...data);
            const maxVal = maxY !== null ? maxY : Math.max(...data);
            const range = maxVal - (maxY !== null ? 0 : minVal);

            // Draw grid lines
            const gridLines = 5;
            for (let i = 0; i <= gridLines; i++) {
                const y = padding.top + (chartHeight / gridLines) * i;
                const gridLine = document.createElementNS('http://www.w3.org/2000/svg', 'line');
                gridLine.setAttribute('x1', padding.left);
                gridLine.setAttribute('y1', y);
                gridLine.setAttribute('x2', width - padding.right);
                gridLine.setAttribute('y2', y);
                gridLine.setAttribute('stroke', '#ecf0f1');
                gridLine.setAttribute('stroke-width', '1');
                svg.appendChild(gridLine);

                // Y-axis labels
                const labelValue = maxVal - (range / gridLines) * i;
                const text = document.createElementNS('http://www.w3.org/2000/svg', 'text');
                text.setAttribute('x', padding.left - 10);
                text.setAttribute('y', y + 5);
                text.setAttribute('text-anchor', 'end');
                text.setAttribute('fill', '#7f8c8d');
                text.setAttribute('font-size', '12');
                text.textContent = labelValue.toFixed(1);
                svg.appendChild(text);
            }

            // Create path for line
            let pathData = '';
            data.forEach((value, index) => {
                const x = padding.left + (chartWidth / (data.length - 1)) * index;
                const y = padding.top + chartHeight - ((value - (maxY !== null ? 0 : minVal)) / range) * chartHeight;

                if (index === 0) {
                    pathData += `M ${x} ${y}`;
                } else {
                    pathData += ` L ${x} ${y}`;
                }

                // Add dot
                const circle = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
                circle.setAttribute('cx', x);
                circle.setAttribute('cy', y);
                circle.setAttribute('r', '4');
                circle.setAttribute('fill', color);
                svg.appendChild(circle);
            });

            // Add the line path
            const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
            path.setAttribute('d', pathData);
            path.setAttribute('fill', 'none');
            path.setAttribute('stroke', color);
            path.setAttribute('stroke-width', '2');
            svg.insertBefore(path, svg.firstChild);

            // Add area fill
            const areaData = pathData + ` L ${width - padding.right} ${padding.top + chartHeight} L ${padding.left} ${padding.top + chartHeight} Z`;
            const area = document.createElementNS('http://www.w3.org/2000/svg', 'path');
            area.setAttribute('d', areaData);
            area.setAttribute('fill', color);
            area.setAttribute('fill-opacity', '0.1');
            svg.insertBefore(area, svg.firstChild);
        }

        // Function to calculate stats
        function calculateStats(data, label, unit) {
            if (!data || data.length === 0) return '';

            const latest = data[data.length - 1];
            const avg = data.reduce((a, b) => a + b, 0) / data.length;
            const min = Math.min(...data);
            const max = Math.max(...data);

            // Calculate trend
            let trend = 'stable';
            let trendSymbol = '→';
            let trendClass = 'trend-stable';

            if (data.length >= 2) {
                const recent = data.slice(-3).reduce((a, b) => a + b, 0) / Math.min(3, data.length);
                const older = data.slice(0, -3).reduce((a, b) => a + b, 0) / (data.length - Math.min(3, data.length));

                if (recent > older * 1.1) {
                    trend = 'increasing';
                    trendSymbol = '↑';
                    trendClass = 'trend-up';
                } else if (recent < older * 0.9) {
                    trend = 'decreasing';
                    trendSymbol = '↓';
                    trendClass = 'trend-down';
                }
            }

            return `<p style="margin-top: 10px; color: #7f8c8d;">
                <strong>Latest:</strong> ${latest.toFixed(1)}${unit} |
                <strong>Avg:</strong> ${avg.toFixed(1)}${unit} |
                <strong>Min:</strong> ${min.toFixed(1)}${unit} |
                <strong>Max:</strong> ${max.toFixed(1)}${unit} |
                <strong class="${trendClass}">Trend: ${trend} ${trendSymbol}</strong>
            </p>`;
        }

        // Initialize trend charts
        function initTrendCharts() {
            if (!historicalData || historicalData.length === 0) {
                return;
            }

            const submissionTimes = historicalData.map(d => d.submission_time);
            const executionTimes = historicalData.map(d => d.execution_time);
            const throughputs = historicalData.map(d => d.throughput);
            const successRates = historicalData.map(d => {
                return d.total_jobs > 0 ? (d.success_count / d.total_jobs * 100) : 0;
            });

            createLineChart('submissionChart', submissionTimes, 'rgb(52, 152, 219)', 'Submission Time');
            createLineChart('executionChart', executionTimes, 'rgb(155, 89, 182)', 'Execution Time');
            createLineChart('throughputChart', throughputs, 'rgb(230, 126, 34)', 'Throughput');
            createLineChart('successRateChart', successRates, 'rgb(46, 204, 113)', 'Success Rate', 100);

            // Add stats
            document.getElementById('submissionStats').innerHTML = calculateStats(submissionTimes, 'Submission Time', 's');
            document.getElementById('executionStats').innerHTML = calculateStats(executionTimes, 'Execution Time', 's');
            document.getElementById('throughputStats').innerHTML = calculateStats(throughputs, 'Throughput', ' jobs/s');
            document.getElementById('successStats').innerHTML = calculateStats(successRates, 'Success Rate', '%');
        }

        // Filter logs
        function filterLogs(filter) {
            const entries = document.querySelectorAll('.log-entry');
            const buttons = document.querySelectorAll('.filter-btn');

            // Update button states
            buttons.forEach(btn => btn.classList.remove('active'));
            event.target.classList.add('active');

            // Filter entries
            entries.forEach(entry => {
                if (filter === 'all') {
                    entry.style.display = 'block';
                } else if (entry.dataset.status === filter) {
                    entry.style.display = 'block';
                } else {
                    entry.style.display = 'none';
                }
            });
        }

        // Animate progress bars and load history on page load
        window.addEventListener('load', async () => {
            document.querySelectorAll('.progress-bar-success, .progress-bar-fail').forEach(bar => {
                const width = bar.style.width;
                bar.style.width = '0%';
                setTimeout(() => {
                    bar.style.width = width;
                }, 100);
            });

            historicalData = await loadHistoricalData();
            initTrendCharts();
        });
    </script>
</body>
</html>
EOF

# Persist historical data JSON for reference/upload
if ! printf '%s\n' "$HISTORICAL_DATA" | jq '.' > "$HISTORY_JSON_FILE" 2>/dev/null; then
    echo "[]" > "$HISTORY_JSON_FILE"
fi

echo -e "${GREEN}✓ HTML report generated successfully${NC}"
echo ""
echo "Report saved to: $OUTPUT_FILE"
echo "Historical data JSON: $HISTORY_JSON_FILE"
echo ""

# Upload to XNAT if credentials provided
if [ -n "$XNAT_HOST" ] && [ -n "$USERNAME" ] && [ -n "$PASSWORD" ] && [ -n "$REPORT_PROJECT" ]; then
    echo -e "${YELLOW}Uploading report to XNAT...${NC}"
    echo ""
    echo "Target: $XNAT_HOST"
    echo "Project: $REPORT_PROJECT"
    echo "Resource: BATCH_TESTS"
    echo ""

    # Authenticate
    echo -e "${YELLOW}Authenticating...${NC}"
    JSESSION=$(curl -s -u "${USERNAME}:${PASSWORD}" "${XNAT_HOST}/data/JSESSION")

    if [ -z "$JSESSION" ]; then
        echo -e "${RED}Failed to authenticate${NC}"
        exit 1
    fi

    echo -e "${GREEN}✓ Authenticated${NC}"

    # Check if project exists
    echo -e "${YELLOW}Verifying project exists...${NC}"
    PROJECT_CHECK=$(curl -s -b "JSESSIONID=$JSESSION" "${XNAT_HOST}/data/projects/${REPORT_PROJECT}?format=json")

    if echo "$PROJECT_CHECK" | grep -q "<!doctype html"; then
        echo -e "${RED}Project $REPORT_PROJECT not found${NC}"
        echo "Please create the project first or specify an existing project."
        exit 1
    fi

    echo -e "${GREEN}✓ Project exists${NC}"

    # Generate filename with timestamp and run-specific subfolder
    FILENAME=$(basename "$OUTPUT_FILE")
    DATE_FOLDER=$(date '+%Y-%m-%d')
    RUN_TIME=$(date '+%H%M%S')
    RUN_FOLDER="${DATE_FOLDER}/${RUN_TIME}"
    UPLOAD_PATH="${RUN_FOLDER}/${FILENAME}"

    # Upload HTML report to project resource
    echo -e "${YELLOW}Uploading $FILENAME to ${RUN_FOLDER}/...${NC}"
    echo "Upload URL: ${XNAT_HOST}/data/projects/${REPORT_PROJECT}/resources/BATCH_TESTS/files/${UPLOAD_PATH}"

    if upload_with_retry "$OUTPUT_FILE" "text/html" "$UPLOAD_PATH" "BATCH_TEST_REPORT" "HTML report"; then
        echo ""
        echo "Report uploaded to:"
        echo "  ${XNAT_HOST}/data/projects/${REPORT_PROJECT}/resources/BATCH_TESTS/files/${UPLOAD_PATH}"
        echo ""
        echo "View in XNAT:"
        echo "  ${XNAT_HOST}/app/action/DisplayItemAction/search_element/xnat:projectData/search_field/xnat:projectData.ID/search_value/${REPORT_PROJECT}/popup/false"
    else
        exit 1
    fi

    # Upload historical JSON alongside report
    if [ -f "$HISTORY_JSON_FILE" ]; then
        echo ""
        echo -e "${YELLOW}Uploading historical performance data...${NC}"
        HISTORY_JSON_NAME=$(basename "$HISTORY_JSON_FILE")
        HISTORY_UPLOAD_PATH="${RUN_FOLDER}/${HISTORY_JSON_NAME}"

        if ! upload_with_retry "$HISTORY_JSON_FILE" "application/json" "$HISTORY_UPLOAD_PATH" "BATCH_TEST_HISTORY" "Historical data"; then
            echo -e "${YELLOW}⚠ Proceeding without uploading historical JSON${NC}"
        fi
    fi

    # Also upload the original log file
    if [ -f "$LOG_FILE" ]; then
        echo ""
        echo -e "${YELLOW}Uploading original log file...${NC}"
        LOG_FILENAME=$(basename "$LOG_FILE")
        UPLOAD_LOG_PATH="${RUN_FOLDER}/${LOG_FILENAME}"

        if ! upload_with_retry "$LOG_FILE" "text/plain" "$UPLOAD_LOG_PATH" "BATCH_TEST_LOG" "Log file"; then
            echo -e "${YELLOW}⚠ Log upload failed after retries${NC}"
        fi
    fi

    echo ""
fi

echo "Open in browser:"
echo "  open $OUTPUT_FILE"
echo ""
