WHENEVER SQLERROR EXIT SQL.SQLCODE
SET DEFINE OFF

PROMPT Granting read-only Banana Commerce access to ASSESSMENT_READER...

BEGIN
    FOR object_record IN (
        SELECT object_name
          FROM user_objects
         WHERE object_name LIKE 'BANANA_%'
           AND object_type IN ('TABLE', 'VIEW')
    ) LOOP
        EXECUTE IMMEDIATE 'GRANT SELECT ON '
            || DBMS_ASSERT.SIMPLE_SQL_NAME(object_record.object_name)
            || ' TO assessment_reader';
    END LOOP;
END;
/

PROMPT Assessment grants applied.