/*

This script gathers the following details and NO user database data is accessed:
1.      SERVER VERSION INFO
2.      SERVER PARAMETERS INFO TO LOAD
3.      SERVER INNODB INFO 
4.      ROLE-USER-PRIVILEGES DETAILS INFO
5.      AAD-USER DETAILS INFO

Note: This data is used only for supporting Azure migration/related activities.

Usage: psql -q -U pguser -h servername -d databasename -f pg_db_gather_v0.3.sql > output.log

*/

Select 'SERVER INNODB INFO BEGIN' as "Query_Description",CURRENT_TIMESTAMP;
SET @SCH = IF(VERSION()<'5.7','information_schema','performance_schema');

Select 'SERVER VERSION INFO BEGIN' as "Query_Description",CURRENT_TIMESTAMP;
SELECT VERSION();
Select 'SERVER VERSION INFO END' as "Query_Description",CURRENT_TIMESTAMP;

Select 'SERVER PARAMETERS INFO TO LOAD BEGIN' as "Query_Description",CURRENT_TIMESTAMP;
SET @SQLSTMT=CONCAT("SELECT variable_name,variable_value FROM ",@SCH,".global_variables order by 1");
PREPARE s FROM @SQLSTMT; EXECUTE s ; DEALLOCATE PREPARE s;
Select 'SERVER PARAMETERS INFO TO LOAD END' as "Query_Description",CURRENT_TIMESTAMP;


Select 'SERVER INNODB INFO BEGIN' as "Query_Description",CURRENT_TIMESTAMP;
SET @SQLSTMT=CONCAT("SELECT variable_value INTO @SERVER_COLLATION        FROM ",@SCH,".global_variables WHERE variable_name='collation_server'");
PREPARE s FROM @SQLSTMT; EXECUTE s ; DEALLOCATE PREPARE s;

SET @SQLSTMT=CONCAT("SELECT variable_value INTO @HOSTNAME        FROM ",@SCH,".global_variables WHERE variable_name='hostname'");
PREPARE s FROM @SQLSTMT; EXECUTE s ; DEALLOCATE PREPARE s;

SET @SQLSTMT=CONCAT("SELECT variable_value INTO @IBP_SIZE        FROM ",@SCH,".global_variables WHERE variable_name='innodb_buffer_pool_size'");
PREPARE s FROM @SQLSTMT; EXECUTE s ; DEALLOCATE PREPARE s;

SET @SQLSTMT=CONCAT("SELECT variable_value INTO @IBP_PAGES_DATA  FROM ",@SCH,".global_status    WHERE variable_name='Innodb_buffer_pool_pages_data'");
PREPARE s FROM @SQLSTMT; EXECUTE s ; DEALLOCATE PREPARE s;

SET @SQLSTMT=CONCAT("SELECT variable_value INTO @IBP_PAGES_FREE  FROM ",@SCH,".global_status    WHERE variable_name='Innodb_buffer_pool_pages_free'");
PREPARE s FROM @SQLSTMT; EXECUTE s ; DEALLOCATE PREPARE s;

SET @SQLSTMT=CONCAT("SELECT variable_value INTO @IBP_PAGES_MISC  FROM ",@SCH,".global_status    WHERE variable_name='Innodb_buffer_pool_pages_misc'");
PREPARE s FROM @SQLSTMT; EXECUTE s ; DEALLOCATE PREPARE s;

SET @SQLSTMT=CONCAT("SELECT variable_value INTO @IBP_PAGES_TOTAL FROM ",@SCH,".global_status    WHERE variable_name='Innodb_buffer_pool_pages_total'");
PREPARE s FROM @SQLSTMT; EXECUTE s ; DEALLOCATE PREPARE s;

SET @SQLSTMT=CONCAT("SELECT variable_value INTO @IBP_PAGE_SIZE   FROM ",@SCH,".global_status    WHERE variable_name='Innodb_page_size'");
PREPARE s FROM @SQLSTMT; EXECUTE s ; DEALLOCATE PREPARE s;

SET @IBP_PCT_DATA = 100.00 * @IBP_PAGES_DATA / @IBP_PAGES_TOTAL;
SET @IBP_PCT_FREE = 100.00 * @IBP_PAGES_FREE / @IBP_PAGES_TOTAL;
SET @IBP_PCT_MISC = 100.00 * @IBP_PAGES_MISC / @IBP_PAGES_TOTAL;
SET @IBP_PCT_FULL = 100.00 * (@IBP_PAGES_TOTAL - @IBP_PAGES_FREE) / @IBP_PAGES_TOTAL;
SET @initpad = 19;
SET @padding = IF(LENGTH(@HOSTNAME)>@initpad,LENGTH(@HOSTNAME),@initpad);
SET @decimal_places = 5; SET @KB = 1024; SET @MB = POWER(1024,2); SET @GB = POWER(1024,3);

-- SELECT @IBP_SIZE, @GB;
SELECT       'innodb_buffer_pool_size' as 'Option',LPAD(FORMAT(@IBP_SIZE,0),@padding,' ') Value
UNION SELECT 'innodb_buffer_pool_size GB',LPAD(FORMAT(@IBP_SIZE / @GB,0),@padding,' ');

SELECT       'Hostname' Status                ,LPAD(@HOSTNAME,@padding,' ') Value
UNION SELECT 'This Moment'                    ,NOW()
UNION SELECT 'Innodb_page_size'               ,LPAD(FORMAT(@IBP_PAGE_SIZE,0),@padding,' ')
UNION SELECT 'Innodb_buffer_pool_pages_data'  ,LPAD(FORMAT(@IBP_PAGES_DATA ,0),@padding,' ')
UNION SELECT 'Innodb_buffer_pool_pages_free'  ,LPAD(FORMAT(@IBP_PAGES_FREE ,0),@padding,' ')
UNION SELECT 'Innodb_buffer_pool_pages_misc'  ,LPAD(FORMAT(@IBP_PAGES_MISC ,0),@padding,' ')
UNION SELECT 'Innodb_buffer_pool_pages_total' ,LPAD(FORMAT(@IBP_PAGES_TOTAL,0),@padding,' ')
UNION SELECT 'Innodb_buffer_pool_bytes_data'  ,LPAD(FORMAT(@IBP_PAGES_DATA  * @IBP_PAGE_SIZE,0),@padding,' ')
UNION SELECT 'Innodb_buffer_pool_bytes_free'  ,LPAD(FORMAT(@IBP_PAGES_FREE  * @IBP_PAGE_SIZE,0),@padding,' ')
UNION SELECT 'Innodb_buffer_pool_bytes_misc'  ,LPAD(FORMAT(@IBP_PAGES_MISC  * @IBP_PAGE_SIZE,0),@padding,' ')
UNION SELECT 'Innodb_buffer_pool_bytes_total' ,LPAD(FORMAT(@IBP_PAGES_TOTAL * @IBP_PAGE_SIZE,0),@padding,' ')
UNION SELECT 'Innodb_buffer_pool_data GB'     ,LPAD(FORMAT(@IBP_PAGES_DATA  * @IBP_PAGE_SIZE / @GB,@decimal_places),@padding,' ')
UNION SELECT 'Innodb_buffer_pool_free KB'     ,LPAD(FORMAT(@IBP_PAGES_FREE  * @IBP_PAGE_SIZE / @KB,@decimal_places),@padding,' ')
UNION SELECT 'Innodb_buffer_pool_free MB'     ,LPAD(FORMAT(@IBP_PAGES_FREE  * @IBP_PAGE_SIZE / @MB,@decimal_places),@padding,' ')
UNION SELECT 'Innodb_buffer_pool_free GB'     ,LPAD(FORMAT(@IBP_PAGES_FREE  * @IBP_PAGE_SIZE / @GB,@decimal_places),@padding,' ')
UNION SELECT 'Innodb_buffer_pool_free GB'     ,LPAD(FORMAT(@IBP_PAGES_FREE  * @IBP_PAGE_SIZE / @GB,@decimal_places),@padding,' ')
UNION SELECT 'Innodb_buffer_pool_misc KB'     ,LPAD(FORMAT(@IBP_PAGES_MISC  * @IBP_PAGE_SIZE / @KB,@decimal_places),@padding,' ')
UNION SELECT 'Innodb_buffer_pool_misc MB'     ,LPAD(FORMAT(@IBP_PAGES_MISC  * @IBP_PAGE_SIZE / @MB,@decimal_places),@padding,' ')
UNION SELECT 'Innodb_buffer_pool_misc GB'     ,LPAD(FORMAT(@IBP_PAGES_MISC  * @IBP_PAGE_SIZE / @GB,@decimal_places),@padding,' ')
UNION SELECT 'Innodb_buffer_pool_total GB'    ,LPAD(FORMAT(@IBP_PAGES_TOTAL * @IBP_PAGE_SIZE / @GB,@decimal_places),@padding,' ')
UNION SELECT 'Percentage Data'                ,LPAD(CONCAT(FORMAT(@IBP_PCT_DATA,2),' %'),@padding,' ')
UNION SELECT 'Percentage Free'                ,LPAD(CONCAT(FORMAT(@IBP_PCT_FREE,2),' %'),@padding,' ')
UNION SELECT 'Percentage Misc'                ,LPAD(CONCAT(FORMAT(@IBP_PCT_MISC,2),' %'),@padding,' ')
UNION SELECT 'Percentage Used'                ,LPAD(CONCAT(FORMAT(@IBP_PCT_FULL,2),' %'),@padding,' ')
;
Select 'SERVER INNODB INFO END' as "Query_Description",CURRENT_TIMESTAMP;

Select 'DATABASE SIZE INFO BEGIN' as "Query_Description",CURRENT_TIMESTAMP;
SELECT table_schema as database_name, SUM(data_length + index_length)/1024/1024 AS total_mb, SUM(data_length)/1024/1024 AS data_mb, SUM(index_length)/1024/1024 AS index_mb, COUNT(*) AS tables, CURDATE() AS today 
FROM information_schema.tables where table_schema not in ('information_schema','mysql','sys','performance_schema') 
GROUP BY table_schema ORDER BY 2 DESC ;
Select 'DATABASE SIZE INFO END' as "Query_Description",CURRENT_TIMESTAMP;

Select 'DATA AND INDEX INFO BEGIN' as "Query_Description",CURRENT_TIMESTAMP;
select table_schema as database_name,
       table_name,
       round(1.0*data_length/1024/1024, 2) as data_size,
       round(index_length/1024/1024, 2) as index_size,
       round((data_length + index_length)/1024/1024, 2) as total_size
from information_schema.tables
where table_schema not in('information_schema','mysql','sys','performance_schema')
order by database_name,total_size desc;
Select 'DATA AND INDEX INFO END' as "Query_Description",CURRENT_TIMESTAMP;

Select 'REFERENCE KEY INFO BEGIN' as "Query_Description",CURRENT_TIMESTAMP;
select concat(fks.constraint_schema, '.', fks.table_name) as foreign_table,
       '->' as rel,
       concat(fks.unique_constraint_schema, '.', fks.referenced_table_name)
              as primary_table,
       fks.constraint_name,
       group_concat(kcu.column_name
            order by position_in_unique_constraint separator ', ')
             as fk_columns
from information_schema.referential_constraints fks
join information_schema.key_column_usage kcu
     on fks.constraint_schema = kcu.table_schema
     and fks.table_name = kcu.table_name
     and fks.constraint_name = kcu.constraint_name
-- where fks.constraint_schema = @dbname COLLATE @SERVER_COLLATION
where  fks.constraint_schema not in('information_schema','mysql','sys','performance_schema')
group by fks.constraint_schema,
         fks.table_name,
         fks.unique_constraint_schema,
         fks.referenced_table_name,
         fks.constraint_name
order by fks.constraint_schema,
         fks.table_name;
Select 'REFERENCE KEY INFO END' as "Query_Description",CURRENT_TIMESTAMP;

Select 'TOP 10 TABLES SIZE INFO BEGIN' as "Query_Description",CURRENT_TIMESTAMP;
SELECT CONCAT(table_schema, '.', table_name) table_name,
        CONCAT(ROUND(table_rows / 1000000, 2), 'M')                                    total_rows,
        CONCAT(ROUND(data_length / ( 1024 * 1024 * 1024 ), 2), 'G')                    DATA,
        CONCAT(ROUND(index_length / ( 1024 * 1024 * 1024 ), 2), 'G')                   idx,
        CONCAT(ROUND(( data_length + index_length ) / ( 1024 * 1024 * 1024 ), 2), 'G') total_size,
        ROUND(index_length / data_length, 2)                                           idxPct
 FROM   information_schema.TABLES
-- WHERE table_schema = @dbname
 WHERE table_schema not in('information_schema','mysql','sys','performance_schema')
 ORDER  BY data_length + index_length DESC
 LIMIT  10 ;
Select 'TOP 10 TABLES SIZE INFO END' as "Query_Description",CURRENT_TIMESTAMP;

Select 'SERVER PLUGIN INFO BEGIN' as "Query_Description",CURRENT_TIMESTAMP;
SELECT PLUGIN_NAME, PLUGIN_STATUS FROM INFORMATION_SCHEMA.PLUGINS; -- WHERE PLUGIN_NAME LIKE '%pam%';
Select 'SERVER PLUGIN INFO END' as "Query_Description",CURRENT_TIMESTAMP;

Select 'TABLE INVISIBLE COLUMN INFO BEGIN' as "Query_Description",CURRENT_TIMESTAMP;
SELECT TABLE_NAME, COLUMN_NAME, EXTRA FROM INFORMATION_SCHEMA.COLUMNS WHERE EXTRA = 'INVISIBLE';
Select 'TABLE INVISIBLE COLUMN INFO END' as "Query_Description",CURRENT_TIMESTAMP;

Select 'TABLE DATA TRUNCATE ERROR INFO BEGIN' as "Query_Description",CURRENT_TIMESTAMP;
SELECT table_schema, table_name, column_name, column_type FROM information_schema.columns WHERE TABLE_SCHEMA not in ('information_schema','mysql','sys','performance_schema') and    data_type = 'enum'; 
Select 'TABLE DATA TRUNCATE ERROR INFO END' as "Query_Description",CURRENT_TIMESTAMP;

Select 'FOREIGN KEY DATATYPE MISMATCH INFO BEGIN' as "Query_Description",CURRENT_TIMESTAMP;
select tab2.CONSTRAINT_NAME,
tab2.TABLE_SCHEMA,
tab2.TABLE_NAME,
tab2.COLUMN_NAME,
tab1.DATA_TYPE,
tab2.ORDINAL_POSITION,
tab2.REFERENCED_TABLE_SCHEMA,
tab2.REFERENCED_TABLE_NAME,
tab2.REFERENCED_COLUMN_NAME,
tab2.DATA_TYPE
FROM 
(SELECT
table1.CONSTRAINT_NAME,
table1.TABLE_SCHEMA,
table1.TABLE_NAME,
table1.COLUMN_NAME,
table1.ORDINAL_POSITION,
column1.DATA_TYPE 
FROM     information_schema.key_column_usage AS table1 
JOIN     information_schema.columns as column1
on table1.TABLE_SCHEMA = column1.TABLE_SCHEMA
and table1.TABLE_NAME   = column1.TABLE_NAME
and table1.COLUMN_NAME  = column1.COLUMN_NAME ) tab1,
(SELECT
table2.CONSTRAINT_NAME,
table2.TABLE_SCHEMA,
table2.TABLE_NAME,
table2.COLUMN_NAME,
table2.ORDINAL_POSITION,
table2.REFERENCED_TABLE_SCHEMA,
table2.REFERENCED_TABLE_NAME,
table2.REFERENCED_COLUMN_NAME,
column2.DATA_TYPE 
FROM     information_schema.key_column_usage AS table2
JOIN     information_schema.columns as column2
on table2.REFERENCED_TABLE_SCHEMA = column2.TABLE_SCHEMA
and table2.REFERENCED_TABLE_NAME  = column2.TABLE_NAME
and table2.REFERENCED_COLUMN_NAME = column2.COLUMN_NAME) tab2
WHERE 
     tab2.CONSTRAINT_NAME  =  tab1.CONSTRAINT_NAME
and tab2.TABLE_SCHEMA      =  tab1.TABLE_SCHEMA
and tab2.TABLE_NAME        =  tab1.TABLE_NAME
and tab2.COLUMN_NAME       =  tab1.COLUMN_NAME
and tab2.ORDINAL_POSITION  =  tab1.ORDINAL_POSITION
and tab1.DATA_TYPE != tab2.DATA_TYPE
Order by 1,2,3;
Select 'FOREIGN KEY DATATYPE MISMATCH INFO END' as "Query_Description",CURRENT_TIMESTAMP;

Select 'DATABASE ENGINE INFO BEGIN' as "Query_Description",CURRENT_TIMESTAMP;
SELECT distinct table_schema, engine FROM information_schema.tables WHERE table_schema NOT IN ('information_schema', 'mysql', 'performance_schema', 'sys') AND engine NOT IN ('InnoDB');
Select 'DATABASE ENGINE INFO END' as "Query_Description",CURRENT_TIMESTAMP;

Select 'AAD-USER INFO BEGIN' as "Query_Description",CURRENT_TIMESTAMP;
select user,host,plugin from mysql.user order by 3,1;
Select 'AAD-USER INFO END' as "Query_Description",CURRENT_TIMESTAMP;

Select 'AAD-PLUGIN INFO BEGIN' as "Query_Description",CURRENT_TIMESTAMP;
select * from  mysql.user where upper(plugin) like '%AAD%';
Select 'AAD-PLUGIN INFO END' as "Query_Description",CURRENT_TIMESTAMP;

Select 'PARTION-TABLE INFO BEGIN' as "Query_Description",CURRENT_TIMESTAMP;
SELECT TABLE_SCHEMA, TABLE_NAME, PARTITION_NAME FROM  information_schema.PARTITIONS WHERE  PARTITION_NAME IS NOT NULL ORDER BY TABLE_SCHEMA, TABLE_NAME;
Select 'PARTION-TABLE INFO END' as "Query_Description",CURRENT_TIMESTAMP;

Select 'ALL SEQUENCE OBJECTS INFO BEGIN' as "Query_Description",CURRENT_TIMESTAMP;
SELECT table_schema, table_name, table_type FROM information_schema.tables WHERE table_type = 'SEQUENCE';
Select 'ALL SEQUENCE OBJECTS INFO END' as "Query_Description",CURRENT_TIMESTAMP;

Select 'ALL ROLES INFO BEGIN' as "Query_Description",CURRENT_TIMESTAMP;
select Host, User, Role, Admin_option from mysql.roles_mapping;
Select 'ALL ROLES OBJECTS INFO END' as "Query_Description",CURRENT_TIMESTAMP;

Select 'TABLES WITH CHECK CONSTRAINTS INFO BEGIN' as "Query_Description",CURRENT_TIMESTAMP;
SELECT constraint_schema, table_name, constraint_name, check_clause FROM information_schema.check_constraints WHERE constraint_schema NOT IN ('information_schema', 'mysql', 'performance_schema', 'sys');
Select 'TABLES WITH CHECK CONSTRAINTS INFO END' as "Query_Description",CURRENT_TIMESTAMP;

Select 'ALL TABLES WITH JSON DATATYPE COLUMNS INFO BEGIN' as "Query_Description",CURRENT_TIMESTAMP;
SELECT table_schema, table_name, column_name, data_type FROM information_schema.columns WHERE data_type = 'longtext';
Select 'ALL TABLES WITH JSON DATATYPE COLUMNS INFO END' as "Query_Description",CURRENT_TIMESTAMP;