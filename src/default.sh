#!/usr/bin/env bash

source "$SRC_DIR"/utils.sh

choose_database() {
    cd "$WORK_DIR" || return 1
    while true; do
        read -re -p "filename: " || { echo "^D" >&2 && return 1; }
        FILENAME=$(eval echo "$REPLY")
        [[ -z "$FILENAME" ]] && continue
        [[ ! -e "$FILENAME" ]] && echo "Cannot access '$FILENAME': No such file or directory" >&2 && continue
        [[ -d "$FILENAME" ]] &&  echo "Cannot load '$FILENAME': Is a directory" >&2 && continue
        err=$(sqlite3 "$FILENAME" .tables 2>&1 >/dev/null)
        [[ "$err" == *"not a database" ]] && echo "Cannot load '$FILENAME': Not a database" >&2 && continue
        [[ -n "$err" ]] && echo "Cannot load '$FILENAME': $err" >&2 && continue
        echo "$FILENAME" && break
    done
    cd - >/dev/null || return 1
}

create_database() {
    cd "$WORK_DIR" || return 1
    while true; do
        read -re -p "new filename: " || { echo "^D" >&2 && return 1; }
        FILENAME=$(eval echo "$REPLY")
        FULL_PATH=$(real_path "$FILENAME")
        DIR_PATH=${FULL_PATH%/*}
        [[ -e "$FULL_PATH" ]] && echo "Cannot create '$FILENAME': Already exists" >&2 && continue
        mkdir -p "$DIR_PATH" || continue
        touch "$FULL_PATH" || continue
        echo "$FULL_PATH" && break
    done
    cd - >/dev/null || return 1
}

update_cache() {
    # test validity, save to cache if successful
    output=$(sqlite3 "$1" '.tables' 2>&1)
    if [[ "$output" == *"not a database"* ]]; then
        $jq "$OUTPUT_FILE" -u success = 'false'
        $jq "$OUTPUT_FILE" -u message = "$output"
        return 1
    else
        $jq "$CACHE_FILE" -u database.tables = "$(echo "$output" | tr -s ' ' '\n' | jq -R -s 'split("\n") | map(select(. != ""))')"
    fi
}

run_default() {
    file=$($jq "$CACHE_FILE" database.file)
    if [[ "$file" == null ]]; then
        if [[ -n $DATABASE || $(wc -l <<< "$(list_attached_databases)" 2>/dev/null || echo 0) -gt 0 ]]; then
            ./load_database.sh || return $?
        else
            echo "No database found in the cache. What would you like to do?" >&2
            echo "0) Abort" >&2
            echo "1) Load existing database" >&2
            echo "2) Create new database" >&2
            while true; do
                read -r -p "#? " || { echo "^D" >&2 && return 1; }
                case "$REPLY" in
                    0) return 1;;
                    1) DATABASE=$(choose_database) && ./load_database.sh "$DATABASE" || return $?; break;;
                    2) DATABASE=$(create_database) && ./load_database.sh "$DATABASE" || return $?; break;;
                esac
            done
        fi
    else
        update_cache "$file" || return $?
        $jq "$OUTPUT_FILE" -u success = true
        $jq "$OUTPUT_FILE" -u message = "Updated cache"
        $jq "$OUTPUT_FILE" -u database = "$file"
    fi

    file=$($jq "$CACHE_FILE" database.file)
    table=$($jq "$CACHE_FILE" database.table)
    if [[ "$table" == null ]]; then
        if [[ -n "$TABLE" ]]; then
            ./target.sh
        else
            read -ra all_tables <<< "$(sqlite3 "$file" .tables)"
            case ${#all_tables[@]} in
            0)
                ;;
            1)
                table=${all_tables[0]}
                echo "There is only one table in the database." >&2
                while true; do
                    read -r -p "Load table '$table'? (Y/n): " || { echo "^D"; break; }
                    case "$REPLY" in y|Y|n|N) break;; esac
                done
                case "$REPLY" in y|Y) ./target.sh "$table";; esac
                ;;
            *)
                echo "No table is loaded yet." >&2
                echo "Please, choose a table to load:" >&2
                while select table in "${all_tables[@]}" skip; do break; done; do
                    [[ -n "$table" ]] && break || echo "Please, choose a valid entry or press Ctrl+D to abort!" >&2
                done
                [[ -n "$table" && "$table" != skip && "$table" != null ]] && ./target.sh "$table"
                ;;
            esac
        fi
    else
        $jq "$OUTPUT_FILE" -u target.table = "$table"
    fi
}

run_default "$@"
