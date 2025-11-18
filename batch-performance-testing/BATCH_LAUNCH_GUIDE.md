# XNAT CSV Batch Launch - Quick Reference

## Overview
Script: `batch_test_csv.sh` - Launches XNAT container jobs on existing experiments listed in a CSV file.

**Important:** This script launches containers on experiments that **already exist** in XNAT. It does NOT create experiments or subjects.

## CSV Format

### Required Columns (case-insensitive)
- `ID` - Experiment identifier
- `Project` - XNAT project ID (e.g., XNAT01)

### Important
- ✅ Columns can be in **any order**
- ✅ **Extra columns** are ignored
- ✅ Column names are **case-insensitive** (ID = id = Id)
- ✅ **Experiments must already exist in XNAT**

## ID Format

The `ID` column can contain:
- **Simple ID** (e.g., `00001`) - Formatted as `{Project}_E{ID}` → `XNAT01_E00001`
- **Full experiment ID** (e.g., `XNAT01_E00001`) - Used as-is

## Basic Usage

```bash
# Dry-run to validate CSV (recommended first step)
./batch_test_csv.sh -h https://xnat.example.com -u admin -p password -f data.csv -c container-name -d

# Basic run with CSV file
./batch_test_csv.sh -h https://xnat.example.com -u admin -p password -f data.csv -c container-name

# With HTML report upload
./batch_test_csv.sh -h https://xnat.example.com -u admin -p password -f data.csv -c container-name -r REPORTS

# Limit to first 10 experiments
./batch_test_csv.sh -h https://xnat.example.com -u admin -p password -f data.csv -c container-name -m 10

# Interactive container selection
./batch_test_csv.sh -h https://xnat.example.com -u admin -p password -f data.csv
```

## Command Options

```
-h  XNAT host (required)
-u  Username (required)
-p  Password (required)
-f  CSV file path (required)
-c  Container wrapper name/ID (optional - interactive if not provided)
-m  Maximum jobs to submit (optional - defaults to all)
-r  Report project ID for HTML report upload (optional)
-d  Dry-run mode - validate CSV without launching containers (optional)
```

## Example CSV Files

### Simple IDs (most common)
```csv
ID,Project
00001,XNAT01
00002,XNAT01
00003,XNAT01
```
Launches containers on: `XNAT01_E00001`, `XNAT01_E00002`, `XNAT01_E00003`

### Full Experiment IDs
```csv
ID,Project
XNAT01_E00001,XNAT01
XNAT01_E00002,XNAT01
XNAT02_E00001,XNAT02
```
Launches containers on: `XNAT01_E00001`, `XNAT01_E00002`, `XNAT02_E00001`

### Mixed Format
```csv
ID,Project
00001,XNAT01
XNAT01_E00002,XNAT01
```
Launches containers on: `XNAT01_E00001`, `XNAT01_E00002`

### Multiple Projects
```csv
ID,Project
00001,XNAT01
00002,XNAT01
00001,XNAT02
```
Launches containers on: `XNAT01_E00001`, `XNAT01_E00002`, `XNAT02_E00001`

## What The Script Does

1. **Authenticates** to XNAT
2. **Parses CSV** and validates required columns (ID, Project)
3. **Identifies unique projects** from CSV
4. **Shows project confirmation** with experiment counts per project
5. **Selects container** (interactive or via -c flag)
6. **Enables container** for ALL projects found in CSV (automatic)
7. **Launches container jobs** on each experiment in the CSV
8. **Logs results** with performance metrics
9. **Generates HTML report** (if -r flag provided)

## Key Features

- **Dry-run mode** - Validate CSV and preview actions without launching containers
- **Multi-project support** - Automatically enables container for each unique project
- **Dynamic column parsing** - Columns can be in any order
- **Case-insensitive headers** - ID = id = Id
- **Flexible ID format** - Accepts simple IDs or full experiment IDs
- **Project confirmation** - Shows what will be processed before starting
- **Retry logic** - Retries failed submissions with logging
- **Performance tracking** - Throughput, timing, success/fail counts
- **HTML reports** - Auto-generates and uploads to XNAT

## Dry-Run Mode

**Always test first with `-d` flag** to validate your CSV before launching containers:

```bash
./batch_test_csv.sh -h $HOST -u $USER -p $PASS -f data.csv -c wrapper-name -d
```

**What dry-run does:**
- ✅ Validates CSV format and required columns
- ✅ Shows all experiment IDs that would be launched
- ✅ Shows which projects would have wrapper enabled
- ✅ Confirms container selection
- ❌ Does NOT enable wrappers
- ❌ Does NOT launch containers
- ❌ Does NOT modify XNAT

**Dry-run output example:**
```
=== DRY RUN SUMMARY ===
Experiments to launch: 5
Container: totalsegmentator-scan (ID: 123)
Projects: 2 unique project(s)

Experiment IDs that would be launched:
  - XNAT01_E00001 (project: XNAT01)
  - XNAT01_E00002 (project: XNAT01)
  - XNAT01_E00003 (project: XNAT01)
  - XNAT02_E00001 (project: XNAT02)
  - XNAT02_E00002 (project: XNAT02)

✓ Dry-run validation complete
CSV is valid and ready for batch submission.
Run without -d flag to launch containers.
```

## Example Workflow

```bash
# 1. Create CSV file with existing experiment IDs
cat > my_experiments.csv << 'EOF'
ID,Project
00001,XNAT01
00002,XNAT01
00003,XNAT01
EOF

# 2. Validate CSV with dry-run (RECOMMENDED)
./batch_test_csv.sh \
  -h https://xnat.example.com \
  -u admin \
  -p password \
  -f my_experiments.csv \
  -c totalsegmentator-scan \
  -d

# 3. Run batch container launch (after validating)
./batch_test_csv.sh \
  -h https://xnat.example.com \
  -u admin \
  -p password \
  -f my_experiments.csv \
  -c totalsegmentator-scan \
  -r REPORTS

# 4. Monitor container workflows
./check_status.sh \
  -h https://xnat.example.com \
  -u admin \
  -p password \
  -j XNAT01 \
  -r today
```

## Project Confirmation Output

The script shows this before processing:
```
=== PROJECT CONFIRMATION ===
The script will work with the following project(s):

  XNAT01          (3 experiments)
  XNAT02          (2 experiments)

Total: 5 experiments across 2 project(s)

Continue with these projects? (y/yes):
```

## Logs and Reports

### Logs
- Saved to: `logs/YYYY-MM-DD/batch_test_csv_HHMMSS.log`
- Contains: timestamps, success/fail, workflow IDs, performance metrics

### HTML Reports (with -r flag)
- Uploaded to: `{ReportProject}/BATCH_TESTS/YYYY-MM-DD/HHMMSS/`
- Contains: visual dashboard, stats, filterable job log

## Troubleshooting

### CSV validation fails
- Check column names are: ID, Project (case-insensitive)
- Ensure no extra spaces in headers
- Verify CSV has header row

### Experiment not found
- Ensure experiments exist in XNAT before running
- Check experiment IDs match XNAT exactly
- Verify project is correct

### Container not found
- Script lists available containers
- Use exact wrapper name or ID from the list

### Submissions fail
- Check automation.enabled=false (script does this automatically)
- Verify wrapper is enabled for the project (script does this automatically)
- Verify experiments exist in XNAT
- Check logs for specific error messages

## Related Scripts

- `batch_test.sh` - Original batch test (queries XNAT for experiments)
- `check_status.sh` - Monitor workflow status
- `generate_html_report.sh` - Generate HTML reports from logs

## Example CSV Files Included

- `example_simple_ids.csv` - Simple IDs (e.g., 00001)
- `example_full_ids.csv` - Full experiment IDs (e.g., XNAT01_E00001)
- `example_multi_project.csv` - Multiple projects
- `example_mixed_format.csv` - Mix of simple and full IDs

## Quick Command Templates

```bash
# Dry-run validation (ALWAYS do this first!)
./batch_test_csv.sh -h $HOST -u $USER -p $PASS -f data.csv -c wrapper-name -d

# Production run with report
./batch_test_csv.sh -h $HOST -u $USER -p $PASS -f data.csv -c wrapper-name -r REPORTS

# Test run (first 5 experiments only)
./batch_test_csv.sh -h $HOST -u $USER -p $PASS -f data.csv -c wrapper-name -m 5

# Dry-run with limit (validate first 10 only)
./batch_test_csv.sh -h $HOST -u $USER -p $PASS -f data.csv -c wrapper-name -m 10 -d

# Interactive container selection
./batch_test_csv.sh -h $HOST -u $USER -p $PASS -f data.csv

# With environment variables
export XNAT_HOST=https://xnat.example.com
export XNAT_USER=admin
export XNAT_PASS=password
./batch_test_csv.sh -h $XNAT_HOST -u $XNAT_USER -p $XNAT_PASS -f data.csv -c wrapper-name
```

## Repository
Location: `xnat_misc/batch-performance-testing/`
Latest: https://github.com/mrjamesdickson/xnat_misc
