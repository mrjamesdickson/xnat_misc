# Prompt History - XNAT Batch Performance Testing

**Date:** 2025-11-13
**Project:** xnat_misc/batch-performance-testing

## Objective
Create scripts for batch container submission and workflow monitoring on XNAT to test performance at scale.

## Key Requirements
1. Batch submit container jobs across multiple experiments
2. Monitor workflow/container status with real-time updates
3. Follow XNAT Container Service API best practices
4. Support date range filtering and watch mode
5. Query workflow table (authoritative source for job status)

## Implementation Journey

### Initial Approach
- Started with container launch using JSON payload
- Used project-scoped endpoints
- Checked container API for status

### Key Learnings from xnat_pipeline_client
1. **Launch payload must be form-encoded**, not JSON:
   - ✅ `context=session&session=<EXPERIMENT_ID>`
   - ❌ `{"root-element-name": "<EXPERIMENT_ID>"}`

2. **Endpoint structure**:
   - `/xapi/wrappers/{id}/root/{rootElement}/launch`
   - Not project-scoped (works but unnecessary)

3. **Workflow table is authoritative**:
   - Always check workflows for job status
   - Container API may lag or not show all job types
   - Some wrappers (debug-session) create workflows without containers

### Workflow API Discovery
- Initial attempts used GET `/data/projects/{project}/workflows?format=json` - timed out
- Correct approach from browser inspection:
  - POST to `/xapi/workflows`
  - JSON payload: `{"page":1,"id":"PROJECT","data_type":"xnat:projectData","sortable":true,"days":N}`
  - Returns array of workflow objects
  - Server-side filtering by days parameter

### Final Architecture

**batch_test.sh:**
1. Authenticate → get JSESSION
2. Show top 10 projects by experiment count
3. List containers (enabled/disabled for selected project)
4. Auto-enable wrapper if disabled
5. Test first experiment, show response
6. Batch submit with form-encoded data
7. Track success/failure

**check_status.sh:**
1. POST to `/xapi/workflows` with project filter and days range
2. Parse workflow array (not ResultSet)
3. Extract fields: status, name, label, launchTime, percentComplete
4. Format Unix timestamps (milliseconds → date)
5. Display summary, status breakdown, recent 20 workflows
6. Support watch mode (-w flag)

## API Endpoints Used

### Container Launch
```bash
POST /xapi/wrappers/{wrapper_id}/root/xnat:imageSessionData/launch
Content-Type: application/x-www-form-urlencoded

context=session&session=<EXPERIMENT_ID>
```

### Workflow Query
```bash
POST /xapi/workflows
Content-Type: application/json
X-Requested-With: XMLHttpRequest

{
  "page": 1,
  "id": "PROJECT_ID",
  "data_type": "xnat:projectData",
  "sortable": true,
  "days": 7
}
```

### Wrapper Discovery
```bash
GET /xapi/commands
Accept: application/json
```

### Wrapper Enablement Check
```bash
GET /xapi/projects/{project}/wrappers/{wrapper_id}/enabled

Returns: {"enabled-for-site":true,"enabled-for-project":true,"project":"PROJECT"}
```

### Wrapper Enable/Disable
```bash
PUT /xapi/projects/{project}/wrappers/{wrapper_id}/enabled
Content-Type: text/plain

true
```

## Test Results

**Test Run:** 2025-11-13 11:43 AM
**Project:** TOTALSEGMENTATOR
**Wrapper:** debug-session (ID 70)
**Experiments:** 51
**Success Rate:** 51/51 (100%)
**Status:** All Complete, 100% progress

## Files Created

1. **batch_test.sh** - Main batch submission script
2. **check_status.sh** - Workflow monitoring (updated to use workflows API)
3. **check_workflows.sh** - Standalone workflow checker
4. **check_workflows_simple.sh** - Simplified workflow viewer
5. **debug_container.sh** - Container data structure inspector
6. **README.md** - User documentation
7. **BATCH_TEST_SUCCESS.md** - Test verification results
8. **PROMPTS.md** - This file

## Key Code Patterns

### Form-Encoded Launch
```bash
curl -X POST \
  -b "JSESSIONID=$JSESSION" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  "${XNAT_HOST}/xapi/wrappers/${WRAPPER_ID}/root/xnat:imageSessionData/launch" \
  -d "context=session&session=${EXP_ID}"
```

### Workflow Query
```bash
WORKFLOW_QUERY="{\"page\":1,\"id\":\"$PROJECT_ID\",\"data_type\":\"xnat:projectData\",\"sortable\":true,\"days\":$DAYS}"

WORKFLOWS=$(curl -s -X POST \
  -b "JSESSIONID=$JSESSION" \
  -H "Content-Type: application/json" \
  -H "X-Requested-With: XMLHttpRequest" \
  "${XNAT_HOST}/xapi/workflows" \
  -d "$WORKFLOW_QUERY")
```

### Unix Timestamp Conversion
```bash
if [[ "$launch_time" =~ ^[0-9]+$ ]]; then
    launch_sec=$((launch_time / 1000))
    launch_fmt=$(date -r "$launch_sec" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || \
                 date -d "@$launch_sec" '+%Y-%m-%d %H:%M:%S' 2>/dev/null)
fi
```

## Lessons Learned

1. **Always check browser network traffic** for correct API usage
2. **Workflow table is the source of truth** for job status
3. **Form encoding vs JSON matters** - XNAT launch expects form data
4. **Test wrappers (debug-session) don't create containers** - only workflows
5. **Server-side filtering is faster** than client-side (use `days` parameter)
6. **Unix timestamps in milliseconds** need division by 1000 for date conversion
7. **Session persistence** - JSESSIONID cookie must be maintained across requests

## Next Steps / Potential Enhancements

- [ ] Add parallel submission with concurrency control
- [ ] Export results to CSV/JSON
- [ ] Add workflow retry logic for failed jobs
- [ ] Support bulk operations across multiple projects
- [ ] Add performance metrics (jobs/sec, avg completion time)
- [ ] Integration with xnat_pipeline_client Python library
- [ ] Support for scan-level and assessor-level containers
- [ ] Email notifications on batch completion

## References

- xnat_pipeline_client: ~/projects/xnat_pipeline_client
- XNAT proxy site plugin: ~/projects/xnat_proxy_site_plugin
- XNAT Container Service docs: Container launch uses form data, not JSON
