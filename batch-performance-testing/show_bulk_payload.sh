#!/bin/bash
# Show bulk submission payload examples

echo "=== Bulk Submission Payload Examples ==="
echo ""

# Example 1: Simple format
echo "Example 1: Two experiments from one project"
echo "==========================================="
cat << 'JSON'
{
  "session": "[\"/archive/experiments/XNAT01_E00001\",\"/archive/experiments/XNAT01_E00002\"]"
}
JSON
echo ""

# Example 2: Larger batch
echo "Example 2: Five experiments"
echo "=============================="
cat << 'JSON'
{
  "session": "[\"/archive/experiments/XNAT01_E00001\",\"/archive/experiments/XNAT01_E00002\",\"/archive/experiments/XNAT01_E00003\",\"/archive/experiments/XNAT01_E00004\",\"/archive/experiments/XNAT01_E00005\"]"
}
JSON
echo ""

# Show how it's built in the script
echo "How the payload is built in batch_test_csv.sh:"
echo "==============================================="
cat << 'SCRIPT'
# 1. Build JSON array of experiment paths
SESSION_ARRAY=$(printf '/archive/experiments/%s\n' "${PROJECT_EXPERIMENTS[@]}" | jq -R . | jq -s .)

# Example output of SESSION_ARRAY:
#   ["/archive/experiments/XNAT01_E00001","/archive/experiments/XNAT01_E00002"]

# 2. Create final payload
BULK_PAYLOAD=$(jq -n --argjson sessions "$SESSION_ARRAY" '{"session": ($sessions | tostring)}')

# Final BULK_PAYLOAD:
#   {"session": "[\"/archive/experiments/XNAT01_E00001\",\"/archive/experiments/XNAT01_E00002\"]"}
SCRIPT
echo ""

# Actual test payload from our run
echo "Actual payload from test run (debug mode):"
echo "==========================================="
grep -A 6 "DEBUG: BULK API REQUEST" logs/2025-11-18/batch_test_csv_135900.log 2>/dev/null | tail -6
echo ""

# Show the curl command
echo "API Endpoint:"
echo "============="
echo "POST /xapi/projects/{project}/wrappers/{wrapper_id}/root/session/bulklaunch"
echo ""
echo "Headers:"
echo "  Content-Type: application/json"
echo "  X-Requested-With: XMLHttpRequest"
echo "  Cookie: JSESSIONID=..."
echo ""

# Compare to individual submission
echo "Comparison: Bulk vs Individual Submission"
echo "=========================================="
echo ""
echo "Individual (default):"
echo "  POST /xapi/wrappers/{id}/root/xnat:imageSessionData/launch"
echo "  Data: context=session&session=XNAT01_E00001"
echo "  → Makes N API calls for N experiments"
echo ""
echo "Bulk (-b flag):"
echo "  POST /xapi/projects/{project}/wrappers/{id}/root/session/bulklaunch"
echo "  Data: {\"session\": \"[...array of paths...]\"}"
echo "  → Makes 1 API call per project"
echo ""

# Performance example
echo "Performance Example:"
echo "===================="
echo "1000 experiments across 5 projects:"
echo ""
echo "Individual mode: 1000 API calls"
echo "  Avg 0.1s per call = 100 seconds total"
echo ""
echo "Bulk mode: 5 API calls (one per project)"  
echo "  Avg 0.5s per call = 2.5 seconds total"
echo ""
echo "Speed improvement: ~40x faster"
