#!/bin/bash

# ========================
# MongoDB Dump & Restore Script (Menu Driven)
# - Full dump/restore
# - Partial dump/restore
# ========================

# VARIABLES & CONNECTION STRINGS
CLUST_URI="$1"
CLUST_DIR="$2"
COLLECTION_LIST_FILE="$3"  # Optional: file listing DB.COLLECTION names
CLUST_LOG_FILE=$CLUST_DIR"_$(date +%Y%m%d_%H%M%S).log"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ -z "$CLUST_URI" || -z "$CLUST_DIR" ]]; then
  echo "Usage: $0 <clust_uri> <clust_dir> [clust_list_file]"
  echo "Example:"
  echo "  $0 'mongodb://user:pass@source:27017' '/datadrive/mongodump' [collections.list]"
  exit 1
fi

echo "===================================="
echo " MongoDB Dump & Restore Menu"
echo "===================================="
echo "1) Full Backup "
echo "2) Full Restore"
echo "3) Partial Backup  (uses collection.list file)"
echo "4) Partial Restore (uses collection list file)"
echo "===================================="
read -p "Choose an option ( 1 or 2 or 3 or 4 ): " choice

# Ask for confirmation before --drop
echo "WARNING: This script uses '--drop' and will DELETE collections before restoring."
read -p "Are you sure you want to continue? (yes/no): " confirm
if [[ "$confirm" != "yes" ]]; then
  echo "Operation canceled by user."
  exit 1
fi

# ========================
# OPTION 1: FULL BACKUP 
# ========================
if [ "$choice" -eq 1 ]; then
    echo "=== Full Dump Started: $(date) ==="
    mongodump --uri="$CLUST_URI" --authenticationMechanism=SCRAM-SHA-256 --out="$CLUST_DIR" | tee -a "$CLUST_LOG_FILE" 
    echo "=== Full Dump Completed: $(date) ==="

# ========================
# OPTION 2: FULL RESTORE
# ========================
elif [ "$choice" -eq 2 ]; then
    echo "=== Full Restore Started: $(date) ===" | tee -a "$CLUST_LOG_FILE"
    nohup mongorestore --uri="$CLUST_URI" --nsExclude=admin.system.views --drop "$CLUST_DIR" >> $CLUST_LOG_FILE 2>&1 &
    echo "Full restore running in background. Check /datadrive/full_restore.log for progress." | tee -a "$CLUST_LOG_FILE"

# ========================
# OPTION 3: PARTIAL BACKUP 
# ========================
elif [ "$choice" -eq 3 ]; then
    if [ ! -f "$COLLECTION_LIST_FILE" ]; then
      echo "ERROR: Collection list file not found. Please provide it as the first argument."
      echo "  $0 'mongodb://user:pass@source:27017' '/datadrive/mongodump' [collections.list]"
      exit 1
    fi

    echo "=== Partial Dump Started: $(date) ==="
    while IFS= read -r line; do
      [[ -z "$line" || "$line" =~ ^# ]] && continue
      dbname=$(echo "$line" | cut -d'.' -f1)
      coll=$(echo "$line" | cut -d'.' -f2)
      echo "Dumping $dbname.$coll..."
      mongodump --uri="$CLUST_URI" --db="$dbname" --collection="$coll" \
  --authenticationDatabase=admin --authenticationMechanism=SCRAM-SHA-256 \
  --out="$CLUST_DIR"
    done < "$COLLECTION_LIST_FILE"
    echo "=== Partial Dump Completed: $(date) ==="

# ========================
# OPTION 4: PARTIAL RESTORE
# ========================
elif [ "$choice" -eq 4 ]; then
    echo "=== Partial Restore Started: $(date) ===" | tee -a "$CLUST_LOG_FILE"
    while IFS= read -r line; do
      [[ -z "$line" || "$line" =~ ^# ]] && continue
      dbname=$(echo "$line" | cut -d'.' -f1)
      coll=$(echo "$line" | cut -d'.' -f2)
      BSON_FILE="$CLUST_DIR/$dbname/$coll.bson"

      if [ ! -f "$BSON_FILE" ]; then
        echo "WARNING: BSON file for $dbname.$coll not found, skipping." | tee -a "$CLUST_LOG_FILE"
        continue
      fi

      echo "Restoring $dbname.$coll..."
      nohup mongorestore \
         --uri="$CLUST_URI" \
         --nsInclude="$dbname.$coll" \
         --dir="$CLUST_DIR" \
         --drop >> "/datadrive/restore_${dbname}_${coll}.log" 2>&1 &
    echo "$dbname.$coll restore started in background. Check /datadrive/restore_${dbname}_${coll}.log for progress." | tee -a "$CLUST_LOG_FILE"
    done < "$COLLECTION_LIST_FILE"
    echo "=== Partial Restore Submitted: $(date) ===" | tee -a "$CLUST_LOG_FILE"
else
    echo "Invalid choice. Please run the script again and select 1 or 2."
    exit 1
fi
