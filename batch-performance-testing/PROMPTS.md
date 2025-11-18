# Batch Performance Testing Scripts - Session Summary
Date: 2025-11-18
Project: xnat_misc/batch-performance-testing

## Major Changes Completed

### 1. Removed Experiment Creation (Pure Container Launcher)
- **Before:** Script created synthetic MR sessions in XNAT before launching containers
- **After:** Script only launches containers on EXISTING experiments
- Simplified CSV format: only requires `ID` and `Project` columns
- Removed: Subject, UID, Date columns (were for creating experiments)

### 2. Added Workflow Monitoring (MANDATORY DEFAULT)
- Script now WAITS for all jobs to complete before exiting
- Polls workflow status every 10 seconds
- Shows real-time: Running/Complete/Failed/Pending counts
- Reports ACTUAL completion status (not just "queued")
- Updates log with final execution results
- No way to skip - this is the entire point of the script

### 3. Added Debug Mode (-D flag)
- Shows exact API request URL, headers, data
- Shows HTTP response status and body
- Provides copy-pastable curl command for manual testing
- Helpful for diagnosing API errors (like HTTP 415)

### 4. Added Bulk Submission Mode (-b flag)
- Submits all experiments in single API call per project
- Much faster: 1 API call per project vs N calls
- Uses `/bulklaunch` endpoint
- Automatically groups experiments by project

### 5. Fixed macOS Compatibility
- Replaced `grep -P` (GNU) with `sed` (BSD compatible)
- Fixed HTML title extraction for error messages

### 6. Optimized -m Flag
- When `-m 5` specified, only reads first 5 CSV rows
- Never reads entire CSV when limit specified
- More efficient with large files (e.g., 21,793 rows)

### 7. Fixed API URL
- **Before:** `/xapi/projects/{project}/wrappers/{id}/root/xnat:imageSessionData/launch` (HTTP 415)
- **After:** `/xapi/wrappers/{id}/root/xnat:imageSessionData/launch` (HTTP 200)
- Project context inferred from session ID, not URL path

## CSV Format

### New Format (Simple)
```csv
ID,Project
00001,XNAT01
00002,XNAT01
```

### Supported ID Formats
- Simple: `00001` → formatted as `XNAT01_E00001`
- Full: `XNAT01_E00001` → used as-is

## Usage Examples

```bash
# Dry-run validation (recommended first)
./batch_test_csv.sh -h $HOST -u $USER -p $PASS -f data.csv -c wrapper -d

# Individual submission (default)
./batch_test_csv.sh -h $HOST -u $USER -p $PASS -f data.csv -c wrapper

# Bulk submission (faster for large batches)
./batch_test_csv.sh -h $HOST -u $USER -p $PASS -f data.csv -c wrapper -b

# With debug mode
./batch_test_csv.sh -h $HOST -u $USER -p $PASS -f data.csv -c wrapper -D

# Limit to first 5 experiments
./batch_test_csv.sh -h $HOST -u $USER -p $PASS -f data.csv -c wrapper -m 5

# With HTML report upload
./batch_test_csv.sh -h $HOST -u $USER -p $PASS -f data.csv -c wrapper -r REPORTS
```

## Key Features

1. **Waits for Completion (MANDATORY)** - No bullshit reports
2. **Multi-Project Support** - Automatically enables wrapper for each project
3. **Dry-Run Mode** - Validate CSV without launching
4. **Bulk Mode** - Single API call per project
5. **Debug Mode** - Show exact API requests/responses
6. **Flexible ID Format** - Simple or full experiment IDs
7. **Case-Insensitive Headers** - ID = id = Id
8. **Dynamic Column Parsing** - Columns in any order

## Files Modified

- `batch_test_csv.sh` - Main CSV batch launcher
- `batch_test.sh` - Original batch launcher (also updated for consistency)
- `BATCH_LAUNCH_GUIDE.md` - Complete documentation rewrite
- `example_*.csv` - New example files

## Testing

Tested successfully on `http://localhost` XNAT:
- CSV parsing: ✅
- Individual submission: ✅ (HTTP 200)
- Bulk submission: ✅ (HTTP 200, 0.047s for 3 experiments)
- Workflow monitoring: ✅
- Debug output: ✅
- Project-based wrapper enabling: ✅
- macOS BSD compatibility: ✅

### Bulk Submission Payload Format
Key discovery: The `session` field must be a STRING containing JSON array, not array directly.

**Correct format:**
```json
{
  "session": "[\"/archive/experiments/XNAT_E02227\",\"/archive/experiments/XNAT_E02214\"]"
}
```

**Endpoint:** `POST /xapi/projects/{project}/wrappers/{id}/root/session/bulklaunch`

See `BULK_PAYLOAD_EXAMPLES.md` for detailed examples and performance comparisons.

## Real-World Test Data Ready

Downloaded CSV from demo02: `admin_11_18_2025_19_15_12.csv`
- **Total experiments:** 1,289
- **Projects:** 12 unique projects
- **Largest project:** MedNIST with 701 experiments
- **Performance estimate:**
  - Individual mode: ~129 seconds (0.1s per call × 1,289)
  - Bulk mode: ~6 seconds (0.5s per call × 12 projects)
  - **Expected speedup:** ~21x faster

## Batch-Launch Plugin Deployment

**Status:** Deployed to localhost XNAT (`http://localhost`)
- **Plugin:** batch-launch-0.8.1-xpl.jar (144KB)
- **Location:** `/Users/james/projects/xnat_docker_testing/xnat/plugins/`
- **XNAT container:** `xnat-web` (restarted successfully)
- **Startup time:** 61 seconds
- **Verification:** Pending - need to check plugin loaded via API

**Deployment commands used:**
```bash
cd /Users/james/projects/xnat_docker_testing
curl -L -o xnat/plugins/batch-launch-0.8.1-xpl.jar \
  "https://bitbucket.org/xnatdev/batch-launch-plugin/downloads/batch-launch-0.8.1-xpl.jar"
docker-compose restart xnat-web
```

## Repository

Location: `xnat_misc/batch-performance-testing/`
GitHub: https://github.com/mrjamesdickson/xnat_misc
Branch: `main`
Latest commit: `1e11cbc Add comprehensive batch launch quick reference guide`

All changes committed and pushed.

## Current State (End of Session)

**Completed:**
1. ✅ Pure container launcher (no experiment creation)
2. ✅ Mandatory workflow monitoring (waits for completion)
3. ✅ Bulk submission mode (-b flag)
4. ✅ Debug mode (-D flag) with detailed API output
5. ✅ Optimized -m flag (only reads first N rows)
6. ✅ macOS BSD compatibility throughout
7. ✅ Comprehensive documentation (BATCH_LAUNCH_GUIDE.md, BULK_PAYLOAD_EXAMPLES.md)
8. ✅ Test scripts created (test_bulk_submission.sh, show_bulk_payload.sh)
9. ✅ Batch-launch plugin deployed to localhost

**Ready to test:**
- Real CSV with 1,289 experiments across 12 projects
- Bulk mode expected to be ~21x faster than individual mode
- Plugin verification and testing on localhost XNAT

**Next steps if continuing:**
1. Verify batch-launch plugin loaded: `curl -u admin:admin http://localhost/xapi/plugins | jq`
2. Test bulk submission with real CSV data
3. Compare performance: bulk vs individual mode
4. Document actual performance results
