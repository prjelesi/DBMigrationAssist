WHENEVER SQLERROR EXIT SQL.SQLCODE
SET DEFINE OFF
SET SERVEROUTPUT ON

PROMPT Removing an existing Banana Commerce installation when present...

BEGIN
    FOR object_record IN (
        SELECT object_type, object_name
          FROM user_objects
         WHERE object_name LIKE 'BANANA_%'
           AND object_type IN ('VIEW', 'PACKAGE', 'TABLE', 'SEQUENCE')
         ORDER BY CASE object_type
             WHEN 'VIEW' THEN 1
             WHEN 'PACKAGE' THEN 2
             WHEN 'TABLE' THEN 3
             WHEN 'SEQUENCE' THEN 4
             ELSE 5
         END,
         object_name
    ) LOOP
        BEGIN
            IF object_record.object_type = 'TABLE' THEN
                EXECUTE IMMEDIATE 'DROP TABLE ' || DBMS_ASSERT.SIMPLE_SQL_NAME(object_record.object_name)
                    || ' CASCADE CONSTRAINTS PURGE';
            ELSE
                EXECUTE IMMEDIATE 'DROP ' || object_record.object_type || ' '
                    || DBMS_ASSERT.SIMPLE_SQL_NAME(object_record.object_name);
            END IF;
        EXCEPTION
            WHEN OTHERS THEN
                IF SQLCODE NOT IN (-942, -2289, -4043) THEN
                    RAISE;
                END IF;
        END;
    END LOOP;
END;
/

PROMPT Existing Banana Commerce installation removed.