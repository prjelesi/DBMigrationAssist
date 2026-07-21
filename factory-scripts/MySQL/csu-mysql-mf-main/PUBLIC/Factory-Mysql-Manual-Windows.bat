@echo OFF
IF exist Output ( echo "Output" folder already exists! ) ELSE ( mkdir Output && echo "Output" Folder created!)
for /F "skip=1 tokens=1-12 delims=," %%A in (CMF_MySQL_Server_Input_file.csv) do (
REM "Host_Name","Resource_Group","Port","VCore","User_ID","Password","Auth_Type","DB_Name","Tenant","Subscription_ID","Approval_Status","SSL_Mode"
if /i [%%~K]==[YES] (
echo Processing :%%A
SET MYSQL_PWD=%%F
mysql -u %%E -h %%A -P %%C -D %%H < MySQL_Templates\dbgather.sql > .\Output\Manual_%%A_%%H.log
)
)