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
            "${XNAT_HOST}/xapi/projects/${project_id}/wrappers/${WRAPPER_ID}/root/xnat:imageSessionData/launch" \
            -d "context=session&session=${exp_id}")

        local response
        response=$(cat "$tmp_file")
        rm -f "$tmp_file"

        SUBMIT_ATTEMPTS=$attempt
        SUBMIT_HTTP_STATUS="${curl_status:-000}"
        SUBMIT_RESPONSE="$response"

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
            SUBMIT_ERROR_REASON=$(echo "$response" | grep -oP '(?<=<title>)[^<]+' | head -1)
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
    unset COL_ID COL_LABEL COL_SUBJECT COL_DATE COL_GENDER COL_AGE
    unset COL_ACCESSION COL_PATIENT_ID COL_PATIENT_NAME COL_UID COL_SCANS COL_PROJECT

    for col_name in $header; do
        # Trim whitespace
        col_name=$(echo "$col_name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        case "$col_name" in
            ID) COL_ID=$col_num ;;
            Label) COL_LABEL=$col_num ;;
            Subject) COL_SUBJECT=$col_num ;;
            Date) COL_DATE=$col_num ;;
            Gender) COL_GENDER=$col_num ;;
            Age) COL_AGE=$col_num ;;
            dcmAccessionNumber) COL_ACCESSION=$col_num ;;
            dcmPatientId) COL_PATIENT_ID=$col_num ;;
            dcmPatientName) COL_PATIENT_NAME=$col_num ;;
            UID) COL_UID=$col_num ;;
            Scans) COL_SCANS=$col_num ;;
            Project) COL_PROJECT=$col_num ;;
        esac
        col_num=$((col_num + 1))
    done

    # Validate required columns exist
    local missing_cols=""
    [ -z "$COL_ID" ] && missing_cols="${missing_cols}ID "
    [ -z "$COL_SUBJECT" ] && missing_cols="${missing_cols}Subject "
    [ -z "$COL_UID" ] && missing_cols="${missing_cols}UID "
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
    echo "Usage: $0 -h <XNAT_HOST> -u <USERNAME> -p <PASSWORD> -f <CSV_FILE> [-c <CONTAINER_NAME>] [-m <MAX_JOBS>] [-r <REPORT_PROJECT>] [-s]"
    echo "  -h  XNAT host (e.g., https://xnat.example.com)"
    echo "  -u  Username"
    echo "  -p  Password"
    echo "  -f  CSV file with experiment data (required)"
    echo "  -c  Container name, ID, or Docker image to run (optional - will list if not provided)"
    echo "  -m  Maximum number of jobs to submit (optional - defaults to all experiments in CSV)"
    echo "  -r  Report project ID to upload results to (optional - creates BATCH_TESTS resource)"
    echo "  -s  Skip creating sessions (assumes experiments already exist in XNAT)"
    echo ""
    echo "Required CSV columns (can be in any order, extra columns ignored):"
    echo "  ID, Subject, UID, Project"
    echo ""
    echo "Optional CSV columns:"
    echo "  Date, Label, Gender, Age, dcmAccessionNumber, dcmPatientId, dcmPatientName, Scans"
    echo ""
    echo "Example CSV (minimal):"
    echo '  ID,Subject,UID,Project'
    echo '  00001,00001,1.2.840.113619.2.1.1.1,XNAT01'
    echo '  00002,00002,1.2.840.113619.2.1.1.2,XNAT01'
    echo ""
    echo "Example CSV (with optional columns):"
    echo '  ID,Subject,UID,Project,Date,Gender'
    echo '  00001,00001,1.2.840.113619.2.1.1.1,XNAT01,2024-01-15,M'
    echo '  00002,00001,1.2.840.113619.2.1.1.2,XNAT01,2024-01-16,F'
    echo ""
    echo "Note: Columns can be in any order. Extra columns are ignored."
    echo "      Each row can specify a different project."
    exit 1
}

# Parse arguments
SKIP_CREATE=false
while getopts "h:u:p:f:c:m:r:s" opt; do
    case $opt in
        h) XNAT_HOST="$OPTARG" ;;
        u) USERNAME="$OPTARG" ;;
        p) PASSWORD="$OPTARG" ;;
        f) CSV_FILE="$OPTARG" ;;
        c) CONTAINER_NAME="$OPTARG" ;;
        m) MAX_JOBS="$OPTARG" ;;
        r) REPORT_PROJECT="$OPTARG" ;;
        s) SKIP_CREATE=true ;;
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

echo -e "${GREEN}=== XNAT CSV Batch Performance Testing ===${NC}"
echo "Host: $XNAT_HOST"
echo "User: $USERNAME"
echo "CSV File: $CSV_FILE"
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
echo "  Required columns found: ID (col $COL_ID), Subject (col $COL_SUBJECT), UID (col $COL_UID), Project (col $COL_PROJECT)"
[ -n "$COL_DATE" ] && echo "  Optional: Date (col $COL_DATE)"
[ -n "$COL_LABEL" ] && echo "  Optional: Label (col $COL_LABEL)"
[ -n "$COL_GENDER" ] && echo "  Optional: Gender (col $COL_GENDER)"
[ -n "$COL_AGE" ] && echo "  Optional: Age (col $COL_AGE)"
[ -n "$COL_ACCESSION" ] && echo "  Optional: dcmAccessionNumber (col $COL_ACCESSION)"
[ -n "$COL_PATIENT_ID" ] && echo "  Optional: dcmPatientId (col $COL_PATIENT_ID)"
[ -n "$COL_PATIENT_NAME" ] && echo "  Optional: dcmPatientName (col $COL_PATIENT_NAME)"
[ -n "$COL_SCANS" ] && echo "  Optional: Scans (col $COL_SCANS)"
echo ""

# Count experiments in CSV (exclude header)
CSV_EXPERIMENT_COUNT=$(tail -n +2 "$CSV_FILE" | wc -l | tr -d ' ')
echo -e "${GREEN}✓ Found $CSV_EXPERIMENT_COUNT experiments in CSV${NC}"
echo ""

# Extract unique projects from CSV using dynamic column index
PROJECTS=$(tail -n +2 "$CSV_FILE" | awk -F',' -v col="$COL_PROJECT" '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $col); print $col}' | sort -u)
PROJECT_COUNT=$(echo "$PROJECTS" | wc -l | tr -d ' ')

echo "Projects found in CSV:"
echo "$PROJECTS" | nl -w 3 -s '. '
echo ""

if [ "$PROJECT_COUNT" -eq 1 ]; then
    echo -e "${GREEN}All experiments use a single project${NC}"
else
    echo -e "${YELLOW}Multiple projects detected - container will be enabled for each${NC}"
fi
echo ""

# Confirm projects before proceeding
echo -e "${YELLOW}=== PROJECT CONFIRMATION ===${NC}"
echo "The script will work with the following project(s):"
echo ""

# Show experiment count per project
echo "$PROJECTS" | while read -r proj; do
    COUNT=$(tail -n +2 "$CSV_FILE" | awk -F',' -v col="$COL_PROJECT" -v project="$proj" '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $col); if ($col == project) count++} END {print count+0}')
    printf "  %-15s (%d experiments)\n" "$proj" "$COUNT"
done
echo ""
echo "Total: $CSV_EXPERIMENT_COUNT experiments across $PROJECT_COUNT project(s)"
echo ""

read -p "Continue with these projects? (y/yes): " PROJECT_CONFIRM

if [[ ! "$PROJECT_CONFIRM" =~ ^[Yy]([Ee][Ss])?$ ]]; then
    echo "Aborted. Please check your CSV file and try again."
    exit 0
fi
echo ""

# Show first few experiments
echo "First 5 experiments from CSV:"
tail -n +2 "$CSV_FILE" | head -5 | nl -w 3 -s '. '
echo ""

# Apply max jobs limit if specified
if [ -n "$MAX_JOBS" ] && [ "$MAX_JOBS" -gt 0 ] && [ "$MAX_JOBS" -lt "$CSV_EXPERIMENT_COUNT" ]; then
    EXPERIMENT_COUNT="$MAX_JOBS"
    echo -e "${YELLOW}Limiting to $MAX_JOBS experiments${NC}"
    echo ""
else
    EXPERIMENT_COUNT="$CSV_EXPERIMENT_COUNT"
fi

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

# Step 4: Enable wrapper for all projects in CSV
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

# Step 5: Create/verify experiments
if [ "$SKIP_CREATE" = false ]; then
    echo -e "${YELLOW}[5/5] Creating/verifying experiments in XNAT...${NC}"
    echo ""
    echo -e "${BLUE}Note: This will create MR sessions in XNAT if they don't exist${NC}"
    echo ""
    read -p "Continue with experiment creation? (y/yes): " CREATE_CONFIRM

    if [[ ! "$CREATE_CONFIRM" =~ ^[Yy]([Ee][Ss])?$ ]]; then
        echo "Skipping experiment creation. Use -s flag to skip this step in future."
        SKIP_CREATE=true
    else
        echo "Creating experiments..."
        echo ""

        CREATE_COUNT=0
        SKIP_COUNT=0
        ERROR_COUNT=0

        # Read CSV and create experiments
        tail -n +2 "$CSV_FILE" | head -n "$EXPERIMENT_COUNT" | while IFS= read -r row; do
            # Extract values using dynamic column indices
            subj_label=$(get_csv_value "$row" "$COL_SUBJECT")
            project=$(get_csv_value "$row" "$COL_PROJECT")
            exp_label=$(get_csv_value "$row" "$COL_ID")

            # Optional: get date if column exists
            if [ -n "$COL_DATE" ]; then
                date=$(get_csv_value "$row" "$COL_DATE")
            else
                date=$(date '+%Y-%m-%d')  # Use current date if not provided
            fi

            # Build IDs in XNAT format: {Project}_E{ID} and {Project}_S{Subject}
            EXP_ID="${project}_E${exp_label}"
            SUBJ_ID="${project}_S${subj_label}"

            # Step 1: Create/verify subject exists
            SUBJ_CHECK=$(curl_api -b "JSESSIONID=$JSESSION" "${XNAT_HOST}/data/projects/${project}/subjects/${SUBJ_ID}?format=json" 2>/dev/null)

            if ! echo "$SUBJ_CHECK" | jq -e '.items[0]' >/dev/null 2>&1; then
                # Subject doesn't exist, create it
                SUBJ_CREATE=$(curl_api -w "\nHTTP_CODE:%{http_code}" -X PUT \
                    -b "JSESSIONID=$JSESSION" \
                    -H "Content-Type: application/xml" \
                    "${XNAT_HOST}/data/projects/${project}/subjects/${SUBJ_ID}" \
                    -d "<Subject xmlns=\"http://nrg.wustl.edu/xnat\" ID=\"${SUBJ_ID}\" project=\"${project}\" label=\"${subj_label}\"/>")

                SUBJ_HTTP_CODE=$(echo "$SUBJ_CREATE" | grep "HTTP_CODE:" | sed 's/HTTP_CODE://')

                if [[ "$SUBJ_HTTP_CODE" =~ ^(200|201)$ ]]; then
                    echo -e "${BLUE}  Created subject: $SUBJ_ID (label: $subj_label)${NC}"
                else
                    echo -e "${RED}✗${NC} Failed to create subject $SUBJ_ID (HTTP $SUBJ_HTTP_CODE)"
                    ERROR_COUNT=$((ERROR_COUNT + 1))
                    continue
                fi
            fi

            # Step 2: Check if experiment already exists
            CHECK_RESULT=$(curl_api -b "JSESSIONID=$JSESSION" "${XNAT_HOST}/data/experiments/${EXP_ID}?format=json" 2>/dev/null)

            if echo "$CHECK_RESULT" | jq -e '.items[0]' >/dev/null 2>&1; then
                echo -e "${YELLOW}⚠${NC} $EXP_ID already exists, skipping creation"
                SKIP_COUNT=$((SKIP_COUNT + 1))
                continue
            fi

            # Step 3: Create experiment (MR Session) with proper subject_ID
            CREATE_XML="<MRSession xmlns=\"http://nrg.wustl.edu/xnat\" xmlns:xnat=\"http://nrg.wustl.edu/xnat\" ID=\"${EXP_ID}\" project=\"${project}\" label=\"${exp_label}\">
  <xnat:subject_ID>${SUBJ_ID}</xnat:subject_ID>
  <xnat:date>${date}</xnat:date>
</MRSession>"

            CREATE_RESULT=$(curl_api -w "\nHTTP_CODE:%{http_code}" -X PUT \
                -b "JSESSIONID=$JSESSION" \
                -H "Content-Type: application/xml" \
                "${XNAT_HOST}/data/projects/${project}/experiments/${EXP_ID}?xsiType=xnat:mrSessionData" \
                -d "$CREATE_XML")

            HTTP_CODE=$(echo "$CREATE_RESULT" | grep "HTTP_CODE:" | sed 's/HTTP_CODE://')

            if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
                echo -e "${GREEN}✓${NC} Created experiment $EXP_ID (label: $exp_label) for subject $SUBJ_ID"
                CREATE_COUNT=$((CREATE_COUNT + 1))
            else
                echo -e "${RED}✗${NC} Failed to create experiment $EXP_ID (HTTP $HTTP_CODE)"
                ERROR_COUNT=$((ERROR_COUNT + 1))
            fi
        done

        echo ""
        echo "Experiment creation complete:"
        echo "  Created: $CREATE_COUNT"
        echo "  Skipped (already exists): $SKIP_COUNT"
        echo "  Errors: $ERROR_COUNT"
        echo ""
    fi
else
    echo -e "${YELLOW}[5/5] Skipping experiment creation (-s flag)${NC}"
    echo "Assuming experiments already exist in XNAT"
    echo ""
fi

# Prepare for submission
echo -e "${YELLOW}Preparing for batch submission...${NC}"
echo ""

# Confirm batch submission
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
XNAT CSV Batch Performance Test Log
=================================================================
Test Started: $BATCH_START_TIMESTAMP
Host: $XNAT_HOST
User: $USERNAME
CSV File: $CSV_FILE
Container: $CONTAINER_NAME (Wrapper ID: $WRAPPER_ID)
Projects: $PROJECT_COUNT unique project(s)
Experiments to Process: $EXPERIMENT_COUNT
Max Jobs Limit: ${MAX_JOBS:-None}
Skip Create: $SKIP_CREATE
Site Automation Enabled: ${AUTOMATION_ENABLED_VALUE}
Automation Check Note: ${AUTOMATION_CHECK_NOTE}
=================================================================

Projects in CSV:
$(echo "$PROJECTS" | sed 's/^/  /')

=================================================================

EOF

echo "Logging to: $LOG_FILE"
echo ""

# Submit jobs - read CSV and submit for each row
JOB_NUMBER=0
tail -n +2 "$CSV_FILE" | head -n "$EXPERIMENT_COUNT" | while IFS= read -r row; do
    JOB_NUMBER=$((JOB_NUMBER + 1))

    # Extract values using dynamic column indices
    project=$(get_csv_value "$row" "$COL_PROJECT")
    exp_label=$(get_csv_value "$row" "$COL_ID")

    # Build experiment ID in XNAT format: {Project}_E{ID}
    EXP_ID="${project}_E${exp_label}"

    echo -e "${BLUE}Submitting job ${JOB_NUMBER}/${EXPERIMENT_COUNT}:${NC} $EXP_ID (label: $exp_label, project: $project)"
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

BATCH_END_TIME=$(date +%s)
BATCH_END_TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
TOTAL_DURATION=$((BATCH_END_TIME - BATCH_START_TIME))

# Count results
if [ -f "$RESULTS_FILE" ]; then
    SUCCESS_COUNT=$(grep -c "SUCCESS" "$RESULTS_FILE" 2>/dev/null || echo "0")
    FAIL_COUNT=$(grep -c "FAIL" "$RESULTS_FILE" 2>/dev/null || echo "0")
    rm "$RESULTS_FILE"
else
    SUCCESS_COUNT=0
    FAIL_COUNT=0
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
