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
- Workflow monitoring: ✅
- Debug output: ✅
- Project-based wrapper enabling: ✅

## Repository

Location: `xnat_misc/batch-performance-testing/`
GitHub: https://github.com/mrjamesdickson/xnat_misc
Branch: `main`
Latest commit: `27023d6 Add bulk submission mode (-b flag) to batch_test_csv.sh`

## Next Steps / Future Enhancements

- None pending - all requested features implemented
