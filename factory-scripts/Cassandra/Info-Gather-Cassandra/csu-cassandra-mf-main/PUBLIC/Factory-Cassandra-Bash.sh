#!/bin/bash

function exit_code() {
    echo "-Ending Execution"
    exit
}

function create_folder() {
    local new_folder="$1"
    if [ -d "$new_folder" ]; then
        echo "-Folder '$new_folder' exists..."
    else
        mkdir -p "$new_folder"
        echo "-$new_folder folder created..."
    fi
}

# Detect OS type and base folder
folder="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Detect OS and set folder paths 
if [[ "$OSTYPE" == "msys"* || "$OSTYPE" == "cygwin"* || "$OSTYPE" == "win32" ]]; then
    logs_folder="${folder}\\Logs"
    output_folder="${folder}\\Output"
elif [[ "$OSTYPE" == "linux-gnu"* || "$OSTYPE" == "darwin"* ]]; then
    logs_folder="${folder}/Logs"
    output_folder="${folder}/Output"
else
    echo "Unsupported OS: $OSTYPE"
    exit_code
fi

# Create folders
create_folder "$logs_folder"
create_folder "$output_folder"

# Detect Cassandra Binary
cassandra_cmd=""

if command -v cqlsh >/dev/null 2>&1; then
    cassandra_cmd="cqlsh"
else
    echo " 'cqlsh' not found in PATH."
    exit_code
fi

echo "Operating System: $OSTYPE"
echo " Cassandra client: $cassandra_cmd"

today_date=$(date +"%m_%d_%Y_%H_%M_%S")

# Logging to transcript
if [[ "$cassandra_cmd" == *".exe" ]]; then
   exec > >(tee -a "$folder\\Logs\\Factory-Cassandra_Info_Gathering_Automation_Transcript_$today_date.txt") 2>&1
else
   exec > >(tee -a "$folder/Logs/Factory-Cassandra_Info_Gathering_Automation_Transcript_$today_date.txt") 2>&1
fi

echo "Transcript started at $(date)"
echo "========================="

# Log setup
if [[ "$cassandra_cmd" == *".exe" ]]; then
  log_file_valid="$folder\\Output\\Cassandra_validation.log"
  log_file_err="$folder\\Output\\Cassandra_validation.err"
  inputfile="$folder\\Factory_Cassandra_Input_File.csv"
  sql_file="$folder\\Factory-Cassandra-Dbgather.sql"
else
  log_file_valid="$folder/Output/Cassandra_validation.log"
  log_file_err="$folder/Output/Cassandra_validation.err"
  inputfile="$folder/Factory_Cassandra_Input_File.csv"
  sql_file="$folder/Factory-Cassandra-Dbgather.sql"
fi

echo "Checking for cassandra client version path"
$cassandra_cmd --version &> "$log_file_valid"
if [ $? -ne 0 ]; then
    echo "Failed to validate cassandra client location"
    echo "$(< "$log_file_err")"
    exit_code
else
    $cassandra_cmd --version
    echo "Cassandra client validated successfully"
fi
 # Create a unique output file for each host
    # Dbfile="$folder/Output/Database_${HOST}_${today_date}.txt"
    # Clusterfile="$folder/Output/Cluster_${Host_Name}_${today_date}.txt"
    # echo "Logging to $Dbfile & $Clusterfile..."

# Ensure the CSV file exists
if [ ! -f "$inputfile" ]; then
    echo "CSV file not found: $inputfile"
    exit_code
fi

# Skip header and read each line from the CSV file
tail -n +2 "$inputfile" | while IFS=',' read -r HOST DB_USER DB_PASSWD; do
         
          
                  Dbfile="$folder/Output/Database_${HOST}_${today_date}.txt"
	          Clusterfile="$folder/Output/Cluster_${HOST}_${today_date}.txt"	  
# Skip empty lines or lines with missing values
    if [ -z "$HOST" ] || [ -z "$DB_USER" ] || [ -z "$DB_PASSWD" ]; then
        continue
    fi


    # Execute the CQL script using cqlsh and capture output
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Running CQL script on $HOST" > "$Dbfile"
    $cassandra_cmd "$HOST" -u "$DB_USER" -p "$DB_PASSWD" -f "$sql_file" >> "$Dbfile" 2>&1

    # Check the exit status of the cqlsh command
    if [ $? -eq 0 ]; then
	echo "Output from ${HOST} saved to $Dbfile"
    else	
        echo "Failed to execute CQL script on $HOST." >> "$Dbfile"
    fi
# done
    echo "########## Number of nodes in cluster Info Begins for "$HOST" ##########" >> "$Clusterfile"
   # /usr/bin/nodetool -u "$DB_USER" -pw "$DB_PASSWD" -h "$HOST"  status >> "$Clusterfile" 2>&1
   /usr/bin/nodetool status >> "$Clusterfile" 2>&1
    echo "########## Number of nodes in cluster Info Ends for "$HOST" ###########" >> "$Clusterfile"


    echo "########## Table information Begins for "$HOST"  ##########" >> "$Clusterfile"
   for ks in $($cassandra_cmd "$HOST" -u "$DB_USER" -p "$DB_PASSWD"  -e "DESCRIBE KEYSPACES" | tr ' ' '\n' | grep -v -E '^system|system_schema|system_auth|system_distributed|system_traces|system_views$'); do
    echo "=== Keyspace: $ks for "$HOST" ===" >> "$Clusterfile"
  #  /usr/bin/nodetool  -u "$DB_USER" -pw "$DB_PASSWD" -h "$HOST" tablestats "$ks"  | grep -E 'Keyspace|Table:|Number of partitions|Space used \(total\)|Compacted partition*' >> "$Clusterfile"
     /usr/bin/nodetool tablestats "$ks"  | grep -E 'Keyspace|Table:|Number of partitions|Space used \(total\)|Compacted partition*' >> "$Clusterfile"
done
    echo "########## Table information Ends for "$HOST"  ##########" >> "$Clusterfile"

    # Log the status of the operation
    if [ $? -eq 0 ]; then
        echo "Output from ${HOST} saved to $Clusterfile"
    else
        echo "An error occurred while gathering info from $HOST" >> "$Clusterfile"
    fi

done 
