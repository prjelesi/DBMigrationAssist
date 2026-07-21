#!/bin/ksh

###############################################################################
# PG-MIGRATE-KSH.sh
# Purpose : Migrate / prepare PostgreSQL DBs for migration - KSH version
# Author  : Akli IMARAZENE
# Version : 1.1
###############################################################################

# ---- Helpers ---------------------------------------------------------------

exit_script() {
  echo "\n- Ending Execution"
  unset PGPASSWORD
  exit 0
}

# Colors
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
RESET="\033[0m"

# Trim function (CORRECTED)
Trim() {
    echo "$1" | sed 's/^[ \t]//;s/[ \t]$//'
}

mkdir_if_missing() {
    dir="$1"
    mkdir -p "$dir" 2>/tmp/mkdir_error.$$

    if [ $? -ne 0 ]; then
        err_msg=$(cat /tmp/mkdir_error.$$)
        print "${RED}ERROR: Failed to create directory '$dir'${RESET}"
        print "${RED}$err_msg${RESET}"
        rm -f /tmp/mkdir_error.$$
        exit 1
    fi

    rm -f /tmp/mkdir_error.$$

    if [ ! -d "$dir" ]; then
        print "${RED}ERROR: Directory '$dir' does not exist after creation attempt.${RESET}"
        exit 1
    fi

    print "${GREEN}SUCCESS: Directory '$dir' created.${RESET}"
}

psql_exec() {
  db="$1"
  sql="$2"
  PGPASSWORD="$PGPASSWORD" psql -h "$PGHOST" -p "$PGPORT" \
      -U "$PGUSER" -d "$db" -t -A -F '|' -c "$sql" 2>/dev/null
}

timestamp() { date "+%Y-%m-%d_%H-%M-%S"; }


# ---- Banner ----------------------------------------------------------------

clear
echo ""
echo "==============================================================="
echo "\033[37;45m Welcome to Factory - PG_info_Gathering_Automation (KSH) \033[0m"
echo "\033[37;45m      (PostgreSQL DB Migration Factory)                \033[0m"
echo "==============================================================="
echo ""

Yprint() { echo "\n${YELLOW}$@${RESET}"; }
Gprint() { echo "\n${GREEN}$@${RESET}"; }
Rprint() { echo "\n${RED}$@${RESET}"; }


echo "\nScript executed: $0\n"
Yprint "Check prerequisites..."

# Check psql
if command -v psql >/dev/null 2>&1 ; then
  echo "[psql] Found : $(command -v psql)"
  PV=$(psql -V)
  echo "[PSQL version] : [$PV]"
else
  echo "${RED}ERROR: psql not found in PATH.${RESET}"
  exit 1
fi

echo "\n-------------------------------------------------------\n"

# ---- Connection parameters --------------------------------------------------

PGHOST_DEFAULT="localhost"
PGPORT_DEFAULT="5432"
DEFAULT_WORKDIR="C:/OUTPUT"

read_host() {
  echo -n "Enter PostgreSQL host [${PGHOST_DEFAULT}]: "
  read PGHOST
  PGHOST=$(Trim "${PGHOST:-$PGHOST_DEFAULT}")

  echo -n "Enter PostgreSQL port [${PGPORT_DEFAULT}]: "
  read PGPORT

  PGPORT=$(Trim "${PGPORT:-$PGPORT_DEFAULT}")

  echo -n "Enter PostgreSQL user [${PGUSER_DEFAULT}]: "
  read PGUSER
  PGUSER=$(Trim "${PGUSER:-$PGUSER_DEFAULT}")


  
 
if [[ -z "$PGUSER" ]]; then
    while : ; do
        echo -n "Postgres  username is mandatory: "
        read PGUSER
        if [[ -z "$PGUSER" ]]; then
            echo "${RED}Error:Postgres username is mandatory.${RESET}"
        else
            break
        fi
    done
fi

echo -n "Enter PostgreSQL user Password [${PGPASSWORD_DEFAULT}]: "
         stty -echo 
        read    PGPASSWORD
        stty  echo
        echo 
  PGPASSWORD=$(Trim "${PGPASSWORD:-$PGPASSWORD_DEFAULT}")
 

if [[ -z "$PGPASSWORD" ]]; then
    while : ; do
        echo -n "Password is mandatory: "
        stty -echo 
        read    PGPASSWORD
        stty  echo
        echo 
        if [[ -z "$PGPASSWORD" ]]; then
            echo "${RED}Error: Password is mandatory.${RESET}"
        else
            break
        fi
    done
fi  
}

read_host

 
 
# Force password entry if empty


# ---- Retrieve databases -----------------------------------------------------
Yprint "Trying connection ..."

# ==============================
# Étape 1 - tenter connexion sans base
# ==============================

ERR=$(PGPASSWORD="$PGPASSWORD" psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" 2>&1 </dev/null)

# Extraction du nom de la base indiquée par l’erreur
DB_GUESS=$(echo "$ERR" | sed -n 's/.database "\(.\)" does not exist.*/\1/p')

# ==============================
# Étape 2 - bases candidates
# ==============================

CANDIDATES=""

# Ajouter la base devinée si trouvée
[ -n "$DB_GUESS" ] && CANDIDATES="$CANDIDATES $DB_GUESS"

# Bases universelles (si existent)
CANDIDATES="$CANDIDATES postgres template1 template0"

# Ajouter une base portant le nom de l’utilisateur
CANDIDATES="$CANDIDATES $PGUSER"

 

# ==============================
# Étape 3 - Test de toutes les bases candidates
# ==============================

FOUND_DB=""
for DB in $CANDIDATES ; do
 
    DBS=$(PGPASSWORD="$PGPASSWORD" psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" \
          -d "$DB" -t -A -c "SELECT datname FROM pg_database 
                             WHERE datistemplate = false AND datallowconn = true;" 2>/dev/null)

    if [ $? -eq 0 ] ; then
        FOUND_DB="$DB"
        break
    fi
done

if [ -z "$FOUND_DB" ] ; then
    Yprint "ERROR: Erro getting db connection ."
    exit 1
fi

# ==============================
# Étape 4 - Affichage des bases accessibles
# ==============================

Gprint "✔ Connection Successfully"
Yprint "Available Databases:"
echo "$DBS"

 # ---- SELECT DATABASES WITH LOOP + ERROR IF NOT VALID (ROBUST VERSION) ----

normalize_list() {
    echo "$1" \
        | tr ',' ' ' \
        | tr -s ' ' \
        | sed 's/^ *//;s/ *$//'
}

list_contains() {
    printf "%s\n" "$DBS" | grep -Fxq "$1"
}

unique_list() {
    for w in $@; do
        printf "%s\n" "$w"
    done | sort -u
}

while : ; do
    echo -n "Enter database list (comma/space separated), * for all, or 0 to exit: "
    read DBLIST

    DBLIST=$(Trim "$DBLIST")

    [[ "$DBLIST" = "0" ]] && exit_script

    # All DBs
    if [[ -z "$DBLIST" || "$DBLIST" = "*" ]]; then
        databases="$DBS"
        break
    fi

    # Normalize
    DBLIST=$(normalize_list "$DBLIST")

    # Split into words
    INPUT_DBS=$DBLIST

    databases=""
    all_valid=true
    invalid_db_list=""

    for db in $INPUT_DBS; do
        if list_contains "$db"; then
            databases="$databases $db"
        else
            echo "${RED}ERROR: Database '$db' does not exist.${RESET}"
            invalid_db_list="$invalid_db_list $db"
            all_valid=false
        fi
    done

    if [[ "$all_valid" = false ]]; then
        echo "${YELLOW}Please choose valid database names or 0 to exit.${RESET}"
        echo "Valid DBs are:"
        printf "%s\n" "$DBS" | sed 's/^/ - /'
        continue
    fi

    # Deduplicate
    databases=$(unique_list $databases)

    break
done

Gprint "Databases selected:"
for d in $databases; do
    echo " - $d"
done


 
 # ---- Working Directory ------------------------------------------------------

# Détection OS pour définir le répertoire par défaut
if [[ "$OS" == "Windows_NT" ]]; then
    DEFAULT_WORKDIR="C:/OUTPUT"
else
    DEFAULT_WORKDIR="$HOME/output"
fi
 
echo ""
while : ; do
  echo -n "Please Enter working directory for scripts generation, default:[$DEFAULT_WORKDIR], 0 to exit"
  read WORKDIR
  WORKDIR=$(Trim "$WORKDIR")

  [[ "$WORKDIR" = "0" ]] && exit_script

  # Si vide → utiliser default
  if [[ -z "$WORKDIR" ]]; then
      WORKDIR="$DEFAULT_WORKDIR"
  fi

  # Vérifier si dossier existe
  if [[ ! -d "$WORKDIR" ]]; then
      while : ; do
          echo -n "Directory [$WORKDIR] does not exist. Create it? (Y/N) [Y]: "
          read create_ans
          case "$create_ans" in
              ""|Y|y)
                  mkdir_if_missing "$WORKDIR"
                  break 2
                  ;;
              N|n)
                  echo "Enter another directory."
                  continue 2
                  ;;
              0)
                  exit_script
                  ;;
              *)
                  echo "Invalid choice. Please enter Y or N (or 0 to exit)."
                  ;;
          esac
      done
  else
      break
  fi
done

Gprint "Working directory & Script will be generated in [$WORKDIR]"

# ---- Create Subdirectories --------------------------------------------------

mkdir_if_missing "$WORKDIR/FK"
mkdir_if_missing "$WORKDIR/FK/LOG"
mkdir_if_missing "$WORKDIR/TRIGGERS"
mkdir_if_missing "$WORKDIR/TRIGGERS/LOG"
mkdir_if_missing "$WORKDIR/TABLES"
mkdir_if_missing "$WORKDIR/TABLES/LOG"

# ---- End of initial setup --------------------------------------------------

Gprint "Initial setup completed successfully."


show_menu() {
  echo "\nPlease select the assessment operation to perform"
  echo "================================================"
  echo "GenerateSQL Cleanup:"
  echo "  11. Drop FK"
  echo "  12. Disable Triggers"
  echo "  13. Cleanup Tables (TRUNCATE)"
  echo "Run Pre-Migration:"
  echo "  21. Drop FK"
  echo "  22. Disable Triggers"
  echo "  23. Cleanup Tables (TRUNCATE)"
  echo "Run Post-Migration:"
  echo "  31. Create/Enable FK"
  echo "  32. Enable Triggers"
  echo "4. Validate Pre/Post-Migration Log Files"
  echo "5. Databases inventory (FK/ TRIGGERS/TABLES)"
  echo "6. Execute SQL Script"
  echo "0. Exit"
  echo "------------------------------------------------"
}

VALID_CHOICES="0 11 12 13 21 22 23 31 32 4 5 6"


read_choices() {
  while : ; do
    Yprint "Please enter choice(s) (e.g., 11 12 13) or 0 to Exit: "
    read INPUT
    # Convertir virgules en espaces et supprimer espaces superflus
    INPUT=$(echo "$INPUT" | tr ',' ' ' | awk '{$1=$1;print}')

    [[ -z "$INPUT" ]] && Rprint "No selection. Try again." && continue

    # Vérifier toutes les entrées et collecter invalides
    INVALID=""
    for c in $INPUT; do
      echo "$VALID_CHOICES" | tr ' ' '\n' | grep -Fxq "$c" || INVALID="$INVALID $c"
    done

    if [[ -z "$INVALID" ]]; then
      CHOICES="$INPUT"
      break
    else
      Rprint "Invalid choice(s):$INVALID"
      Yprint "Please enter only valid choice(s) from the list."
    fi
  done
}
show_menu;
 read_choices;
Gprint""
Gprint "---------------------------------------------------------"

 
Gprint " Selected actions: "
  for c in $CHOICES; do
    case "$c" in
      11) print "[11] Generate Drop FK scripts..." ;;
      12) print "[12] Disable Triggers..." ;;
      13) print "[13] Cleanup Tables..." ;;
      21) print "[21] Pre-Migration Drop FK..." ;;
      22) print "[22] Pre-Migration Disable Triggers..." ;;
      23) print "[23] Pre-Migration Cleanup Tables..." ;;
      31) print "[31] Post-Migration Create/Enable FK..." ;;
      32) print "[32] Post-Migration Enable Triggers..." ;;
      4)  print "[4] Validate Log Files..." ;;
      5)  print "[5] Database inventory..." ;;
      6)  print "[6] Execute SQL Script..." ;;
      0)  exit_script ;;
    esac
  done


Gprint "---------------------------------------------------------"
Gprint""
  # Colors
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
WHITE="\033[37m"
RESET="\033[0m"

 

  for sel in $CHOICES; do
    case $sel in

      0)
        exit_script
        ;;



11)
  echo -e "${GREEN}    -----------------------   ${RESET}"
  echo -e "${GREEN} [11] GenerateSQL Cleanup for Foreign Keys ...${RESET}\n"

  for db in $databases; do
    fkfile="$WORKDIR/FK/DropFKs_${db}.sql"
    createfile="$WORKDIR/FK/CreateFKs_${db}.sql"
    fk_drop_log="$WORKDIR/FK/LOG/DropFKs_${db}.log"
    fk_create_log="$WORKDIR/FK/LOG/CreateFKs_${db}.log"

    echo -e "${GREEN}Generating FK scripts for database '$db'...${RESET}"

    sql_fk_query="
select kcu.table_schema || '|' || kcu.table_name || '|' || kcu.constraint_name || '|' ||
       string_agg(kcu.column_name, ', ' order by kcu.ordinal_position) || '|' ||
       string_agg(rel_kcu.column_name, ', ' order by rel_kcu.ordinal_position) || '|' ||
       rel_kcu.table_schema || '|' || rel_kcu.table_name
from information_schema.table_constraints tco
join information_schema.key_column_usage kcu
          on tco.constraint_schema = kcu.constraint_schema
          and tco.constraint_name = kcu.constraint_name
join information_schema.referential_constraints rco
          on tco.constraint_schema = rco.constraint_schema
          and tco.constraint_name = rco.constraint_name
join information_schema.key_column_usage rel_kcu
          on rco.unique_constraint_schema = rel_kcu.constraint_schema
          and rco.unique_constraint_name = rel_kcu.constraint_name
          and kcu.ordinal_position = rel_kcu.ordinal_position
where tco.constraint_type = 'FOREIGN KEY'
group by kcu.table_schema, kcu.table_name, kcu.constraint_name,
         rel_kcu.table_schema, rel_kcu.table_name
order by kcu.table_schema, kcu.table_name, kcu.constraint_name;
"

    fk_rows=$(psql_exec "$db" "$sql_fk_query")
    drop_sql=""
    create_sql=""
    fk_count=0
    fk_detail_log=""

    if [ -z "$fk_rows" ]; then
      # Aucun FK trouvé : générer fichiers vides avec commentaire
      echo "-- No foreign keys found in database '$db'" > "$fkfile"
      echo "-- No foreign keys found in database '$db'" > "$createfile"
      echo "FK scripts generated on $(timestamp)" > "$fk_drop_log"
      echo "Database: $db" >> "$fk_drop_log"
      echo "No foreign keys found" >> "$fk_drop_log"
      echo "Drop FK script file: $fkfile" >> "$fk_drop_log"
      echo "FK scripts generated on $(timestamp)" > "$fk_create_log"
      echo "Database: $db" >> "$fk_create_log"
      echo "No foreign keys found" >> "$fk_create_log"
      echo "Create FK script file: $createfile" >> "$fk_create_log"

      echo -e "${YELLOW}No user-defined foreign keys found in database '$db'.${RESET}\n"
      continue
    fi

    # Construire DROP/CREATE SQL et log détaillé
    while IFS='|' read -r schema parent_table conname parent_cols ref_cols ref_schema ref_table; do
      drop_sql="${drop_sql}ALTER TABLE \"${schema}\".\"${parent_table}\" DROP CONSTRAINT IF EXISTS \"${conname}\";\n"
      create_sql="${create_sql}ALTER TABLE \"${schema}\".\"${parent_table}\" ADD CONSTRAINT \"${conname}\" FOREIGN KEY (${parent_cols}) REFERENCES \"${ref_schema}\".\"${ref_table}\" (${ref_cols});\n"
      fk_detail_log="${fk_detail_log}Constraint: ${conname}, Table: ${schema}.${parent_table} -> ${ref_schema}.${ref_table}, Columns: ${parent_cols} -> ${ref_cols}\n"
      fk_count=$((fk_count + 1))
    done <<EOF
$fk_rows
EOF

    # Écriture fichiers DROP/CREATE
    echo "BEGIN;" > "$fkfile"
    echo -e "$drop_sql" >> "$fkfile"
    echo "COMMIT;" >> "$fkfile"

    echo "BEGIN;" > "$createfile"
    echo -e "$create_sql" >> "$createfile"
    echo "COMMIT;" >> "$createfile"

    # Logs avec détails des FK
    echo "FK scripts generated on $(timestamp)" > "$fk_drop_log"
    echo "Database: $db" >> "$fk_drop_log"
    echo "Number of FKs: $fk_count" >> "$fk_drop_log"
    echo -e "$fk_detail_log" >> "$fk_drop_log"
    echo "Drop FK script file: $fkfile" >> "$fk_drop_log"

    echo "FK scripts generated on $(timestamp)" > "$fk_create_log"
    echo "Database: $db" >> "$fk_create_log"
    echo "Number of FKs: $fk_count" >> "$fk_create_log"
    echo -e "$fk_detail_log" >> "$fk_create_log"
    echo "Create FK script file: $createfile" >> "$fk_create_log"

    echo -e "${BLUE}Number of foreign keys found in database '$db': $fk_count${RESET}"
    echo "Drop FK script saved: $fkfile"
    echo "Drop FK log saved: $fk_drop_log"
    echo "Create FK script saved: $createfile"
    echo "Create FK log saved: $fk_create_log"
    echo
  done
  ;;
  
   12)
  echo -e "${GREEN}    -----------------------   ${RESET}"
  echo -e "${GREEN} [12] GenerateSQL Cleanup for Triggers ...${RESET}\n"

  for db in $databases; do
    disable_file="$WORKDIR/TRIGGERS/DisableTriggers_${db}.sql"
    enable_file="$WORKDIR/TRIGGERS/EnableTriggers_${db}.sql"
    disable_log="$WORKDIR/TRIGGERS/LOG/DisableTriggers_${db}.log"
    enable_log="$WORKDIR/TRIGGERS/LOG/EnableTriggers_${db}.log"

    echo -e "${GREEN}Processing database '$db'...${RESET}"

    sql_triggers="
SELECT DISTINCT ON (ist.event_object_schema, ist.event_object_table, ist.trigger_name)
    ist.event_object_schema || '|' ||
    ist.event_object_table  || '|' ||
    ist.trigger_name        || '|' ||
    CASE t.tgenabled
        WHEN 'O' THEN 'ENABLED'
        WHEN 'D' THEN 'DISABLED'
        WHEN 'R' THEN 'REPLICA'
        WHEN 'A' THEN 'ALWAYS'
    END AS status
FROM information_schema.triggers ist
JOIN pg_trigger t 
    ON t.tgname = ist.trigger_name
JOIN pg_class c
    ON c.relname = ist.event_object_table
    AND c.oid = t.tgrelid
WHERE NOT t.tgisinternal
ORDER BY 
    ist.event_object_schema,
    ist.event_object_table,
    ist.trigger_name;
"

    trigger_rows=$(psql_exec "$db" "$sql_triggers")
    if [ -z "$trigger_rows" ]; then
      echo "-- No triggers found in database '$db'" > "$disable_file"
      echo "-- No triggers found in database '$db'" > "$enable_file"
      echo -e "${YELLOW}No triggers found in database '$db'.${RESET}\n"
      continue
    fi

    disable_sql=""
    enable_sql=""
    trigger_detail_log=""
    count_enabled=0
    count_disabled=0

    enabled_list=""
    disabled_list=""

    while IFS='|' read -r schema table trigger status; do
      # Génération des commandes SQL
      disable_sql="${disable_sql}ALTER TABLE \"${schema}\".\"${table}\" DISABLE TRIGGER \"${trigger}\";\n"
      enable_sql="${enable_sql}ALTER TABLE \"${schema}\".\"${table}\" ENABLE TRIGGER \"${trigger}\";\n"

      # Statistiques
      if [[ "$status" == "ENABLED" ]]; then
          count_enabled=$((count_enabled + 1))
          enabled_list="${enabled_list}${schema}.${table}.${trigger}\n"
      elif [[ "$status" == "DISABLED" ]]; then
          count_disabled=$((count_disabled + 1))
          disabled_list="${disabled_list}${schema}.${table}.${trigger}\n"
      fi

      trigger_detail_log="${trigger_detail_log}${schema}.${table}.${trigger} - ${status}\n"

    done <<EOF
$trigger_rows
EOF

    total_triggers=$((count_enabled + count_disabled))

    #
    # Écriture fichiers Disable/Enable
    #
    echo "BEGIN;" > "$disable_file"
    echo -e "$disable_sql" >> "$disable_file"
    echo "COMMIT;" >> "$disable_file"

    echo "BEGIN;" > "$enable_file"
    echo -e "$enable_sql" >> "$enable_file"
    echo "COMMIT;" >> "$enable_file"

    #
    # Logs détaillés
    #
    {
      echo "Trigger analysis for database: $db"
      echo "Generated: $(timestamp)"
      echo
      echo "Total triggers     : $total_triggers"
      echo "Enabled triggers   : $count_enabled"
      echo "Disabled triggers  : $count_disabled"
      echo
      echo "------ ENABLED TRIGGERS ------"
      if [ -n "$enabled_list" ]; then echo -e "$enabled_list"; else echo "(none)"; fi
      echo
      echo "------ DISABLED TRIGGERS ------"
      if [ -n "$disabled_list" ]; then echo -e "$disabled_list"; else echo "(none)"; fi
      echo
      echo "Disable script file: $disable_file"
    } > "$disable_log"

    cp "$disable_log" "$enable_log"

    #
    # Affichage terminal
    #
    echo -e "${BLUE}Database: $db${RESET}"
    echo -e "  Total triggers   : ${GREEN}$total_triggers${RESET}"
    echo -e "  Enabled          : ${GREEN}$count_enabled${RESET}"
    echo -e "  Disabled         : ${YELLOW}$count_disabled${RESET}"
    echo "Disable trigger script saved: $disable_file"
    echo "Enable trigger script saved: $enable_file"
    echo "Logs saved:"
    echo "  $disable_log"
    echo "  $enable_log"
    echo
  done

  echo -e "All Trigger scripts and logs generated in: $WORKDIR/TRIGGERS "
  ;;

 # ----------------------- BLOCK 13 -----------------------
13)
echo -e "${GREEN}    -----------------------   ${RESET}"
echo -e "${GREEN} [13] Generate SQL scripts for TRUNCATE TABLE (scan per table)...${RESET}\n"

mkdir -p "$WORKDIR/TRUNCATE/LOG"
mkdir -p "$WORKDIR/TRUNCATE/SUMMARY"

for db in $databases; do
    truncate_file="$WORKDIR/TRUNCATE/TruncateTables_${db}.sql"
    truncate_log="$WORKDIR/TRUNCATE/LOG/TruncateTables_${db}.log"

    echo -e "${GREEN}Processing database '$db' for script generation...${RESET}"

    # Récupérer toutes les tables utilisateur
    sql_tables="
SELECT table_schema || '|' || table_name AS tbl
FROM information_schema.tables
WHERE table_schema NOT IN ('pg_catalog','information_schema')
  AND table_type='BASE TABLE'
ORDER BY table_schema, table_name;
"

    table_rows=$(psql_exec "$db" "$sql_tables" "-t -A")

    if [ -z "$table_rows" ]; then
        echo "-- No tables found in database '$db'" > "$truncate_file"
        echo "No tables found in database." > "$truncate_log"
        echo -e "${YELLOW}No tables found in database '$db'.${RESET}"
        continue
    fi

    total_tables=0
    truncate_list=""
    log_empty=""
    log_non_empty=""

    while IFS='|' read -r schema table; do
        total_tables=$((total_tables+1))
        row_count=$(psql_exec "$db" "SELECT COUNT(*) FROM \"${schema}\".\"${table}\";" "-t -A")
        row_count=${row_count:-0}

        log_entry="${schema}.${table} : ${row_count} rows"

        if [ "$row_count" -eq 0 ]; then
            log_empty="${log_empty}${log_entry}\n"
        else
            log_non_empty="${log_non_empty}${log_entry}\n"
        fi

        truncate_list="${truncate_list}\"${schema}\".\"${table}\", "
    done <<< "$table_rows"

    # Nettoyer la liste TRUNCATE
    truncate_list=$(echo "$truncate_list" | sed 's/, $//')

    # Générer le script TRUNCATE pour toutes les tables
    if [ -n "$truncate_list" ]; then
        echo "BEGIN;" > "$truncate_file"
        echo "TRUNCATE TABLE $truncate_list RESTART IDENTITY CASCADE;" >> "$truncate_file"
        echo "COMMIT;" >> "$truncate_file"
    else
        echo "-- No tables to truncate" > "$truncate_file"
    fi

    # Générer le log détaillé
    {
        echo "TRUNCATE script generated on $(timestamp)"
        echo "Database: $db"
        echo "-----------------------------------------"
        echo "Total tables: $total_tables"
        echo "Empty tables:"
        echo -e "$log_empty"
        echo "Non-empty tables:"
        echo -e "$log_non_empty"
        echo "Generated script: $truncate_file"
    } > "$truncate_log"

    # Affichage utilisateur
    echo -e "${BLUE}Total tables      : $total_tables${RESET}"
    echo -e "${BLUE}Tables empty      : $(echo -e "$log_empty" | grep -c ':')${RESET}"
    echo -e "${BLUE}Tables non-empty  : $(echo -e "$log_non_empty" | grep -c ':')${RESET}"
    echo -e "${BLUE}SQL script        : $truncate_file${RESET}"
    echo -e "${BLUE}Log file          : $truncate_log${RESET}"
    echo
done

echo -e "${GREEN}All TRUNCATE scripts and logs generated in: $WORKDIR/TRUNCATE${RESET}"
;;



  
21)
  echo -e "${GREEN}    -----------------------   ${RESET}"
  echo -e "${GREEN}Pre-Migration: Drop Foreign Keys${RESET}\n"

  mkdir -p "$WORKDIR/FK/LOG"

  for db in $databases; do
    fk_script="$WORKDIR/FK/DropFKs_${db}.sql"
    fk_log="$WORKDIR/FK/LOG/DropFKs_Execution_${db}.log"

    echo -e "${YELLOW}Processing database '$db'...${RESET}"

    if [ ! -f "$fk_script" ]; then
      echo -e "${RED}FK script not found: $fk_script${RESET}"
      echo "Skipping database '$db'."
      continue
    fi

    # Nombre de FK avant exécution
    fk_before=$(psql_exec "$db" "SELECT COUNT(*) FROM information_schema.table_constraints WHERE constraint_type='FOREIGN KEY';" "-t -A" | tr -d '[:space:]')
    fk_before=${fk_before:-0}
    echo "Foreign keys before execution: $fk_before"

    # Exécution du script FK et capture du log
    psql_exec "$db" "\i $fk_script" > "$fk_log" 2>&1

    # Nombre de FK après exécution
    fk_after=$(psql_exec "$db" "SELECT COUNT(*) FROM information_schema.table_constraints WHERE constraint_type='FOREIGN KEY';" "-t -A" | tr -d '[:space:]')
    fk_after=${fk_after:-0}
    fk_dropped=$((fk_before - fk_after))

    echo -e "${BLUE}Processed $fk_dropped foreign key(s) in database '$db'${RESET}"

    # Final verification
    if [ "$fk_after" -eq 0 ]; then
      echo -e "${GREEN}Final Verification: No foreign keys remain in database '$db'.${RESET}"
    else
      echo -e "${RED}Final Verification: $fk_after foreign key(s) remain in database '$db'.${RESET}"
    fi

    echo "Drop FKs log saved: $fk_log"

    # Vérification des erreurs dans le log
    if grep -iE "error|fail|cannot|syntax" "$fk_log" > /dev/null; then
      echo -e "Check of errors on the log ..."
      grep -iE "error|fail|cannot|syntax" "$fk_log"
      echo -e "${RED}Processed with errors.${RESET}"
    else
      echo -e "Check of errors on the log ..."
      echo -e "${GREEN}Processed successfully. No errors found.${RESET}"
    fi

    echo
  done

  echo -e "${GREEN}All Drop FK scripts executed.${RESET}"
  ;;
  22)
  echo -e "${GREEN}    -----------------------   ${RESET}"
  echo -e "${GREEN}Pre-Migration: Disable Triggers${RESET}\n"

  mkdir -p "$WORKDIR/TRIGGERS/LOG"

  for db in $databases; do
    disable_file="$WORKDIR/TRIGGERS/DisableTriggers_${db}.sql"
    disable_log="$WORKDIR/TRIGGERS/LOG/DisableTriggers_Execution_${db}.log"

    echo -e "${YELLOW}Processing database '$db'...${RESET}"

    if [ ! -f "$disable_file" ]; then
      echo -e "${RED}Disable triggers script not found: $disable_file${RESET}"
      echo "Skipping database '$db'."
      continue
    fi

    # Compter triggers enabled avant execution
    triggers_enabled_before=$(psql_exec "$db" "
      SELECT COUNT(*) 
      FROM pg_trigger t
      JOIN pg_class c ON c.oid = t.tgrelid
      WHERE NOT t.tgisinternal AND t.tgenabled='O';
    " "-t -A" | tr -d '[:space:]')
    triggers_enabled_before=${triggers_enabled_before:-0}

    # Exécution du script Disable Triggers
    psql_exec "$db" "\i $disable_file" > "$disable_log" 2>&1

    # Compter triggers après execution
    triggers_enabled_after=$(psql_exec "$db" "
      SELECT COUNT(*) 
      FROM pg_trigger t
      JOIN pg_class c ON c.oid = t.tgrelid
      WHERE NOT t.tgisinternal AND t.tgenabled='O';
    " "-t -A" | tr -d '[:space:]')
    triggers_enabled_after=${triggers_enabled_after:-0}

    triggers_disabled=$((triggers_enabled_before - triggers_enabled_after))

    echo -e "${BLUE}Processed $triggers_disabled trigger(s) disabled in database '$db'${RESET}"

    # Final verification
    if [ "$triggers_enabled_after" -eq 0 ]; then
      echo -e "${GREEN}Final Verification: All user triggers are disabled in database '$db'.${RESET}"
    else
      echo -e "${RED}Final Verification: $triggers_enabled_after trigger(s) still enabled in database '$db'.${RESET}"
    fi

    echo "Disable triggers log saved: $disable_log"

    # Vérification des erreurs dans le log
    if grep -iE "error|fail|cannot|syntax" "$disable_log" > /dev/null; then
      echo -e "${RED}Check of errors on the log ...${RESET}"
      grep -iE "error|fail|cannot|syntax" "$disable_log"
      echo -e "${RED}Processed with errors.${RESET}"
    else
      echo -e "${GREEN}Check of errors on the log ...${RESET}"
      echo -e "${GREEN}Processed successfully. No errors found.${RESET}"
    fi

    echo
  done

  echo -e "${GREEN}All Disable Triggers scripts executed.${RESET}"
;;

23)
echo -e "${GREEN}    -----------------------   ${RESET}"
echo -e "${GREEN} [23] Pre-Migration: Execute TRUNCATE Scripts${RESET}\n"

mkdir -p "$WORKDIR/TRUNCATE/LOG"
mkdir -p "$WORKDIR/TRUNCATE/SUMMARY"

for db in $databases; do
    truncate_file="$WORKDIR/TRUNCATE/TruncateTables_${db}.sql"
    truncate_log="$WORKDIR/TRUNCATE/LOG/TruncateTables_Execution_${db}.log"

    echo -e "${GREEN}Processing database: $db${RESET}"
    echo "--------------------------------------------"

    if [ ! -f "$truncate_file" ]; then
        echo -e "${RED}✘ TRUNCATE script not found for database '$db'${RESET}"
        continue
    fi

    # Récupérer toutes les tables du script
    table_list=$(grep -oP '"[^"]+"\."[^"]+"' "$truncate_file" | tr '\n' ' ')
    echo "Tables to TRUNCATE in database '$db':"
    for tbl in $table_list; do
        rows=$(psql_exec "$db" "SELECT COUNT(*) FROM $tbl;" "-t -A")
        rows=${rows:-0}
        echo -e " - $tbl ($rows rows)"
    done

    # Confirmation utilisateur par base
    while : ; do
        echo -n "Are you sure you want to TRUNCATE these tables for database '$db'? [Y/n/0] (default Y): "
        read answer
        answer=${answer:-Y}
        case "$answer" in
            Y|y) echo "Proceeding with TRUNCATE on database '$db'..."; break ;;
            N|n) echo -e "${RED}Operation cancelled for database '$db'.${RESET}"; continue 2 ;;
            0) exit_script ;;
            *) echo -e "${RED}Invalid choice. Only Y, N or 0 allowed.${RESET}" ;;
        esac
    done

    # Exécution TRUNCATE
    psql_exec "$db" "\i $truncate_file" > "$truncate_log" 2>&1

    # Vérification tables non vidées après TRUNCATE
    non_empty_tables=""
    for tbl in $table_list; do
        rows=$(psql_exec "$db" "SELECT COUNT(*) FROM $tbl;" "-t -A")
        rows=${rows:-0}
        if [ "$rows" -gt 0 ]; then
            non_empty_tables="${non_empty_tables}${tbl}|${rows}\n"
        fi
    done

    non_empty_count=$(echo -e "$non_empty_tables" | grep -c '|')
    empty_count=$(echo "$table_list" | wc -w)
    empty_count=$((empty_count - non_empty_count))

    # Vérification erreurs log
    if grep -iE "error|fail|cannot|syntax" "$truncate_log" > /dev/null; then
        echo -e "${RED}Errors detected in TRUNCATE log for $db:${RESET}"
        grep -iE "error|fail|cannot|syntax" "$truncate_log"
        log_status="Errors found"
    else
        echo -e "${GREEN}Execution successful — No errors in log.${RESET}"
        log_status="No errors"
    fi

    # Message tables non vidées
    if [ "$non_empty_count" -gt 0 ]; then
        echo -e "${RED}Some tables could not be truncated in '$db':${RESET}"
        echo -e "$non_empty_tables"
    else
        echo -e "${GREEN}All tables emptied successfully for database '$db'.${RESET}"
    fi

    # Résumé par base
    summary_file="$WORKDIR/TRUNCATE/SUMMARY/TruncateSummary_${db}.txt"
    {
        echo "TRUNCATE SUMMARY FOR DATABASE: $db"
        echo "===================================="
        echo "Script used: $truncate_file"
        echo "Execution log: $truncate_log"
        echo "Errors in log: $log_status"
        echo "Tables empty after TRUNCATE: $empty_count"
        echo "Tables non-empty after TRUNCATE: $non_empty_count"
        [ "$non_empty_count" -gt 0 ] && echo -e "$non_empty_tables"
    } > "$summary_file"

    echo "Summary written to: $summary_file"
    echo
done

# Global summary
echo -e "${GREEN}All TRUNCATE operations completed.${RESET}"
echo "    -----------------------"
echo " Summary"
printf "\n%-15s | %-10s | %-15s | %-17s\n" "Database" "FK Count" "Tables Empty" "Tables Not Empty"
echo "--------------------------------------------------------------"
for db in $databases; do
    summary_file=$(ls -1t "$WORKDIR/TRUNCATE/SUMMARY/TruncateSummary_${db}"* 2>/dev/null | head -1)
    if [ -f "$summary_file" ]; then
        empty=$(grep "Tables empty after TRUNCATE" "$summary_file" | awk -F': ' '{print $2}')
        non_empty=$(grep "Tables non-empty after TRUNCATE" "$summary_file" | awk -F': ' '{print $2}')
        printf "%-15s | %-10s | %-15s | %-17s\n" "$db" "0" "$empty" "$non_empty"
    fi
done
echo "Summary completed."
;;

31)
  echo -e "${GREEN}    -----------------------   ${RESET}"
  echo -e "${GREEN}Post-Migration: Enable Foreign Keys${RESET}\n"

  mkdir -p "$WORKDIR/FK/LOG"

  for db in $databases; do
    fk_script="$WORKDIR/FK/CreateFKs_${db}.sql"
    fk_log="$WORKDIR/FK/LOG/EnableFKs_Execution_${db}.log"

    echo -e "${YELLOW}Processing database '$db'...${RESET}"

    if [ ! -f "$fk_script" ]; then
      echo -e "${RED}Enable FK script not found: $fk_script${RESET}"
      echo "Skipping database '$db'."
      continue
    fi

    # Nombre de FK avant exécution
    fk_before=$(psql_exec "$db" "SELECT COUNT(*) FROM information_schema.table_constraints WHERE constraint_type='FOREIGN KEY';" "-t -A" | tr -d '[:space:]')
    fk_before=${fk_before:-0}
    echo "Foreign keys before execution: $fk_before"

    # Exécution du script FK pour créer / activer les FK
    psql_exec "$db" "\i $fk_script" > "$fk_log" 2>&1

    # Nombre de FK après exécution
    fk_after=$(psql_exec "$db" "SELECT COUNT(*) FROM information_schema.table_constraints WHERE constraint_type='FOREIGN KEY';" "-t -A" | tr -d '[:space:]')
    fk_after=${fk_after:-0}
    fk_created=$((fk_after - fk_before))

    echo -e "${BLUE}Processed $fk_created foreign key(s) enabled in database '$db'${RESET}"

    # Vérification finale
    echo -e "${GREEN}Final Verification: $fk_after foreign key(s) now present in database '$db'.${RESET}"

    echo "Enable FKs log saved: $fk_log"

    # Vérification des erreurs
    if grep -iE "error|fail|cannot|syntax" "$fk_log" > /dev/null; then
      echo -e "${RED}Check of errors on the log ...${RESET}"
      grep -iE "error|fail|cannot|syntax" "$fk_log"
      echo -e "${RED}Processed with errors.${RESET}"
    else
      echo -e "${GREEN}Check of errors on the log ...${RESET}"
      echo -e "${GREEN}Processed successfully. No errors found.${RESET}"
    fi

    echo
  done

  echo -e "${GREEN}All Enable FK scripts executed.${RESET}"
  ;;

32)
  echo -e "${GREEN}    -----------------------   ${RESET}"
  echo -e "${GREEN}Post-Migration: Enable Triggers${RESET}\n"

  mkdir -p "$WORKDIR/TRIGGERS/LOG"

  for db in $databases; do
    enable_file="$WORKDIR/TRIGGERS/EnableTriggers_${db}.sql"
    enable_log="$WORKDIR/TRIGGERS/LOG/EnableTriggers_Execution_${db}.log"

    echo -e "${YELLOW}Processing database '$db'...${RESET}"

    if [ ! -f "$enable_file" ]; then
      echo -e "${RED}Enable triggers script not found: $enable_file${RESET}"
      echo "Skipping database '$db'."
      continue
    fi

    # Triggers activés avant
    triggers_enabled_before=$(psql_exec "$db" "
      SELECT COUNT(*) FROM pg_trigger t
      JOIN pg_class c ON c.oid = t.tgrelid
      WHERE NOT t.tgisinternal AND t.tgenabled='O';
    " "-t -A" | tr -d '[:space:]')
    triggers_enabled_before=${triggers_enabled_before:-0}

    # Exécution du script Enable Triggers
    psql_exec "$db" "\i $enable_file" > "$enable_log" 2>&1

    # Triggers activés après
    triggers_enabled_after=$(psql_exec "$db" "
      SELECT COUNT(*) FROM pg_trigger t
      JOIN pg_class c ON c.oid = t.tgrelid
      WHERE NOT t.tgisinternal AND t.tgenabled='O';
    " "-t -A" | tr -d '[:space:]')
    triggers_enabled_after=${triggers_enabled_after:-0}

    triggers_new=$((triggers_enabled_after - triggers_enabled_before))

    echo -e "${BLUE}Processed $triggers_new trigger(s) enabled in database '$db'${RESET}"

    # Final verification
    triggers_disabled=$(psql_exec "$db" "
      SELECT COUNT(*) FROM pg_trigger t
      JOIN pg_class c ON c.oid = t.tgrelid
      WHERE NOT t.tgisinternal AND t.tgenabled='D';
    " "-t -A" | tr -d '[:space:]')
    triggers_disabled=${triggers_disabled:-0}

    if [ "$triggers_disabled" -eq 0 ]; then
      echo -e "${GREEN}Final Verification: All user triggers are enabled in database '$db'.${RESET}"
    else
      echo -e "${RED}Final Verification: $triggers_disabled trigger(s) still disabled in database '$db'.${RESET}"
    fi

    echo "Enable triggers log saved: $enable_log"

    # Vérification des erreurs
    if grep -iE "error|fail|cannot|syntax" "$enable_log" > /dev/null; then
      echo -e "${RED}Check of errors on the log ...${RESET}"
      grep -iE "error|fail|cannot|syntax" "$enable_log"
      echo -e "${RED}Processed with errors.${RESET}"
    else
      echo -e "${GREEN}Check of errors on the log ...${RESET}"
      echo -e "${GREEN}Processed successfully. No errors found.${RESET}"
    fi

    echo
  done

  echo -e "${GREEN}All Enable Triggers scripts executed.${RESET}"
  ;;


 4)
echo -e "${GREEN}    -----------------------   ${RESET}"
echo -e "${GREEN}Validation: Pre/Post-Migration Summary${RESET}\n"

mkdir -p "$WORKDIR/VALIDATION"
report_txt="$WORKDIR/VALIDATION/ValidationReport.txt"
report_html="$WORKDIR/VALIDATION/ValidationReport.html"

for db in $databases; do
    echo -e "\nProcessing validation for database '$db'...\n" | tee -a "$report_txt"

    # Paths of logs
    triggers_disable_log="$WORKDIR/TRIGGERS/LOG/DisableTriggers_${db}.log"
    triggers_enable_log="$WORKDIR/TRIGGERS/LOG/EnableTriggers_${db}.log"
    truncate_log="$WORKDIR/TRUNCATE/LOG/TruncateTables_${db}.log"
    dropfk_log="$WORKDIR/FK/LOG/DropFKs_Execution_${db}.log"
    enablefk_log="$WORKDIR/FK/LOG/EnableFKs_Execution_${db}.log"

    # Count from logs
    triggers_disabled=$(grep -c "Trigger:" "$triggers_disable_log" 2>/dev/null)
    triggers_disabled=${triggers_disabled:-0}
    triggers_enabled=$(grep -c "Trigger:" "$triggers_enable_log" 2>/dev/null)
    triggers_enabled=${triggers_enabled:-0}
    tables_truncated=$(grep -c "ALTER TABLE" "$truncate_log" 2>/dev/null)
    tables_truncated=${tables_truncated:-0}
    fks_dropped=$(grep -c "ALTER TABLE" "$dropfk_log" 2>/dev/null)
    fks_dropped=${fks_dropped:-0}
    fks_enabled=$(grep -c "ALTER TABLE" "$enablefk_log" 2>/dev/null)
    fks_enabled=${fks_enabled:-0}

    echo "===== Pre/Post-Migration Validation Summary (from logs) =====" | tee -a "$report_txt"
    echo "Database: $db" | tee -a "$report_txt"
    echo "Triggers Disabled: $triggers_disabled | Log: $triggers_disable_log" | tee -a "$report_txt"
    echo "Triggers Enabled  : $triggers_enabled | Log: $triggers_enable_log" | tee -a "$report_txt"
    echo "Tables Truncated  : $tables_truncated | Log: $truncate_log" | tee -a "$report_txt"
    echo "FKs Dropped       : $fks_dropped | Log: $dropfk_log" | tee -a "$report_txt"
    echo "FKs Enabled       : $fks_enabled | Log: $enablefk_log" | tee -a "$report_txt"

    errors=$(grep -iE "error|fail|cannot|syntax" "$triggers_disable_log" "$triggers_enable_log" "$truncate_log" "$dropfk_log" "$enablefk_log" 2>/dev/null)
    if [ -z "$errors" ]; then
        echo "No errors found" | tee -a "$report_txt"
    else
        echo "Errors found:" | tee -a "$report_txt"
        echo "$errors" | tee -a "$report_txt"
    fi

    # Actual database situation
    echo -e "\n===== Actual Database Situation =====" | tee -a "$report_txt"

    # Tables with row counts
    psql_exec "$db" "
    SELECT n.nspname || '.' || c.relname AS table_name,
           COALESCE(s.n_live_tup,0) AS rows
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    LEFT JOIN pg_stat_all_tables s ON s.relid = c.oid
    WHERE c.relkind='r' AND n.nspname NOT IN ('pg_catalog','information_schema')
    ORDER BY table_name;
    " "-F '|' -A" | while IFS='|' read -r table rows; do
        echo "Table: $table | Rows: $rows" | tee -a "$report_txt"
    done

    # Triggers Disabled list with table
    echo -e "\nTriggers Disabled ($(psql_exec "$db" "
      SELECT COUNT(*) FROM pg_trigger t
      JOIN pg_class c ON c.oid = t.tgrelid
      WHERE NOT t.tgisinternal AND t.tgenabled='D';
    " "-t -A")):" | tee -a "$report_txt"

    psql_exec "$db" "
    SELECT c.relname AS table_name, t.tgname
    FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    WHERE NOT t.tgisinternal AND t.tgenabled='D'
    ORDER BY c.relname, t.tgname;
    " "-F '|' -A" | while IFS='|' read -r table trigger; do
        echo " - $trigger on $table" | tee -a "$report_txt"
    done

    # Triggers Enabled list with table
    echo -e "\nTriggers Enabled ($(psql_exec "$db" "
      SELECT COUNT(*) FROM pg_trigger t
      JOIN pg_class c ON c.oid = t.tgrelid
      WHERE NOT t.tgisinternal AND t.tgenabled='O';
    " "-t -A")):" | tee -a "$report_txt"

    psql_exec "$db" "
    SELECT c.relname AS table_name, t.tgname
    FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    WHERE NOT t.tgisinternal AND t.tgenabled='O'
    ORDER BY c.relname, t.tgname;
    " "-F '|' -A" | while IFS='|' read -r table trigger; do
        echo " - $trigger on $table" | tee -a "$report_txt"
    done

    # Foreign keys
    fk_count=$(psql_exec "$db" "SELECT COUNT(*) FROM pg_constraint WHERE contype='f';" "-t -A")
    echo -e "\nForeign Keys ($fk_count):" | tee -a "$report_txt"
    if [ "$fk_count" -eq 0 ]; then
        echo "No foreign keys found." | tee -a "$report_txt"
    else
        psql_exec "$db" "
        SELECT conname || ' on ' || conrelid::regclass
        FROM pg_constraint
        WHERE contype='f'
        ORDER BY conname;
        " "-t -A" | while read fk; do
            echo " - $fk" | tee -a "$report_txt"
        done
    fi

    # Database summary table
    total_tables=$(psql_exec "$db" "SELECT COUNT(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE c.relkind='r' AND n.nspname NOT IN ('pg_catalog','information_schema');" "-t -A")
    total_rows=$(psql_exec "$db" "SELECT SUM(s.n_live_tup) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace LEFT JOIN pg_stat_all_tables s ON s.relid=c.oid WHERE c.relkind='r' AND n.nspname NOT IN ('pg_catalog','information_schema');" "-t -A")

    echo -e "\n===== Database Summary Table =====" | tee -a "$report_txt"
    echo "Database           : $db" | tee -a "$report_txt"
    echo "Total Tables       : $total_tables" | tee -a "$report_txt"
    echo "Total Rows         : $total_rows" | tee -a "$report_txt"
    echo "Triggers Enabled   : $(psql_exec "$db" "SELECT COUNT(*) FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid WHERE NOT t.tgisinternal AND t.tgenabled='O';" "-t -A")" | tee -a "$report_txt"
    echo "Triggers Disabled  : $(psql_exec "$db" "SELECT COUNT(*) FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid WHERE NOT t.tgisinternal AND t.tgenabled='D';" "-t -A")" | tee -a "$report_txt"
    echo "Foreign Keys       : $fk_count" | tee -a "$report_txt"
    echo "Tables Truncated   : $tables_truncated" | tee -a "$report_txt"
    echo "FKs Dropped        : $fks_dropped" | tee -a "$report_txt"
    echo "FKs Enabled        : $fks_enabled" | tee -a "$report_txt"
    echo "=================================" | tee -a "$report_txt"

    # Export HTML (basic)
    awk '{print "<pre>" $0 "</pre>"}' "$report_txt" > "$report_html"

    echo -e "\nReport exported to TXT: $report_txt"
    echo "Report exported to HTML: $report_html"
done

echo -e "${GREEN}Validation completed for all databases.${RESET}\n"
;;

 
5)
  echo -e "${GREEN}    -----------------------${RESET}"
  echo -e "${GREEN} [5] Database Detailed Inventory${RESET}\n"

  mkdir -p "$WORKDIR/INVENTORY/TXT"
  mkdir -p "$WORKDIR/INVENTORY/HTML"

  echo "Selected databases for inventory: $databases"
  echo

  # Initialisation du résumé global
  summary=""
  summary+="Database | FK Count | Tables Empty | Tables Not Empty | Triggers Disabled | Triggers Enabled\n"
  summary+="--------------------------------------------------------------------------------------------\n"

  for db in $databases; do
      echo -e "${GREEN}Processing database '$db'...${RESET}"

      # Récupérer toutes les tables utilisateur
      table_rows=$(psql_exec "$db" "
SELECT table_schema || '.' || table_name AS tbl
FROM information_schema.tables
WHERE table_schema NOT IN ('pg_catalog','information_schema')
  AND table_type='BASE TABLE'
ORDER BY table_schema, table_name;
" "-t -A")

      empty_list=""
      non_empty_list=""
      empty_count=0
      non_empty_count=0

      # Parcours des tables et comptage des lignes
      while IFS='.' read -r schema table; do
          row_count=$(psql_exec "$db" "SELECT COUNT(*) FROM \"${schema}\".\"${table}\";" "-t -A")
          row_count=$(echo "$row_count" | tr -d '[:space:]')
          [ -z "$row_count" ] && row_count=0

          if [ "$row_count" -eq 0 ]; then
              empty_count=$((empty_count+1))
              empty_list+="${schema}.${table} : ${row_count} rows\n"
          else
              non_empty_count=$((non_empty_count+1))
              non_empty_list+="${schema}.${table} : ${row_count} rows\n"
          fi
      done <<< "$table_rows"

      # Récupérer FK
      fk_list=$(psql_exec "$db" "
SELECT conname || ' on ' || conrelid::regclass AS fk
FROM pg_constraint
WHERE contype='f';
" "-t -A")
      fk_count=$(echo "$fk_list" | grep -c .)

      # Récupérer triggers
      triggers_enabled=$(psql_exec "$db" "
SELECT tgname || ' on ' || tgrelid::regclass
FROM pg_trigger
WHERE tgenabled='O';
" "-t -A")
      triggers_disabled=$(psql_exec "$db" "
SELECT tgname || ' on ' || tgrelid::regclass
FROM pg_trigger
WHERE tgenabled<>'O';
" "-t -A")
      triggers_enabled_count=$(echo "$triggers_enabled" | grep -c .)
      triggers_disabled_count=$(echo "$triggers_disabled" | grep -c .)

      # Affichage écran détaillé
      echo -e "${CYAN}Database: $db${RESET}"
      echo -e "Total tables: $((empty_count + non_empty_count))"
      echo -e "Tables empty ($empty_count):\n$empty_list"
      echo -e "Tables non-empty ($non_empty_count):\n$non_empty_list"
      echo -e "Foreign Keys ($fk_count):\n$fk_list"
      echo -e "Triggers enabled ($triggers_enabled_count):\n$triggers_enabled"
      echo -e "Triggers disabled ($triggers_disabled_count):\n$triggers_disabled"
      echo

      # Fichier TXT
      txt_file="$WORKDIR/INVENTORY/TXT/Inventory_${db}.txt"
      {
        echo "Inventory for database: $db"
        echo "Total tables: $((empty_count + non_empty_count))"
        echo
        echo "Tables empty ($empty_count):"
        echo -e "$empty_list"
        echo "Tables non-empty ($non_empty_count):"
        echo -e "$non_empty_list"
        echo
        echo "Foreign Keys ($fk_count):"
        echo -e "$fk_list"
        echo
        echo "Triggers enabled ($triggers_enabled_count):"
        echo -e "$triggers_enabled"
        echo
        echo "Triggers disabled ($triggers_disabled_count):"
        echo -e "$triggers_disabled"
      } > "$txt_file"

      # Fichier HTML simple
      html_file="$WORKDIR/INVENTORY/HTML/Inventory_${db}.html"
      {
        echo "<html><body><h2>Inventory for database: $db</h2>"
        echo "<p>Total tables: $((empty_count + non_empty_count))</p>"
        echo "<h3>Tables empty ($empty_count)</h3><pre>$empty_list</pre>"
        echo "<h3>Tables non-empty ($non_empty_count)</h3><pre>$non_empty_list</pre>"
        echo "<h3>Foreign Keys ($fk_count)</h3><pre>$fk_list</pre>"
        echo "<h3>Triggers enabled ($triggers_enabled_count)</h3><pre>$triggers_enabled</pre>"
        echo "<h3>Triggers disabled ($triggers_disabled_count)</h3><pre>$triggers_disabled</pre>"
        echo "</body></html>"
      } > "$html_file"

      echo -e "Inventory for '$db' written to : \n - TXT: $txt_file  \n   - HTML: $html_file\n"

      # Ajouter au résumé global
      summary+=$(printf "%-14s | %-8s | %-12s | %-15s | %-16s | %-15s\n" \
        "$db" "$fk_count" "$empty_count" "$non_empty_count" "$triggers_disabled_count" "$triggers_enabled_count")
         echo -e ""
  done

  echo -e "${GREEN}Database inventory completed for all selected databases.${RESET}\n"
  
;;

6)
echo -e "${GREEN}   -----------------------${RESET}"
echo -e "${GREEN} [6] Execute SQL Script on Selected Databases${RESET}\n"

while : ; do
    echo -n "Please enter the full path to the SQL script (0 to exit): "
    read SQL_SCRIPT
    SQL_SCRIPT=$(Trim "$SQL_SCRIPT")
    [[ "$SQL_SCRIPT" = "0" ]] && exit_script

    if [[ ! -f "$SQL_SCRIPT" ]]; then
        echo -e "${RED}File not found: $SQL_SCRIPT${RESET}"
    else
        echo -e "${GREEN}SQL script found: $SQL_SCRIPT${RESET}"
        break
    fi
done

mkdir -p "$WORKDIR/SQL/LOG"

for db in $databases; do
    SQL_LOG="$WORKDIR/SQL/LOG/SQLExecutionLog_${db}.log"
    SQL_RESULT="$WORKDIR/SQL/LOG/SQLExecutionResult_${db}.log"
    echo -e "${GREEN}Processing database '$db'...${RESET}"

    # Exécution avec echo all pour capturer toutes les commandes et résultats
    # ON_ERROR_STOP=1 pour que toute erreur soit capturée
     PGPASSWORD="$PGPASSWORD" psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$db"  -a -f "$SQL_SCRIPT"  > "$SQL_RESULT" 2> "$SQL_LOG"    

    
    # Vérifier erreurs dans le log ou code de sortie
    if grep -iE "ERROR|FATAL|cannot|fail" "$SQL_LOG" >/dev/null ; then
        echo -e "${RED}Errors detected while executing SQL on database '$db':${RESET}"
        grep -iE "ERROR|FATAL|cannot|fail" "$SQL_LOG"
    else
        echo -e "${GREEN}Execution successful on database '$db'. No errors found.${RESET}"
    fi

    echo "Execution log for '$db' : $SQL_LOG  and result on $SQL_RESULT"
    echo
done

echo -e "${GREEN}SQL script execution completed for all selected databases.${RESET}"
echo "    -----------------------"
echo " Summary"
;;

      *)
        print "Invalid option: $sel"
        ;;
    esac



    
done
 


 
 
 echo -e "${GREEN}    -----------------------   ${RESET}"
  echo -e "${GREEN} Summary  ${RESET}\n"

 

  printf "%-15s | %-10s | %-12s | %-12s | %-15s | %-15s\n" \
    "Database" "FK Count" "Tables Empty" "Tables Not Empty" "Triggers Disabled" "Triggers Enabled"
printf "%s\n" "--------------------------------------------------------------------------------------------------"

for db in $databases; do

    # FK count : nombre réel de FK existantes
    fk_count=$(psql_exec "$db" "SELECT COUNT(*) FROM pg_constraint WHERE contype='f';" "-t -A" | tr -d '[:space:]')
    fk_count=${fk_count:-0}

    # Tables counts
    tables_info=$(psql_exec "$db" "
      SELECT 
        SUM(CASE WHEN s.n_live_tup = 0 THEN 1 ELSE 0 END) AS empty_tables,
        SUM(CASE WHEN s.n_live_tup > 0 THEN 1 ELSE 0 END) AS not_empty_tables
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      LEFT JOIN pg_stat_all_tables s ON s.relid = c.oid
      WHERE c.relkind='r' AND n.nspname NOT IN ('pg_catalog','information_schema');
    " "-t -A")

    empty_tables=$(echo "$tables_info" | cut -d '|' -f1)
    not_empty_tables=$(echo "$tables_info" | cut -d '|' -f2)
    empty_tables=${empty_tables:-0}
    not_empty_tables=${not_empty_tables:-0}

    # Triggers counts (directly from DB)
    triggers_disabled=$(psql_exec "$db" "
      SELECT COUNT(*) FROM pg_trigger t
      JOIN pg_class c ON c.oid = t.tgrelid
      WHERE NOT t.tgisinternal AND t.tgenabled='D';
    " "-t -A" | tr -d '[:space:]')
    triggers_disabled=${triggers_disabled:-0}

    triggers_enabled=$(psql_exec "$db" "
      SELECT COUNT(*) FROM pg_trigger t
      JOIN pg_class c ON c.oid = t.tgrelid
      WHERE NOT t.tgisinternal AND t.tgenabled='O';
    " "-t -A" | tr -d '[:space:]')
    triggers_enabled=${triggers_enabled:-0}

    # Affichage tableau synthèse
    printf "%-15s | %-10s | %-12s | %-12s | %-15s | %-15s\n" \
      "$db" "$fk_count" "$empty_tables" "$not_empty_tables" "$triggers_disabled" "$triggers_enabled"

done


  echo -e "${GREEN}Summary   completed.${RESET}"
 