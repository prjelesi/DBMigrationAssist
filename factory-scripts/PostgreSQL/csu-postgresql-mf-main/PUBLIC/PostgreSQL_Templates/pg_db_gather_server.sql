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

