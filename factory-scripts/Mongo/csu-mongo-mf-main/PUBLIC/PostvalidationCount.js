db.adminCommand({ listDatabases: 1, nameOnly: true }).databases.forEach(function (mydb) {
    var dbName = mydb.name;
    if (!["admin", "config", "local"].includes(dbName)) {
        var currentDB = db.getSiblingDB(dbName);
        var collections = currentDB.getCollectionNames();
        collections.forEach(function (collName) {
            if (/^system\./.test(collName)) {
                return; // Skip system collections
            }
            // Use count() instead of countDocuments()
            var count = currentDB.getCollection(collName).count();
            print(dbName + "," + collName + "," + count);
        });
    }
});
