#!/bin/bash
# Generate HTML Report from Index Test Results
# Creates an interactive HTML dashboard with drill-down details

set -e

# Check if results directory provided
if [ -z "$1" ]; then
    # Find latest results directory
    RESULTS_DIR=$(ls -td ./results/*/ 2>/dev/null | head -1)
    if [ -z "$RESULTS_DIR" ]; then
        echo "Error: No results directory found"
        exit 1
    fi
else
    RESULTS_DIR="$1"
fi

# Remove trailing slash
RESULTS_DIR="${RESULTS_DIR%/}"

echo "Generating HTML report for: $RESULTS_DIR"

# Database connection (use same defaults as main script)
DB_USER="${DB_USER:-xnat}"
DB_NAME="${DB_NAME:-xnat}"
DOCKER_CONTAINER="${DOCKER_CONTAINER:-xnat-db}"

# Output file
OUTPUT_FILE="$RESULTS_DIR/index_test_report.html"

# Generate HTML
cat > "$OUTPUT_FILE" <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>PostgreSQL Index Test Report</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
            background: #f5f7fa;
            color: #333;
            line-height: 1.6;
        }

        .container {
            max-width: 1400px;
            margin: 0 auto;
            padding: 20px;
        }

        header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 40px 20px;
            margin-bottom: 30px;
            border-radius: 8px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
        }

        header h1 {
            font-size: 2.5rem;
            margin-bottom: 10px;
        }

        header .subtitle {
            opacity: 0.9;
            font-size: 1.1rem;
        }

        .summary-cards {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }

        .card {
            background: white;
            padding: 25px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            transition: transform 0.2s, box-shadow 0.2s;
        }

        .card:hover {
            transform: translateY(-2px);
            box-shadow: 0 4px 8px rgba(0,0,0,0.15);
        }

        .card-title {
            font-size: 0.875rem;
            color: #666;
            text-transform: uppercase;
            letter-spacing: 0.5px;
            margin-bottom: 8px;
        }

        .card-value {
            font-size: 2.5rem;
            font-weight: bold;
            color: #667eea;
        }

        .card-label {
            font-size: 0.875rem;
            color: #999;
            margin-top: 5px;
        }

        .section {
            background: white;
            padding: 30px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            margin-bottom: 30px;
        }

        .section-title {
            font-size: 1.5rem;
            margin-bottom: 20px;
            color: #333;
            border-bottom: 2px solid #667eea;
            padding-bottom: 10px;
        }

        table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 15px;
        }

        th {
            background: #f8f9fa;
            padding: 12px;
            text-align: left;
            font-weight: 600;
            color: #555;
            border-bottom: 2px solid #dee2e6;
            position: sticky;
            top: 0;
            z-index: 10;
        }

        td {
            padding: 12px;
            border-bottom: 1px solid #dee2e6;
        }

        tr:hover {
            background: #f8f9fa;
        }

        .badge {
            display: inline-block;
            padding: 4px 12px;
            border-radius: 12px;
            font-size: 0.875rem;
            font-weight: 500;
        }

        .badge-success {
            background: #d4edda;
            color: #155724;
        }

        .badge-danger {
            background: #f8d7da;
            color: #721c24;
        }

        .badge-info {
            background: #d1ecf1;
            color: #0c5460;
        }

        .improvement {
            font-weight: bold;
        }

        .improvement-high {
            color: #28a745;
        }

        .improvement-medium {
            color: #ffc107;
        }

        .improvement-low {
            color: #17a2b8;
        }

        .improvement-negative {
            color: #dc3545;
        }

        .table-name {
            font-family: 'Courier New', monospace;
            font-weight: 600;
            color: #764ba2;
            cursor: pointer;
        }

        .table-name:hover {
            text-decoration: underline;
        }

        .index-name {
            font-family: 'Courier New', monospace;
            font-size: 0.875rem;
            color: #555;
        }

        .sql-code {
            background: #f8f9fa;
            padding: 15px;
            border-radius: 4px;
            font-family: 'Courier New', monospace;
            font-size: 0.875rem;
            overflow-x: auto;
            border-left: 4px solid #667eea;
            margin: 10px 0;
        }

        .detail-section {
            display: none;
            margin-top: 20px;
            padding: 20px;
            background: #f8f9fa;
            border-radius: 4px;
            border-left: 4px solid #667eea;
        }

        .detail-section.active {
            display: block;
        }

        .expand-icon {
            display: inline-block;
            width: 0;
            height: 0;
            border-left: 5px solid transparent;
            border-right: 5px solid transparent;
            border-top: 5px solid #764ba2;
            margin-right: 8px;
            transition: transform 0.2s;
        }

        .expand-icon.expanded {
            transform: rotate(180deg);
        }

        .actions {
            margin-top: 30px;
            display: flex;
            gap: 15px;
            flex-wrap: wrap;
        }

        .btn {
            padding: 12px 24px;
            border: none;
            border-radius: 6px;
            font-size: 1rem;
            cursor: pointer;
            text-decoration: none;
            display: inline-block;
            transition: all 0.2s;
        }

        .btn-primary {
            background: #667eea;
            color: white;
        }

        .btn-primary:hover {
            background: #5568d3;
            transform: translateY(-1px);
            box-shadow: 0 4px 8px rgba(102, 126, 234, 0.3);
        }

        .btn-secondary {
            background: #6c757d;
            color: white;
        }

        .btn-secondary:hover {
            background: #5a6268;
        }

        .timestamp {
            color: #999;
            font-size: 0.875rem;
        }

        footer {
            text-align: center;
            padding: 30px;
            color: #999;
            font-size: 0.875rem;
        }

        .filter-controls {
            margin-bottom: 20px;
            display: flex;
            gap: 15px;
            flex-wrap: wrap;
        }

        .filter-controls input,
        .filter-controls select {
            padding: 8px 12px;
            border: 1px solid #dee2e6;
            border-radius: 4px;
            font-size: 0.875rem;
        }

        .no-data {
            padding: 40px;
            text-align: center;
            color: #999;
        }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>📊 PostgreSQL Index Test Report</h1>
            <div class="subtitle">Comprehensive index performance analysis and recommendations</div>
            <div class="timestamp">Generated: <span id="timestamp"></span></div>
        </header>
EOF

# Extract summary data
echo "Extracting summary data..."
docker exec $DOCKER_CONTAINER psql -U $DB_USER -d $DB_NAME -t -c "
SELECT
    COUNT(DISTINCT table_name),
    COUNT(DISTINCT index_name) FILTER (WHERE test_phase = 'decision'),
    COUNT(*) FILTER (WHERE decision = 'KEEP'),
    COUNT(*) FILTER (WHERE decision = 'ROLLBACK'),
    ROUND(AVG(improvement_percent) FILTER (WHERE decision = 'KEEP'), 2),
    ROUND(MAX(improvement_percent), 2)
FROM pg_index_test_log
WHERE test_phase = 'decision';
" | while IFS='|' read tables indexes kept rolled avg max; do
    tables=$(echo $tables | xargs)
    indexes=$(echo $indexes | xargs)
    kept=$(echo $kept | xargs)
    rolled=$(echo $rolled | xargs)
    avg=$(echo $avg | xargs)
    max=$(echo $max | xargs)

    cat >> "$OUTPUT_FILE" <<HTML
        <div class="summary-cards">
            <div class="card">
                <div class="card-title">Tables Tested</div>
                <div class="card-value">$tables</div>
                <div class="card-label">Unique tables analyzed</div>
            </div>
            <div class="card">
                <div class="card-title">Indexes Tested</div>
                <div class="card-value">$indexes</div>
                <div class="card-label">Total indexes benchmarked</div>
            </div>
            <div class="card">
                <div class="card-title">Indexes Kept</div>
                <div class="card-value" style="color: #28a745;">$kept</div>
                <div class="card-label">≥5% improvement</div>
            </div>
            <div class="card">
                <div class="card-title">Rolled Back</div>
                <div class="card-value" style="color: #dc3545;">$rolled</div>
                <div class="card-label">&lt;5% improvement</div>
            </div>
            <div class="card">
                <div class="card-title">Avg Improvement</div>
                <div class="card-value" style="color: #28a745;">$avg%</div>
                <div class="card-label">For kept indexes</div>
            </div>
            <div class="card">
                <div class="card-title">Max Improvement</div>
                <div class="card-value" style="color: #28a745;">$max%</div>
                <div class="card-label">Best performing index</div>
            </div>
        </div>
HTML
done

# Tables section
cat >> "$OUTPUT_FILE" <<'HTML'
        <div class="section">
            <h2 class="section-title">📋 Tables Tested</h2>
            <div class="filter-controls">
                <input type="text" id="tableFilter" placeholder="Filter by table name..." onkeyup="filterTable()">
                <select id="statusFilter" onchange="filterTable()">
                    <option value="">All Status</option>
                    <option value="has-kept">Has Kept Indexes</option>
                    <option value="all-rolled">All Rolled Back</option>
                </select>
            </div>
            <table id="tablesTable">
                <thead>
                    <tr>
                        <th>Table Name</th>
                        <th>Indexes Tested</th>
                        <th>Kept</th>
                        <th>Rolled Back</th>
                        <th>Avg Improvement</th>
                        <th>Actions</th>
                    </tr>
                </thead>
                <tbody>
HTML

# Extract table data with details
echo "Extracting table data..."
docker exec $DOCKER_CONTAINER psql -U $DB_USER -d $DB_NAME -t -c "
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
" | while IFS='|' read table indexes kept rolled avg; do
    table=$(echo $table | xargs)
    indexes=$(echo $indexes | xargs)
    kept=$(echo $kept | xargs)
    rolled=$(echo $rolled | xargs)
    avg=$(echo $avg | xargs)

    # Determine improvement class
    improvement_class=""
    if [ ! -z "$avg" ] && [ "$avg" != "" ] && [ "$avg" != " " ]; then
        if (( $(echo "$avg >= 80" | bc -l 2>/dev/null || echo 0) )); then
            improvement_class="improvement-high"
        elif (( $(echo "$avg >= 50" | bc -l 2>/dev/null || echo 0) )); then
            improvement_class="improvement-medium"
        else
            improvement_class="improvement-low"
        fi
    else
        avg=""
    fi

    # Status badge
    status_badge=""
    if [ ! -z "$kept" ] && [ "$kept" -gt 0 ] 2>/dev/null; then
        status_badge="<span class='badge badge-success'>$kept Kept</span>"
    fi
    if [ ! -z "$rolled" ] && [ "$rolled" -gt 0 ] 2>/dev/null; then
        status_badge="$status_badge <span class='badge badge-danger'>$rolled Rolled Back</span>"
    fi

    safe_table=$(echo "$table" | sed 's/[^a-zA-Z0-9_]/_/g')

    cat >> "$OUTPUT_FILE" <<HTML
                    <tr data-table="$table" data-has-kept="$kept" data-rolled="$rolled">
                        <td>
                            <span class="expand-icon" id="icon-$safe_table"></span>
                            <span class="table-name" onclick="toggleDetails('$safe_table')">$table</span>
                        </td>
                        <td>$indexes</td>
                        <td>$kept</td>
                        <td>$rolled</td>
                        <td class="improvement $improvement_class">$avg%</td>
                        <td>$status_badge</td>
                    </tr>
                    <tr>
                        <td colspan="6" style="padding: 0;">
                            <div id="details-$safe_table" class="detail-section">
                                <h3>Index Details for $table</h3>
HTML

    # Get index details for this table
    docker exec $DOCKER_CONTAINER psql -U $DB_USER -d $DB_NAME -t -c "
    SELECT
        index_name,
        decision,
        ROUND(improvement_percent, 2),
        notes
    FROM pg_index_test_log
    WHERE test_phase = 'decision'
      AND table_name = '$table'
    ORDER BY improvement_percent DESC NULLS LAST;
    " | while IFS='|' read idx_name decision improvement notes; do
        idx_name=$(echo $idx_name | xargs)
        decision=$(echo $decision | xargs)
        improvement=$(echo $improvement | xargs)
        notes=$(echo $notes | xargs)

        decision_badge=""
        if [ "$decision" = "KEEP" ]; then
            decision_badge="<span class='badge badge-success'>KEPT</span>"
        else
            decision_badge="<span class='badge badge-danger'>ROLLED BACK</span>"
        fi

        # Generate production index name
        prod_idx_name=$(echo "$idx_name" | sed 's/idx_test_/idx_/')

        cat >> "$OUTPUT_FILE" <<HTML
                                <div style="margin: 15px 0; padding: 15px; background: white; border-radius: 4px;">
                                    <div style="margin-bottom: 10px;">
                                        <strong class="index-name">$idx_name</strong>
                                        $decision_badge
                                        <span class="improvement" style="margin-left: 10px;">$improvement% improvement</span>
                                    </div>
                                    <div style="color: #666; font-size: 0.875rem; margin-bottom: 8px;">
                                        $notes
                                    </div>
HTML

        if [ "$decision" = "KEEP" ]; then
            cat >> "$OUTPUT_FILE" <<HTML
                                    <div class="sql-code">CREATE INDEX IF NOT EXISTS $prod_idx_name ON $table (...);  -- $improvement% improvement</div>
HTML
        fi

        cat >> "$OUTPUT_FILE" <<HTML
                                </div>
HTML
    done

    cat >> "$OUTPUT_FILE" <<HTML
                            </div>
                        </td>
                    </tr>
HTML
done

# Close table and add actions
cat >> "$OUTPUT_FILE" <<'HTML'
                </tbody>
            </table>
        </div>

        <div class="section">
            <h2 class="section-title">🚀 Next Steps</h2>
            <div class="actions">
                <a href="08_production_fk_indexes.sql" class="btn btn-primary">📄 View FK Indexes SQL</a>
                <a href="09_production_non_fk_indexes.sql" class="btn btn-primary">📄 View Non-FK Indexes SQL</a>
                <a href="06_test_results.csv" class="btn btn-secondary">📊 Download CSV Data</a>
                <a href="00_README.md" class="btn btn-secondary">📖 View Full Report</a>
            </div>
            <div style="margin-top: 20px; padding: 20px; background: #fff3cd; border-left: 4px solid #ffc107; border-radius: 4px;">
                <strong>⚠️ Important:</strong> Review all indexes before deploying to production. Test in a development environment first.
            </div>
        </div>

        <footer>
            <p>Generated by PostgreSQL Index Testing Suite</p>
            <p>Database: <code id="dbname"></code> | Container: <code id="container"></code></p>
        </footer>
    </div>

    <script>
        // Set timestamp
        document.getElementById('timestamp').textContent = new Date().toLocaleString();
        document.getElementById('dbname').textContent = '$DB_NAME';
        document.getElementById('container').textContent = '$DOCKER_CONTAINER';

        // Toggle details
        function toggleDetails(tableId) {
            const details = document.getElementById('details-' + tableId);
            const icon = document.getElementById('icon-' + tableId);
            details.classList.toggle('active');
            icon.classList.toggle('expanded');
        }

        // Filter table
        function filterTable() {
            const nameFilter = document.getElementById('tableFilter').value.toLowerCase();
            const statusFilter = document.getElementById('statusFilter').value;
            const rows = document.querySelectorAll('#tablesTable tbody tr[data-table]');

            rows.forEach(row => {
                const nextRow = row.nextElementSibling; // Detail row
                const tableName = row.getAttribute('data-table').toLowerCase();
                const hasKept = parseInt(row.getAttribute('data-has-kept'));
                const rolled = parseInt(row.getAttribute('data-rolled'));

                let showRow = true;

                // Name filter
                if (nameFilter && !tableName.includes(nameFilter)) {
                    showRow = false;
                }

                // Status filter
                if (statusFilter === 'has-kept' && hasKept === 0) {
                    showRow = false;
                } else if (statusFilter === 'all-rolled' && hasKept > 0) {
                    showRow = false;
                }

                row.style.display = showRow ? '' : 'none';
                nextRow.style.display = showRow ? '' : 'none';
            });
        }

        // Keyboard shortcuts
        document.addEventListener('keydown', function(e) {
            if (e.key === '/' && e.target.tagName !== 'INPUT') {
                e.preventDefault();
                document.getElementById('tableFilter').focus();
            }
        });
    </script>
</body>
</html>
HTML

echo ""
echo "✅ HTML report generated: $OUTPUT_FILE"
echo ""
echo "Open with:"
echo "  open $OUTPUT_FILE"
echo ""
