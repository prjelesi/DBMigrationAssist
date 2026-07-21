Select 'DATABASEINFO-START' as "Database Info";

select current_database(), current_user, version();

SELECT current_setting('TIMEZONE');

SELECT CURRENT_TIMESTAMP;

select name,setting from pg_settings where name like 'archive%';

select setting from pg_settings where name = 'data_directory';

SELECT name, setting FROM pg_settings WHERE category = 'File Locations';

select 'DATABASEINFO-END' As "DATABASE INFO END";

Select 'EXTENSIONINFO-START' as "Extension Info";

SELECT extname, extversion FROM pg_extension order by 1,2;

select 'EXTENSIONINFO-END' As "EXTENSION INFO END";