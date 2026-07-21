// Utility: Check if document has $-prefixed fields
function hasDollarFields(doc) {
  for (let key in doc) {
    if (key.startsWith("$")) return true;
    if (typeof doc[key] === "object" && doc[key] !== null) {
      if (hasDollarFields(doc[key])) return true;
    }
  }
  return false;
}

db.getMongo().getDBs().databases.forEach(function (dbInfo) {
  const dbName = dbInfo.name;
  const dbRef = db.getSiblingDB(dbName);
  const excludedDBs = ['admin', 'config', 'local'];

  // 1. Get All Users Information                
  if (excludedDBs.includes(dbName)) return;
  print(`\n** START OF SECTION 1 DATABASE: ${dbName} : User Information`);
  try {
    const dbRef = db.getSiblingDB(dbName);

    // Show users
    const users = dbRef.getUsers();
    print(`\nUsers in ${dbName}:`);
    printjson(users);

    // Show roles
    const roles = dbRef.getRoles({ showBuiltinRoles: false });
    print(`\nCustom Roles in ${dbName}:`);
    printjson(roles);

  } catch (e) {
    print(`\n** ERROR SECTION 1 : ${dbName} ➤ ${e}`);
  }
  print(`\n** END OF SECTION 1 DATABASE: ${dbName} : User Information`);

  // 2. Capped & Time-Series Collections
  print(`\n** START OF SECTION 2 DATABASE: ${dbName} : Capped & Time-Series Collections`);
  try {
    dbRef.getCollectionInfos({}).forEach(function (coll) {
      const name = coll.name;
      const options = coll.options || {};
      if (options.capped) {
        print(`** CAPPED,${dbName},${name}`);
      }
      if (options.timeseries) {
        print(`** TIME-SERIES,${dbName},${name}, TimeField: ${options.timeseries.timeField}`);
      }
    });
  } catch (e) {
    print(`** Error SECTION 2 : ${e}`);
  }
  print(`\n** END OF SECTION 2 DATABASE: ${dbName} : Capped & Time-Series Collections`);

  // 3. Documents with $-prefixed fields
  print(`\n** START OF SECTION 3 DATABASE: ${dbName} : Documents with $-prefixed Fields`);
  try {
    dbRef.getCollectionNames().forEach(function (coll) {
      try {
        const cursor = dbRef.getCollection(collName).find({}).limit(100);
        cursor.forEach(doc => {
          if (hasDollarFields(doc)) {
            print(`** $-FIELD, ${dbName},${collName},${doc._id}`);
          }
        });
      } catch (err) {
        print(`** Error SECTION 3 ${collName} due to error: ${err}`);
      }
    });
  } catch (e) {
    print(`** Error SECTION 3 : ${e}`);
  }
  print(`\n** END OF SECTION 3 DATABASE: ${dbName} : Documents with $-prefixed Fields`);

  // 4. Queryable Encryption
  print(`\n** START OF SECTION 4 DATABASE: ${dbName} : Queryable Encryption Enabled Collections`);
  try {
    dbRef.getCollectionInfos({}).forEach(function (coll) {
      if (coll.options?.encryptedFields) {
        print(`** QE ENABLED,${dbName},${coll.name}`);
        printjson(coll.options.encryptedFields);
      }
    });
  } catch (e) {
    print(`** Error SECTION 4 : ${e}`);
  }
  print(`\n** END OF SECTION 4 DATABASE: ${dbName} : Queryable Encryption Enabled Collections`);

  // 5. Mixed Unique and Non-Unique Indexes
  print(`\n** START OF SECTION 5 DATABASE: ${dbName} : Mixed Unique and Non-Unique Indexes`);
  try {
    dbRef.getCollectionInfos({ type: "collection" }).forEach(function (coll) {
      const collName = coll.name;
      try {
        const indexMap = {};
        const indexes = dbRef.getCollection(collName).getIndexes();
        indexes.forEach(idx => {
          const keyStr = JSON.stringify(idx.key);
          indexMap[keyStr] = indexMap[keyStr] || [];
          indexMap[keyStr].push({ name: idx.name, unique: !!idx.unique });
        });

        for (let key in indexMap) {
          const defs = indexMap[key];
          const hasUnique = defs.some(d => d.unique);
          const hasNonUnique = defs.some(d => !d.unique);
          if (defs.length > 1 && hasUnique && hasNonUnique) {
            print(`** MIXED INDEX, ${dbName},${collName},${key}`);
            printjson(defs);
          }
        }
      } catch (e) {
        print(`** Error reading indexes from ${collName}: ${e}`);
      }
    });
  } catch (e) {
    print(`** Error SECTION 5: ${e}`);
  }
  print(`\n** END OF SECTION 5 DATABASE: ${dbName} : Mixed Unique and Non-Unique Indexes`);

  // 6. Documents with empty timestamps
  print(`\n** START OF SECTION 6 DATABASE: ${dbName} : Empty Timestamp Documents`);
  try {
    dbRef.getCollectionInfos({ type: "collection" }).forEach(function (coll) {
      const collName = coll.name;
      try {
        const count = dbRef.getCollection(collName).countDocuments({
          timestamp: { $in: [null, "", {}] }
        });

        if (count > 0) {
          print(`** EMPTY-TIMESTAMP-PRE6.0,${dbName},${collName},${count}`);
        }
      } catch (err) {
        print(`** Error scanning ${collName} for timestamps: ${err}`);
      }
    });
  } catch (e) {
    print(`** Error SECTION 6: ${e}`);
  }
  print(`\n** END OF SECTION 6 DATABASE: ${dbName} : Empty Timestamp Documents`);

  // 7. Clustered collections with expireAfterSeconds
  print(`\n** START OF SECTION 7 DATABASE: ${dbName} : Clustered Collections with expireAfterSeconds`);
  try {
    dbRef.getCollectionInfos({}).forEach(function (coll) {
      if (coll.options?.clusteredIndex && coll.options.expireAfterSeconds) {
        print(`** EXPIRY-AFTER-SECONDS,${dbName},${coll.name},${coll.options.expireAfterSeconds}`);
      }
    });
  } catch (e) {
    print(`** Error SECTION 7 : ${e}`);
  }
  print(`\n** END OF SECTION 7 DATABASE: ${dbName} : Clustered Collections with expireAfterSeconds`);

  if (excludedDBs.includes(dbName)) return;
  print(`\n** START OF SECTION 8 DATABASE: ${dbName} : Non-Default Collations Information`);
  try {
      dbRef.getCollectionNames().forEach(function(collName) {
      dbRef.getCollection(collName).getIndexes().forEach(function(index) {
        if (index.collation) {
          print("** NON-DEFAULT-COLLATION," + dbName + "," + collName + "," + index.name);
        }
      });
    });
  } catch (e) {
    print(`\n** ERROR SECTION 8: ${dbName} ➤ ${e}`);
  }
  print(`\n** END OF SECTION 8 DATABASE: ${dbName} : Non-Default Collations Information`);

  if (excludedDBs.includes(dbName)) return;
  print(`\n** START OF SECTION 9 DATABASE: ${dbName} : Hash Indexes Collations Information`);
  try {
     dbRef.getCollectionNames().forEach(function(collName) {
     dbRef.getCollection(collName).getIndexes().forEach(function(index) {
       if (Object.values(index.key).includes("hashed")) {
         print("** HASH-INDEX," + collName + "," + index.name);
       }
     });
   });
  } catch (e) {
    print(`\n** ERROR SECTION 9: ${dbName} ➤ ${e}`);
  }
  print(`\n** END OF SECTION 9 DATABASE: ${dbName} : Hash Indexes Collations Information`);


  if (excludedDBs.includes(dbName)) return;
  print(`\n** START OF SECTION 10 DATABASE: ${dbName} : identity type of _id Information`);
  try {
     dbRef.getCollectionNames().forEach(function(coll) {
     var count = -1
     count = dbRef.getCollection(coll).countDocuments( { "_id" : { $type : 7 } } )
     if (count > 0) {
         print("** ID-CHECKER-ObjectId," + dbName + "," + coll + "," + count);
     }
     count = dbRef.getCollection(coll).countDocuments( { "_id" : { $type : 1 } } )
     if (count > 0) {
         print("** ID-CHECKER-Double," + dbName + "," + coll + "," + count);
     }
     count = dbRef.getCollection(coll).countDocuments( { "_id" : { $type : 2 } } )
     if (count > 0) {
         print("** ID-CHECKER-String," + dbName + "," + coll + "," + count);
     }
     count = dbRef.getCollection(coll).countDocuments( { "_id" : { $type : 3 } } )
     if (count > 0) {
         print("** ID-CHECKER-Object," + dbName + "," + coll + "," + count);
     }
     count = dbRef.getCollection(coll).countDocuments( { "_id" : { $type : 5 } } )
     if (count > 0) {
         print("** ID-CHECKER-Bindata," + dbName + "," + coll + "," + count);
     }
     count = dbRef.getCollection(coll).countDocuments( { "_id" : { $type : 6 } } )
     if (count > 0) {
         print("** ID-CHECKER-Undefined," + dbName + "," + coll + "," + count);
     }
     count = dbRef.getCollection(coll).countDocuments( { "_id" : { $type : 8 } } )
     if (count > 0) {
         print("** ID-CHECKER-Boolean," + dbName + "," + coll + "," + count);
     }
     count = dbRef.getCollection(coll).countDocuments( { "_id" : { $type : 9 } } )
     if (count > 0) {
         print("** ID-CHECKER-Date," + dbName + "," + coll + "," + count);
     }
     count = dbRef.getCollection(coll).countDocuments( { "_id" : { $type : 10 } } )
     if (count > 0) {
         print("** ID-CHECKER-Null," + dbName + "," + coll + "," + count);
     }
     count = dbRef.getCollection(coll).countDocuments( { "_id" : { $type : 11 } } )
     if (count > 0) {
         print("** ID-CHECKER-Regexp," + dbName + "," + coll + "," + count);
     }
     count = dbRef.getCollection(coll).countDocuments( { "_id" : { $type : 12 } } )
     if (count > 0) {
         print("** ID-CHECKER-DBPointer," + dbName + "," + coll + "," + count);
     }
     count = dbRef.getCollection(coll).countDocuments( { "_id" : { $type : 13 } } )
     if (count > 0) {
         print("** ID-CHECKER-Javascript," + dbName + "," + coll + "," + count);
     }
     count = dbRef.getCollection(coll).countDocuments( { "_id" : { $type : 14 } } )
     if (count > 0) {
         print("** ID-CHECKER-Symbol," + dbName + "," + coll + "," + count);
     }
     count = dbRef.getCollection(coll).countDocuments( { "_id" : { $type : 15 } } )
     if (count > 0) {
         print("** ID-CHECKER-Javascriptcode," + dbName + "," + coll + "," + count);
     }
     count = dbRef.getCollection(coll).countDocuments( { "_id" : { $type : 16 } } )
     if (count > 0) {
         print("** ID-CHECKER-32bitint," + dbName + "," + coll + "," + count);
     }
     count = dbRef.getCollection(coll).countDocuments( { "_id" : { $type : 18 } } )
     if (count > 0) {
         print("** ID-CHECKER-64bitint," + dbName + "," + coll + "," + count);
     }
     count = dbRef.getCollection(coll).countDocuments( { "_id" : { $type : 19 } } )
     if (count > 0) {
         print("** ID-CHECKER-Decimal128," + dbName + "," + coll + "," + count);
     }
     count = dbRef.getCollection(coll).countDocuments( { "_id" : { $type : -1 } } )
     if (count > 0) {
         print("** ID-CHECKER-Minkey," + dbName + "," + coll + "," + count);
     }
     count = dbRef.getCollection(coll).countDocuments( { "_id" : { $type : 127 } } )
     if (count > 0) {
         print("** ID-CHECKER-Maxkey," + dbName + "," + coll + "," + count);
     }
   });
  } catch (e) {
    print(`\n** ERROR SECTION 10: ${dbName} ➤ ${e}`);
  }
  print(`\n** END OF SECTION 10 DATABASE: ${dbName} : identity type of _id Information`);

  print(`============================== END DB: ${dbName} ==============================\n`);
});
