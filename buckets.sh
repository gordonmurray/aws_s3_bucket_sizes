#!/bin/bash

# Define storage types to check and mapping to CSV columns.
# We'll combine StandardIA and OneZoneIA as "IAStorage" and GlacierStorage and DeepArchiveStorage as "Glacier"
storage_types=("StandardStorage" "StandardIAStorage" "OneZoneIAStorage" "GlacierStorage" "DeepArchiveStorage")

# Print CSV header
echo "BucketName,StandardStorage,IAStorage,Glacier,Total"

# Get all bucket names using profile "default"
buckets=$(aws s3api list-buckets --profile default --query "Buckets[].Name" --output text)

# Set time range: from 2 days ago to 1 day ago (ensuring metrics are available)
start_time=$(date -u +"%Y-%m-%dT00:00:00Z" -d "2 days ago")
end_time=$(date -u +"%Y-%m-%dT00:00:00Z" -d "yesterday")

for bucket in $buckets; do

  # Get bucket region. For us-east-1, this returns "None" or an empty string.
  region=$(aws s3api get-bucket-location --bucket "$bucket" --profile default --output text)
  if [[ "$region" == "None" || "$region" == "" ]]; then
    region="us-east-1"
  fi

  # Initialize variables for each storage type
  sizeStandard=0
  sizeStandardIA=0
  sizeOneZoneIA=0
  sizeGlacier=0
  sizeDeepArchive=0

  for st in "${storage_types[@]}"; do
    result=$(aws cloudwatch get-metric-statistics \
      --profile default \
      --region "$region" \
      --namespace AWS/S3 \
      --metric-name BucketSizeBytes \
      --dimensions Name=BucketName,Value="$bucket" Name=StorageType,Value="$st" \
      --start-time "$start_time" \
      --end-time "$end_time" \
      --period 86400 \
      --statistics Average \
      --output json)

    size=$(echo "$result" | jq -r '.Datapoints[0].Average // 0')
    # Remove any fractional part (e.g., 18252330.0 -> 18252330)
    size=${size%.*}

    case "$st" in
      "StandardStorage")
        sizeStandard=$size
        ;;
      "StandardIAStorage")
        sizeStandardIA=$size
        ;;
      "OneZoneIAStorage")
        sizeOneZoneIA=$size
        ;;
      "GlacierStorage")
        sizeGlacier=$size
        ;;
      "DeepArchiveStorage")
        sizeDeepArchive=$size
        ;;
    esac
  done

  # Combine IA storage and Glacier storage values
  ia_storage=$(( sizeStandardIA + sizeOneZoneIA ))
  glacier_total=$(( sizeGlacier + sizeDeepArchive ))
  total=$(( sizeStandard + ia_storage + glacier_total ))

  # Output CSV line: bucket name, StandardStorage, IAStorage, Glacier, Total
  echo "$bucket,$sizeStandard,$ia_storage,$glacier_total,$total"
done
