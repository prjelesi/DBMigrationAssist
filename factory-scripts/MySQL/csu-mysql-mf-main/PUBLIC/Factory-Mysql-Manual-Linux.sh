for i in `cat Factory_MySQL_Server_Input_file.csv`
do
#"Host_Name","Resource_Group","Port","VCore","User_ID","Password","Auth_Type","DB_Name","Tenant","Subscription_ID","Approval_Status","SSL_Mode"
Host_Name=`echo $i | awk -F"," '{print $1}' | sed 's/"//g'`
Port=`echo $i | awk -F"," '{print $3}' | sed 's/"//g'`
User_ID=`echo $i | awk -F"," '{print $5}' | sed 's/"//g'`
Password=`echo $i | awk -F"," '{print $6}' | sed 's/"//g'`
DB_Name=`echo $i | awk -F"," '{print $8}' | sed 's/"//g'`
Approval_Status=`echo $i | awk -F"," '{print $11}' | sed 's/"//g'`
SSL_Mode=`echo $i | awk -F"," '{print $12}' | sed 's/"//g'`
DbGather_path="./MySQL_Templates/dbgather.sql"
Log_File="Manual_${Host_Name}_${DB_Name}.log"
export MYSQL_PWD=$Password
if [[ $(echo "$Approval_Status" | tr '[:upper:]' '[:lower:]') == "yes" ]];then
echo "Processing:$Host_Name"
mysql -u $User_ID -h $Host_Name -P $Port -D $DB_Name < $DbGather_path > ./Output/$Log_File
fi
done
