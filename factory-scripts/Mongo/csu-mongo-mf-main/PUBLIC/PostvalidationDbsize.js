db.adminCommand({ listDatabases: 1 }).databases.forEach(function (mydb) {
    var dbName = mydb.name;
    if (!["admin", "config", "local"].includes(dbName)) {
        print("Database: " + dbName + " | Size on disk (MB): " + (mydb.sizeOnDisk / (1024 * 1024)).toFixed(2));
    }
});
