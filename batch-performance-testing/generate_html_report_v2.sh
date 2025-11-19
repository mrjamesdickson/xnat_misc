#!/bin/bash

# HTML Report Generator v2 - Data-driven version
# Creates a lightweight HTML viewer that loads external data files

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Usage
usage() {
    echo "Usage: $0 -l <LOG_FILE> [-o <OUTPUT_DIR>] [-h <XNAT_HOST>] [-u <USERNAME>] [-p <PASSWORD>] [-r <REPORT_PROJECT>]"
    echo "  -l  Log file to convert (required)"
    echo "  -o  Output directory (optional - defaults to same directory as log)"
    echo "  -h  XNAT host for upload (optional)"
    echo "  -u  XNAT username for upload (optional)"
    echo "  -p  XNAT password for upload (optional)"
    echo "  -r  Report project ID to upload to (creates BATCH_TESTS resource)"
    exit 1
}

# Parse arguments
while getopts "l:o:h:u:p:r:" opt; do
    case $opt in
        l) LOG_FILE="$OPTARG" ;;
        o) OUTPUT_DIR="$OPTARG" ;;
        h) XNAT_HOST="$OPTARG" ;;
        u) USERNAME="$OPTARG" ;;
        p) PASSWORD="$OPTARG" ;;
        r) REPORT_PROJECT="$OPTARG" ;;
        *) usage ;;
    esac
done

# Remove trailing slash from host
XNAT_HOST="${XNAT_HOST%/}"

if [ -z "$LOG_FILE" ]; then
    usage
fi

if [ ! -f "$LOG_FILE" ]; then
    echo -e "${RED}Log file not found: $LOG_FILE${NC}"
    exit 1
fi

# Determine output directory
if [ -z "$OUTPUT_DIR" ]; then
    OUTPUT_DIR=$(dirname "$LOG_FILE")
fi

# Get base filename without extension
BASENAME=$(basename "$LOG_FILE" .log)

# Output files
METADATA_JSON="$OUTPUT_DIR/${BASENAME}_data.json"
HTML_FILE="$OUTPUT_DIR/${BASENAME}.html"
WORKFLOW_CSV="$OUTPUT_DIR/${BASENAME}_workflow_metrics.csv"

echo -e "${GREEN}=== HTML Report Generator v2 ===${NC}"
echo "Log file: $LOG_FILE"
echo "Output directory: $OUTPUT_DIR"
echo ""

# Extract metadata from log
echo -e "${YELLOW}Extracting metadata...${NC}"

HOST=$(grep "^Host:" "$LOG_FILE" | head -1 | sed 's/Host: //' || echo "N/A")
USER=$(grep "^User:" "$LOG_FILE" | head -1 | sed 's/User: //' || echo "N/A")
CSV_FILE=$(grep "^CSV File:" "$LOG_FILE" | head -1 | sed 's/CSV File: //' || echo "N/A")
CONTAINER=$(grep "^Container:" "$LOG_FILE" | head -1 | sed 's/Container: //' || echo "N/A")
JOBS_SUBMITTED=$(grep "^Jobs Submitted:" "$LOG_FILE" | sed 's/Jobs Submitted: //' || echo "0")
SUCCESS_COUNT=$(grep "Successfully Queued:" "$LOG_FILE" | sed -E 's/.*Successfully Queued: ([0-9]+).*/\1/' || echo "0")
FAIL_COUNT=$(grep "Failed to Queue:" "$LOG_FILE" | sed -E 's/.*Failed to Queue: ([0-9]+).*/\1/' || echo "0")
SUBMISSION_DURATION=$(grep "Submission Duration:" "$LOG_FILE" | sed -E 's/.*Submission Duration: ([^ ]+).*/\1/' || echo "0s")
EXECUTION_DURATION=$(grep "Execution Duration:" "$LOG_FILE" | sed -E 's/.*Execution Duration: ([^ ]+).*/\1/' || echo "0s")
THROUGHPUT=$(grep "Submission Throughput:" "$LOG_FILE" | sed -E 's/.*Submission Throughput: ([^ ]+).*/\1/' || echo "0.00")

# Extract query performance data (BSD-compatible)
QUERY_TIMES=$(grep -oE 'query: [0-9.]+s' "$LOG_FILE" 2>/dev/null | sed 's/query: //; s/s$//' || echo "")

# Build JSON
echo -e "${YELLOW}Creating metadata JSON...${NC}"

cat > "$METADATA_JSON" <<EOF
{
  "test_info": {
    "host": "$HOST",
    "user": "$USER",
    "csv_file": "$CSV_FILE",
    "container": "$CONTAINER"
  },
  "results": {
    "jobs_submitted": $JOBS_SUBMITTED,
    "successful": $SUCCESS_COUNT,
    "failed": $FAIL_COUNT,
    "submission_duration": "$SUBMISSION_DURATION",
    "execution_duration": "$EXECUTION_DURATION",
    "throughput": "$THROUGHPUT"
  },
  "query_performance": [
EOF

# Add query times as JSON array
if [ -n "$QUERY_TIMES" ]; then
    FIRST=true
    for time in $QUERY_TIMES; do
        if [ "$FIRST" = true ]; then
            echo "    $time" >> "$METADATA_JSON"
            FIRST=false
        else
            echo "    ,$time" >> "$METADATA_JSON"
        fi
    done
fi

cat >> "$METADATA_JSON" <<EOF
  ]
}
EOF

echo -e "${GREEN}✓ Metadata JSON created: $METADATA_JSON${NC}"

# Create lightweight HTML viewer
echo -e "${YELLOW}Creating HTML viewer...${NC}"

cat > "$HTML_FILE" <<'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>XNAT Batch Performance Report</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            padding: 20px;
            min-height: 100vh;
        }
        .container {
            max-width: 1400px;
            margin: 0 auto;
            background: white;
            border-radius: 12px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            overflow: hidden;
        }
        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 30px;
            text-align: center;
        }
        .header h1 {
            font-size: 2.5em;
            margin-bottom: 10px;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.2);
        }
        .header p {
            font-size: 1.1em;
            opacity: 0.9;
        }
        .content {
            padding: 30px;
        }
        .loading {
            text-align: center;
            padding: 50px;
            color: #666;
            font-size: 1.2em;
        }
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .stat-card {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
        }
        .stat-label {
            font-size: 0.9em;
            opacity: 0.9;
            margin-bottom: 5px;
        }
        .stat-value {
            font-size: 2em;
            font-weight: bold;
        }
        .chart-wrapper {
            background: white;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            margin-bottom: 30px;
        }
        .chart-wrapper h3 {
            margin-bottom: 15px;
            color: #333;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            background: white;
            border-radius: 8px;
            overflow: hidden;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        thead {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
        }
        th, td {
            padding: 12px;
            text-align: left;
            border-bottom: 1px solid #eee;
        }
        tbody tr:hover {
            background: #f8f9fa;
        }
        .status-complete {
            color: #28a745;
            font-weight: bold;
        }
        .status-failed {
            color: #dc3545;
            font-weight: bold;
        }
        .error {
            background: #f8d7da;
            color: #721c24;
            padding: 20px;
            border-radius: 8px;
            margin: 20px 0;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>XNAT Batch Performance Report</h1>
            <p id="test-info">Loading test data...</p>
        </div>
        <div class="content">
            <div id="loading" class="loading">Loading data files...</div>
            <div id="error" class="error" style="display:none;"></div>
            <div id="report" style="display:none;">
                <div class="stats-grid" id="stats"></div>

                <div class="chart-wrapper">
                    <h3>Query Response Time Over Test Duration</h3>
                    <canvas id="queryPerfChart"></canvas>
                </div>

                <div class="chart-wrapper">
                    <h3>Workflow Execution Time Distribution</h3>
                    <canvas id="workflowTimingChart"></canvas>
                </div>

                <div class="chart-wrapper">
                    <h3>Per-Workflow Details</h3>
                    <table id="workflow-table">
                        <thead>
                            <tr>
                                <th>Workflow ID</th>
                                <th>Experiment ID</th>
                                <th>Status</th>
                                <th>Queued (s)</th>
                                <th>Running (s)</th>
                                <th>Total (s)</th>
                                <th>State Timeline</th>
                            </tr>
                        </thead>
                        <tbody id="workflow-tbody"></tbody>
                    </table>
                </div>
            </div>
        </div>
    </div>

    <script>
        // Get basename from HTML filename
        const htmlPath = window.location.pathname;
        const basename = htmlPath.split('/').pop().replace('.html', '');
        const dataFile = basename + '_data.json';
        const workflowFile = basename + '_workflow_metrics.csv';

        let metadata = null;
        let workflows = [];

        // Load metadata JSON
        fetch(dataFile)
            .then(response => {
                if (!response.ok) throw new Error('Failed to load metadata: ' + dataFile);
                return response.json();
            })
            .then(data => {
                metadata = data;
                document.getElementById('test-info').textContent =
                    `Host: ${data.test_info.host} | Container: ${data.test_info.container}`;
                renderStats(data);
                renderQueryChart(data);
                return fetch(workflowFile);
            })
            .then(response => {
                if (!response.ok) throw new Error('Failed to load workflows: ' + workflowFile);
                return response.text();
            })
            .then(csv => {
                workflows = parseCSV(csv);
                renderWorkflowTable(workflows);
                renderWorkflowChart(workflows);
                document.getElementById('loading').style.display = 'none';
                document.getElementById('report').style.display = 'block';
            })
            .catch(error => {
                console.error('Error loading data:', error);
                document.getElementById('loading').style.display = 'none';
                document.getElementById('error').style.display = 'block';
                document.getElementById('error').textContent =
                    'Error loading data files: ' + error.message +
                    '\n\nMake sure the following files are in the same directory:\n' +
                    '- ' + dataFile + '\n' +
                    '- ' + workflowFile;
            });

        function renderStats(data) {
            const stats = [
                { label: 'Jobs Submitted', value: data.results.jobs_submitted },
                { label: 'Successful', value: data.results.successful },
                { label: 'Failed', value: data.results.failed },
                { label: 'Throughput', value: data.results.throughput + ' jobs/s' }
            ];

            const html = stats.map(s => `
                <div class="stat-card">
                    <div class="stat-label">${s.label}</div>
                    <div class="stat-value">${s.value}</div>
                </div>
            `).join('');

            document.getElementById('stats').innerHTML = html;
        }

        function renderQueryChart(data) {
            const ctx = document.getElementById('queryPerfChart').getContext('2d');
            const queryData = data.query_performance || [];
            const labels = queryData.map((_, i) => `Check ${i + 1}`);

            new Chart(ctx, {
                type: 'line',
                data: {
                    labels: labels,
                    datasets: [{
                        label: 'Query Response Time (seconds)',
                        data: queryData,
                        borderColor: 'rgb(75, 192, 192)',
                        backgroundColor: 'rgba(75, 192, 192, 0.1)',
                        tension: 0.1,
                        fill: true
                    }]
                },
                options: {
                    responsive: true,
                    plugins: {
                        legend: { display: true },
                        tooltip: { mode: 'index', intersect: false }
                    },
                    scales: {
                        y: {
                            beginAtZero: true,
                            title: { display: true, text: 'Seconds' }
                        }
                    }
                }
            });
        }

        function parseCSV(text) {
            const lines = text.trim().split('\n');
            const headers = lines[0].split(',');
            return lines.slice(1).map(line => {
                const values = line.split(',');
                const obj = {};
                headers.forEach((header, i) => {
                    obj[header.trim()] = values[i];
                });
                return obj;
            });
        }

        function renderWorkflowTable(workflows) {
            const tbody = document.getElementById('workflow-tbody');
            tbody.innerHTML = workflows.map(w => {
                const statusClass = w.Status === 'Complete' ? 'status-complete' : 'status-failed';
                return `
                    <tr>
                        <td>${w.WorkflowID || 'N/A'}</td>
                        <td>${w.ExperimentID || 'N/A'}</td>
                        <td class="${statusClass}">${w.Status || 'N/A'}</td>
                        <td>${parseFloat(w.QueuedDuration || 0).toFixed(1)}</td>
                        <td>${parseFloat(w.RunningDuration || 0).toFixed(1)}</td>
                        <td>${parseFloat(w.TotalDuration || 0).toFixed(1)}</td>
                        <td style="font-size: 0.85em">${w.StateTimeline || 'N/A'}</td>
                    </tr>
                `;
            }).join('');
        }

        function renderWorkflowChart(workflows) {
            const ctx = document.getElementById('workflowTimingChart').getContext('2d');
            const labels = workflows.map((w, i) => `WF ${i + 1}`);
            const queuedTimes = workflows.map(w => parseFloat(w.QueuedDuration || 0));
            const runningTimes = workflows.map(w => parseFloat(w.RunningDuration || 0));

            new Chart(ctx, {
                type: 'bar',
                data: {
                    labels: labels,
                    datasets: [
                        {
                            label: 'Queued Time',
                            data: queuedTimes,
                            backgroundColor: 'rgba(255, 159, 64, 0.7)',
                            stack: 'Stack 0'
                        },
                        {
                            label: 'Running Time',
                            data: runningTimes,
                            backgroundColor: 'rgba(54, 162, 235, 0.7)',
                            stack: 'Stack 0'
                        }
                    ]
                },
                options: {
                    responsive: true,
                    plugins: {
                        legend: { display: true },
                        tooltip: { mode: 'index', intersect: false }
                    },
                    scales: {
                        x: { stacked: true },
                        y: {
                            stacked: true,
                            title: { display: true, text: 'Seconds' }
                        }
                    }
                }
            });
        }
    </script>
</body>
</html>
HTMLEOF

echo -e "${GREEN}✓ HTML viewer created: $HTML_FILE${NC}"

# Check if workflow CSV exists
if [ -f "$WORKFLOW_CSV" ]; then
    echo -e "${GREEN}✓ Found workflow metrics CSV: $WORKFLOW_CSV${NC}"
else
    echo -e "${YELLOW}⚠ Workflow metrics CSV not found: $WORKFLOW_CSV${NC}"
    echo -e "${YELLOW}  The report will show an error. Make sure the CSV is in the same directory.${NC}"
fi

# Upload to XNAT if requested
if [ -n "$REPORT_PROJECT" ] && [ -n "$XNAT_HOST" ] && [ -n "$USERNAME" ] && [ -n "$PASSWORD" ]; then
    echo ""
    echo -e "${YELLOW}=== Uploading to XNAT ===${NC}"

    # Authenticate
    echo -e "${YELLOW}Authenticating...${NC}"
    JSESSION=$(curl -s -u "${USERNAME}:${PASSWORD}" "${XNAT_HOST}/data/JSESSION" || echo "")

    if [ -z "$JSESSION" ]; then
        echo -e "${RED}✗ Authentication failed${NC}"
    else
        echo -e "${GREEN}✓ Authenticated${NC}"

        # Create resource if needed
        RESOURCE_URL="${XNAT_HOST}/data/projects/${REPORT_PROJECT}/resources/BATCH_TESTS"

        # Upload files using original names so HTML can find them
        # Note: Filenames already contain timestamp from log generation

        # Upload HTML
        echo -e "${YELLOW}Uploading HTML report...${NC}"
        HTML_UPLOAD_NAME=$(basename "$HTML_FILE")
        curl -s -b "JSESSIONID=$JSESSION" -X PUT \
            -H "Content-Type: text/html" \
            --data-binary "@$HTML_FILE" \
            "${RESOURCE_URL}/files/${HTML_UPLOAD_NAME}" > /dev/null
        echo -e "${GREEN}✓ HTML uploaded: ${HTML_UPLOAD_NAME}${NC}"

        # Upload JSON metadata
        echo -e "${YELLOW}Uploading metadata JSON...${NC}"
        JSON_UPLOAD_NAME=$(basename "$METADATA_JSON")
        curl -s -b "JSESSIONID=$JSESSION" -X PUT \
            -H "Content-Type: application/json" \
            --data-binary "@$METADATA_JSON" \
            "${RESOURCE_URL}/files/${JSON_UPLOAD_NAME}" > /dev/null
        echo -e "${GREEN}✓ JSON uploaded: ${JSON_UPLOAD_NAME}${NC}"

        # Upload workflow CSV
        if [ -f "$WORKFLOW_CSV" ]; then
            echo -e "${YELLOW}Uploading workflow metrics CSV...${NC}"
            CSV_UPLOAD_NAME=$(basename "$WORKFLOW_CSV")
            curl -s -b "JSESSIONID=$JSESSION" -X PUT \
                -H "Content-Type: text/csv" \
                --data-binary "@$WORKFLOW_CSV" \
                "${RESOURCE_URL}/files/${CSV_UPLOAD_NAME}" > /dev/null
            echo -e "${GREEN}✓ CSV uploaded: ${CSV_UPLOAD_NAME}${NC}"
        fi

        # Upload original log file for reference
        if [ -f "$LOG_FILE" ]; then
            echo -e "${YELLOW}Uploading log file...${NC}"
            LOG_UPLOAD_NAME=$(basename "$LOG_FILE")
            curl -s -b "JSESSIONID=$JSESSION" -X PUT \
                -H "Content-Type: text/plain" \
                --data-binary "@$LOG_FILE" \
                "${RESOURCE_URL}/files/${LOG_UPLOAD_NAME}" > /dev/null
            echo -e "${GREEN}✓ Log uploaded: ${LOG_UPLOAD_NAME}${NC}"
        fi

        echo ""
        echo -e "${GREEN}✓ All files uploaded to XNAT${NC}"
        echo -e "${BLUE}View at: ${XNAT_HOST}/data/projects/${REPORT_PROJECT}/resources/BATCH_TESTS${NC}"
    fi
fi

echo ""
echo -e "${GREEN}=== Report Generation Complete ===${NC}"
echo ""
echo "Generated files:"
echo "  - HTML: $HTML_FILE"
echo "  - Data: $METADATA_JSON"
echo "  - Workflows: $WORKFLOW_CSV"
echo ""
echo "Open in browser:"
echo "  open $HTML_FILE"
