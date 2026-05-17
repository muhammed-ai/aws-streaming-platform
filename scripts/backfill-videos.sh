#!/bin/bash
# Scans the S3 output bucket and registers any videos missing from DynamoDB.
# Run this once to backfill existing transcoded videos.
#
# Usage: ./scripts/backfill-videos.sh [env]
# Example: ./scripts/backfill-videos.sh dev

ENV=${1:-dev}
OUTPUT_BUCKET="netflix-${ENV}-output"
TABLE="videos-${ENV}"
API="https://ww2c299ev0.execute-api.us-east-1.amazonaws.com"

echo "Scanning s3://${OUTPUT_BUCKET} for transcoded videos..."

# List all .m3u8 files in the output bucket
aws s3 ls "s3://${OUTPUT_BUCKET}/" --recursive | grep "_1080p.m3u8" | while read -r line; do
  OUTPUT_KEY=$(echo "$line" | awk '{print $4}')
  FOLDER=$(echo "$OUTPUT_KEY" | cut -d'/' -f1)
  VIDEO_ID="$FOLDER"
  TITLE=$(echo "$VIDEO_ID" | sed 's/[-_]/ /g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2); print}')

  echo "Found: $OUTPUT_KEY → video_id=$VIDEO_ID"

  # Register via the API — will overwrite if already exists
  RESPONSE=$(curl -s -X POST "${API}/videos" \
    -H "Content-Type: application/json" \
    -d "{
      \"video_id\": \"${VIDEO_ID}\",
      \"title\": \"${TITLE}\",
      \"description\": \"\",
      \"genre\": \"Uncategorized\",
      \"duration\": 0,
      \"output_key\": \"${OUTPUT_KEY}\",
      \"status\": \"ready\"
    }")

  echo "Response: $RESPONSE"
done

echo "Backfill complete."
