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

echo -e "${GREEN}=== HTML Report Generator ===${NC}"
echo ""

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
                    <div class="stat-label">Total Duration</div>
                    <div class="stat-value">$(echo "$TOTAL_DURATION" | awk '{print $1}')</div>
                    <div class="stat-sublabel">$TOTAL_DURATION</div>
                </div>
                <div class="stat-card performance">
                    <div class="stat-label">Throughput</div>
                    <div class="stat-value">$(echo "$THROUGHPUT" | awk '{print $1}')</div>
                    <div class="stat-sublabel">$THROUGHPUT</div>
                </div>
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

    <script>
        // Set generation date
        document.getElementById('gen-date').textContent = new Date().toLocaleString();

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

        // Animate progress bars on load
        window.addEventListener('load', () => {
            document.querySelectorAll('.progress-bar-success, .progress-bar-fail').forEach(bar => {
                const width = bar.style.width;
                bar.style.width = '0%';
                setTimeout(() => {
                    bar.style.width = width;
                }, 100);
            });
        });
    </script>
</body>
</html>
EOF

echo -e "${GREEN}✓ HTML report generated successfully${NC}"
echo ""
echo "Report saved to: $OUTPUT_FILE"
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

    # Debug: show the upload URL
    echo "Upload URL: ${XNAT_HOST}/data/projects/${REPORT_PROJECT}/resources/BATCH_TESTS/files/${UPLOAD_PATH}"

    UPLOAD_RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X PUT \
        -b "JSESSIONID=$JSESSION" \
        -H "Content-Type: text/html" \
        --data-binary "@${OUTPUT_FILE}" \
        "${XNAT_HOST}/data/projects/${REPORT_PROJECT}/resources/BATCH_TESTS/files/${UPLOAD_PATH}?format=json&content=BATCH_TEST_REPORT&inbody=true")

    # Extract HTTP code and response body
    HTTP_CODE=$(echo "$UPLOAD_RESPONSE" | grep "HTTP_CODE:" | sed 's/HTTP_CODE://')
    RESPONSE_BODY=$(echo "$UPLOAD_RESPONSE" | grep -v "HTTP_CODE:")

    echo "HTTP Code: $HTTP_CODE"

    # Check if upload was successful (200 or 201)
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
        echo -e "${GREEN}✓ Upload successful${NC}"
        echo ""
        echo "Report uploaded to:"
        echo "  ${XNAT_HOST}/data/projects/${REPORT_PROJECT}/resources/BATCH_TESTS/files/${UPLOAD_PATH}"
        echo ""
        echo "View in XNAT:"
        echo "  ${XNAT_HOST}/app/action/DisplayItemAction/search_element/xnat:projectData/search_field/xnat:projectData.ID/search_value/${REPORT_PROJECT}/popup/false"
    else
        echo -e "${RED}Upload failed${NC}"
        echo "HTTP Code: $HTTP_CODE"
        echo "Response: $RESPONSE_BODY"

        # Try to parse error message if it's JSON
        if echo "$RESPONSE_BODY" | jq empty 2>/dev/null; then
            echo "Error details:"
            echo "$RESPONSE_BODY" | jq '.'
        fi
        exit 1
    fi

    # Also upload the original log file
    if [ -f "$LOG_FILE" ]; then
        echo ""
        echo -e "${YELLOW}Uploading original log file...${NC}"
        LOG_FILENAME=$(basename "$LOG_FILE")
        UPLOAD_LOG_PATH="${RUN_FOLDER}/${LOG_FILENAME}"

        LOG_UPLOAD_RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X PUT \
            -b "JSESSIONID=$JSESSION" \
            -H "Content-Type: text/plain" \
            --data-binary "@${LOG_FILE}" \
            "${XNAT_HOST}/data/projects/${REPORT_PROJECT}/resources/BATCH_TESTS/files/${UPLOAD_LOG_PATH}?format=json&content=BATCH_TEST_LOG&inbody=true")

        LOG_HTTP_CODE=$(echo "$LOG_UPLOAD_RESPONSE" | grep "HTTP_CODE:" | sed 's/HTTP_CODE://')

        if [ "$LOG_HTTP_CODE" = "200" ] || [ "$LOG_HTTP_CODE" = "201" ]; then
            echo -e "${GREEN}✓ Log file uploaded${NC}"
        else
            echo -e "${YELLOW}⚠ Log upload failed (HTTP $LOG_HTTP_CODE)${NC}"
        fi
    fi

    echo ""
fi

echo "Open in browser:"
echo "  open $OUTPUT_FILE"
echo ""
