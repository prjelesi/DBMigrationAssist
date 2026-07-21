/*

This script gathers the following details and NO user database data is accessed:
1.	SERVER INFO
2.	SERVER PARAMETERS INFO TO LOAD
3.	ROLE-USER-PRIVILEGES DETAILS INFO
4.      AAD-USER DETAILS INFO

Note: This data is used only for supporting Azure migration/related activities.

Usage: psql -q -U pguser -h servername -d databasename -f pg_db_gather_v0.3.sql > output.log

*/

set enable_seqscan = off;

Select 'SERVER INFO BEGIN' as "Query_Description",CURRENT_TIMESTAMP;

select current_database() as current_db, current_user, version(), current_setting('TIMEZONE'),CURRENT_TIMESTAMP, pg_backend_pid() AS "currentPID";

Select 'SERVER INFO END' as "Query_Description",CURRENT_TIMESTAMP;

Select 'SERVER PARAMETERS INFO TO LOAD BEGIN' as "Query_Description",CURRENT_TIMESTAMP;

select name,setting,short_desc from pg_settings order by 1;

Select 'SERVER PARAMETERS INFO TO LOAD END' as "Query_Description",CURRENT_TIMESTAMP;

Select 'SERVER PARAMETERS INFO BEGIN' as "Query_Description",CURRENT_TIMESTAMP;

select * from pg_settings order by 1;

Select 'SERVER PARAMETERS INFO END' as "Query_Description",CURRENT_TIMESTAMP;

Select 'ROLE-USER-PRIVILEGES DETAILS INFO BEGIN' as "Query_Description",CURRENT_TIMESTAMP;

select rolname,rolcanlogin,rolvaliduntil from pg_roles ORDER BY 1;

SELECT r.rolname,
       ARRAY(
             SELECT b.rolname
             FROM pg_catalog.pg_auth_members m
              JOIN pg_catalog.pg_roles b ON (m.roleid = b.oid)
             WHERE m.member = r.oid) as memberof
FROM pg_catalog.pg_roles r
ORDER BY 1;

Select 'ROLE-USER-PRIVILEGES DETAILS INFO END' as "Query_Description",CURRENT_TIMESTAMP;

Select 'AAD-USER DETAILS INFO BEGIN' as "Query_Description",CURRENT_TIMESTAMP;

SELECT r.rolname
        FROM
          pg_roles r
          JOIN pg_auth_members am ON r.oid = am.member
          JOIN pg_roles m ON am.roleid = m.oid
        WHERE
          m.rolname IN (
                'azure_ad_admin',
                'azure_ad_user',
                'azure_ad_mfa'
          );

Select 'AAD-USER DETAILS INFO END' as "Query_Description",CURRENT_TIMESTAMP;

/*

This script gathers the following details and NO user database data is accessed:
1.	DATABASE INFO
2.	LARGE OBJECT INFO
3.	EXTENSION INFO
4.	DATABASE SIZE AND COLLATE INFO
5.	TABLE COLUMN COLLATE INFO
6.	TABLESPACE INFO
7.	OBJECT COUNT INFO
8.	SCHEMA INFO
9.	TABLE SIZE INFO
10.	JSON COLUMN INFO
11.	PARTITIONED DETAILS INFO
12.	REFERENCE CONSTRAINTS INFO
13.	TABLE NOT HAVING PRIMARY KEY INFO
14.	TABLE COUNT >= 10000000 WITHOUT BIGINT or INT INDEX INFO

Note: This data is used only for supporting Azure migration/related activities.

Usage: psql -q -U pguser -h servername -d databasename -f pg_db_gather_v0.2.sql > output.log

*/


Select 'DATABASE INFO BEGIN' as "Query_Description",CURRENT_TIMESTAMP;

select current_database() as current_db, current_user, version(), current_setting('TIMEZONE'),CURRENT_TIMESTAMP, pg_backend_pid() AS "currentPID";

Select 'DATABASE INFO END' as "Query_Description",CURRENT_TIMESTAMP;

Select 'LARGE OBJECT INFO BEGIN' as "Query_Description",CURRENT_TIMESTAMP;

Select current_database() as current_db,count(1) from pg_largeobject;

Select 'LARGE OBJECT INFO END' as "Query_Description",CURRENT_TIMESTAMP;

Select 'EXTENSION INFO BEGIN' as "Query_Description",CURRENT_TIMESTAMP;

SELECT extname, extversion FROM pg_extension order by 1,2;

Select 'EXTENSION INFO END' as "Query_Description",CURRENT_TIMESTAMP;

Select 'DATABASE SIZE AND COLLATE INFO BEGIN' as "Query_Description",CURRENT_TIMESTAMP;

select datname "DB Name",(pg_database_size(oid))/(1024*1024) as "DB Size(MB)" , datcollate from pg_database where datname = current_database();

Select 'DATABASE SIZE AND COLLATE INFO END' as "Query_Description",CURRENT_TIMESTAMP;

Select 'TABLE COLUMN COLLATE INFO BEGIN' as "Query_Description",CURRENT_TIMESTAMP;

select  n.nspname as schema,t.relname as table_name,a.attname as column_name, 
        y.typname,c.collname as collation
              FROM pg_catalog.pg_attribute a
              join pg_catalog.pg_class t on t.oid=a.attrelid
              join pg_catalog.pg_type y on y.oid=a.atttypid
              join pg_collation c on c.oid=a.attcollation
              join pg_namespace n on n.oid=t.relnamespace
              where a.attname not in ('tableoid',
              'cmax',
              'xmax',
              'cmin',
              'xmin',
              'ctid')
              and a.attisdropped='false'
              and c.collname <>'default' 
              and n.nspname not in ('information_schema','pg_catalog', 'pg_toast');

Select 'TABLE COLUMN COLLATE INFO END' as "Query_Description",CURRENT_TIMESTAMP;

Select 'TABLESPACE INFO BEGIN' as "Query_Description",CURRENT_TIMESTAMP;

select * from pg_tablespace;

Select 'TABLESPACE INFO END' as "Query_Description",CURRENT_TIMESTAMP;

Select 'OBJECT COUNT INFO BEGIN' as "Query_Description",CURRENT_TIMESTAMP;

SELECT
        n.nspname as schema_name
        ,CASE c.relkind
           WHEN 'r' THEN 'table'
           WHEN 'v' THEN 'view'
           WHEN 'i' THEN 'index'
           WHEN 'S' THEN 'sequence'
           WHEN 's' THEN 'special'
           WHEN 't' THEN 'ToastTable'
           WHEN 'm' THEN 'materializedView'
           WHEN 'c' THEN 'compositeType'
           WHEN 'f' THEN 'foreignTable'
           WHEN 'p' THEN 'partitionedTable'
        END as object_type
        ,count(1) as object_count
FROM pg_catalog.pg_class c
LEFT JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r','v','i','S','s','t','m','c','f','p')
and n.nspname not in ('information_schema','pg_catalog', 'pg_toast')
GROUP BY  n.nspname,
        CASE c.relkind
           WHEN 'r' THEN 'table'
           WHEN 'v' THEN 'view'
           WHEN 'i' THEN 'index'
           WHEN 'S' THEN 'sequence'
           WHEN 's' THEN 'special'
           WHEN 't' THEN 'ToastTable'
           WHEN 'm' THEN 'materializedView'
           WHEN 'c' THEN 'compositeType'
           WHEN 'f' THEN 'foreignTable'
           WHEN 'p' THEN 'partitionedTable'
        END
ORDER BY n.nspname,
        CASE c.relkind
           WHEN 'r' THEN 'table'
           WHEN 'v' THEN 'view'
           WHEN 'i' THEN 'index'
           WHEN 'S' THEN 'sequence'
           WHEN 's' THEN 'special'
           WHEN 't' THEN 'ToastTable'
           WHEN 'm' THEN 'materializedView'
           WHEN 'c' THEN 'compositeType'
           WHEN 'f' THEN 'foreignTable'
           WHEN 'p' THEN 'partitionedTable'
        END;


Select 'OBJECT COUNT INFO END' as "Query_Description",CURRENT_TIMESTAMP;

Select 'SCHEMA INFO BEGIN' as "Query_Description",CURRENT_TIMESTAMP;

SELECT schema_name FROM information_schema.schemata order by 1;

Select 'SCHEMA INFO END' as "Query_Description",CURRENT_TIMESTAMP;

Select 'TABLE SIZE INFO BEGIN' as "Query_Description",CURRENT_TIMESTAMP;

SELECT c.oid,nspname AS table_schema, relname AS TABLE_NAME
              , to_char(c.reltuples,'99999999999999999999999999999999') AS row_estimate
              , pg_size_pretty(pg_total_relation_size(c.oid)-pg_indexes_size(c.oid)-COALESCE(pg_total_relation_size(reltoastrelid),0)) AS table_bytes
              , pg_size_pretty(pg_total_relation_size(c.oid)) AS total_bytes
              , pg_size_pretty(pg_indexes_size(c.oid)) AS index_bytes
              , pg_size_pretty(pg_total_relation_size(reltoastrelid)) AS toast_bytes
          FROM pg_class c
          LEFT JOIN pg_namespace n ON n.oid = c.relnamespace
          WHERE relkind = 'r'
            AND n.nspname not in ('information_schema','pg_catalog', 'pg_toast');

Select 'TABLE SIZE INFO END' as "Query_Description",CURRENT_TIMESTAMP;

Select 'JSON COLUMN INFO BEGIN' as "Query_Description",CURRENT_TIMESTAMP;

select  a.current_database,n.nspname as schema_name, a."Tables with JSON columns"
from pg_catalog.pg_namespace n, (
  SELECT  current_database(),t.relname as "Tables with JSON columns", t.relnamespace
  FROM  pg_catalog.pg_class t
  JOIN  pg_attribute a ON a.attrelid = t.oid  
  WHERE (a.atttypid='json'::regtype or a.atttypid='jsonb'::regtype) ) a
where n.oid = a.relnamespace;
 
Select 'JSON COLUMN INFO END' as "Query_Description",CURRENT_TIMESTAMP;

Select 'PARTITIONED DETAILS INFO BEGIN' as "Query_Description",CURRENT_TIMESTAMP;

SELECT nmsp_parent.nspname AS parent_schema,
       parent.relname AS parent,
       nmsp_child.nspname AS child_schema,
       child.relname AS child
FROM pg_inherits
JOIN pg_class parent ON pg_inherits.inhparent = parent.oid
JOIN pg_class child ON pg_inherits.inhrelid = child.oid
JOIN pg_namespace nmsp_parent ON nmsp_parent.oid = parent.relnamespace
JOIN pg_namespace nmsp_child ON nmsp_child.oid = child.relnamespace;

Select 'PARTITIONED DETAILS INFO END' as "Query_Description",CURRENT_TIMESTAMP;

Select 'REFERENCE CONSTRAINTS INFO BEGIN' as "Query_Description",CURRENT_TIMESTAMP;

SELECT DISTINCT A.* FROM (
SELECT c.conrelid::regclass AS table_from,
       c.conname,
       pg_get_constraintdef(c.oid)
       FROM pg_constraint c
            INNER JOIN pg_namespace n
                       ON n.oid = c.connamespace
            CROSS JOIN LATERAL unnest(c.conkey) ak(k)
            INNER JOIN pg_attribute a
                       ON a.attrelid = c.conrelid
                          AND a.attnum = ak.k
       WHERE c.contype ='f') A;
		 
Select 'REFERENCE CONSTRAINTS INFO END' as "Query_Description",CURRENT_TIMESTAMP;

Select 'TABLE NOT HAVING PRIMARY KEY INFO BEGIN' as "Query_Description",CURRENT_TIMESTAMP;

SELECT  current_database() as current_db, n.nspname as schema_name, c.relname as "Tables with No Primary index"
FROM pg_catalog.pg_class c
LEFT JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace and c.relkind IN ('r','p')
AND  c.oid not in (
  SELECT t.oid
  FROM  pg_catalog.pg_class t
    JOIN  pg_index ix ON t.oid = ix.indrelid and t.relkind IN ('r','p') -- to check Primary or Unique
  WHERE (ix.indisprimary = TRUE)
                  )
WHERE n.nspname not in ('information_schema','pg_catalog', 'pg_toast')
ORDER BY 1,2,3; 

Select 'TABLE NOT HAVING PRIMARY KEY INFO END' as "Query_Description",CURRENT_TIMESTAMP;

Select 'TABLE COUNT > 10000000 WITHOUT BIGINT or INT INDEX INFO BEGIN' as "Query_Description",CURRENT_TIMESTAMP;

SELECT current_database() as current_db, n.nspname as schema_name,c.relname as "No int/bigint data-type single column Primary/unique index"
FROM pg_catalog.pg_class c
LEFT JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace and c.relkind IN ('r','p')
AND  c.oid not in (
	SELECT t.oid
	   FROM  pg_catalog.pg_class t
	     JOIN  pg_index ix ON t.oid = ix.indrelid and t.relkind IN ('r','p') -- to check Primary or Unique
	     JOIN  pg_attribute a ON a.attnum = ANY(ix.indkey) AND a.attrelid = t.oid -- to check index type
	   WHERE (ix.indisprimary = TRUE or ix.indisunique = TRUE)
	    AND   ix.indnatts = 1
	    AND   (a.atttypid = 'int'::regtype OR a.atttypid = 'bigint'::regtype)
                ) 
WHERE n.nspname not in ('information_schema','pg_catalog', 'pg_toast')
AND   c.reltuples >= 10000000
ORDER BY 1,2,3;

Select 'TABLE COUNT > 10000000 WITHOUT BIGINT or INT INDEX INFO END' as "Query_Description",CURRENT_TIMESTAMP;

Select 'TABLE WITH DEPRECATED DATA TYPE BEGIN' as "Query_Description",CURRENT_TIMESTAMP;

SELECT
    table_schema,
    table_name,
    column_name,
    data_type
FROM
    information_schema.columns
WHERE
    table_schema not in  ('pg_catalog','information_schema') and data_type in ('reltime','abstime','tinterval','char(n)','name','oid','bpchar','int2vector')
ORDER BY
    table_name,
    column_name;
	
Select 'TABLE WITH DEPRECATED DATA TYPE END' as "Query_Description",CURRENT_TIMESTAMP;
\q
