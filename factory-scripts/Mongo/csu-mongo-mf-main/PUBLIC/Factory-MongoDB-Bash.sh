#!/bin/bash
#---------------------------------------------------------------------------------------------------------------------------*
# Purpose        : Script to fetch Information from MongoDB.
# Schedule       : Ad-Hoc / On-Demand
# Start Date     : 03-July-2024
# Author         : Rackimuthu Kandaswamy , Arun (Converted to Bash)
# Version        : 1.1
#
# INPUTS         : Server List and other parameters in CSV file; SSL_Modes = allow, disable, prefer, require, verify-ca, verify-full
# VARIABLE       : NONE
# PARENT         : NONE
# CHILD          : NONE
#---------------------------------------------------------------------------------------------------------------------------*

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

# Detect OS type
# Create necessary folders

#folder=$(dirname "$0")
folder="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" || "$OSTYPE" == "cygwin" ]]; then
    mongo_cmd="mongosh.exe"
    create_folder "$folder\Logs"
    create_folder "$folder\Output"
elif [[ "$OSTYPE" == "linux-gnu"* || "$OSTYPE" == "darwin"* ]]; then
    mongo_cmd="mongosh"
    create_folder "$folder/Logs"
    create_folder "$folder/Output"
else
    echo "Unsupported OS: $OSTYPE"
    exit 1
fi
echo "Operating System is $OSTYPE"
echo "Client is $mongo_cmd"

today_date=$(date +"%m_%d_%Y_%H_%M_%S")

# Start logging using tee (both screen and file)
if [[ "$mongo_cmd" == "mongosh.exe" ]]; then
   exec > >(tee -a "$folder\Logs\Factory-Mongo_Info_Gathering_Automation_Transcript_$today_date.txt") 2>&1
fi

if [[ "$mongo_cmd" == "mongosh" ]]; then
   exec > >(tee -a "$folder/Logs/Factory-Mongo_Info_Gathering_Automation_Transcript_$today_date.txt") 2>&1
fi

# Start of transcript
echo "Transcript started at $(date)"
echo "========================="

# Logging
if [[ "$mongo_cmd" == "mongosh.exe" ]]; then
  log_file_valid="$folder\Output\MongoDB_validation.log"
  log_file_err="$folder\Output\MongoDB_validation.err"
  inputfile="$folder\Factory_Mongo_Input_File.csv"
fi

if [[ "$mongo_cmd" == "mongosh" ]]; then
  log_file_valid="$folder/Output/MongoDB_validation.log"
  log_file_err="$folder/Output/MongoDB_validation.err"
  inputfile="$folder/Factory_Mongo_Input_File.csv"
fi

echo "Checking for mongosh client version path"
$mongo_cmd --version &> "$log_file_valid"
if [ $? -ne 0 ]; then
    echo "Failed to validate mongosh client location"
    echo "$(< "$log_file_err")"
    exit_code
else
    $mongo_cmd --version
    echo "Mongosh client validated successfully"
fi

# Read input file
echo "Input file is $inputfile"
if [ ! -f "$inputfile" ]; then
    echo "Unable to read the input file [$inputfile]. Check file & its permission..."
    exit_code
fi
# While loop to read input until 'exit' is typed
for i in `tail -n +2 $inputfile`
do
    Host_Name=`echo $i | awk -F ',' '{print $1}'`
    Port=`echo $i | awk -F ',' '{print $2}'`
    Approval_Status=`echo $i | awk -F ',' '{print $8}'`
    if [ "$Approval_Status" == "Yes" ]; then
	Output_host+=$(printf "\n %s,%s \n" "$Host_Name" "$Port")
    fi
done

echo -e "$Output_host"
echo " "
echo "Please press Y to continue MongoDB Info-Gathering. Press N to terminate the execution."
read -p "Please provide your input: " response

if [[ "$response" != "y" && "$response" != "Y" ]]; then
    exit_code
fi

Output_data=''

# While loop to read input until 'exit' is typed
for i in `tail -n +2 $inputfile`
do
 Host_Name=`echo $i | awk -F ',' '{print $1}'`
 Port=`echo $i | awk -F ',' '{print $2}'`
 User_ID=`echo $i | awk -F ',' '{print $3}'`
 Password=`echo $i | awk -F ',' '{print $4}'`
 Auth_DB=`echo $i | awk -F ',' '{print $5}'`
 TLS_Certificate_Path=`echo $i | awk -F ',' '{print $6}'`
 CA_Certificate_Path=`echo $i | awk -F ',' '{print $7}'`
 Approval_Status=`echo $i | awk -F ',' '{print $8}'`

 if [ "$Approval_Status" == "Yes" ]; then
    echo $Host_Name $Port $User_ID $Password $Auth_db $TLS_Certificate_Path $CA_Certificate_Path $Approval_Status

    if [[ "$mongo_cmd" == "mongosh.exe" ]]; then
      log_file_cluster="$folder/Output/Cluster_${Host_Name}_${today_date}.log"
      log_file_db="$folder/Output/Database_${Host_Name}_${today_date}.log"
      log_file_size="$folder/Output/DBSize_${Host_Name}_${today_date}.log"
    fi

    if [[ "$mongo_cmd" == "mongosh" ]]; then
      log_file_cluster="$folder/Output/Cluster_${Host_Name}_${today_date}.log"
      log_file_db="$folder/Output/Database_${Host_Name}_${today_date}.log"
      log_file_size="$folder/Output/DBSize_${Host_Name}_${today_date}.log"
    fi
    echo ""
    echo "Initiating Info-Gathering for $Host_Name"
   #echo "Log File is $log_file_cluster"
   #echo "Log File is $log_file_db"
   #echo "Log File is $log_file_size"

    # Interactive password validation
    if [ "$Password" == "IN" ]; then
        read -s -p "Enter MongoDB Password for $Host_Name:" Password
        echo
        if [ -z "$Password" ]; then
            echo "Password cannot be empty. Exiting."
            exit 1
        fi
    fi

    if [[ -n "$User_ID" && -n "$Password" ]]; then
       Connection_USER="$User_ID:$Password@"
    elif [[ -z "$User_ID" && -z "$Password" ]]; then
       Connection_USER=""
    else
       echo "Error: User_ID and Password must be set or both must be empty."
    fi

    if [[ "$Host_Name" == *".mongodb.net"* ]]; then
      if [[ -n "$Port" ]]; then
        echo "ERROR: Port must be empty for .mongodb.net SRV connection."
      fi
    fi

    Connection_PARAM="?serverSelectionTimeoutMS=120000&connectTimeoutMS=20000&socketTimeoutMS=30000&readPreference=secondaryPreferred"

    if [[ "$Host_Name" == *".mongodb.net"* ]]; then
       Connection_URI="mongodb+srv://${Connection_USER}${Host_Name}/${Auth_DB}${Connection_PARAM}"
    else
       Connection_URI="mongodb://${Connection_USER}${Host_Name}:${Port}/${Auth_DB}${Connection_PARAM}"
    fi

    if [[ -n "$CA_Certificate_Path" && -n "$TLS_Certificate_Path" ]]; then
       Connection_TLS=" --tls --tlsCAFile \"$CA_Certificate_Path\" --tlsCertificateKeyFile \"$TLS_Certificate_Path\""
    elif [[ -z "$CA_Certificate_Path" && -z "$TLS_Certificate_Path" ]]; then
       Connection_TLS=""
    else
       echo "Error: $Connection_URI CA_Certificate_Path and TLS_Certificate_Path must be set or both must be empty."
    fi

    Connection_AUTHDB=" --authenticationDatabase $Auth_DB --quiet --eval \"var _printJSON=false;\" "

    Mongo_Cmd="$mongo_cmd \"$Connection_URI\" $Connection_TLS $Connection_AUTHDB"

    Mongo_Cmd_db_ver="$Mongo_Cmd --eval 'db.version()'"
    Error_Msg=$(eval "$Mongo_Cmd_db_ver")
    dbstat=$?
    if [ $dbstat = 1 ]; then
         Status="FAILED"
         Output_data+=$(printf "\n %s,%s,%s \n" "$Host_Name" "$Status" "$log_file_cluster")
	 continue
    fi

    Connection_PARAM="?serverSelectionTimeoutMS=120000&connectTimeoutMS=20000&socketTimeoutMS=30000&readPreference=secondaryPreferred"

    if [[ "$Host_Name" == *".mongodb.net"* ]]; then
       Connection_URI="mongodb+srv://${Connection_USER}${Host_Name}/${Auth_DB}${Connection_PARAM}"
    else
       Connection_URI="mongodb://${Connection_USER}${Host_Name}:${Port}/${Auth_DB}${Connection_PARAM}"
    fi

    Mongo_Cmd="$mongo_cmd \"$Connection_URI\" $Connection_TLS $Connection_AUTHDB"
    Mongo_Cmd_getmongo_js="$Mongo_Cmd getMongoData.js >> $log_file_cluster"
    ## echo "******* Command : " $Mongo_Cmd_getmongo_js
    getjs=$(eval "$Mongo_Cmd_getmongo_js")
    dbstat=$(echo $?)
    if [ $dbstat = 1 ]; then
         Status="FAILED:GET MONGO JS"
         Output_data+=$(printf "\n %s,%s,%s \n" "$Host_Name" "$Status" "$log_file_cluster")
    fi

    Connection_PARAM="?serverSelectionTimeoutMS=120000&connectTimeoutMS=20000&socketTimeoutMS=30000&readPreference=secondaryPreferred"

    if [[ "$Host_Name" == *".mongodb.net"* ]]; then
       Connection_URI="mongodb+srv://${Connection_USER}${Host_Name}/${Auth_DB}${Connection_PARAM}"
    else
       Connection_URI="mongodb://${Connection_USER}${Host_Name}:${Port}/${Auth_DB}${Connection_PARAM}"
    fi

    Mongo_Cmd="$mongo_cmd \"$Connection_URI\" $Connection_TLS $Connection_AUTHDB"
    Mongo_Cmd_chksize_js="$Mongo_Cmd Checksize.js >> $log_file_size"
    ## echo "******* Command : " $Mongo_Cmd_chksize_js
    getjs=$(eval "$Mongo_Cmd_chksize_js")
    dbstat=$(echo $?)
    if [ $dbstat = 1 ]; then
         Status="FAILED:CHECK DB SIZE JS"
         Output_data+=$(printf "\n %s,%s,%s \n" "$Host_Name" "$Status" "$log_file_size")
    fi

    Connection_PARAM="?serverSelectionTimeoutMS=120000&connectTimeoutMS=20000&socketTimeoutMS=30000&readPreference=secondaryPreferred"

    if [[ "$Host_Name" == *".mongodb.net"* ]]; then
       Connection_URI="mongodb+srv://${Connection_USER}${Host_Name}/${Auth_DB}${Connection_PARAM}"
    else
       Connection_URI="mongodb://${Connection_USER}${Host_Name}:${Port}/${Auth_DB}${Connection_PARAM}"
    fi

    Mongo_Cmd="$mongo_cmd \"$Connection_URI\" $Connection_TLS $Connection_AUTHDB"
    Mongo_Cmd_chkmongo_js="$Mongo_Cmd CheckMongoDB.js >> $log_file_db"
    ## echo "******* Command : " $Mongo_Cmd_chkmongo_js
    getjs=$(eval "$Mongo_Cmd_chkmongo_js")
    dbstat=$(echo $?)
    if [ $dbstat = 1 ]; then
         Status="FAILED:CHECK MONGO DB"
         Output_data+=$(printf "\n %s,%s,%s \n" "$Host_Name" "$Status" "$log_file_db")
    fi

    if [ -s "$log_file_cluster" ] && [ -s "$log_file_db" ] && [ -s "$log_file_size" ]; then
       echo "Cluster Information Gathered is stored at $log_file_cluster"
       echo "Database Information Gathered is stored at $log_file_db"
       echo "DBSize Information Gathered is stored at $log_file_size"
       Status="SUCCESS"
       Output_data+=$(printf "\n %s,%s,%s \n" "$Host_Name" "$Status")
    fi
 fi ###### approval is yes 
done 

echo "Below is the final status of MongoDB Script Execution:"

# Print the output data to the console in a formatted way
echo -e "Host_Name\t\t\tStatus\t\t\tError_Message"
echo -e "$Output_data" | awk -F, '{printf "%-30s %-20s %-60s \n", $1, $2, $3}'

echo "Transcript End at $(date)"
echo "========================="
exec &>/dev/tty
exit_code
