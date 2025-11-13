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

## Scripts

### `batch_test.sh` - Batch Container Submission ✅
Submits container jobs in batch across multiple experiments.

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
- Performance metrics (throughput, avg/min/max times)
- Detailed logs saved to `logs/YYYY-MM-DD/`
- Optional workflow status monitoring
- **Auto-generates and uploads HTML report if `-r` specified**

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
6. Report success/failure counts
7. **Generate and upload HTML report (if `-r` specified)**

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
When `-r` is specified, uploads to project-level resource with date-based organization:
- Resource: `BATCH_TESTS`
- Structure: `YYYY-MM-DD/YYYYMMDD_HHMMSS_batch_test_HHMMSS.html` (report)
- Structure: `YYYY-MM-DD/YYYYMMDD_HHMMSS_batch_test_HHMMSS.log` (original log)
- Files organized in date subfolders for easy navigation
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

Reports are organized by date in the BATCH_TESTS resource:
```
BATCH_TESTS/
├── 2025-11-13/
│   ├── 20251113_140235_batch_test_140235.html
│   ├── 20251113_140235_batch_test_140235.log
│   ├── 20251113_140913_batch_test_140913.html
│   └── 20251113_140913_batch_test_140913.log
└── 2025-11-14/
    ├── 20251114_093021_batch_test_093021.html
    └── 20251114_093021_batch_test_093021.log
```

Each test run uploads both:
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
└── YYYY-MM-DD/                # Date-based subfolder
    ├── YYYYMMDD_HHMMSS_batch_test_HHMMSS.html  # HTML report
    └── YYYYMMDD_HHMMSS_batch_test_HHMMSS.log   # Raw log
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
