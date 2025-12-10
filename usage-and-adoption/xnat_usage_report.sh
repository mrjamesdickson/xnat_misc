#!/usr/bin/env bash
#
# XNAT Usage and Adoption Statistics Report
# Generates an HTML report with user activity, project stats, and system metrics
#
# Usage: ./xnat_usage_report.sh [XNAT_URL] [USERNAME] [PASSWORD] [OUTPUT_FILE]
#
# Example: ./xnat_usage_report.sh http://demo02.xnatworks.io admin admin report.html
#

set -euo pipefail

# Configuration
XNAT_URL="${1:-}"
UPLOAD_PROJECT="${2:-}"
OUTPUT_FILE="${3:-xnat_usage_report.html}"
USERNAME="${4:-}"
PASSWORD="${5:-}"

# Check required parameters
if [[ -z "$XNAT_URL" || -z "$UPLOAD_PROJECT" ]]; then
    echo "Usage: $0 <XNAT_URL> <UPLOAD_PROJECT> [OUTPUT_FILE] [USERNAME] [PASSWORD]"
    echo ""
    echo "Example: $0 http://xnat.example.com RADVAL"
    echo "Example: $0 http://xnat.example.com RADVAL report.html admin mypass"
    echo ""
    echo "The report will be uploaded to a project-level resource called 'USAGE'"
    echo "in the specified project."
    echo ""
    echo "USERNAME and PASSWORD will be prompted if not provided."
    exit 1
fi

if [[ -z "$USERNAME" ]]; then
    read -p "Enter username: " USERNAME
fi

# Prompt for password if not supplied
if [[ -z "$PASSWORD" ]]; then
    read -s -p "Enter password for ${USERNAME}@${XNAT_URL}: " PASSWORD
    echo ""
fi

# Pause between API calls (seconds) to avoid server overload
API_PAUSE=0.5

# Page size for experiment fetching
PAGE_SIZE=500

# Remove trailing slash from URL
XNAT_URL="${XNAT_URL%/}"

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check dependencies
check_dependencies() {
    for cmd in curl jq bc; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "Required command '$cmd' not found. Please install it."
            exit 1
        fi
    done
}

# API call helper with rate limiting
api_get() {
    local endpoint="$1"
    sleep "$API_PAUSE"
    curl -s -u "${USERNAME}:${PASSWORD}" "${XNAT_URL}${endpoint}"
}

# Test connection
test_connection() {
    log_info "Testing connection to ${XNAT_URL}..."
    local response
    response=$(curl -s -o /dev/null -w "%{http_code}" -u "${USERNAME}:${PASSWORD}" "${XNAT_URL}/data/projects")
    if [[ "$response" != "200" ]]; then
        log_error "Failed to connect to XNAT (HTTP $response). Check URL and credentials."
        exit 1
    fi
    log_info "Connection successful!"
}

# Generate report
generate_report() {
    log_info "Fetching data from XNAT (with ${API_PAUSE}s pause between calls)..."

    # Get site configuration
    log_info "  - Site configuration..."
    local site_config
    site_config=$(api_get "/xapi/siteConfig")
    local site_url admin_email
    site_url=$(echo "$site_config" | jq -r '.siteUrl // "N/A"')
    admin_email=$(echo "$site_config" | jq -r '.adminEmail // "N/A"')

    # Get users data
    log_info "  - User data..."
    local users_profiles
    users_profiles=$(api_get "/xapi/users/profiles")

    local total_users enabled_users disabled_users verified_users users_with_login
    total_users=$(echo "$users_profiles" | jq 'length')
    enabled_users=$(echo "$users_profiles" | jq '[.[] | select(.enabled == true)] | length')
    disabled_users=$(echo "$users_profiles" | jq '[.[] | select(.enabled == false)] | length')
    verified_users=$(echo "$users_profiles" | jq '[.[] | select(.verified == true)] | length')
    users_with_login=$(echo "$users_profiles" | jq '[.[] | select(.lastSuccessfulLogin != null)] | length')

    # Get projects data
    log_info "  - Project data..."
    local projects_json
    projects_json=$(api_get "/data/projects?format=json")
    local total_projects
    total_projects=$(echo "$projects_json" | jq '.ResultSet.totalRecords | tonumber')

    # Get subjects data
    log_info "  - Subject data..."
    local subjects_json
    subjects_json=$(api_get "/data/subjects?format=json")
    local total_subjects
    total_subjects=$(echo "$subjects_json" | jq '.ResultSet.totalRecords | tonumber')

    # =========================================
    # FETCH EXPERIMENTS WITH PAGING (to avoid server overload)
    # =========================================
    log_info "  - Experiment/session data (fetching with page size ${PAGE_SIZE})..."
    local experiments_json='{"ResultSet":{"Result":[]}}'
    local offset=0
    local page_count=0
    local fetched_count=0
    local total_fetched=0

    while true; do
        page_count=$((page_count + 1))
        log_info "      Fetching page ${page_count} (offset ${offset}, limit ${PAGE_SIZE})..."

        local page_experiments
        page_experiments=$(api_get "/data/experiments?format=json&columns=ID,label,project,insert_date,insert_user,xsiType&limit=${PAGE_SIZE}&offset=${offset}")

        # Count results in this page
        fetched_count=$(echo "$page_experiments" | jq '.ResultSet.Result | length')
        total_fetched=$((total_fetched + fetched_count))
        log_info "      Fetched ${fetched_count} experiments (total: ${total_fetched})"

        # Merge results
        experiments_json=$(echo "$experiments_json" "$page_experiments" | jq -s '
            {ResultSet: {Result: (.[0].ResultSet.Result + (.[1].ResultSet.Result // []))}}
        ')

        # Stop if we got fewer results than page size (last page)
        if [[ "$fetched_count" -lt "$PAGE_SIZE" ]]; then
            break
        fi

        offset=$((offset + PAGE_SIZE))
    done

    local total_experiments
    total_experiments=$(echo "$experiments_json" | jq '.ResultSet.Result | length')
    log_info "      Total experiments fetched: ${total_experiments}"

    # Count experiment types
    local mr_sessions ct_sessions pet_sessions other_sessions
    mr_sessions=$(echo "$experiments_json" | jq '[.ResultSet.Result[] | select(.xsiType == "xnat:mrSessionData")] | length')
    ct_sessions=$(echo "$experiments_json" | jq '[.ResultSet.Result[] | select(.xsiType == "xnat:ctSessionData")] | length')
    pet_sessions=$(echo "$experiments_json" | jq '[.ResultSet.Result[] | select(.xsiType == "xnat:petSessionData")] | length')
    other_sessions=$((total_experiments - mr_sessions - ct_sessions - pet_sessions))

    # Get recent logins (users who logged in)
    log_info "  - Login activity..."
    local recent_logins_30d recent_logins_7d recent_logins_24h
    local now_ms=$(($(date +%s) * 1000))
    local day_ms=$((24 * 60 * 60 * 1000))
    local week_ms=$((7 * day_ms))
    local month_ms=$((30 * day_ms))

    recent_logins_24h=$(echo "$users_profiles" | jq --argjson now "$now_ms" --argjson period "$day_ms" \
        '[.[] | select(.lastSuccessfulLogin != null and (.lastSuccessfulLogin > ($now - $period)))] | length')
    recent_logins_7d=$(echo "$users_profiles" | jq --argjson now "$now_ms" --argjson period "$week_ms" \
        '[.[] | select(.lastSuccessfulLogin != null and (.lastSuccessfulLogin > ($now - $period)))] | length')
    recent_logins_30d=$(echo "$users_profiles" | jq --argjson now "$now_ms" --argjson period "$month_ms" \
        '[.[] | select(.lastSuccessfulLogin != null and (.lastSuccessfulLogin > ($now - $period)))] | length')

    # Get top users by last login (active users)
    log_info "  - Active users..."
    local active_users_table
    active_users_table=$(echo "$users_profiles" | jq -r '
        [.[] | select(.lastSuccessfulLogin != null)]
        | sort_by(-.lastSuccessfulLogin)
        | .[0:20]
        | .[]
        | "<tr><td>\(.username)</td><td>\(.firstName // "N/A") \(.lastName // "")</td><td>\(.email // "N/A")</td><td>\(if .lastSuccessfulLogin then (.lastSuccessfulLogin / 1000 | strftime("%Y-%m-%d %H:%M:%S")) else "Never" end)</td><td>\(if .enabled then "Yes" else "No" end)</td></tr>"
    ')

    # Get all users table
    log_info "  - All users list..."
    local all_users_table
    all_users_table=$(echo "$users_profiles" | jq -r '
        sort_by(.username)
        | .[]
        | "<tr><td>\(.username)</td><td>\(.firstName // "N/A") \(.lastName // "")</td><td>\(.email // "N/A")</td><td>\(if .lastSuccessfulLogin then (.lastSuccessfulLogin / 1000 | strftime("%Y-%m-%d %H:%M:%S")) else "Never" end)</td><td>\(if .enabled then "Yes" else "No" end)</td><td>\(if .verified then "Yes" else "No" end)</td></tr>"
    ')

    # Get projects table with subject counts
    log_info "  - Project details..."
    local projects_table
    projects_table=$(echo "$projects_json" | jq -r '
        .ResultSet.Result
        | sort_by(.name)
        | .[]
        | "<tr><td>\(.ID)</td><td>\(.name)</td><td>\(.pi_firstname // "") \(.pi_lastname // "")</td><td>\(.description[0:100] // "")...</td></tr>"
    ')

    # Count projects by subject count
    log_info "  - Project statistics..."

    # Get experiments by project
    local experiments_by_project
    experiments_by_project=$(echo "$experiments_json" | jq -r '
        [.ResultSet.Result | group_by(.project) | .[] | {project: .[0].project, count: length}]
        | sort_by(-.count)
        | .[0:15]
        | .[]
        | "<tr><td>\(.project)</td><td>\(.count)</td></tr>"
    ')

    # Get experiments by type
    local experiments_by_type
    experiments_by_type=$(echo "$experiments_json" | jq -r '
        [.ResultSet.Result | group_by(.xsiType) | .[] | {type: .[0].xsiType, count: length}]
        | sort_by(-.count)
        | .[]
        | "<tr><td>\(.type)</td><td>\(.count)</td></tr>"
    ')

    # Recent experiments (last 20)
    log_info "  - Recent experiments..."
    local recent_experiments
    recent_experiments=$(echo "$experiments_json" | jq -r '
        .ResultSet.Result
        | sort_by(.insert_date)
        | reverse
        | .[0:20]
        | .[]
        | "<tr><td>\(.label)</td><td>\(.project)</td><td>\(.xsiType | split(":")[1] // .xsiType)</td><td>\(.insert_date // "N/A")</td></tr>"
    ')

    # =========================================
    # ACTIVITY GRAPHS DATA
    # =========================================
    log_info "  - Weekly activity data..."

    # Get weekly activity (experiments per week)
    local weekly_activity_data
    weekly_activity_data=$(echo "$experiments_json" | jq -r '
        .ResultSet.Result
        | map(select(.insert_date != null))
        | map({
            week: (.insert_date | split(" ")[0] | strptime("%Y-%m-%d") | mktime | . - (. % 604800) | strftime("%Y-%m-%d")),
            insert_date: .insert_date
          })
        | group_by(.week)
        | map({week: .[0].week, count: length})
        | sort_by(.week)
        | .[]
        | "\(.week),\(.count)"
    ')

    # Calculate go-live date (first experiment)
    local go_live_date total_weeks avg_per_week
    go_live_date=$(echo "$experiments_json" | jq -r '.ResultSet.Result | map(select(.insert_date != null)) | sort_by(.insert_date) | .[0].insert_date | split(" ")[0] // "N/A"')
    total_weeks=$(echo "$weekly_activity_data" | grep -c ',' || echo "0")
    if [[ "$total_weeks" -gt 0 && "$total_experiments" -gt 0 ]]; then
        avg_per_week=$(echo "scale=1; $total_experiments / $total_weeks" | bc)
    else
        avg_per_week="0"
    fi

    # Convert weekly data to JSON for Chart.js
    local weekly_labels weekly_values
    weekly_labels=$(echo "$weekly_activity_data" | cut -d',' -f1 | jq -R -s 'split("\n") | map(select(length > 0))')
    weekly_values=$(echo "$weekly_activity_data" | cut -d',' -f2 | jq -R -s 'split("\n") | map(select(length > 0) | tonumber)')

    # =========================================
    # MONTHLY USER ACTIVITY (Days logged in per month)
    # =========================================
    log_info "  - Monthly activity data..."

    # Calculate monthly activity days per user (based on upload activity as proxy for logins)
    local monthly_user_activity
    monthly_user_activity=$(echo "$experiments_json" | jq -c '
        .ResultSet.Result
        | map(select(.insert_user != null and .insert_date != null))
        | map({
            user: .insert_user,
            month: (.insert_date | split(" ")[0] | split("-")[0:2] | join("-")),
            date: (.insert_date | split(" ")[0])
          })
        | group_by(.user)
        | map({
            user: .[0].user,
            months: (group_by(.month) | map({
                month: .[0].month,
                days_active: ([.[].date] | unique | length)
              }))
          })
    ')

    # Overall monthly stats (unique users active per month, total active days)
    local monthly_overall_stats
    monthly_overall_stats=$(echo "$experiments_json" | jq -c '
        .ResultSet.Result
        | map(select(.insert_user != null and .insert_date != null))
        | map({
            user: .insert_user,
            month: (.insert_date | split(" ")[0] | split("-")[0:2] | join("-")),
            date: (.insert_date | split(" ")[0])
          })
        | group_by(.month)
        | map({
            month: .[0].month,
            unique_users: ([.[].user] | unique | length),
            total_active_days: ([.[] | {user: .user, date: .date}] | unique | length),
            uploads: length
          })
        | sort_by(.month)
    ')

    # Monthly stats table
    local monthly_stats_table
    monthly_stats_table=$(echo "$monthly_overall_stats" | jq -r '
        .[]
        | "<tr><td>\(.month)</td><td>\(.unique_users)</td><td>\(.total_active_days)</td><td>\(.uploads)</td></tr>"
    ')

    # User monthly activity table (days active per month per user)
    local user_monthly_table
    user_monthly_table=$(echo "$monthly_user_activity" | jq -r '
        .[]
        | . as $user
        | .months[]
        | "<tr><td>\($user.user)</td><td>\(.month)</td><td>\(.days_active)</td></tr>"
    ' | head -100)  # Limit to first 100 rows for performance

    # Monthly labels and values for chart
    local monthly_labels monthly_users monthly_uploads
    monthly_labels=$(echo "$monthly_overall_stats" | jq '[.[].month]')
    monthly_users=$(echo "$monthly_overall_stats" | jq '[.[].unique_users]')
    monthly_uploads=$(echo "$monthly_overall_stats" | jq '[.[].uploads]')

    # =========================================
    # USER RETENTION DATA
    # =========================================
    log_info "  - User retention data..."

    # Calculate user retention (first activity to last activity per user)
    local user_retention_data
    user_retention_data=$(echo "$experiments_json" | jq -c '
        .ResultSet.Result
        | map(select(.insert_user != null and .insert_date != null))
        | group_by(.insert_user)
        | map({
            user: .[0].insert_user,
            first_activity: (map(.insert_date) | sort | .[0]),
            last_activity: (map(.insert_date) | sort | reverse | .[0]),
            total_uploads: length
          })
        | map(. + {
            first_ts: (.first_activity | split(" ")[0] | strptime("%Y-%m-%d") | mktime),
            last_ts: (.last_activity | split(" ")[0] | strptime("%Y-%m-%d") | mktime)
          })
        | map(. + {
            retention_days: ((.last_ts - .first_ts) / 86400 | floor)
          })
        | sort_by(-.total_uploads)
    ')

    # User retention table
    local user_retention_table
    user_retention_table=$(echo "$user_retention_data" | jq -r '
        .[]
        | "<tr><td>\(.user)</td><td>\(.first_activity | split(" ")[0])</td><td>\(.last_activity | split(" ")[0])</td><td>\(.retention_days)</td><td>\(.total_uploads)</td></tr>"
    ')

    # Retention summary stats
    local users_with_activity avg_retention max_retention
    users_with_activity=$(echo "$user_retention_data" | jq 'length')
    avg_retention=$(echo "$user_retention_data" | jq 'if length > 0 then ([.[].retention_days] | add / length | floor) else 0 end')
    max_retention=$(echo "$user_retention_data" | jq 'if length > 0 then ([.[].retention_days] | max) else 0 end')

    # =========================================
    # INDIVIDUAL USER ACTIVITY TIMELINE DATA
    # =========================================
    log_info "  - Individual user timeline data..."

    # Get daily activity per user for timeline chart
    local user_daily_activity
    user_daily_activity=$(echo "$experiments_json" | jq -c '
        .ResultSet.Result
        | map(select(.insert_user != null and .insert_date != null))
        | map({
            user: .insert_user,
            date: (.insert_date | split(" ")[0])
          })
        | group_by(.user)
        | map({
            user: .[0].user,
            activity: (group_by(.date) | map({date: .[0].date, count: length}))
          })
        | sort_by(-(.activity | length))
    ')

    # Get list of active users for dropdown
    local active_user_list
    active_user_list=$(echo "$user_daily_activity" | jq -r '.[].user' | sort -u)

    # =========================================
    # ACTIVITY BY USER (uploads per user)
    # =========================================
    log_info "  - Activity by user..."
    local activity_by_user
    activity_by_user=$(echo "$experiments_json" | jq -r '
        [.ResultSet.Result
        | map(select(.insert_user != null))
        | group_by(.insert_user)
        | .[]
        | {user: .[0].insert_user, count: length}]
        | sort_by(-.count)
        | .[0:20]
        | .[]
        | "<tr><td>\(.user)</td><td>\(.count)</td></tr>"
    ')

    # Generate timestamp
    local report_time
    report_time=$(date "+%Y-%m-%d %H:%M:%S %Z")

    log_info "Generating HTML report..."

    # Write HTML report
    cat > "$OUTPUT_FILE" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>XNAT Usage Report</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/chartjs-adapter-date-fns"></script>
    <style>
        :root {
            --primary: #2c3e50;
            --secondary: #3498db;
            --success: #27ae60;
            --warning: #f39c12;
            --danger: #e74c3c;
            --light: #ecf0f1;
            --dark: #2c3e50;
        }
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
            background: #f5f6fa;
            color: #2c3e50;
            line-height: 1.6;
        }
        .header {
            background: linear-gradient(135deg, var(--primary) 0%, var(--secondary) 100%);
            color: white;
            padding: 30px 20px;
            text-align: center;
        }
        .header h1 { font-size: 2.5em; margin-bottom: 10px; }
        .header .subtitle { opacity: 0.9; font-size: 1.1em; }
        .header .meta { margin-top: 15px; font-size: 0.9em; opacity: 0.8; }
        .container { max-width: 1400px; margin: 0 auto; padding: 20px; }
        .dashboard { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; margin: 30px 0; }
        .card {
            background: white;
            border-radius: 10px;
            padding: 25px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.08);
            text-align: center;
            transition: transform 0.2s, box-shadow 0.2s;
        }
        .card:hover { transform: translateY(-5px); box-shadow: 0 5px 20px rgba(0,0,0,0.12); }
        .card .number { font-size: 3em; font-weight: bold; color: var(--secondary); }
        .card .label { color: #7f8c8d; font-size: 0.95em; margin-top: 5px; }
        .card.users .number { color: var(--secondary); }
        .card.projects .number { color: var(--success); }
        .card.subjects .number { color: var(--warning); }
        .card.sessions .number { color: var(--danger); }
        .section {
            background: white;
            border-radius: 10px;
            padding: 25px;
            margin: 25px 0;
            box-shadow: 0 2px 10px rgba(0,0,0,0.08);
        }
        .section h2 {
            color: var(--primary);
            border-bottom: 3px solid var(--secondary);
            padding-bottom: 10px;
            margin-bottom: 20px;
            font-size: 1.5em;
        }
        .section h3 {
            color: var(--dark);
            margin: 20px 0 15px 0;
            font-size: 1.2em;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin: 15px 0;
            font-size: 0.9em;
        }
        th, td {
            padding: 12px 15px;
            text-align: left;
            border-bottom: 1px solid #eee;
        }
        th {
            background: var(--primary);
            color: white;
            font-weight: 600;
            position: sticky;
            top: 0;
        }
        tr:hover { background: #f8f9fa; }
        tr:nth-child(even) { background: #fafbfc; }
        tr:nth-child(even):hover { background: #f0f1f2; }
        .stats-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 15px; margin: 20px 0; }
        .stat-item {
            background: #f8f9fa;
            padding: 15px;
            border-radius: 8px;
            text-align: center;
        }
        .stat-item .value { font-size: 1.8em; font-weight: bold; color: var(--secondary); }
        .stat-item .label { font-size: 0.85em; color: #7f8c8d; }
        .chart-container { display: flex; flex-wrap: wrap; gap: 20px; margin: 20px 0; }
        .chart-box { flex: 1; min-width: 300px; }
        .chart-wrapper { position: relative; height: 300px; margin: 20px 0; }
        .chart-wrapper.tall { height: 400px; }
        .table-wrapper { max-height: 500px; overflow-y: auto; border: 1px solid #eee; border-radius: 8px; }
        .footer {
            text-align: center;
            padding: 30px;
            color: #7f8c8d;
            font-size: 0.9em;
        }
        select {
            padding: 10px 15px;
            font-size: 1em;
            border: 2px solid var(--secondary);
            border-radius: 8px;
            background: white;
            cursor: pointer;
            min-width: 200px;
        }
        select:focus { outline: none; border-color: var(--primary); }
        .user-selector { margin: 20px 0; display: flex; align-items: center; gap: 15px; }
        .user-selector label { font-weight: 600; color: var(--primary); }
        @media (max-width: 768px) {
            .dashboard { grid-template-columns: repeat(2, 1fr); }
            .card .number { font-size: 2em; }
        }
        @media print {
            .header { background: var(--primary) !important; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
            .section { break-inside: avoid; }
        }
    </style>
</head>
<body>
    <div class="header">
        <h1>XNAT Usage & Adoption Report</h1>
HTMLEOF

    # Insert dynamic site URL
    cat >> "$OUTPUT_FILE" << EOF
        <div class="subtitle">${site_url}</div>
        <div class="meta">
            Generated: ${report_time}<br>
            Admin Contact: ${admin_email}
        </div>
    </div>

    <div class="container">
        <!-- Summary Dashboard -->
        <div class="dashboard">
            <div class="card users">
                <div class="number">${total_users}</div>
                <div class="label">Total Users</div>
            </div>
            <div class="card projects">
                <div class="number">${total_projects}</div>
                <div class="label">Projects</div>
            </div>
            <div class="card subjects">
                <div class="number">${total_subjects}</div>
                <div class="label">Subjects</div>
            </div>
            <div class="card sessions">
                <div class="number">${total_experiments}</div>
                <div class="label">Sessions/Experiments</div>
            </div>
        </div>

        <!-- Activity Overview -->
        <div class="section">
            <h2>Activity Overview</h2>
            <div class="stats-grid">
                <div class="stat-item">
                    <div class="value">${go_live_date}</div>
                    <div class="label">Go-Live Date (First Upload)</div>
                </div>
                <div class="stat-item">
                    <div class="value">${total_weeks}</div>
                    <div class="label">Total Weeks Active</div>
                </div>
                <div class="stat-item">
                    <div class="value">${avg_per_week}</div>
                    <div class="label">Avg Uploads/Week</div>
                </div>
                <div class="stat-item">
                    <div class="value">${users_with_activity}</div>
                    <div class="label">Users with Uploads</div>
                </div>
            </div>

            <h3>Weekly Upload Activity (Since Go-Live)</h3>
            <div class="chart-wrapper tall">
                <canvas id="weeklyActivityChart"></canvas>
            </div>
        </div>

        <!-- Monthly Activity -->
        <div class="section">
            <h2>Monthly Activity Analysis</h2>
            <h3>Users & Uploads Per Month</h3>
            <div class="chart-wrapper tall">
                <canvas id="monthlyActivityChart"></canvas>
            </div>

            <h3>Monthly Statistics</h3>
            <div class="table-wrapper">
                <table>
                    <thead>
                        <tr>
                            <th>Month</th>
                            <th>Unique Users Active</th>
                            <th>Total User-Days Active</th>
                            <th>Total Uploads</th>
                        </tr>
                    </thead>
                    <tbody>
                        ${monthly_stats_table}
                    </tbody>
                </table>
            </div>

            <h3>User Activity Days per Month (First 100)</h3>
            <div class="table-wrapper">
                <table>
                    <thead>
                        <tr>
                            <th>Username</th>
                            <th>Month</th>
                            <th>Days Active</th>
                        </tr>
                    </thead>
                    <tbody>
                        ${user_monthly_table}
                    </tbody>
                </table>
            </div>
        </div>

        <!-- User Retention -->
        <div class="section">
            <h2>User Retention Analysis</h2>
            <div class="stats-grid">
                <div class="stat-item">
                    <div class="value">${avg_retention}</div>
                    <div class="label">Avg Retention (Days)</div>
                </div>
                <div class="stat-item">
                    <div class="value">${max_retention}</div>
                    <div class="label">Max Retention (Days)</div>
                </div>
                <div class="stat-item">
                    <div class="value">${users_with_activity}</div>
                    <div class="label">Active Users</div>
                </div>
            </div>

            <h3>User Retention (First to Last Activity)</h3>
            <div class="table-wrapper">
                <table>
                    <thead>
                        <tr>
                            <th>Username</th>
                            <th>First Activity</th>
                            <th>Last Activity</th>
                            <th>Retention (Days)</th>
                            <th>Total Uploads</th>
                        </tr>
                    </thead>
                    <tbody>
                        ${user_retention_table}
                    </tbody>
                </table>
            </div>
        </div>

        <!-- Individual User Activity -->
        <div class="section">
            <h2>Individual User Activity Timeline</h2>
            <div class="user-selector">
                <label for="userSelect">Select User:</label>
                <select id="userSelect" onchange="updateUserChart()">
                    <option value="">-- Select a user --</option>
EOF

    # Add user options
    echo "$active_user_list" | while read -r user; do
        [[ -n "$user" ]] && echo "                    <option value=\"$user\">$user</option>" >> "$OUTPUT_FILE"
    done

    cat >> "$OUTPUT_FILE" << 'EOF'
                </select>
            </div>
            <div class="chart-wrapper tall">
                <canvas id="userActivityChart"></canvas>
            </div>
        </div>

        <!-- Activity by User -->
        <div class="section">
            <h2>Top Users by Upload Activity</h2>
            <div class="chart-container">
                <div class="chart-box">
                    <div class="chart-wrapper">
                        <canvas id="topUsersChart"></canvas>
                    </div>
                </div>
                <div class="chart-box">
                    <div class="table-wrapper" style="max-height: 300px;">
                        <table>
                            <thead>
                                <tr><th>Username</th><th>Total Uploads</th></tr>
                            </thead>
                            <tbody>
EOF

    echo "                        ${activity_by_user}" >> "$OUTPUT_FILE"

    cat >> "$OUTPUT_FILE" << 'EOF'
                            </tbody>
                        </table>
                    </div>
                </div>
            </div>
        </div>

        <!-- User Statistics -->
        <div class="section">
            <h2>User Statistics</h2>
            <div class="stats-grid">
                <div class="stat-item">
EOF

    cat >> "$OUTPUT_FILE" << EOF
                    <div class="value">${enabled_users}</div>
                    <div class="label">Enabled Users</div>
                </div>
                <div class="stat-item">
                    <div class="value">${disabled_users}</div>
                    <div class="label">Disabled Users</div>
                </div>
                <div class="stat-item">
                    <div class="value">${verified_users}</div>
                    <div class="label">Verified Users</div>
                </div>
                <div class="stat-item">
                    <div class="value">${users_with_login}</div>
                    <div class="label">Users with Login History</div>
                </div>
            </div>

            <h3>Login Activity</h3>
            <div class="stats-grid">
                <div class="stat-item">
                    <div class="value">${recent_logins_24h}</div>
                    <div class="label">Active (24 hours)</div>
                </div>
                <div class="stat-item">
                    <div class="value">${recent_logins_7d}</div>
                    <div class="label">Active (7 days)</div>
                </div>
                <div class="stat-item">
                    <div class="value">${recent_logins_30d}</div>
                    <div class="label">Active (30 days)</div>
                </div>
            </div>

            <h3>Recently Active Users (Top 20)</h3>
            <div class="table-wrapper">
                <table>
                    <thead>
                        <tr>
                            <th>Username</th>
                            <th>Name</th>
                            <th>Email</th>
                            <th>Last Login</th>
                            <th>Enabled</th>
                        </tr>
                    </thead>
                    <tbody>
                        ${active_users_table}
                    </tbody>
                </table>
            </div>
        </div>

        <!-- Session/Experiment Statistics -->
        <div class="section">
            <h2>Session Statistics</h2>
            <div class="stats-grid">
                <div class="stat-item">
                    <div class="value">${mr_sessions}</div>
                    <div class="label">MR Sessions</div>
                </div>
                <div class="stat-item">
                    <div class="value">${ct_sessions}</div>
                    <div class="label">CT Sessions</div>
                </div>
                <div class="stat-item">
                    <div class="value">${pet_sessions}</div>
                    <div class="label">PET Sessions</div>
                </div>
                <div class="stat-item">
                    <div class="value">${other_sessions}</div>
                    <div class="label">Other Types</div>
                </div>
            </div>

            <div class="chart-container">
                <div class="chart-box">
                    <h3>Sessions by Type</h3>
                    <div class="table-wrapper" style="max-height: 300px;">
                        <table>
                            <thead>
                                <tr><th>Session Type</th><th>Count</th></tr>
                            </thead>
                            <tbody>
                                ${experiments_by_type}
                            </tbody>
                        </table>
                    </div>
                </div>
                <div class="chart-box">
                    <h3>Sessions by Project (Top 15)</h3>
                    <div class="table-wrapper" style="max-height: 300px;">
                        <table>
                            <thead>
                                <tr><th>Project</th><th>Sessions</th></tr>
                            </thead>
                            <tbody>
                                ${experiments_by_project}
                            </tbody>
                        </table>
                    </div>
                </div>
            </div>

            <h3>Recent Sessions (Last 20)</h3>
            <div class="table-wrapper">
                <table>
                    <thead>
                        <tr>
                            <th>Label</th>
                            <th>Project</th>
                            <th>Type</th>
                            <th>Insert Date</th>
                        </tr>
                    </thead>
                    <tbody>
                        ${recent_experiments}
                    </tbody>
                </table>
            </div>
        </div>

        <!-- Projects -->
        <div class="section">
            <h2>Projects (${total_projects})</h2>
            <div class="table-wrapper">
                <table>
                    <thead>
                        <tr>
                            <th>ID</th>
                            <th>Name</th>
                            <th>PI</th>
                            <th>Description</th>
                        </tr>
                    </thead>
                    <tbody>
                        ${projects_table}
                    </tbody>
                </table>
            </div>
        </div>

        <!-- All Users -->
        <div class="section">
            <h2>All Users (${total_users})</h2>
            <div class="table-wrapper">
                <table>
                    <thead>
                        <tr>
                            <th>Username</th>
                            <th>Name</th>
                            <th>Email</th>
                            <th>Last Login</th>
                            <th>Enabled</th>
                            <th>Verified</th>
                        </tr>
                    </thead>
                    <tbody>
                        ${all_users_table}
                    </tbody>
                </table>
            </div>
        </div>
    </div>

    <div class="footer">
        <p>XNAT Usage Report | Generated by xnat_usage_report.sh</p>
        <p>${site_url}</p>
    </div>

    <script>
        // Weekly Activity Chart Data
        const weeklyLabels = ${weekly_labels};
        const weeklyValues = ${weekly_values};

        // Monthly Activity Data
        const monthlyLabels = ${monthly_labels};
        const monthlyUsers = ${monthly_users};
        const monthlyUploads = ${monthly_uploads};

        // User daily activity data
        const userDailyActivity = ${user_daily_activity};

        // User retention data
        const userRetentionData = ${user_retention_data};

        // Weekly Activity Chart
        const weeklyCtx = document.getElementById('weeklyActivityChart').getContext('2d');
        new Chart(weeklyCtx, {
            type: 'bar',
            data: {
                labels: weeklyLabels,
                datasets: [{
                    label: 'Uploads per Week',
                    data: weeklyValues,
                    backgroundColor: 'rgba(52, 152, 219, 0.7)',
                    borderColor: 'rgba(52, 152, 219, 1)',
                    borderWidth: 1
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    title: {
                        display: true,
                        text: 'Weekly Upload Activity Since Go-Live'
                    }
                },
                scales: {
                    x: {
                        title: { display: true, text: 'Week Starting' }
                    },
                    y: {
                        beginAtZero: true,
                        title: { display: true, text: 'Number of Uploads' }
                    }
                }
            }
        });

        // Monthly Activity Chart
        const monthlyCtx = document.getElementById('monthlyActivityChart').getContext('2d');
        new Chart(monthlyCtx, {
            type: 'bar',
            data: {
                labels: monthlyLabels,
                datasets: [
                    {
                        label: 'Unique Users Active',
                        data: monthlyUsers,
                        backgroundColor: 'rgba(46, 204, 113, 0.7)',
                        borderColor: 'rgba(46, 204, 113, 1)',
                        borderWidth: 1,
                        yAxisID: 'y'
                    },
                    {
                        label: 'Total Uploads',
                        data: monthlyUploads,
                        backgroundColor: 'rgba(155, 89, 182, 0.7)',
                        borderColor: 'rgba(155, 89, 182, 1)',
                        borderWidth: 1,
                        yAxisID: 'y1'
                    }
                ]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    title: {
                        display: true,
                        text: 'Monthly Activity: Users & Uploads'
                    }
                },
                scales: {
                    x: {
                        title: { display: true, text: 'Month' }
                    },
                    y: {
                        type: 'linear',
                        display: true,
                        position: 'left',
                        beginAtZero: true,
                        title: { display: true, text: 'Unique Users' }
                    },
                    y1: {
                        type: 'linear',
                        display: true,
                        position: 'right',
                        beginAtZero: true,
                        title: { display: true, text: 'Uploads' },
                        grid: { drawOnChartArea: false }
                    }
                }
            }
        });

        // Top Users Chart
        const topUsersCtx = document.getElementById('topUsersChart').getContext('2d');
        new Chart(topUsersCtx, {
            type: 'bar',
            data: {
                labels: userRetentionData.slice(0, 10).map(u => u.user),
                datasets: [{
                    label: 'Total Uploads',
                    data: userRetentionData.slice(0, 10).map(u => u.total_uploads),
                    backgroundColor: 'rgba(46, 204, 113, 0.7)',
                    borderColor: 'rgba(46, 204, 113, 1)',
                    borderWidth: 1
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                indexAxis: 'y',
                plugins: {
                    title: {
                        display: true,
                        text: 'Top 10 Users by Upload Activity'
                    }
                }
            }
        });

        // User Activity Chart (individual)
        let userChart = null;

        function updateUserChart() {
            const selectedUser = document.getElementById('userSelect').value;
            const canvas = document.getElementById('userActivityChart');
            const ctx = canvas.getContext('2d');

            if (userChart) {
                userChart.destroy();
            }

            if (!selectedUser) {
                return;
            }

            const userData = userDailyActivity.find(u => u.user === selectedUser);
            if (!userData) {
                return;
            }

            const sortedActivity = userData.activity.sort((a, b) => a.date.localeCompare(b.date));

            userChart = new Chart(ctx, {
                type: 'bar',
                data: {
                    labels: sortedActivity.map(a => a.date),
                    datasets: [{
                        label: 'Uploads by ' + selectedUser,
                        data: sortedActivity.map(a => a.count),
                        backgroundColor: 'rgba(155, 89, 182, 0.7)',
                        borderColor: 'rgba(155, 89, 182, 1)',
                        borderWidth: 1
                    }]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    plugins: {
                        title: {
                            display: true,
                            text: 'Daily Upload Activity for ' + selectedUser
                        }
                    },
                    scales: {
                        x: {
                            title: { display: true, text: 'Date' }
                        },
                        y: {
                            beginAtZero: true,
                            title: { display: true, text: 'Uploads' }
                        }
                    }
                }
            });
        }
    </script>
</body>
</html>
EOF

    log_info "Report generated: ${OUTPUT_FILE}"
}

# Upload report to XNAT project resource
upload_report() {
    local project="$1"
    local file="$2"
    local filename
    filename=$(basename "$file")

    log_info "Uploading report to project ${project}..."

    # Create USAGE resource if it doesn't exist
    log_info "  - Creating/updating USAGE resource..."
    curl -s -u "${USERNAME}:${PASSWORD}" -X PUT \
        "${XNAT_URL}/data/projects/${project}/resources/USAGE?format=HTML&content=Usage%20Report" \
        > /dev/null

    # Upload the file
    log_info "  - Uploading ${filename}..."
    local response
    response=$(curl -s -w "%{http_code}" -u "${USERNAME}:${PASSWORD}" -X PUT \
        "${XNAT_URL}/data/projects/${project}/resources/USAGE/files/${filename}?inbody=true" \
        --data-binary "@${file}" \
        -H "Content-Type: text/html")

    local http_code="${response: -3}"
    if [[ "$http_code" == "200" || "$http_code" == "201" ]]; then
        log_info "  - Upload successful!"
        log_info "  - View at: ${XNAT_URL}/data/projects/${project}/resources/USAGE/files/${filename}"
    else
        log_error "  - Upload failed (HTTP ${http_code})"
        return 1
    fi
}

# Main
main() {
    echo ""
    echo "=========================================="
    echo "  XNAT Usage & Adoption Report Generator"
    echo "=========================================="
    echo ""
    echo "Note: This report fetches experiments in pages of ${PAGE_SIZE} with"
    echo "      ${API_PAUSE}s pauses between API calls to avoid server overload."
    echo ""

    check_dependencies
    test_connection
    generate_report

    # Upload to project
    echo ""
    upload_report "$UPLOAD_PROJECT" "$OUTPUT_FILE"

    echo ""
    log_info "Done! Open ${OUTPUT_FILE} in a browser to view the report."
    echo ""
}

main "$@"
