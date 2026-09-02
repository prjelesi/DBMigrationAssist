WHENEVER OSERROR EXIT FAILURE
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET ECHO ON
SET DEFINE OFF
SET SERVEROUTPUT ON

PROMPT Installing the fictional Banana Commerce database...

@@00-uninstall.sql
@@01-schema.sql
@@02-business-logic.sql
@@03-seed-data.sql
@@04-validation.sql

PROMPT Banana Commerce installation completed successfully.
EXIT SUCCESS