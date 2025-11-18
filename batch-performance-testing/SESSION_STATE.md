# Current Session State
**Date:** 2025-11-18
**Project:** batch-performance-testing
**Status:** Ready for bulk submission testing

## What Was Built

A pure container launcher for XNAT that:
- Launches containers on EXISTING experiments (does NOT create experiments)
- Reads CSV with just `ID,Project` columns
- Waits for ALL jobs to complete before reporting results
- Supports bulk submission mode (1 API call per project vs N calls)

## Key Scripts

### batch_test_csv.sh
Main script for CSV-based container launching.

**Basic usage:**
```bash
./batch_test_csv.sh -h http://localhost -u admin -p admin \
  -f data.csv -c wrapper-id
```

**Flags:**
- `-b` = Bulk mode (one API call per project, much faster)
- `-d` = Dry-run (validate CSV without launching)
- `-D` = Debug mode (show API requests/responses)
- `-m N` = Process only first N experiments
- `-r PROJECT` = Upload HTML report to XNAT project

**CSV format:**
```csv
ID,Project
XNAT_E02227,test
XNAT_E02214,test
```

## Current Environment

### Localhost XNAT
- **URL:** http://localhost
- **Container:** xnat-web (in xnat_docker_testing)
- **Credentials:** admin/admin
- **Plugins dir:** `/Users/james/projects/xnat_docker_testing/xnat/plugins/`

### Batch-Launch Plugin
- **File:** batch-launch-0.8.1-xpl.jar
- **Size:** 144KB
- **Status:** Deployed to localhost, XNAT restarted
- **Verification needed:** Check if plugin loaded successfully

### Test Data Ready
- **File:** `admin_11_18_2025_19_15_12.csv`
- **Location:** `/Users/james/Downloads/` (already downloaded)
- **Experiments:** 1,289 across 12 projects
- **Largest project:** MedNIST (701 experiments)

## Performance Expected

**Individual mode (default):**
- 1,289 API calls
- ~0.1s per call = ~129 seconds total

**Bulk mode (-b flag):**
- 12 API calls (one per project)
- ~0.5s per call = ~6 seconds total
- **21x faster**

## Important Technical Details

### Bulk Submission Payload
The `session` field MUST be a STRING containing JSON array:
```json
{
  "session": "[\"/archive/experiments/XNAT_E02227\",\"/archive/experiments/XNAT_E02214\"]"
}
```

Built in script via:
```bash
SESSION_ARRAY=$(printf '/archive/experiments/%s\n' "${EXPERIMENTS[@]}" | jq -R . | jq -s .)
BULK_PAYLOAD=$(jq -n --argjson sessions "$SESSION_ARRAY" '{"session": ($sessions | tostring)}')
```

### API Endpoints

**Individual submission:**
```
POST /xapi/wrappers/{id}/root/xnat:imageSessionData/launch
Content-Type: application/x-www-form-urlencoded
Data: context=session&session={experiment_id}
```

**Bulk submission:**
```
POST /xapi/projects/{project}/wrappers/{id}/root/session/bulklaunch
Content-Type: application/json
Data: {"session": "[...]"}
```

## Next Actions

If continuing this work:

1. **Verify plugin loaded:**
   ```bash
   curl -u admin:admin http://localhost/xapi/plugins | jq '.[] | select(.name | contains("batch"))'
   ```

2. **Test bulk submission:**
   ```bash
   cd /Users/james/projects/xnat_misc/batch-performance-testing
   ./batch_test_csv.sh -h http://localhost -u admin -p admin \
     -f ~/Downloads/admin_11_18_2025_19_15_12.csv -c 15 -b -m 10
   ```

3. **Compare performance:**
   - Run with `-b` (bulk mode)
   - Run without `-b` (individual mode)
   - Document actual timings

## Documentation Files

- **BATCH_LAUNCH_GUIDE.md** - Complete usage guide
- **BULK_PAYLOAD_EXAMPLES.md** - Payload format examples
- **PROMPTS.md** - Session summary and changes
- **SESSION_STATE.md** - This file (quick reference)

## Repository Status

- **Location:** `/Users/james/projects/xnat_misc/batch-performance-testing/`
- **Branch:** main
- **Latest commit:** 1e11cbc
- **Status:** All changes committed and pushed

## Critical Notes

1. **Workflow monitoring is MANDATORY** - Script waits for jobs to complete
2. **macOS BSD compatible** - No GNU-specific commands
3. **No experiment creation** - Only launches on existing data
4. **Case-insensitive CSV headers** - ID/id/Id all work
5. **Flexible ID format** - Accepts simple (00001) or full (XNAT_E00001)
