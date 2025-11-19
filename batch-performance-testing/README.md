# XNAT Batch Performance Testing

Tools for testing XNAT container batch submission performance and monitoring workflow status.

## Quick Start

### Basic batch test:
```bash
./batch_test.sh -h https://xnat.example.com -u admin -p password
```

### With HTML report upload to XNAT project:
```bash
./batch_test.sh -h https://xnat.example.com -u admin -p password -r REPORTS
```

## Development

### Testing Requirements (CRITICAL)

**ALL code changes MUST pass tests before pushing:**

1. **Run the test suite after EVERY code change:**
   ```bash
   ./test_report_generation.sh
   ```

2. **ALL tests must pass (100%)** before committing/pushing code
3. **NEVER push code with failing tests**
4. **NEVER remove or skip tests to make them pass** - fix the code or fix the tests

The test suite validates:
- File generation (HTML, JSON, CSV, logs)
- JSON structure and validity
- CSV format and data integrity
- HTML structure and data loading
- Data consistency across all files

**Before every commit:**
```bash
# 1. Make your changes
# 2. Run tests
./test_report_generation.sh

# 3. Verify all tests pass
# 4. Only then commit and push
git add .
git commit -m "Your changes"
git push
```

## Scripts

### `batch_test.sh` - Batch Container Submission ✅
Submits container jobs in batch across multiple experiments.

### `batch_test_csv.sh` - CSV-Based Batch Submission ✅
Submits container jobs based on experiment data from a CSV file. Can create experiments in XNAT or use existing ones.

**Usage:**
```bash
./batch_test.sh -h <XNAT_HOST> -u <USERNAME> -p <PASSWORD> [-j <PROJECT_ID>] [-c <CONTAINER_NAME>] [-m <MAX_JOBS>] [-r <REPORT_PROJECT>]
```

**Example:**
```bash
# Interactive project selection
./batch_test.sh -h https://demo02.xnat.org -u admin -p password -m 10 -r RADVAL

# Skip to specific project
./batch_test.sh -h https://demo02.xnat.org -u admin -p password -j test2 -c debug-session -m 10
```

**Features:**
- Auto-selects project or lets you choose from top 10 by experiment count
- Lists available containers filtered by project (enabled/disabled)
- Auto-enables disabled containers if you select them
- Shows API call syntax before submission
- Tests with first experiment before full batch
- Tracks success/failure for each submission
- Retries job submissions (e.g., HTTP 503/service errors) with logging before giving up
- Automatically forces `automation.enabled=false` (via `/xapi/siteConfig`) if the site is misconfigured
- **Monitors job execution until completion** (checks every 10 seconds)
- Shows real-time status: Running, Complete, Failed, Pending counts
- Performance metrics (throughput, avg/min/max times, total runtime)
- Detailed logs saved to `logs/YYYY-MM-DD/`
- **Auto-generates and uploads HTML report if `-r` specified**
- Verifies the site-level `automation.enabled` flag is `false` before batch runs

**Options:**
- `-h` XNAT host (required)
- `-u` Username (required)
- `-p` Password (required)
- `-j` Project ID to test (optional - shows interactive selection if not provided)
- `-c` Container wrapper name/ID (optional - interactive if not provided)
- `-m` Maximum jobs to submit (optional - defaults to all experiments)
- `-r` Report project ID to upload results to (optional - creates BATCH_TESTS resource)

**Workflow:**
1. Authenticate → Select project → Select wrapper
2. Verify wrapper enabled for project (enable if needed)
3. Retrieve experiments from project
4. Test launch on first experiment
5. Batch submit to all experiments
6. **Monitor job execution until completion** (10s polling)
7. Report final status with completion counts
8. **Generate and upload HTML report (if `-r` specified)**

### `batch_test_csv.sh` - CSV-Based Batch Submission ✅
Submits container jobs based on experiment metadata from a CSV file.

**Usage:**
```bash
./batch_test_csv.sh -h <XNAT_HOST> -u <USERNAME> -p <PASSWORD> -f <CSV_FILE> [-c <CONTAINER_NAME>] [-m <MAX_JOBS>] [-r <REPORT_PROJECT>] [-t <CHECK_INTERVAL>] [-T <STUCK_TIMEOUT>] [-i] [-d] [-D] [-v]
```

**Options:**
- `-h` - XNAT host URL (required)
- `-u` - Username (required)
- `-p` - Password (required)
- `-f` - CSV file with experiment IDs (required)
- `-c` - Container name, ID, or Docker image to run (optional)
- `-m` - Maximum number of jobs to submit (optional - defaults to all experiments)
- `-r` - Report project ID to upload results to (optional - creates BATCH_TESTS resource)
- `-t` - Workflow check interval (optional - defaults to 10s, supports: 30s, 10m, 1h)
- `-T` - Stuck timeout - exit if no state changes detected (optional - defaults to 10m)
- `-i` - Use individual mode (one API call per experiment) - default is bulk mode (200x faster)
- `-d` - Dry-run mode - validate CSV without launching containers
- `-D` - Debug mode - show detailed API requests and responses
- `-v` - Verbose mode - show individual workflow details during monitoring

**Example:**
```bash
# Basic usage with default settings
./batch_test_csv.sh -h https://demo02.xnat.org -u admin -p password -f example_batch.csv -c totalsegmentator-scan

# Limit to first 10 experiments with custom monitoring intervals
./batch_test_csv.sh -h https://demo02.xnat.org -u admin -p password -f example_batch.csv -m 10 -t 30s -T 5m

# With report generation and verbose mode
./batch_test_csv.sh -h https://demo02.xnat.org -u admin -p password -f example_batch.csv -r BATCH_TESTS -v

# Dry-run to validate CSV without launching jobs
./batch_test_csv.sh -h https://demo02.xnat.org -u admin -p password -f example_batch.csv -d
```

**CSV Format:**
The CSV file requires these columns (case-sensitive, but order doesn't matter):

**Required columns:**
- `ID` - Experiment identifier (e.g., 00001) → generates experiment ID: `{Project}_E{ID}`
- `Subject` - Subject number/label (e.g., 00001) → generates subject ID: `{Project}_S{Subject}`
- `UID` - DICOM StudyInstanceUID (e.g., 1.2.840.113619.2.1.1.1)
- `Project` - XNAT project ID (e.g., XNAT01)

**Optional columns:**
- `Date` - Session date (YYYY-MM-DD format) - uses current date if not provided
- `Label` - Alternative experiment label
- `Gender` - Patient gender (M/F)
- `Age` - Patient age
- `dcmAccessionNumber` - DICOM accession number
- `dcmPatientId` - DICOM patient ID
- `dcmPatientName` - DICOM patient name (use ^ separator)
- `Scans` - Number of scans or comma-separated scan IDs

**ID Generation:**
The script automatically creates XNAT IDs in standard format:
- Subject ID: `{Project}_S{Subject}` (e.g., `XNAT01_S00001`)
- Experiment ID: `{Project}_E{ID}` (e.g., `XNAT01_E00001`)
- Subjects are created automatically if they don't exist

**Examples:**

Minimal CSV (required columns only):
```
CSV Row:
  ID: 00001, Subject: 00001, UID: 1.2.840.113619.2.1.1.1, Project: XNAT01
  ID: 00002, Subject: 00001, UID: 1.2.840.113619.2.1.1.2, Project: XNAT01

Generated:
  Subject ID:    XNAT01_S00001
  Experiment IDs: XNAT01_E00001, XNAT01_E00002
```

With optional columns:
```
CSV Row:
  ID: 00001, Subject: 00001, UID: 1.2.840.113619.2.1.1.1, Project: XNAT01, Date: 2024-01-15

Generated:
  Subject ID:    XNAT01_S00001
  Experiment ID: XNAT01_E00001 (with date: 2024-01-15)
```

**Important:**
- ✅ Columns can be in **any order**
- ✅ **Extra columns** are ignored
- ✅ Column names are **case-insensitive** (ID, id, Id all work)

**Example CSV (minimal - required only):**
```csv
ID,Subject,UID,Project
00001,00001,1.2.840.113619.2.1.1.1,XNAT01
00002,00001,1.2.840.113619.2.1.1.2,XNAT01
```
This creates: XNAT01_S00001, XNAT01_E00001, XNAT01_E00002

**Example CSV (with optional columns):**
```csv
ID,Subject,UID,Project,Date,Gender,Age
00001,00001,1.2.840.113619.2.1.1.1,XNAT01,2024-01-15,M,45
00002,00001,1.2.840.113619.2.1.1.2,XNAT01,2024-01-16,F,38
```
This creates: XNAT01_S00001, XNAT01_E00001, XNAT01_E00002 (with dates)

**Example CSV Files:**
- `example_required_only.csv` - **Required columns only** (ID, Subject, UID, Project) - recommended starting point
- `example_batch.csv` - Single project with all columns
- `example_multi_project.csv` - Multiple projects example
- `example_reordered.csv` - Different column order + extra columns (demonstrates flexibility)

**Options:**
- `-h` XNAT host (required)
- `-u` Username (required)
- `-p` Password (required)
- `-f` CSV file path (required)
- `-c` Container wrapper name/ID (optional - interactive if not provided)
- `-m` Maximum jobs to submit (optional - defaults to all experiments in CSV)
- `-r` Report project ID to upload results to (optional)
- `-s` Skip creating experiments (assumes they already exist in XNAT)

**Features:**
- Reads experiment metadata from CSV file
- Creates MR sessions in XNAT if they don't exist (unless `-s` specified)
- **Handles multiple projects in one CSV** - automatically enables container for each unique project
- Auto-enables disabled containers on a per-project basis
- Submits jobs using the correct project context for each experiment
- Tracks success/failure for each submission
- Retries failed submissions with logging
- Performance metrics (throughput, avg/min/max times)
- Detailed logs saved to `logs/YYYY-MM-DD/`
- Auto-generates and uploads HTML report if `-r` specified

**Workflow:**
1. Authenticate → Parse CSV file
2. Identify all unique projects from CSV
3. Select wrapper
4. **Enable wrapper for ALL projects** found in CSV (automatic)
5. Create subjects and experiments in XNAT (unless `-s` flag set):
   - For each row: creates subject `{Project}_S{Subject}` if it doesn't exist (e.g., XNAT01_S00001)
   - Then creates experiment `{Project}_E{Label}` linked to that subject (e.g., XNAT01_E00001)
6. Submit container jobs (using correct project for each experiment)
7. Report final status with performance metrics
8. Generate and upload HTML report (if `-r` specified)

**Use Cases:**
- Bulk importing and processing external imaging data
- Reprocessing experiments based on a predefined list
- Testing with synthetic/example data
- Batch processing across multiple projects

### `check_status.sh` - Workflow Status Monitor ✅
Monitors workflow job status for a project (queries XNAT workflow table).

**Usage:**
```bash
# One-time check
./check_status.sh -h <XNAT_HOST> -u <USERNAME> -p <PASSWORD> -j <PROJECT_ID> [-r <RANGE>]

# Watch mode (refreshes every 10s)
./check_status.sh -h <XNAT_HOST> -u <USERNAME> -p <PASSWORD> -j <PROJECT_ID> -w
```

**Example:**
```bash
# Check today's workflows
./check_status.sh -h http://demo02.xnatworks.io -u admin -p admin -j TOTALSEGMENTATOR -r today

# Monitor in watch mode
./check_status.sh -h http://demo02.xnatworks.io -u admin -p admin -j TOTALSEGMENTATOR -w
```

**Date Ranges:**
- `today` (default) - Workflows from last 24 hours
- `week` - Last 7 days
- `month` - Last 30 days
- `all` - Last 365 days

**Features:**
- Queries XNAT workflow table (authoritative source)
- Shows wrapper names and experiment labels
- Color-coded status (green=complete, red=failed, yellow=running)
- Displays launch times and progress percentage
- Status summary and breakdown by pipeline
- Sorted by most recent first
- Watch mode for real-time monitoring

### `generate_html_report.sh` - HTML Report Generator ✅
Converts batch test logs to interactive HTML reports and uploads to XNAT.

**Usage:**
```bash
# Generate single report
./generate_html_report.sh -l logs/2025-01-13/batch_test_143022.log

# Generate and upload to XNAT
./generate_html_report.sh -l <LOG_FILE> -h <HOST> -u <USER> -p <PASS> -r <PROJECT>

# Generate reports for all logs
./generate_html_report.sh -a
```

**Options:**
- `-l` Log file to convert (optional - interactive if not provided)
- `-o` Output HTML file (optional - defaults to `<log_name>.html`)
- `-a` Generate reports for all logs (creates `reports/` directory + index.html)
- `-h` XNAT host (required for upload)
- `-u` Username (required for upload)
- `-p` Password (required for upload)
- `-r` Report project ID (uploads to project-level `BATCH_TESTS` resource)

**HTML Report Features:**
- 📊 Visual dashboard with statistics cards
- 📈 Animated progress bars showing success/fail rates
- 🎨 Color-coded metrics (success=green, fail=red, performance=gradient)
- 🔍 Filterable job log (all/success/fail)
- 📱 Responsive design
- 🖨️ Print-friendly CSS
- 📑 Auto-generated index.html for multiple reports

**Upload to XNAT:**
When `-r` is specified, uploads to project-level resource with run-specific organization:
- Resource: `BATCH_TESTS`
- Structure: `YYYY-MM-DD/HHMMSS/batch_test_HHMMSS.html` (report)
- Structure: `YYYY-MM-DD/HHMMSS/batch_test_HHMMSS.log` (original log)
- Each run gets its own subfolder (date/time)
- Easy to find specific test runs
- Provides direct link to view in XNAT

### `check_workflows.sh` - Workflow Monitor
Checks XNAT workflow table for recent jobs.

**Usage:**
```bash
./check_workflows.sh -h <XNAT_HOST> -u <USERNAME> -p <PASSWORD> [-j <PROJECT_ID>] [-n <COUNT>]
```

## Important Notes

### Test vs Production Wrappers

Some wrappers like `debug-session` (ID 70) are **test/mock wrappers** that:
- ✅ Accept launch API calls successfully
- ✅ Create workflow table entries
- ❌ Do NOT create actual Docker container jobs
- ❌ Do NOT appear in container status monitoring

**Use these wrappers for production workloads:**
- `totalsegmentator-scan` (ID 1) - Operates on scans
- `dcm2bids-session` (ID 11) - Operates on sessions
- `dcm2niix-scan` (ID 13) - Operates on scans

### Container Contexts

Wrappers operate on specific XNAT data types:
- `xnat:imageSessionData` - Experiment/session level (e.g., dcm2bids-session)
- `xnat:imageScanData` - Scan level (e.g., totalsegmentator-scan)
- `xnat:projectData` - Project level
- `xnat:subjectData` - Subject level

Make sure the wrapper context matches your data!

## Report Project Setup

Create a dedicated project for batch test reports:

1. Create project in XNAT (e.g., `REPORTS`, `RADVAL`)
2. Set appropriate permissions
3. Use with `-r` flag in batch_test.sh or generate_html_report.sh

The `BATCH_TESTS` resource will be created automatically on first upload.

### Resource Structure

Reports are organized by date and time in the BATCH_TESTS resource:
```
BATCH_TESTS/
├── 2025-11-13/
│   ├── 140235/
│   │   ├── batch_test_140235.html
│   │   └── batch_test_140235.log
│   ├── 140913/
│   │   ├── batch_test_140913.html
│   │   └── batch_test_140913.log
│   └── 154425/
│       ├── batch_test_154425.html
│       └── batch_test_154425.log
└── 2025-11-14/
    └── 093021/
        ├── batch_test_093021.html
        └── batch_test_093021.log
```

Each test run gets its own subfolder with:
- **HTML report** - Interactive visual dashboard
- **Text log** - Original raw log file

## Example Workflows

### Complete workflow with report upload:
```bash
# 1. Run batch test with report upload
./batch_test.sh -h https://demo02.xnat.org -u admin -p password -r RADVAL -m 10

# (Auto-generates HTML report and uploads to RADVAL/BATCH_TESTS)

# 2. Monitor workflows
./check_status.sh -h https://demo02.xnat.org -u admin -p password -j RADVAL -r today
```

### CSV-based batch submission workflow:
```bash
# 1. Create CSV file with experiment data
cat > my_experiments.csv <<EOF
Label,Subject,Date,Gender,Age,dcmAccessionNumber,dcmPatientId,dcmPatientName,UID,Scans,Project
EXP001,SUBJ001,2024-01-15,M,45,ACC001,PT001,Patient^One,1.2.840.113619.2.1.1.1,3,MyProject
EXP002,SUBJ002,2024-01-16,F,38,ACC002,PT002,Patient^Two,1.2.840.113619.2.1.1.2,5,MyProject
EOF

# 2. Run CSV batch test (creates experiments and submits jobs)
./batch_test_csv.sh -h https://demo02.xnat.org -u admin -p password -f my_experiments.csv -c totalsegmentator-scan -r RADVAL

# 3. Monitor workflows
./check_status.sh -h https://demo02.xnat.org -u admin -p password -j MyProject -r today
```

### Using existing experiments from CSV:
```bash
# If experiments already exist, use -s flag to skip creation
./batch_test_csv.sh -h https://demo02.xnat.org -u admin -p password -f my_experiments.csv -c dcm2niix-scan -s
```

### Multi-project CSV workflow:
```bash
# Use example multi-project CSV (experiments span ProjectA, ProjectB, ProjectC)
# The script will automatically enable the container for all 3 projects
./batch_test_csv.sh -h https://demo02.xnat.org -u admin -p password -f example_multi_project.csv -c totalsegmentator-scan

# Output will show:
# - Projects found: ProjectA, ProjectB, ProjectC
# - Container enabled for each project
# - Jobs submitted with correct project context
```

### Generate report from existing log:
```bash
# Generate and upload report
./generate_html_report.sh \
  -l logs/2025-01-13/batch_test_143022.log \
  -h https://demo02.xnat.org \
  -u admin \
  -p password \
  -r RADVAL
```

### Generate reports for all logs:
```bash
# Creates reports/ directory with index.html
./generate_html_report.sh -a
```

## Directory Structure

### Local Directory
```
batch-performance-testing/
├── batch_test.sh              # Main batch testing script
├── generate_html_report.sh    # HTML report generator
├── check_status.sh            # Workflow status monitor
├── logs/                      # Test logs (by date)
│   └── YYYY-MM-DD/
│       └── batch_test_HHMMSS.log
└── reports/                   # HTML reports (when using -a)
    ├── index.html
    └── batch_test_HHMMSS.html
```

### XNAT Resource Structure (when uploading with -r)
```
XNAT Project > Resources > BATCH_TESTS/
└── YYYY-MM-DD/                          # Date folder
    └── HHMMSS/                          # Run-specific folder (time)
        ├── batch_test_HHMMSS.html       # HTML report
        └── batch_test_HHMMSS.log        # Raw log
```

## API Implementation

The scripts follow XNAT Container Service API best practices based on `xnat_pipeline_client`:

**Container Launch:**
- Uses form-encoded data: `context=session&session=<ID>`
- Endpoint: `/xapi/wrappers/{id}/root/{rootElement}/launch`
- Returns workflow ID in response

**Container Status:**
- Endpoint: `/xapi/projects/{project}/containers`
- Sorted by `status-time` descending
- Filters by date range client-side

**Wrapper Discovery:**
- Endpoint: `/xapi/commands`
- Extracts wrappers from command objects
- Checks project-specific enablement

## Troubleshooting

**"Workflow ID: To be assigned"**
- Normal for test wrappers like `debug-session`
- Real wrappers will show actual workflow/container IDs

**No containers showing with `-r today`**
- Containers may be from earlier dates
- Try `-r all` to see all containers
- Check if wrapper is a test wrapper

**Container not enabled for project**
- Script will offer to enable it automatically
- Requires admin permissions

**Authentication failures**
- Check username/password
- Ensure user has access to the project
- Admin privileges may be required for some operations
