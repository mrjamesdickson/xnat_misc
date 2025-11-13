# XNAT Batch Performance Testing

Scripts for batch container submission and monitoring on XNAT.

## Scripts

### `batch_test.sh` - Batch Container Submission ✅
Submits container jobs in batch across multiple experiments.

**Usage:**
```bash
./batch_test.sh -h <XNAT_HOST> -u <USERNAME> -p <PASSWORD> [-c <CONTAINER_NAME>]
```

**Example:**
```bash
./batch_test.sh -h http://demo02.xnatworks.io -u admin -p admin
```

**Features:**
- Auto-selects project or lets you choose from top 10 by experiment count
- Lists available containers filtered by project (enabled/disabled)
- Auto-enables disabled containers if you select them
- Shows API call syntax before submission
- Tests with first experiment before full batch
- Tracks success/failure for each submission
- Uses correct form-encoded payload (not JSON)

**Workflow:**
1. Authenticate → Select project → Select wrapper
2. Verify wrapper enabled for project (enable if needed)
3. Retrieve experiments from project
4. Test launch on first experiment
5. Batch submit to all experiments
6. Report success/failure counts

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

## Example Workflow

```bash
# 1. Submit batch jobs
./batch_test.sh -h http://demo02.xnatworks.io -u admin -p admin

# 2. Monitor in watch mode
./check_status.sh -h http://demo02.xnatworks.io -u admin -p admin -j TOTALSEGMENTATOR -w

# 3. Check specific date range
./check_status.sh -h http://demo02.xnatworks.io -u admin -p admin -j TOTALSEGMENTATOR -r today

# 4. Check workflows
./check_workflows.sh -h http://demo02.xnatworks.io -u admin -p admin -j TOTALSEGMENTATOR
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
