# XNAT CSV Batch Launch - Quick Reference

## Overview
Script: `batch_test_csv.sh` - Submits XNAT container jobs from a CSV file with experiment data.

## CSV Format

### Required Columns (case-insensitive)
- `ID` - Experiment identifier (e.g., 00001)
- `Subject` - Subject identifier (e.g., 00001)
- `UID` - DICOM StudyInstanceUID (e.g., 1.2.840.113619.2.1.1.1)
- `Project` - XNAT project ID (e.g., XNAT01)

### Optional Columns
- `Date` - Session date (YYYY-MM-DD) - uses current date if not provided
- `Label`, `Gender`, `Age`, `dcmAccessionNumber`, `dcmPatientId`, `dcmPatientName`, `Scans`

### Important
- ✅ Columns can be in **any order**
- ✅ **Extra columns** are ignored
- ✅ Column names are **case-insensitive** (ID = id = Id)

## ID Generation
- Subject ID: `{Project}_S{Subject}` → `XNAT01_S00001`
- Experiment ID: `{Project}_E{ID}` → `XNAT01_E00001`

## Basic Usage

```bash
# Basic run with CSV file
./batch_test_csv.sh -h https://xnat.example.com -u admin -p password -f data.csv -c container-name

# With project confirmation and report
./batch_test_csv.sh -h https://xnat.example.com -u admin -p password -f data.csv -c container-name -r REPORTS

# Skip experiment creation (use existing)
./batch_test_csv.sh -h https://xnat.example.com -u admin -p password -f data.csv -c container-name -s

# Limit to first 10
./batch_test_csv.sh -h https://xnat.example.com -u admin -p password -f data.csv -c container-name -m 10
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
-s  Skip creating experiments (assumes they exist in XNAT)
```

## Example CSV Files

### Minimal (required only)
```csv
id,subject,uid,project
00001,00001,1.2.840.113619.2.1.1.1,XNAT01
00002,00001,1.2.840.113619.2.1.1.2,XNAT01
```

### With optional columns
```csv
ID,Subject,UID,Project,Date,Gender
00001,00001,1.2.840.113619.2.1.1.1,XNAT01,2024-01-15,M
00002,00001,1.2.840.113619.2.1.1.2,XNAT01,2024-01-16,F
```

### Multiple projects
```csv
id,subject,uid,project
00001,00001,1.2.840.113619.2.1.1.1,XNAT01
00002,00001,1.2.840.113619.2.1.1.2,XNAT01
00001,00001,1.2.840.113619.2.1.1.3,XNAT02
```

## What The Script Does

1. **Authenticates** to XNAT
2. **Parses CSV** and validates required columns
3. **Identifies unique projects** from CSV
4. **Shows project confirmation** with experiment counts per project
5. **Selects container** (interactive or via -c flag)
6. **Enables container** for ALL projects found in CSV (automatic)
7. **Creates subjects and experiments** (unless -s flag):
   - Creates subject `{Project}_S{Subject}` if doesn't exist
   - Creates experiment `{Project}_E{ID}` linked to that subject
8. **Submits container jobs** using correct project for each experiment
9. **Logs results** with performance metrics
10. **Generates HTML report** (if -r flag provided)

## Key Features

- **Multi-project support** - Automatically enables container for each unique project
- **Dynamic column parsing** - Columns can be in any order
- **Case-insensitive headers** - ID = id = Id
- **Auto subject creation** - Creates subjects before experiments
- **Project confirmation** - Shows what will be processed before starting
- **Retry logic** - Retries failed submissions with logging
- **Performance tracking** - Throughput, timing, success/fail counts
- **HTML reports** - Auto-generates and uploads to XNAT

## Example Workflow

```bash
# 1. Create CSV file
cat > my_experiments.csv << 'EOF'
id,subject,uid,project
00001,00001,1.2.840.113619.2.1.1.1,XNAT01
00002,00001,1.2.840.113619.2.1.1.2,XNAT01
EOF

# 2. Run batch submission
./batch_test_csv.sh \
  -h https://xnat.example.com \
  -u admin \
  -p password \
  -f my_experiments.csv \
  -c totalsegmentator-scan \
  -r REPORTS

# 3. Monitor workflows
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
- Check column names are: ID, Subject, UID, Project (case-insensitive)
- Ensure no extra spaces in headers
- Verify CSV has header row

### "Project does not exist"
- Script will offer to create the project
- Or create project in XNAT first

### Container not found
- Script lists available containers
- Use exact wrapper name or ID from the list

### Submissions fail
- Check automation.enabled=false (script does this automatically)
- Verify wrapper is enabled for the project (script does this automatically)
- Check logs for specific error messages

## Related Scripts

- `batch_test.sh` - Original batch test (queries XNAT for experiments)
- `check_status.sh` - Monitor workflow status
- `generate_html_report.sh` - Generate HTML reports from logs

## Example CSV Files Included

- `example_required_only.csv` - Minimal format (4 required columns)
- `example_lowercase.csv` - Lowercase column names
- `example_batch.csv` - Single project with all columns
- `example_multi_project.csv` - Multiple projects
- `example_reordered.csv` - Different column order + extras

## Quick Command Templates

```bash
# Production run
./batch_test_csv.sh -h $HOST -u $USER -p $PASS -f data.csv -c wrapper-name -r REPORTS

# Test run (first 5 only)
./batch_test_csv.sh -h $HOST -u $USER -p $PASS -f data.csv -c wrapper-name -m 5

# Use existing experiments
./batch_test_csv.sh -h $HOST -u $USER -p $PASS -f data.csv -c wrapper-name -s

# Interactive container selection
./batch_test_csv.sh -h $HOST -u $USER -p $PASS -f data.csv
```

## Repository
Location: `xnat_misc/batch-performance-testing/`
Latest: https://github.com/mrjamesdickson/xnat_misc
