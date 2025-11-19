# Workflow Metrics Feature Summary

## What's Implemented (v1.0)

### 1. Per-Workflow Tracking During Execution
- Script now records workflow state every 10 seconds
- Saves to `*_workflow_tracking.jsonl` (JSONL format)
- Captures: workflowId, experimentId, status, launchTime, checkTime

### 2. Automated Metrics Generation
- After execution completes, generates `*_workflow_metrics.csv`
- Provides per-workflow breakdown:
  - **QueuedDuration**: Time waiting in queue (launch → running)
  - **RunningDuration**: Time actively processing (running → complete)
  - **TotalDuration**: End-to-end time (launch → final)
- Includes launch time, first seen, last update timestamps
- Shows final status for each workflow

### 3. Files Generated Per Run
```
logs/YYYY-MM-DD/
├── batch_test_csv_HHMMSS.log                     # Main log
├── batch_test_csv_HHMMSS_workflow_tracking.jsonl # Raw state data
└── batch_test_csv_HHMMSS_workflow_metrics.csv     # Calculated metrics
```

### 4. Console Output
Script displays first 10 workflows as preview table when complete:
```
=== GENERATING PER-WORKFLOW METRICS ===

✓ Per-workflow metrics saved to: logs/.../batch_test_csv_HHMMSS_workflow_metrics.csv

Sample (first 10 workflows):
WorkflowID  ExperimentID  Status    QueuedDuration  RunningDuration  TotalDuration
100         XNAT_E02227   Complete  30.0            50.0             80.0
101         XNAT_E02214   Complete  40.0            55.0             95.0
```

## Using the Metrics

### Option 1: Direct CSV Analysis
Import the CSV into:
- Excel / Google Sheets / Numbers
- Python (pandas):  `df = pd.read_csv('logs/.../batch_test_csv_*_workflow_metrics.csv')`
- R: `data <- read.csv('logs/.../batch_test_csv_*_workflow_metrics.csv')`

### Option 2: Command Line
```bash
# View as table
cat logs/*/batch_test_csv_*_workflow_metrics.csv | column -t -s,

# Calculate average queue time
tail -n +2 logs/*/batch_test_csv_*_workflow_metrics.csv | \
  awk -F',' '{sum+=$7; n++} END {print "Avg Queue Time:", sum/n, "seconds"}'

# Find slowest workflows
tail -n +2 logs/*/batch_test_csv_*_workflow_metrics.csv | \
  sort -t',' -k9 -rn | head -5
```

### Option 3: HTML Report Integration (Coming)
- HTML generator will auto-detect workflow metrics CSV
- Will include sortable table in report
- Will show timing distribution charts

## Benefits

1. **Works with Bulk Mode**: Full individual timing even with 200x faster bulk submission
2. **Automatic**: No manual tracking needed
3. **Detailed**: See exactly which experiments were slow
4. **Flexible**: Use CSV in any analysis tool
5. **Historical**: Keep metrics from all runs for comparison

## Example Use Cases

- **Identify Bottlenecks**: Find experiments that queue longer than others
- **Optimize Resources**: See if you need more compute capacity
- **Debug Issues**: Correlate slow jobs with experiment characteristics
- **Report Performance**: Share timing data with stakeholders
- **Track Improvements**: Compare metrics across code/config changes
