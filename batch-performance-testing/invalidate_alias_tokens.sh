#!/usr/bin/env bash

# Script to invalidate/delete all alias tokens for an XNAT user
# Usage: ./invalidate_alias_tokens.sh [OPTIONS] <XNAT_URL> <TARGET_USERNAME> <ADMIN_USER> [ADMIN_PASSWORD]

set -e

# Parse options
DRY_RUN=false
POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS] <XNAT_URL> <TARGET_USERNAME> <ADMIN_USER> [ADMIN_PASSWORD]"
            echo ""
            echo "Options:"
            echo "  -n, --dry-run    Show what would be deleted without actually deleting"
            echo "  -h, --help       Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 --dry-run http://localhost testuser admin admin"
            echo "  $0 http://localhost testuser admin admin"
            echo "  $0 https://xnat.example.com testuser admin"
            echo ""
            echo "If ADMIN_PASSWORD is not provided, you will be prompted for it."
            exit 0
            ;;
        *)
            POSITIONAL_ARGS+=("$1")
            shift
            ;;
    esac
done

# Restore positional parameters
set -- "${POSITIONAL_ARGS[@]}"

if [ "$#" -lt 3 ]; then
    echo "Usage: $0 [OPTIONS] <XNAT_URL> <TARGET_USERNAME> <ADMIN_USER> [ADMIN_PASSWORD]"
    echo "Use --help for more information."
    exit 1
fi

XNAT_URL="${1%/}"  # Remove trailing slash if present
TARGET_USER="$2"
ADMIN_USER="$3"
ADMIN_PASSWORD="$4"

# Prompt for password if not provided
if [ -z "$ADMIN_PASSWORD" ]; then
    read -sp "Enter password for $ADMIN_USER: " ADMIN_PASSWORD
    echo ""
fi

# Create temporary cookie jar
COOKIE_JAR=$(mktemp)
trap "rm -f $COOKIE_JAR" EXIT

# Establish session by fetching tokens (first authenticated request with -u to create session)
echo "Establishing session as $ADMIN_USER..."
echo "Fetching alias tokens for user: $TARGET_USER"

# Get all alias tokens for the user (this creates the session and saves cookie)
TOKENS=$(curl -s -c "$COOKIE_JAR" -u "$ADMIN_USER:$ADMIN_PASSWORD" \
    -H "Accept: application/json" \
    "$XNAT_URL/data/services/tokens/show")

# Check if request was successful
if [ $? -ne 0 ]; then
    echo "Error: Failed to fetch alias tokens"
    exit 1
fi

# Filter tokens for the target user
TOKENS=$(echo "$TOKENS" | jq --arg user "$TARGET_USER" '[.[] | select(.xdatUserId == $user)]')

# Check if response contains tokens
TOKEN_COUNT=$(echo "$TOKENS" | jq '. | length' 2>/dev/null || echo "0")

if [ "$TOKEN_COUNT" = "0" ] || [ "$TOKEN_COUNT" = "null" ]; then
    echo "No alias tokens found for user: $TARGET_USER"
    exit 0
fi

echo "Found $TOKEN_COUNT alias token(s) for user: $TARGET_USER"
echo ""

# In dry-run mode, just show tokens and exit
if [ "$DRY_RUN" = true ]; then
    echo "[DRY RUN] Tokens for user '$TARGET_USER':"
    echo ""
    echo "$TOKENS" | jq -r '.[] | "ID:\(.id) | \(.xdatUserId) | \(.alias[:24])... | created: \((.created / 1000) | strftime("%Y-%m-%d %H:%M")) | expires: \((.estimatedExpirationTime / 1000) | strftime("%Y-%m-%d %H:%M")) | expired: \(.expired) | singleUse: \(.singleUse) | enabled: \(.enabled)"'
    exit 0
fi

# Show tokens that will be deleted
echo "Tokens to be invalidated:"
echo "$TOKENS" | jq -r '.[] | "ID:\(.id) | \(.xdatUserId) | \(.alias[:24])... | created: \((.created / 1000) | strftime("%Y-%m-%d %H:%M")) | expires: \((.estimatedExpirationTime / 1000) | strftime("%Y-%m-%d %H:%M")) | expired: \(.expired)"'
echo ""

# Confirmation prompt
read -p "Are you sure you want to invalidate ALL $TOKEN_COUNT token(s) for user '$TARGET_USER'? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Operation cancelled."
    exit 0
fi

echo ""
echo "Proceeding with token invalidation..."
echo ""

# Delete each token (using session cookie)
echo "$TOKENS" | jq -r '.[] | "\(.id)|\(.alias)"' | while IFS='|' read -r TOKEN_ID ALIAS; do
    if [ -n "$TOKEN_ID" ]; then
        echo "Invalidating token: ${ALIAS:0:24}... (ID: $TOKEN_ID)"
        RESPONSE=$(curl -s -w "\n%{http_code}" -b "$COOKIE_JAR" \
            "$XNAT_URL/data/services/tokens/invalidate/$TOKEN_ID?format=json")

        HTTP_CODE=$(echo "$RESPONSE" | tail -n1)

        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "204" ]; then
            echo "  ✓ Successfully invalidated"
        else
            BODY=$(echo "$RESPONSE" | sed '$d')
            echo "  ✗ Failed (HTTP $HTTP_CODE)"
            if [[ "$BODY" == *"<h3>"* ]]; then
                ERROR_MSG=$(echo "$BODY" | grep -o '<h3>.*</h3>' | sed 's/<[^>]*>//g')
                echo "     Error: $ERROR_MSG"
            fi
        fi
    fi
done

echo ""
echo "Token invalidation complete for user: $TARGET_USER"
