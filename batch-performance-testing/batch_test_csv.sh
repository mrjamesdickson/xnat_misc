#!/bin/bash

# CSV-Based Batch Performance Testing Script
# Submits container jobs based on CSV experiment list
# Handles multiple projects and auto-enables containers per project

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Network timeout/retry configuration
API_CONNECT_TIMEOUT=${API_CONNECT_TIMEOUT:-60}
API_MAX_TIME=${API_MAX_TIME:-300}
API_RETRY_COUNT=${API_RETRY_COUNT:-5}
API_RETRY_DELAY=${API_RETRY_DELAY:-5}
JOB_SUBMIT_CONNECT_TIMEOUT=${JOB_SUBMIT_CONNECT_TIMEOUT:-90}
JOB_SUBMIT_MAX_TIME=${JOB_SUBMIT_MAX_TIME:-600}
JOB_SUBMIT_RETRY_ATTEMPTS=${JOB_SUBMIT_RETRY_ATTEMPTS:-3}
JOB_SUBMIT_RETRY_DELAY=${JOB_SUBMIT_RETRY_DELAY:-10}

AUTOMATION_ENABLED_VALUE="unknown"
AUTOMATION_CHECK_NOTE="Not checked"
SITE_CONFIG_ENDPOINT="/xapi/siteConfig/automation.enabled"

# Track which projects have been enabled (associative array simulation)
ENABLED_PROJECTS_FILE="/tmp/enabled_projects_$$.txt"
touch "$ENABLED_PROJECTS_FILE"

curl_api() {
    curl -s \
        --connect-timeout "$API_CONNECT_TIMEOUT" \
        --max-time "$API_MAX_TIME" \
        --retry "$API_RETRY_COUNT" \
        --retry-delay "$API_RETRY_DELAY" \
        --retry-connrefused \
        "$@"
}

curl_job_submit() {
    curl -s \
        --connect-timeout "$JOB_SUBMIT_CONNECT_TIMEOUT" \
        --max-time "$JOB_SUBMIT_MAX_TIME" \
        --retry "$API_RETRY_COUNT" \
        --retry-delay "$API_RETRY_DELAY" \
        --retry-connrefused \
        "$@"
}

submit_job_with_retry() {
    local exp_id="$1"
    local project_id="$2"
    local log_file="$3"

    SUBMIT_RESPONSE=""
    SUBMIT_HTTP_STATUS=""
    SUBMIT_STATUS=""
    SUBMIT_ERROR_REASON=""
    SUBMIT_WORKFLOW_ID=""
    SUBMIT_ATTEMPTS=0

    local attempt=1

    local api_url="${XNAT_HOST}/xapi/wrappers/${WRAPPER_ID}/root/xnat:imageSessionData/launch"
    local api_data="context=session&session=${exp_id}"

    if [ "$DEBUG" = true ]; then
        echo ""
        echo -e "${YELLOW}=== DEBUG: API REQUEST ===${NC}"
        echo "URL: $api_url"
        echo "Method: POST"
        echo "Cookie: JSESSIONID=$JSESSION"
        echo "Content-Type: application/x-www-form-urlencoded"
        echo "Data: $api_data"
        echo ""
        echo "Full curl command:"
        echo "curl -X POST \\"
        echo "  -b 'JSESSIONID=$JSESSION' \\"
        echo "  -H 'Content-Type: application/x-www-form-urlencoded' \\"
        echo "  -d '$api_data' \\"
        echo "  '$api_url'"
        echo ""
    fi

    while [ $attempt -le "$JOB_SUBMIT_RETRY_ATTEMPTS" ]; do
        local tmp_file
        tmp_file=$(mktemp)

        local curl_status
        curl_status=$(curl_job_submit \
            -o "$tmp_file" \
            -w "%{http_code}" \
            -X POST \
            -b "JSESSIONID=$JSESSION" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            "$api_url" \
            -d "$api_data")

        local response
        response=$(cat "$tmp_file")
        rm -f "$tmp_file"

        SUBMIT_ATTEMPTS=$attempt
        SUBMIT_HTTP_STATUS="${curl_status:-000}"
        SUBMIT_RESPONSE="$response"

        if [ "$DEBUG" = true ]; then
            echo -e "${YELLOW}=== DEBUG: API RESPONSE ===${NC}"
            echo "HTTP Status: $SUBMIT_HTTP_STATUS"
            echo "Response Body:"
            echo "$response" | head -20
            if [ $(echo "$response" | wc -l) -gt 20 ]; then
                echo "... (truncated, see full response above)"
            fi
            echo ""
        fi

        local should_retry=false
        local retry_reason=""

        if [ "$SUBMIT_HTTP_STATUS" = "000" ]; then
            should_retry=true
            retry_reason="Connection error"
        elif [[ "$SUBMIT_HTTP_STATUS" =~ ^[0-9]+$ ]] && [ "$SUBMIT_HTTP_STATUS" -ge 500 ]; then
            should_retry=true
            retry_reason="HTTP $SUBMIT_HTTP_STATUS"
        fi

        if echo "$response" | grep -qi "<!doctype html"; then
            SUBMIT_STATUS="html_error"
            SUBMIT_ERROR_REASON=$(echo "$response" | sed -n 's/.*<title>\([^<]*\)<\/title>.*/\1/p' | head -1)
            [ -z "$SUBMIT_ERROR_REASON" ] && SUBMIT_ERROR_REASON="HTML error page"
            should_retry=true
            [ -z "$retry_reason" ] && retry_reason="$SUBMIT_ERROR_REASON"
        elif echo "$response" | jq empty >/dev/null 2>&1; then
            local status_value
            status_value=$(echo "$response" | jq -r '.status // "unknown"')
            if [ "$status_value" = "success" ]; then
                SUBMIT_STATUS="success"
                SUBMIT_WORKFLOW_ID=$(echo "$response" | jq -r '.["workflow-id"] // "pending"')
                SUBMIT_ERROR_REASON=""
                break
            else
                SUBMIT_STATUS="api_error"
                SUBMIT_ERROR_REASON=$(echo "$response" | jq -r '.message // .error // "Unknown error"')
                should_retry=true
                [ -z "$retry_reason" ] && retry_reason="$SUBMIT_ERROR_REASON"
            fi
        else
            SUBMIT_STATUS="invalid_response"
            SUBMIT_ERROR_REASON="Invalid response"
            should_retry=true
            [ -z "$retry_reason" ] && retry_reason="$SUBMIT_ERROR_REASON"
        fi

        if [ "$SUBMIT_STATUS" = "success" ]; then
            break
        fi

        if [ "$should_retry" = true ] && [ $attempt -lt "$JOB_SUBMIT_RETRY_ATTEMPTS" ]; then
            echo -e "${YELLOW}Attempt $attempt failed for $exp_id: ${retry_reason}. Retrying in ${JOB_SUBMIT_RETRY_DELAY}s...${NC}"
            if [ -n "$log_file" ]; then
                local retry_timestamp
                retry_timestamp=$(date '+%Y-%m-%d %H:%M:%S')
                cat >> "$log_file" <<EOF
[$retry_timestamp] RETRY - $exp_id
  Attempt: $attempt/$JOB_SUBMIT_RETRY_ATTEMPTS
  HTTP Status: ${SUBMIT_HTTP_STATUS:-unknown}
  Reason: $retry_reason
EOF
            fi
            sleep "$JOB_SUBMIT_RETRY_DELAY"
            attempt=$((attempt + 1))
            continue
        fi

        break
    done

    if [ "$SUBMIT_STATUS" != "success" ] && [ -z "$SUBMIT_ERROR_REASON" ]; then
        SUBMIT_ERROR_REASON="Submission failed"
    fi
}

# Check if wrapper is enabled for a project
check_wrapper_enabled() {
    local project="$1"
    local wrapper_id="$2"

    local enabled_resp
    enabled_resp=$(curl_api -b "JSESSIONID=$JSESSION" "${XNAT_HOST}/xapi/projects/${project}/wrappers/${wrapper_id}/enabled" 2>/dev/null)

    if echo "$enabled_resp" | jq empty 2>/dev/null; then
        echo "$enabled_resp" | jq -r '.["enabled-for-project"] // false'
    else
        echo "$enabled_resp"
    fi
}

# Enable wrapper for a project
enable_wrapper_for_project() {
    local project="$1"
    local wrapper_id="$2"

    # Check if already enabled in this session
    if grep -q "^${project}$" "$ENABLED_PROJECTS_FILE" 2>/dev/null; then
        return 0
    fi

    local enabled
    enabled=$(check_wrapper_enabled "$project" "$wrapper_id")

    if [ "$enabled" = "true" ]; then
        echo -e "${GREEN}✓ Wrapper already enabled for project $project${NC}"
        echo "$project" >> "$ENABLED_PROJECTS_FILE"
        return 0
    fi

    echo -e "${YELLOW}Enabling wrapper ${wrapper_id} for project ${project}...${NC}"

    local enable_result
    enable_result=$(curl_api -w "\nHTTP_CODE:%{http_code}" -X PUT \
        -b "JSESSIONID=$JSESSION" \
        -H "Content-Type: text/plain" \
        "${XNAT_HOST}/xapi/projects/${project}/wrappers/${wrapper_id}/enabled" \
        -d "true")

    local http_code
    http_code=$(echo "$enable_result" | grep "HTTP_CODE:" | sed 's/HTTP_CODE://')

    if [ "$http_code" = "200" ] || [ "$http_code" = "201" ]; then
        echo -e "${GREEN}✓ Wrapper enabled for project $project${NC}"
        echo "$project" >> "$ENABLED_PROJECTS_FILE"
        return 0
    else
        echo -e "${RED}✗ Failed to enable wrapper for project $project (HTTP $http_code)${NC}"
        return 1
    fi
}

fetch_site_automation_value() {
    local response
    response=$(curl_api -b "JSESSIONID=$JSESSION" -H "Accept: application/json" "${XNAT_HOST}${SITE_CONFIG_ENDPOINT}" 2>/dev/null)

    if [ -z "$response" ]; then
        response=$(curl_api -b "JSESSIONID=$JSESSION" -H "Accept: text/plain" "${XNAT_HOST}${SITE_CONFIG_ENDPOINT}" 2>/dev/null)
    fi

    if [ -z "$response" ]; then
        return 1
    fi

    local normalized=""
    normalized=$(echo "$response" | jq -r '.' 2>/dev/null)
    if [ $? -eq 0 ] && [[ "$normalized" =~ ^(true|false|null)$ ]]; then
        echo "$normalized"
        return 0
    fi

    normalized=$(echo "$response" | jq -r '.value // .text // empty' 2>/dev/null)
    if [ -n "$normalized" ]; then
        echo "$normalized"
        return 0
    fi

    normalized=$(echo "$response" | tr -d '"\r\n ')
    if [ -n "$normalized" ]; then
        echo "$normalized"
        return 0
    fi

    return 1
}

set_site_automation_value() {
    local desired_value="$1"
    local tmp_file
    tmp_file=$(mktemp)

    local http_code
    http_code=$(curl_api \
        -o "$tmp_file" \
        -w "%{http_code}" \
        -X POST \
        -b "JSESSIONID=$JSESSION" \
        -H "accept: application/json" \
        -H "Content-Type: text/plain" \
        "${XNAT_HOST}${SITE_CONFIG_ENDPOINT}" \
        -d "$desired_value" 2>/dev/null)

    local resp_body
    resp_body=$(cat "$tmp_file")
    rm -f "$tmp_file"

    if [[ "$http_code" =~ ^(200|201|204)$ ]]; then
        echo -e "${GREEN}✓ automation.enabled updated to ${desired_value} via ${SITE_CONFIG_ENDPOINT}${NC}"
        return 0
    fi

    echo -e "${YELLOW}⚠ Failed to update automation.enabled via ${SITE_CONFIG_ENDPOINT} (HTTP ${http_code}).${NC}"
    return 1
}

disable_site_automation_setting() {
    echo -e "${YELLOW}Attempting to force automation.enabled=false...${NC}"
    set_site_automation_value "false"
}

check_site_automation_setting() {
    echo -e "${YELLOW}Checking site automation settings...${NC}"
    local automation_value
    if ! automation_value=$(fetch_site_automation_value); then
        AUTOMATION_ENABLED_VALUE="unknown"
        AUTOMATION_CHECK_NOTE="Unable to read automation.enabled"
        echo -e "${YELLOW}⚠ Unable to read ${SITE_CONFIG_ENDPOINT}; skipping automation check.${NC}"
        return
    fi

    if [ -z "$automation_value" ] || [ "$automation_value" = "null" ]; then
        echo -e "${YELLOW}⚠ automation.enabled not present; attempting to set to false.${NC}"
        if disable_site_automation_setting && automation_value=$(fetch_site_automation_value); then
            :
        fi
    fi

    local automation_lower=$(echo "${automation_value}" | tr '[:upper:]' '[:lower:]')

    if [ "$automation_lower" = "false" ] || [ "$automation_lower" = "0" ]; then
        AUTOMATION_ENABLED_VALUE="false"
        AUTOMATION_CHECK_NOTE="automation.enabled=false"
        echo -e "${GREEN}✓ automation.enabled is disabled at the site level${NC}"
    else
        AUTOMATION_ENABLED_VALUE="$automation_value"
        echo -e "${RED}✗ automation.enabled currently '${automation_value}' (expected false).${NC}"
        if disable_site_automation_setting && automation_value=$(fetch_site_automation_value); then
            automation_lower=$(echo "${automation_value}" | tr '[:upper:]' '[:lower:]')
            if [ "$automation_lower" = "false" ] || [ "$automation_lower" = "0" ]; then
                AUTOMATION_ENABLED_VALUE="false"
                AUTOMATION_CHECK_NOTE="automation.enabled=false (auto-updated)"
                echo -e "${GREEN}✓ automation.enabled successfully set to false${NC}"
                return
            fi
        fi
        AUTOMATION_ENABLED_VALUE="$automation_value"
        AUTOMATION_CHECK_NOTE="automation.enabled=${automation_value} (update failed)"
        echo -e "${YELLOW}⚠ Unable to enforce automation.enabled=false via ${SITE_CONFIG_ENDPOINT}.${NC}"
    fi
}

# Parse CSV header and create column index mapping
parse_csv_header() {
    local header="$1"
    local IFS=','
    local col_num=1

    # Clear any existing mappings
    unset COL_ID COL_PROJECT

    for col_name in $header; do
        # Trim whitespace and convert to lowercase for comparison
        col_name=$(echo "$col_name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        col_name_lower=$(echo "$col_name" | tr '[:upper:]' '[:lower:]')

        case "$col_name_lower" in
            id) COL_ID=$col_num ;;
            project) COL_PROJECT=$col_num ;;
        esac
        col_num=$((col_num + 1))
    done

    # Validate required columns exist
    local missing_cols=""
    [ -z "$COL_ID" ] && missing_cols="${missing_cols}ID "
    [ -z "$COL_PROJECT" ] && missing_cols="${missing_cols}Project "

    if [ -n "$missing_cols" ]; then
        echo -e "${RED}Error: Missing required columns: $missing_cols${NC}"
        return 1
    fi

    return 0
}

# Extract value from CSV row by column index
get_csv_value() {
    local row="$1"
    local col_index="$2"
    echo "$row" | awk -F',' -v col="$col_index" '{print $col}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# Usage
usage() {
    echo "Usage: $0 -h <XNAT_HOST> -u <USERNAME> -p <PASSWORD> -f <CSV_FILE> [-c <CONTAINER_NAME>] [-m <MAX_JOBS>] [-r <REPORT_PROJECT>] [-i] [-d] [-D] [-v]"
    echo "  -h  XNAT host (e.g., https://xnat.example.com)"
    echo "  -u  Username"
    echo "  -p  Password"
    echo "  -f  CSV file with experiment IDs (required)"
    echo "  -c  Container name, ID, or Docker image to run (optional - will list if not provided)"
    echo "  -m  Maximum number of jobs to submit (optional - defaults to all experiments in CSV)"
    echo "  -r  Report project ID to upload results to (optional - creates BATCH_TESTS resource)"
    echo "  -i  Use individual mode (one API call per experiment) - default is bulk mode (single API call, 200x faster)"
    echo "  -d  Dry-run mode - validate CSV and show what would be done without actually launching containers"
    echo "  -D  Debug mode - show detailed API requests and responses"
    echo "  -v  Verbose mode - show individual workflow details during monitoring"
    echo ""
    echo "Required CSV columns (can be in any order, extra columns ignored):"
    echo "  ID, Project"
    echo ""
    echo "ID Format:"
    echo "  - Simple ID (e.g., 00001) - will be formatted as {Project}_E{ID}"
    echo "  - Full experiment ID (e.g., XNAT01_E00001) - used as-is"
    echo ""
    echo "Example CSV (simple IDs):"
    echo '  ID,Project'
    echo '  00001,XNAT01'
    echo '  00002,XNAT01'
    echo ""
    echo "Example CSV (full experiment IDs):"
    echo '  ID,Project'
    echo '  XNAT01_E00001,XNAT01'
    echo '  XNAT01_E00002,XNAT01'
    echo ""
    echo "Note: Columns can be in any order. Extra columns are ignored."
    echo "      Each row can specify a different project."
    echo "      Experiments must already exist in XNAT."
    exit 1
}

# Parse arguments
DRY_RUN=false
DEBUG=false
VERBOSE=false
BULK_MODE=true  # Default to bulk mode (200x faster)
while getopts "h:u:p:f:c:m:r:idDv" opt; do
    case $opt in
        h) XNAT_HOST="$OPTARG" ;;
        u) USERNAME="$OPTARG" ;;
        p) PASSWORD="$OPTARG" ;;
        f) CSV_FILE="$OPTARG" ;;
        c) CONTAINER_NAME="$OPTARG" ;;
        m) MAX_JOBS="$OPTARG" ;;
        r) REPORT_PROJECT="$OPTARG" ;;
        i) BULK_MODE=false ;;  # Individual mode (one API call per experiment)
        d) DRY_RUN=true ;;
        D) DEBUG=true ;;
        v) VERBOSE=true ;;
        *) usage ;;
    esac
done

if [ -z "$XNAT_HOST" ] || [ -z "$USERNAME" ] || [ -z "$PASSWORD" ] || [ -z "$CSV_FILE" ]; then
    usage
fi

# Validate CSV file exists
if [ ! -f "$CSV_FILE" ]; then
    echo -e "${RED}CSV file not found: $CSV_FILE${NC}"
    exit 1
fi

# Remove trailing slash from host
XNAT_HOST="${XNAT_HOST%/}"

if [ "$DRY_RUN" = true ]; then
    echo -e "${BLUE}=== XNAT CSV Batch Container Launch - DRY RUN MODE ===${NC}"
    echo -e "${YELLOW}No containers will be launched. Validating CSV only.${NC}"
else
    echo -e "${GREEN}=== XNAT CSV Batch Container Launch ===${NC}"
fi
echo "Host: $XNAT_HOST"
echo "User: $USERNAME"
echo "CSV File: $CSV_FILE"
[ "$DRY_RUN" = true ] && echo "Mode: DRY RUN"
echo ""

# Step 1: Authenticate
echo -e "${YELLOW}[1/5] Authenticating...${NC}"
JSESSION=$(curl_api -u "${USERNAME}:${PASSWORD}" "${XNAT_HOST}/data/JSESSION")

if [ -z "$JSESSION" ]; then
    echo -e "${RED}Failed to authenticate${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Authenticated (JSESSION: ${JSESSION:0:20}...)${NC}"
echo ""

check_site_automation_setting
echo ""

# Step 2: Parse CSV file
echo -e "${YELLOW}[2/5] Parsing CSV file...${NC}"

# Read CSV header
CSV_HEADER=$(head -1 "$CSV_FILE")
echo "CSV Header: $CSV_HEADER"
echo ""

# Parse header and create column mappings
if ! parse_csv_header "$CSV_HEADER"; then
    echo ""
    echo -e "${RED}Cannot proceed without required columns${NC}"
    exit 1
fi

echo -e "${GREEN}✓ CSV header validated${NC}"
echo "  Required columns found: ID (col $COL_ID), Project (col $COL_PROJECT)"
echo ""
echo -e "${BLUE}CSV header: $CSV_HEADER${NC}"
echo ""

# Determine how many experiments to process
if [ -n "$MAX_JOBS" ] && [ "$MAX_JOBS" -gt 0 ]; then
    # User specified a limit - use it directly without reading entire CSV
    EXPERIMENT_COUNT="$MAX_JOBS"
    echo -e "${GREEN}✓ Processing first $EXPERIMENT_COUNT experiments from CSV${NC}"
else
    # No limit specified - count all experiments in CSV
    EXPERIMENT_COUNT=$(tail -n +2 "$CSV_FILE" | wc -l | tr -d ' ')
    echo -e "${GREEN}✓ Found $EXPERIMENT_COUNT experiments in CSV${NC}"
fi
echo ""

# Extract unique projects from CSV (only from rows we'll process)
PROJECTS=$(tail -n +2 "$CSV_FILE" | head -n "$EXPERIMENT_COUNT" | awk -F',' -v col="$COL_PROJECT" '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $col); print $col}' | sort -u)
PROJECT_COUNT=$(echo "$PROJECTS" | wc -l | tr -d ' ')

echo "Projects found in selected experiments:"
echo "$PROJECTS" | nl -w 3 -s '. '
echo ""

if [ "$PROJECT_COUNT" -eq 1 ]; then
    echo -e "${GREEN}All selected experiments use a single project${NC}"
else
    echo -e "${YELLOW}Multiple projects detected - container will be enabled for each${NC}"
fi
echo ""

# Confirm projects before proceeding
echo -e "${YELLOW}=== PROJECT CONFIRMATION ===${NC}"
echo "The script will work with the following project(s):"
echo ""

# Show experiment count per project (only from selected experiments)
echo "$PROJECTS" | while read -r proj; do
    COUNT=$(tail -n +2 "$CSV_FILE" | head -n "$EXPERIMENT_COUNT" | awk -F',' -v col="$COL_PROJECT" -v project="$proj" '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $col); if ($col == project) count++} END {print count+0}')
    printf "  %-15s (%d experiments)\n" "$proj" "$COUNT"
done
echo ""
if [ -n "$MAX_JOBS" ] && [ "$MAX_JOBS" -gt 0 ]; then
    echo "Total: $EXPERIMENT_COUNT experiments across $PROJECT_COUNT project(s) (limited by -m flag)"
else
    echo "Total: $EXPERIMENT_COUNT experiments across $PROJECT_COUNT project(s)"
fi
echo ""

read -p "Continue with these projects? (y/yes): " PROJECT_CONFIRM

if [[ ! "$PROJECT_CONFIRM" =~ ^[Yy]([Ee][Ss])?$ ]]; then
    echo "Aborted. Please check your CSV file and try again."
    exit 0
fi
echo ""

# Show selected experiments with parsed values
if [ "$EXPERIMENT_COUNT" -le 5 ]; then
    echo "Experiments to process:"
else
    echo "First 5 of $EXPERIMENT_COUNT experiments:"
fi
tail -n +2 "$CSV_FILE" | head -n 5 | while IFS= read -r row; do
    id_val=$(get_csv_value "$row" "$COL_ID")
    proj_val=$(get_csv_value "$row" "$COL_PROJECT")
    echo "  ID='$id_val', Project='$proj_val'"
done
echo ""

# Step 3: Select container
echo -e "${YELLOW}[3/5] Container selection...${NC}"
if [ -z "$CONTAINER_NAME" ]; then
    echo "Fetching available containers..."

    COMMANDS=$(curl_api -b "JSESSIONID=$JSESSION" "${XNAT_HOST}/xapi/commands" -H "Accept: application/json")

    if [ -z "$COMMANDS" ] || [ "$COMMANDS" = "[]" ]; then
        echo -e "${RED}No containers found${NC}"
        read -p "Enter wrapper ID: " CONTAINER_NAME

        if [ -z "$CONTAINER_NAME" ]; then
            echo -e "${RED}No container specified${NC}"
            exit 1
        fi
    else
        echo ""
        echo "Available containers:"
        echo "$COMMANDS" | jq -r '
            .[] |
            .image as $img |
            (.xnat // .["xnat-command-wrappers"] // .xnatCommandWrappers // [])[] |
            "\(.id)\t\(.name)\t\($img // "unknown")\t\(.contexts | join(","))"
        ' | column -t -s $'\t' | nl -w 3 -s '. '
        echo ""

        read -p "Enter wrapper name or ID: " CONTAINER_NAME

        if [ -z "$CONTAINER_NAME" ]; then
            echo -e "${RED}No container specified${NC}"
            exit 1
        fi
    fi
fi

# Get wrapper ID
if [ -z "$COMMANDS" ]; then
    COMMANDS=$(curl_api -b "JSESSIONID=$JSESSION" "${XNAT_HOST}/xapi/commands" -H "Accept: application/json")
fi

WRAPPER_ID=$(echo "$COMMANDS" | jq -r --arg name "$CONTAINER_NAME" '
    .[] |
    (.image // "") as $img |
    (.xnat // .["xnat-command-wrappers"] // .xnatCommandWrappers // [])[] |
    select(.name == $name or (.id|tostring) == $name or $img == $name) |
    .id
' | head -1)

if [ -z "$WRAPPER_ID" ]; then
    WRAPPER_ID="$CONTAINER_NAME"
fi

echo -e "${GREEN}✓ Container: $CONTAINER_NAME (ID: $WRAPPER_ID)${NC}"
echo ""

# Step 4: Enable wrapper for all projects (only from selected experiments)
# Note: $PROJECTS was already filtered to only include projects from first $EXPERIMENT_COUNT rows
if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}[4/5] DRY RUN: Would enable wrapper for projects...${NC}"
    echo ""
    for project in $PROJECTS; do
        echo -e "${BLUE}  Would enable wrapper ${WRAPPER_ID} for project: $project${NC}"
    done
    echo ""
else
    echo -e "${YELLOW}[4/5] Enabling wrapper for all projects...${NC}"
    echo ""

    ENABLE_ERROR=false
    for project in $PROJECTS; do
        if ! enable_wrapper_for_project "$project" "$WRAPPER_ID"; then
            echo -e "${RED}Failed to enable wrapper for project: $project${NC}"
            ENABLE_ERROR=true
        fi
    done
    echo ""

    if [ "$ENABLE_ERROR" = true ]; then
        echo -e "${RED}Some projects failed to enable the wrapper${NC}"
        read -p "Continue anyway? (y/yes): " CONTINUE_ANYWAY
        if [[ ! "$CONTINUE_ANYWAY" =~ ^[Yy]([Ee][Ss])?$ ]]; then
            echo "Aborted."
            rm -f "$ENABLED_PROJECTS_FILE"
            exit 1
        fi
    fi
fi

# Step 5: Verify experiments exist (optional check could be added here)
echo -e "${YELLOW}[5/5] Ready to launch containers${NC}"
echo "Note: Experiments must already exist in XNAT"
echo ""

# Prepare for submission
echo -e "${YELLOW}Preparing for batch submission...${NC}"
echo ""

# Confirm batch submission or show dry-run summary
if [ "$DRY_RUN" = true ]; then
    echo -e "${BLUE}=== DRY RUN SUMMARY ===${NC}"
    echo "Experiments to launch: $EXPERIMENT_COUNT"
    echo "Container: $CONTAINER_NAME (ID: $WRAPPER_ID)"
    echo "Projects: $PROJECT_COUNT unique project(s)"
    echo ""
    echo "Experiment IDs that would be launched:"
    tail -n +2 "$CSV_FILE" | head -n "$EXPERIMENT_COUNT" | while IFS= read -r row; do
        project=$(get_csv_value "$row" "$COL_PROJECT")
        exp_id=$(get_csv_value "$row" "$COL_ID")

        if [[ "$exp_id" != *_* ]]; then
            EXP_ID="${project}_E${exp_id}"
        else
            EXP_ID="$exp_id"
        fi

        echo "  - $EXP_ID (project: $project)"
    done
    echo ""
    echo -e "${GREEN}✓ Dry-run validation complete${NC}"
    echo "CSV is valid and ready for batch submission."
    echo "Run without -d flag to launch containers."
    rm -f "$ENABLED_PROJECTS_FILE"
    exit 0
else
    echo -e "${YELLOW}=== READY TO SUBMIT BATCH ===${NC}"
    echo "Experiments: $EXPERIMENT_COUNT"
    echo "Container: $CONTAINER_NAME (ID: $WRAPPER_ID)"
    echo "Projects: $PROJECT_COUNT unique project(s)"
    echo ""
    echo -e "${RED}This will create $EXPERIMENT_COUNT container jobs!${NC}"
    echo ""
    read -p "Continue with batch submission? (y/yes): " CONFIRM

    if [[ ! "$CONFIRM" =~ ^[Yy]([Ee][Ss])?$ ]]; then
        echo "Aborted."
        rm -f "$ENABLED_PROJECTS_FILE"
        exit 0
    fi
fi

# Submit batch
echo ""
echo -e "${YELLOW}Submitting batch jobs...${NC}"
echo ""

# Initialize timing and logging
BATCH_START_TIME=$(date +%s)
BATCH_START_TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
LOG_DIR="logs/$(date '+%Y-%m-%d')"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/batch_test_csv_$(date '+%H%M%S').log"

SUCCESS_COUNT=0
FAIL_COUNT=0
RESULTS_FILE="/tmp/batch_results_$$.txt"
TIMING_FILE="/tmp/batch_timing_$$.txt"

# Write log header
cat > "$LOG_FILE" <<EOF
=================================================================
XNAT CSV Batch Container Launch Log
=================================================================
Test Started: $BATCH_START_TIMESTAMP
Host: $XNAT_HOST
User: $USERNAME
CSV File: $CSV_FILE
Container: $CONTAINER_NAME (Wrapper ID: $WRAPPER_ID)
Projects: $PROJECT_COUNT unique project(s)
Experiments to Process: $EXPERIMENT_COUNT
Max Jobs Limit: ${MAX_JOBS:-None}
Site Automation Enabled: ${AUTOMATION_ENABLED_VALUE}
Automation Check Note: ${AUTOMATION_CHECK_NOTE}
=================================================================

Projects in CSV:
$(echo "$PROJECTS" | sed 's/^/  /')

=================================================================

EOF

echo "Logging to: $LOG_FILE"
echo ""

# Bulk submission mode
if [ "$BULK_MODE" = true ]; then
    echo -e "${YELLOW}Using bulk submission mode (single API call for all experiments)${NC}"
    echo ""

    # Collect ALL experiment IDs
    ALL_EXPERIMENTS=()
    while IFS= read -r row; do
        proj=$(get_csv_value "$row" "$COL_PROJECT")
        exp_id=$(get_csv_value "$row" "$COL_ID")

        # Format experiment ID if needed
        if [[ "$exp_id" != *_* ]]; then
            EXP_ID="${proj}_E${exp_id}"
        else
            EXP_ID="$exp_id"
        fi
        ALL_EXPERIMENTS+=("$EXP_ID")
    done < <(tail -n +2 "$CSV_FILE" | head -n "$EXPERIMENT_COUNT")

    TOTAL_COUNT=${#ALL_EXPERIMENTS[@]}
    echo -e "${BLUE}Submitting $TOTAL_COUNT experiments in bulk...${NC}"

    # Build JSON array of experiment paths
    SESSION_ARRAY=$(printf '/archive/experiments/%s\n' "${ALL_EXPERIMENTS[@]}" | jq -R . | jq -s .)
    BULK_PAYLOAD=$(jq -n --argjson sessions "$SESSION_ARRAY" '{"session": ($sessions | tostring)}')

    if [ "$DEBUG" = true ]; then
        echo ""
        echo -e "${YELLOW}=== DEBUG: BULK API REQUEST ===${NC}"
        echo "URL: ${XNAT_HOST}/xapi/wrappers/${WRAPPER_ID}/root/session/bulklaunch"
        echo "Method: POST"
        echo "Payload:"
        echo "$BULK_PAYLOAD" | jq '.'
        echo ""
    fi

    BULK_START_TIME=$(date +%s.%N)

    BULK_RESPONSE=$(curl_job_submit \
        -w "\n%{http_code}" \
        -X POST \
        -b "JSESSIONID=$JSESSION" \
        -H "Content-Type: application/json" \
        -H "X-Requested-With: XMLHttpRequest" \
        "${XNAT_HOST}/xapi/wrappers/${WRAPPER_ID}/root/session/bulklaunch" \
        -d "$BULK_PAYLOAD")

    BULK_END_TIME=$(date +%s.%N)
    BULK_DURATION=$(echo "$BULK_END_TIME - $BULK_START_TIME" | bc)

    # Parse response - last line is HTTP code, rest is body
    BULK_HTTP_CODE=$(echo "$BULK_RESPONSE" | tail -1)
    # Use sed to remove last line (works on both BSD and GNU)
    BULK_BODY=$(echo "$BULK_RESPONSE" | sed '$d')

    echo "Bulk submission completed in ${BULK_DURATION}s"
    echo "HTTP Status: $BULK_HTTP_CODE"

    if [ "$BULK_HTTP_CODE" = "200" ] || [ "$BULK_HTTP_CODE" = "201" ]; then
        echo -e "${GREEN}✓ Successfully submitted $TOTAL_COUNT experiments${NC}"
        SUCCESS_COUNT=$TOTAL_COUNT
    else
        echo -e "${RED}✗ Bulk submission failed${NC}"
        echo "Response: $BULK_BODY"
        FAIL_COUNT=$TOTAL_COUNT
    fi
    echo ""

    # Log bulk submission
    cat >> "$LOG_FILE" <<EOF
[$(date '+%Y-%m-%d %H:%M:%S')] BULK SUBMISSION
  Experiments: $TOTAL_COUNT
  Duration: ${BULK_DURATION}s
  HTTP Status: $BULK_HTTP_CODE
  Experiments: ${ALL_EXPERIMENTS[*]}

EOF
else
    # Individual submission mode - submit jobs one by one
    JOB_NUMBER=0
    tail -n +2 "$CSV_FILE" | head -n "$EXPERIMENT_COUNT" | while IFS= read -r row; do
    JOB_NUMBER=$((JOB_NUMBER + 1))

    # Extract values using dynamic column indices
    project=$(get_csv_value "$row" "$COL_PROJECT")
    exp_id=$(get_csv_value "$row" "$COL_ID")

    # Debug: check if values are empty
    if [ -z "$project" ] || [ -z "$exp_id" ]; then
        echo -e "${RED}ERROR: Failed to parse CSV row $JOB_NUMBER${NC}"
        echo "  Raw row: $row"
        echo "  COL_ID=$COL_ID, COL_PROJECT=$COL_PROJECT"
        echo "  Parsed ID='$exp_id', Project='$project'"
        continue
    fi

    # If ID doesn't contain underscore, format as {Project}_E{ID}
    # Otherwise use the ID as-is (assumes it's already a full experiment ID)
    if [[ "$exp_id" != *_* ]]; then
        EXP_ID="${project}_E${exp_id}"
    else
        EXP_ID="$exp_id"
    fi

    echo -e "${BLUE}Submitting job ${JOB_NUMBER}/${EXPERIMENT_COUNT}:${NC} $EXP_ID (project: $project)"
    JOB_START_TIME=$(date +%s.%N)

    submit_job_with_retry "$EXP_ID" "$project" "$LOG_FILE"

    JOB_END_TIME=$(date +%s.%N)
    JOB_DURATION=$(echo "$JOB_END_TIME - $JOB_START_TIME" | bc)
    JOB_TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

    ATTEMPT_NOTE=""
    if [[ "$SUBMIT_ATTEMPTS" =~ ^[0-9]+$ ]] && [ "$SUBMIT_ATTEMPTS" -gt 1 ]; then
        ATTEMPT_NOTE=", after ${SUBMIT_ATTEMPTS} attempts"
    fi

    if [ "$SUBMIT_STATUS" = "success" ]; then
        echo -e "${GREEN}✓${NC} $EXP_ID (workflow: $SUBMIT_WORKFLOW_ID${ATTEMPT_NOTE})"
        echo "SUCCESS" >> "$RESULTS_FILE"
        echo "$JOB_DURATION" >> "$TIMING_FILE"

        cat >> "$LOG_FILE" <<EOF
[$JOB_TIMESTAMP] SUCCESS - $EXP_ID (Project: $project)
  Duration: ${JOB_DURATION}s
  Workflow ID: $SUBMIT_WORKFLOW_ID
  Attempts: $SUBMIT_ATTEMPTS

EOF
    else
        ERROR_MESSAGE="${SUBMIT_ERROR_REASON:-Invalid response}"
        if [[ "$SUBMIT_HTTP_STATUS" =~ ^[0-9]+$ ]]; then
            ERROR_MESSAGE="$ERROR_MESSAGE (HTTP $SUBMIT_HTTP_STATUS)"
        fi
        echo -e "${RED}✗${NC} $EXP_ID: $ERROR_MESSAGE${ATTEMPT_NOTE}"
        echo "FAIL" >> "$RESULTS_FILE"
        echo "$JOB_DURATION" >> "$TIMING_FILE"

        cat >> "$LOG_FILE" <<EOF
[$JOB_TIMESTAMP] FAIL - $EXP_ID (Project: $project)
  Duration: ${JOB_DURATION}s
  Attempts: $SUBMIT_ATTEMPTS
  HTTP Status: ${SUBMIT_HTTP_STATUS:-unknown}
  Error: $ERROR_MESSAGE

EOF
    fi
    done
fi  # End of bulk mode check

BATCH_END_TIME=$(date +%s)
BATCH_END_TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
TOTAL_DURATION=$((BATCH_END_TIME - BATCH_START_TIME))

# Count results (skip if bulk mode already set counts)
if [ "$BULK_MODE" = false ]; then
    if [ -f "$RESULTS_FILE" ]; then
        SUCCESS_COUNT=$(grep -c "SUCCESS" "$RESULTS_FILE" 2>/dev/null || echo "0")
        FAIL_COUNT=$(grep -c "FAIL" "$RESULTS_FILE" 2>/dev/null || echo "0")
        rm "$RESULTS_FILE"
    else
        SUCCESS_COUNT=0
        FAIL_COUNT=0
    fi
fi

# Calculate timing statistics
if [ -f "$TIMING_FILE" ]; then
    AVG_DURATION=$(awk '{ total += $1; count++ } END { if (count > 0) print total/count; else print 0 }' "$TIMING_FILE")
    MIN_DURATION=$(sort -n "$TIMING_FILE" | head -1)
    MAX_DURATION=$(sort -n "$TIMING_FILE" | tail -1)
    rm "$TIMING_FILE"
else
    AVG_DURATION=0
    MIN_DURATION=0
    MAX_DURATION=0
fi

# Cleanup
rm -f "$ENABLED_PROJECTS_FILE"

# Ensure all numeric variables are set
SUCCESS_COUNT=${SUCCESS_COUNT:-0}
FAIL_COUNT=${FAIL_COUNT:-0}
EXPERIMENT_COUNT=${EXPERIMENT_COUNT:-0}
TOTAL_DURATION=${TOTAL_DURATION:-0}
AVG_DURATION=${AVG_DURATION:-0}
MIN_DURATION=${MIN_DURATION:-0}
MAX_DURATION=${MAX_DURATION:-0}

# Calculate percentages
if [ "$EXPERIMENT_COUNT" -gt 0 ] 2>/dev/null; then
    SUCCESS_PCT=$(awk "BEGIN {printf \"%.1f\", ($SUCCESS_COUNT/$EXPERIMENT_COUNT)*100}" 2>/dev/null || echo "0.0")
    FAIL_PCT=$(awk "BEGIN {printf \"%.1f\", ($FAIL_COUNT/$EXPERIMENT_COUNT)*100}" 2>/dev/null || echo "0.0")
else
    SUCCESS_PCT="0.0"
    FAIL_PCT="0.0"
fi

DURATION_MIN=$(awk "BEGIN {printf \"%.1f\", $TOTAL_DURATION/60}" 2>/dev/null || echo "0.0")

if [ "$TOTAL_DURATION" -gt 0 ] 2>/dev/null; then
    THROUGHPUT=$(awk "BEGIN {printf \"%.2f\", $EXPERIMENT_COUNT/$TOTAL_DURATION}" 2>/dev/null || echo "0.00")
else
    THROUGHPUT="0.00"
fi

# Write summary to log
cat >> "$LOG_FILE" <<EOF
=================================================================
Test Summary
=================================================================
Test Completed: $BATCH_END_TIMESTAMP
Test Duration: ${TOTAL_DURATION}s (${DURATION_MIN} minutes)

Test Configuration:
  CSV File: $CSV_FILE
  Projects: $PROJECT_COUNT unique project(s)
  Container: $CONTAINER_NAME (Wrapper ID: $WRAPPER_ID)
  Submission Mode: $([ "$BULK_MODE" = true ] && echo "Bulk" || echo "Individual")
  Max Jobs Limit: ${MAX_JOBS:-None}
  Host: $XNAT_HOST
  User: $USERNAME

Results:
  Jobs Submitted: $EXPERIMENT_COUNT
  Successful: $SUCCESS_COUNT (${SUCCESS_PCT}%)
  Failed: $FAIL_COUNT (${FAIL_PCT}%)

Performance Metrics:
  Total Duration: ${TOTAL_DURATION}s
  Average Job Submission Time: ${AVG_DURATION}s
  Fastest Submission: ${MIN_DURATION}s
  Slowest Submission: ${MAX_DURATION}s
  Throughput: ${THROUGHPUT} jobs/sec
=================================================================
EOF

echo ""
echo -e "${GREEN}=== BATCH SUBMISSION COMPLETE ===${NC}"
echo ""
echo "CSV File: $CSV_FILE"
echo "Projects: $PROJECT_COUNT unique project(s)"
echo "Container: $CONTAINER_NAME (ID: $WRAPPER_ID)"
echo "Jobs Submitted: $EXPERIMENT_COUNT"
echo ""
echo "Submission Results:"
echo "  Successfully Queued: $SUCCESS_COUNT (${SUCCESS_PCT}%)"
echo "  Failed to Queue: $FAIL_COUNT (${FAIL_PCT}%)"
echo ""
echo "Submission Performance:"
echo "  Submission Duration: ${TOTAL_DURATION}s (${DURATION_MIN} min)"
echo "  Avg Time per Job: ${AVG_DURATION}s"
echo "  Submission Throughput: ${THROUGHPUT} jobs/sec"
echo ""
echo -e "${YELLOW}Full log saved to: $LOG_FILE${NC}"
echo ""

# Wait for jobs to complete (MANDATORY - script will NOT exit until jobs finish)
# This ensures the final report contains ACTUAL completion status, not just submission status
if [ "$SUCCESS_COUNT" -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}=== MONITORING JOB EXECUTION ===${NC}"
    echo -e "${YELLOW}NOTE: Script will wait for all jobs to complete before exiting${NC}"
    echo ""
    echo "Monitoring workflow status (checking every 10 seconds)..."
    echo "Press Ctrl+C to stop monitoring and exit early"
    echo ""

    WORKFLOW_START_TIME=$(date +%s)
    CHECK_COUNT=0

    while true; do
        sleep 10
        CHECK_COUNT=$((CHECK_COUNT + 1))
        ELAPSED=$(($(date +%s) - WORKFLOW_START_TIME))
        ELAPSED_MIN=$(awk "BEGIN {printf \"%.1f\", $ELAPSED/60}")

        echo -ne "\r${YELLOW}Check $CHECK_COUNT (${ELAPSED_MIN} min elapsed) - Fetching workflow status...${NC}  "

        # Fetch workflows for each project
        ALL_WORKFLOWS="[]"
        for project in $PROJECTS; do
            PROJECT_WORKFLOWS=$(curl_api -X POST \
                -b "JSESSIONID=$JSESSION" \
                -H "Content-Type: application/json" \
                -H "X-Requested-With: XMLHttpRequest" \
                "${XNAT_HOST}/xapi/workflows" \
                -d "{\"id\":\"$project\",\"data_type\":\"xnat:projectData\",\"sortable\":true,\"days\":1}" 2>/dev/null)

            if [ -n "$PROJECT_WORKFLOWS" ]; then
                # Extract items array
                PROJECT_ITEMS=$(echo "$PROJECT_WORKFLOWS" | jq 'if type == "array" then . else .items // .workflows // [] end' 2>/dev/null)
                # Merge with accumulated workflows
                ALL_WORKFLOWS=$(echo "$ALL_WORKFLOWS" "$PROJECT_ITEMS" | jq -s '.[0] + .[1]' 2>/dev/null)
            fi
        done

        if [ "$ALL_WORKFLOWS" = "[]" ]; then
            echo -ne "\r${YELLOW}No workflows found yet, waiting...${NC}                              "
            if [ "$VERBOSE" = true ]; then
                echo ""
                echo "  (No workflows returned from API)"
                echo ""
            fi
            continue
        fi

        # Filter workflows to only those from our batch (after BATCH_START_TIME)
        BATCH_WORKFLOWS=$(echo "$ALL_WORKFLOWS" | jq --arg container "$CONTAINER_NAME" --argjson start_time "$BATCH_START_TIME" '
            map(select(
                (.pipelineName // .pipeline_name // "") == $container and
                ((.launchTime // .launch_time // 0) / 1000) >= $start_time
            ))
        ' 2>/dev/null)

        TOTAL_WORKFLOWS=$(echo "$BATCH_WORKFLOWS" | jq 'length' 2>/dev/null)

        if [ -z "$TOTAL_WORKFLOWS" ] || [ "$TOTAL_WORKFLOWS" = "0" ]; then
            echo -ne "\r${YELLOW}No workflows found yet, waiting...${NC}                              "
            if [ "$VERBOSE" = true ]; then
                echo ""
                echo "  Workflows returned from API but none match our filter:"
                echo "  Looking for: container='$CONTAINER_NAME', start_time >= $BATCH_START_TIME"
                echo ""
                echo "  All workflows received:"
                echo "$ALL_WORKFLOWS" | jq -r '.[] | "    - Pipeline: \(.pipelineName // .pipeline_name // "N/A"), LaunchTime: \((.launchTime // .launch_time // 0) / 1000), Status: \(.status)"' 2>/dev/null || echo "    (Unable to parse)"
                echo ""
            fi
            continue
        fi

        # Count by status (matches any status containing these keywords)
        RUNNING=$(echo "$BATCH_WORKFLOWS" | jq '[.[] | select(.status | test("Running|Started|In Progress"; "i"))] | length' 2>/dev/null)
        COMPLETE=$(echo "$BATCH_WORKFLOWS" | jq '[.[] | select(.status | test("Complete"; "i"))] | length' 2>/dev/null)
        FAILED=$(echo "$BATCH_WORKFLOWS" | jq '[.[] | select(.status | test("Failed|Killed"; "i"))] | length' 2>/dev/null)
        PENDING=$(echo "$BATCH_WORKFLOWS" | jq '[.[] | select(.status | test("Queued|Pending|Finalizing"; "i"))] | length' 2>/dev/null)

        # Clean up display line
        echo -ne "\r                                                                                           \r"

        echo "Check $CHECK_COUNT (${ELAPSED_MIN} min): Found $TOTAL_WORKFLOWS workflows - Running: ${RUNNING:-0}, Complete: ${COMPLETE:-0}, Failed: ${FAILED:-0}, Pending: ${PENDING:-0}"

        # Show individual workflow details in verbose mode
        if [ "$VERBOSE" = true ] && [ "$TOTAL_WORKFLOWS" -gt 0 ]; then
            echo ""
            echo "$BATCH_WORKFLOWS" | jq -r '.[] | "  - Workflow \(.workflowId // .workflow_id // "N/A"): \(.externalId // .external_id // "N/A") - \(.status) (launched \(.launchTime // .launch_time // 0 | tonumber / 1000 | strftime("%Y-%m-%d %H:%M:%S")))"' 2>/dev/null || echo "  (Unable to parse workflow details)"
            echo ""
        fi

        # Check if all jobs are done (none running or pending)
        if [ "${RUNNING:-0}" -eq 0 ] && [ "${PENDING:-0}" -eq 0 ] && [ "$TOTAL_WORKFLOWS" -ge "$SUCCESS_COUNT" ]; then
            echo ""
            echo -e "${GREEN}✓ All jobs completed!${NC}"
            echo ""

            # Show final status summary
            echo "Execution Results:"
            echo "  Complete: ${COMPLETE:-0}"
            echo "  Failed: ${FAILED:-0}"
            echo ""

            # Calculate total time
            TOTAL_TIME=$((TOTAL_DURATION + ELAPSED))
            TOTAL_TIME_MIN=$(awk "BEGIN {printf \"%.1f\", $TOTAL_TIME/60}" 2>/dev/null || echo "0.0")

            echo "Execution Performance:"
            echo "  Execution Duration: ${ELAPSED}s (${ELAPSED_MIN} min)"
            echo "  Total Time (Submission + Execution): ${TOTAL_TIME}s (${TOTAL_TIME_MIN} min)"
            echo ""

            # Update log file with execution time
            cat >> "$LOG_FILE" <<EOF

=================================================================
Job Execution Monitoring
=================================================================
Execution Time: ${ELAPSED}s (${ELAPSED_MIN} minutes)
Final Status: ${COMPLETE:-0} Complete, ${FAILED:-0} Failed
Total Time (Submission + Execution): ${TOTAL_TIME}s (${TOTAL_TIME_MIN} minutes)
=================================================================
EOF

            # Store workflows for display below
            FINAL_WORKFLOWS="$BATCH_WORKFLOWS"
            break
        fi
    done

    # Display final workflow details
    if [ -n "$FINAL_WORKFLOWS" ]; then
        echo "Workflow details (last 10):"
        echo "$FINAL_WORKFLOWS" | jq -r 'sort_by(.launchTime // .launch_time) | reverse | .[] | "\(.status)\t\(.pipelineName // .pipeline_name // "unknown")\t\(.comments // "unknown")"' 2>/dev/null | head -10 | nl -w 3 -s '. ' | while IFS=$'\t' read -r num status wrapper exp_label; do
            case "$status" in
                *[Cc]omplete*|*[Ss]uccess*|*[Dd]one*)
                    printf "${GREEN}%s${NC} %-15s %-20s %s\n" "$num" "$status" "$wrapper" "$exp_label"
                    ;;
                *[Ff]ail*|*[Ee]rror*)
                    printf "${RED}%s${NC} %-15s %-20s %s\n" "$num" "$status" "$wrapper" "$exp_label"
                    ;;
                *)
                    printf "%s %-15s %-20s %s\n" "$num" "$status" "$wrapper" "$exp_label"
                    ;;
            esac
        done
        echo ""
    fi
fi

# Generate and upload HTML report if requested
if [ -n "$REPORT_PROJECT" ]; then
    echo ""
    echo -e "${YELLOW}=== GENERATING HTML REPORT ===${NC}"
    echo ""

    if [ -f "./generate_html_report.sh" ]; then
        ./generate_html_report.sh \
            -l "$LOG_FILE" \
            -h "$XNAT_HOST" \
            -u "$USERNAME" \
            -p "$PASSWORD" \
            -r "$REPORT_PROJECT"
    else
        echo -e "${RED}generate_html_report.sh not found${NC}"
        echo "Skipping HTML report generation"
    fi
fi

echo ""
echo -e "${GREEN}Done!${NC}"
