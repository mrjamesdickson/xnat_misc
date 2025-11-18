#!/bin/bash
# Test bulk submission mode on localhost XNAT

set -e

HOST="http://localhost"
USER="admin"
PASS="admin"

echo "=== Testing Bulk Submission Mode ==="
echo ""

# Test 1: Create test CSV with multiple experiments
echo "Test 1: Creating test CSV with 3 experiments from test project..."
cat > test_bulk.csv << 'CSVEOF'
ID,Project
XNAT_E02227,test
XNAT_E02214,test
XNAT_E02237,test
CSVEOF

echo "✓ Created test_bulk.csv"
cat test_bulk.csv
echo ""

# Test 2: Dry-run with bulk mode
echo "Test 2: Dry-run with bulk mode (-d -b)..."
./batch_test_csv.sh -h $HOST -u $USER -p $PASS -f test_bulk.csv -c 15 -d -b << ANSWERS
y
ANSWERS
echo ""

# Test 3: Actual bulk submission with debug
echo "Test 3: Bulk submission with debug mode (-b -D -m 2)..."
echo "Limiting to 2 experiments for faster test"
./batch_test_csv.sh -h $HOST -u $USER -p $PASS -f test_bulk.csv -c 15 -b -D -m 2 << ANSWERS
y
y
ANSWERS
echo ""

# Test 4: Compare with individual submission
echo "Test 4: Individual submission for comparison (no -b flag, -m 1)..."
./batch_test_csv.sh -h $HOST -u $USER -p $PASS -f test_bulk.csv -c 15 -m 1 << ANSWERS
y
y
ANSWERS
echo ""

echo "=== All Tests Complete ==="
echo ""
echo "Check logs directory for detailed results"
ls -lth logs/$(date '+%Y-%m-%d')/ | head -5

# Cleanup
rm -f test_bulk.csv
