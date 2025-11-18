# Bulk Submission Payload Examples

## Actual Payload from Test Run

### Request
```
POST http://localhost/xapi/projects/test/wrappers/15/root/session/bulklaunch
Content-Type: application/json
X-Requested-With: XMLHttpRequest
Cookie: JSESSIONID=...
```

### Payload (3 experiments)
```json
{
  "session": "[\"/archive/experiments/XNAT_E02227\",\"/archive/experiments/XNAT_E02214\",\"/archive/experiments/XNAT_E02237\"]"
}
```

### Response
```
HTTP 200 OK
Duration: 0.047 seconds
Result: ✓ Successfully submitted 3 experiments
```

## Key Points

1. **The `session` field is a STRING containing a JSON array**
   - Not a JSON array directly
   - It's `"[...]"` not `[...]`
   - This is the XNAT API requirement

2. **Format**: `/archive/experiments/{experiment_id}`
   - Full path required
   - Must start with `/archive/experiments/`

3. **One call per project**
   - All experiments in CSV for project "test" submitted in single call
   - If CSV had multiple projects, separate bulk call per project

## More Examples

### Two Experiments
```json
{
  "session": "[\"/archive/experiments/XNAT01_E00001\",\"/archive/experiments/XNAT01_E00002\"]"
}
```

### Ten Experiments
```json
{
  "session": "[\"/archive/experiments/XNAT01_E00001\",\"/archive/experiments/XNAT01_E00002\",\"/archive/experiments/XNAT01_E00003\",\"/archive/experiments/XNAT01_E00004\",\"/archive/experiments/XNAT01_E00005\",\"/archive/experiments/XNAT01_E00006\",\"/archive/experiments/XNAT01_E00007\",\"/archive/experiments/XNAT01_E00008\",\"/archive/experiments/XNAT01_E00009\",\"/archive/experiments/XNAT01_E00010\"]"
}
```

## How It's Built (Code Snippet)

```bash
# 1. Collect experiment IDs into array
PROJECT_EXPERIMENTS=("XNAT_E02227" "XNAT_E02214" "XNAT_E02237")

# 2. Build JSON array of paths
SESSION_ARRAY=$(printf '/archive/experiments/%s\n' "${PROJECT_EXPERIMENTS[@]}" | jq -R . | jq -s .)
# Result: ["/archive/experiments/XNAT_E02227","/archive/experiments/XNAT_E02214","/archive/experiments/XNAT_E02237"]

# 3. Convert to string and wrap in {"session": ...}
BULK_PAYLOAD=$(jq -n --argjson sessions "$SESSION_ARRAY" '{"session": ($sessions | tostring)}')
# Result: {"session": "[...]"}
```

## Testing Bulk Payload

```bash
# Show debug output including payload
./batch_test_csv.sh -h $HOST -u $USER -p $PASS \
  -f data.csv -c wrapper-id -b -D -m 5

# Output will show:
# === DEBUG: BULK API REQUEST ===
# URL: ...
# Method: POST
# Payload:
# {
#   "session": "[...]"
# }
```

## Comparison

### Individual Mode (default)
```bash
# For each experiment:
POST /xapi/wrappers/15/root/xnat:imageSessionData/launch
Content-Type: application/x-www-form-urlencoded
Data: context=session&session=XNAT_E02227

# Result: N API calls for N experiments
```

### Bulk Mode (-b flag)
```bash
# Once per project:
POST /xapi/projects/test/wrappers/15/root/session/bulklaunch
Content-Type: application/json
Data: {"session": "[...all experiments...]"}

# Result: 1 API call per project
```

## Performance Impact

**1000 experiments across 5 projects:**

- **Individual:** 1000 API calls @ 0.1s each = 100 seconds
- **Bulk:** 5 API calls @ 0.5s each = 2.5 seconds
- **Speedup:** ~40x faster

**Real test results:**
- 3 experiments
- Bulk submission: 0.047 seconds
- HTTP 200 OK
- Success rate: 100%
