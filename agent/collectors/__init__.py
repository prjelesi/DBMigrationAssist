"""Collector factory — returns the right collector for a given role string."""

from collectors.base import BaseCollector
from collectors.sqlserver import SqlServerCollector
from collectors.postgresql import PostgreSQLCollector
from collectors.mysql import MySQLCollector
from collectors.mariadb import MariaDBCollector
from collectors.oracle import OracleCollector
from collectors.mongodb import MongoDBCollector
from collectors.cassandra import CassandraCollector

_REGISTRY: dict[str, type[BaseCollector]] = {
    "sqlserver":  SqlServerCollector,
    "postgresql": PostgreSQLCollector,
    "mysql":      MySQLCollector,
    "mariadb":    MariaDBCollector,
    "oracle":     OracleCollector,
    "mongodb":    MongoDBCollector,
    "cassandra":  CassandraCollector,
}


def get_collector(role: str) -> BaseCollector:
    cls = _REGISTRY.get(role.lower())
    if not cls:
        raise ValueError(f"No collector registered for role '{role}'")
    return cls()
