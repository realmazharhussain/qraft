#!/usr/bin/env bash

source "$SRC_DIR"/logger.sh
source "$SRC_DIR"/utils.sh
source "$SRC_DIR"/utils/parse_filters.sh

eval "table=($pre_args)"
hide_columns=("$@")

# Sanity checks
[[ $# == 0 ]] && err "Please, provide at least one column name" && exit 1
[[ -z "$SELECTED_DATABASE" ]] && err "No database selected" && exit 1

# Select table
[[ -z "$table" ]] && err "No table provided. Please, provide a table name" && exit 1

_table=$(jq -r '.database.tables | .[]' "$CACHE_FILE" | fzf -0 -1 --prompt="Select a table: " --query="$table")
[[ -z "$_table" ]] && err "Table '$table' not found" && exit 1
table=$_table

# Select columns
if [[ ${#hide_columns[@]} -gt 0 ]]; then
    schema=$(sqlite3 "$SELECTED_DATABASE" ".schema $table")
    schema=${schema#*\(}
    schema=${schema%\)*}
    db_columns=$(echo "$schema" | sed -E 's/,[[:space:]]*/\n/g' | cut -d' ' -f1)

    for((i = 0; i < ${#hide_columns[@]}; i++)); do
        _column=$(fzf -0 -1 --prompt="Select a column: " --query="${hide_columns[$i]}" <<< "$db_columns")
        [[ -z "$_column" ]] && err "Column '${hide_columns[$i]}' not found in table '$table'" && exit 1
        hide_columns[i]=$_column
    done
fi

columns=()
for column in $db_columns; do
    ! contains "$column" "${hide_columns[@]}" && columns+=("$column")
done

[[ "${#columns[@]}" == 0 ]] && err "All columns hidden, no columns left to fetch" && exit 1

# Build query
query="SELECT $(join_str ", " "${columns[@]}") FROM $table"

# Write output
$jq "$OUTPUT_FILE" -u success = true
$jq "$OUTPUT_FILE" -u message = "Fetch data from table '$table'"
$jq "$OUTPUT_FILE" -u database = "$SELECTED_DATABASE"
$jq "$OUTPUT_FILE" -u target.table = "$table"
$jq "$OUTPUT_FILE" -u operation = "QUERY"
$jq "$OUTPUT_FILE" -u query = "$query;"
