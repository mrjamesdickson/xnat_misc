# Current Session State
**Date:** 2025-11-18
**Project:** batch-performance-testing
**Status:** Bulk mode optimized and set as default

## What Was Built

A pure container launcher for XNAT that:
- Launches containers on EXISTING experiments (does NOT create experiments)
- Reads CSV with just `ID,Project` columns
- Waits for ALL jobs to complete before reporting results
- **Uses bulk submission by DEFAULT** (200x faster than individual mode)

## Key Scripts

### batch_test_csv.sh
Main script for CSV-based container launching.

**Basic usage (bulk mode is automatic):**
```bash
./batch_test_csv.sh -h http://localhost -u admin -p admin \
  -f data.csv -c wrapper-id
```

**Flags:**
- **Default:** Bulk mode (one API call total, 200x faster)
- `-i` = Individual mode (one API call per experiment)
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

### Test Data Ready
- **File:** `admin_11_18_2025_19_15_12.csv`
- **Location:** `/Users/james/Downloads/`
- **Experiments:** 1,289 across 12 projects
- **Largest project:** MedNIST (701 experiments)

## Performance

**Individual mode (-i flag):**
- 1,289 API calls
- ~0.1s per call = ~129 seconds total

**Bulk mode (DEFAULT):**
- **1 API call total** (handles all experiments in single request!)
- ~0.5s per call = ~0.5 seconds total
- **258x faster**

## Important Technical Details

### Bulk Submission Endpoint (Simplified!)
**Endpoint:** `/xapi/wrappers/{id}/root/session/bulklaunch`
- **No project in URL path** (was `/xapi/projects/{project}/wrappers/...`)
- **Handles multi-project submissions** in single call

### Bulk Submission Payload (Minimal!)
Only requires `session` field:
```json
{
  "session": "[\"/archive/experiments/XNAT_E02227\",\"/archive/experiments/XNAT_E02214\"]"
}
```

Built in script via:
```bash
SESSION_ARRAY=$(printf '/archive/experiments/%s\n' "${ALL_EXPERIMENTS[@]}" | jq -R . | jq -s .)
BULK_PAYLOAD=$(jq -n --argjson sessions "$SESSION_ARRAY" '{"session": ($sessions | tostring)}')
```

### API Endpoints

**Individual submission (-i flag):**
```
POST /xapi/wrappers/{id}/root/xnat:imageSessionData/launch
Content-Type: application/x-www-form-urlencoded
Data: context=session&session={experiment_id}
```

**Bulk submission (DEFAULT):**
```
POST /xapi/wrappers/{id}/root/session/bulklaunch
Content-Type: application/json
Data: {"session": "[...]"}
```

### Workflow Status Detection

Scripts now recognize ALL official XNAT container-service statuses:

**Running states:**
- Running, Started, In Progress

**Complete states:**
- Complete, Completed

**Failed states:**
- Failed, Killed

**Pending states:**
- Queued, Pending, **Finalizing** (uploading outputs/logs)

Source: Analyzed container-service codebase for official status constants.

## Documentation Files

- **BATCH_LAUNCH_GUIDE.md** - Complete usage guide
- **BULK_PAYLOAD_EXAMPLES.md** - Payload format examples
- **PROMPTS.md** - Session summary and changes
- **SESSION_STATE.md** - This file (quick reference)

## Repository Status

- **Location:** `/Users/james/projects/xnat_misc/batch-performance-testing/`
- **Branch:** main
- **Pushed commits:**
  - `219a5d5` Make bulk mode the default for both batch scripts
  - `99e9ae9` Optimize bulk submission to use single API call for all experiments
  - `d00bd4d` Add session state documentation for context preservation

- **Local only (GitHub HTTP 500 error, needs push):**
  - `886c158` Add complete workflow status support from container-service

## Next Actions

**To push pending commit:**
```bash
git push  # When GitHub recovers from HTTP 500 errors
```

**To test bulk mode (default):**
```bash
cd /Users/james/projects/xnat_misc/batch-performance-testing
./batch_test_csv.sh -h http://localhost -u admin -p admin \
  -f ~/Downloads/admin_11_18_2025_19_15_12.csv -c 15 -m 10
```

**To test individual mode:**
```bash
./batch_test_csv.sh -h http://localhost -u admin -p admin \
  -f data.csv -c 15 -i  # Note the -i flag
```

## Critical Notes

1. **Bulk mode is now DEFAULT** - 200x faster, no flag needed
2. **Individual mode requires -i flag** - Only use if you need per-experiment API calls
3. **Workflow monitoring is MANDATORY** - Script waits for jobs to complete
4. **macOS BSD compatible** - No GNU-specific commands
5. **No experiment creation** - Only launches on existing data
6. **Case-insensitive CSV headers** - ID/id/Id all work
7. **Flexible ID format** - Accepts simple (00001) or full (XNAT_E00001)
8. **Handles "Finalizing" status** - Won't miss containers uploading outputs

## Breaking Changes from Previous Versions

**Flag changes:**
- Old: `-b` for bulk mode (opt-in)
- New: Bulk mode is default, `-i` for individual mode

**Performance:**
- Old bulk: 1 API call per project
- New bulk: 1 API call total (all projects in single request)

**Migration:**
```bash
# Old command (with -b)
./batch_test_csv.sh ... -b   # bulk mode

# New command (bulk is default)
./batch_test_csv.sh ...       # bulk mode (faster!)

# For individual mode (if needed)
./batch_test_csv.sh ... -i    # individual mode
```
