SELECT (text)'NODE INFO BEGIN' AS query_description, toTimestamp(now()) AS current_time FROM system.local;
select cluster_name, listen_address from system.local;
SELECT (text)'NODE ip INFO END' AS query_description, toTimestamp(now()) AS current_time FROM system.local;

SELECT (text)'VERSION INFO BEGIN' AS query_description, toTimestamp(now()) AS current_time FROM system.local;
Show version;
SELECT (text)'VERSION INFO END' AS query_description, toTimestamp(now()) AS current_time FROM system.local;

SELECT (text)'CLUSTER INFO BEGIN' AS query_description, toTimestamp(now()) AS current_time FROM system.local;
select peer, data_center, rack, release_version, rpc_address, schema_version FROM system.peers;
SELECT (text)'Cluster INFO END' AS query_description, toTimestamp(now()) AS current_time FROM system.local;

SELECT (text)'KEYSPACE INFO BEGIN' AS query_description, toTimestamp(now()) AS current_time FROM system.local;
select keyspace_name, replication from system_schema.keyspaces;
SELECT (text)'KEYSPACE INFO END' AS query_description, toTimestamp(now()) AS current_time FROM system.local;

SELECT (text)'CONSISTENCY INFO BEGIN' AS query_description, toTimestamp(now()) AS current_time FROM system.local;
CONSISTENCY;
SELECT (text)'CONSISTENCY INFO END' AS query_description, toTimestamp(now()) AS current_time FROM system.local;

SELECT (text)'TABLE and TTL INFO BEGIN' AS query_description, toTimestamp(now()) AS current_time FROM system.local;
select keyspace_name, table_name, default_time_to_live from system_schema.tables;
SELECT (text)'Table and TTL INFO END' AS query_description, toTimestamp(now()) AS current_time FROM system.local;

SELECT (text)'USERS INFO BEGIN' AS query_description, toTimestamp(now()) AS current_time FROM system.local;
select * from system_auth.roles;
SELECT (text)'USERS INFO END' AS query_description, toTimestamp(now()) AS current_time FROM system.local;

SELECT (text)'VIEWS INFO BEGIN' AS query_description, toTimestamp(now()) AS current_time FROM system.local;
select keyspace_name, view_name, base_table_name, extensions from system_schema.views;
SELECT (text)'VIEWS INFO END' AS query_description, toTimestamp(now()) AS current_time FROM system.local;

SELECT (text)'COMPACTION INFO BEGIN' AS query_description, toTimestamp(now()) AS current_time FROM system.local;
select bytes_in, bytes_out, columnfamily_name, compacted_at, keyspace_name, rows_merged from system.compaction_history;
SELECT (text)'COMPACTION INFO END' AS query_description, toTimestamp(now()) AS current_time FROM system.local;

SELECT (text)'INDEXES INFO BEGIN' AS query_description, toTimestamp(now()) AS current_time FROM system.local;
select * from system_schema.indexes;
SELECT (text)'INDEXES INFO END' AS query_description, toTimestamp(now()) AS current_time FROM system.local;

SELECT (text)'SAI INFO BEGIN' AS query_description, toTimestamp(now()) AS current_time FROM system.local;
SELECT keyspace_name, table_name, index_name, kind FROM system_schema.indexes WHERE kind = 'StorageAttachedIndex' ALLOW FILTERING;
SELECT (text)'SAI INFO END' AS query_description, toTimestamp(now()) AS current_time FROM system.local;
SELECT (text)'COUNTER DATA TYPE INFO BEGIN' AS query_description, toTimestamp(now()) AS current_time FROM system.local;
SELECT keyspace_name, table_name, column_name, type FROM system_schema.columns WHERE type='counter' ALLOW FILTERING;
SELECT (text)'COUNTER DATA TYPE INFO END' AS query_description, toTimestamp(now()) AS current_time FROM system.local;

