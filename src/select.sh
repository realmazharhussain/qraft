#!/usr/bin/env bash

source "$SRC_DIR"/logger.sh
source "$SRC_DIR"/utils.sh
source "$SRC_DIR"/utils/parse_filters.sh

# Prepend $pre_args to $@
eval "pre_args=($pre_args)"
set -- "${pre_args[@]}" "$@"

# Sanity checks
[[ $# == 0 ]] && err "Please, provide at least one filter" && exit 1
[[ -z "$SELECTED_DATABASE" ]] && err "No database selected" && exit 1

# Parse filters
parse_filters "$@" || exit $?

# Select table
table=${table:-$SELECTED_TABLE}
[[ -z "$table" ]] && err "No table provided. Please, select or provide a table name" && exit 1

if [[ "$table" = *:* ]]; then
    IFS=, read -ra columns <<< "${table#*:}"
    table=${table%%:*}
fi

_table=$(jq -r '.database.tables | .[]' "$CACHE_FILE" | fzf -0 -1 --prompt="Select a table: " --query="$table")
[[ -z "$_table" ]] && err "Table '$table' not found" && exit 1
table=$_table

if [[ ${#columns[@]} -gt 0 ]]; then
    schema=$(sqlite3 "$SELECTED_DATABASE" ".schema $table")
    schema=${schema#*\(}
    schema=${schema%\)*}
    db_columns=$(echo "$schema" | sed -E 's/,[[:space:]]*/\n/g' | cut -d' ' -f1)

    for((i = 0; i < ${#columns[@]}; i++)); do
        _column=$(fzf -0 -1 --prompt="Select a column: " --query="${columns[$i]}" <<< "$db_columns")
        [[ -z "$_column" ]] && err "Column '${columns[$i]}' not found in table '$table'" && exit 1
        columns[i]=$_column
    done
fi

# Build query
query="SELECT "

if [[ "${#columns[@]}" -gt 0 ]]; then
    query+=$(join_str ", " "${columns[@]}")
else
    query+="*"
fi

query+=" FROM $table"

[[ "${#filters[@]}" -gt 0 ]] && query+=" WHERE $(join_str " AND " "${filters[@]}")"
[[ -n "$order_by" ]] && query+=" ORDER BY $order_by"
[[ -n "$limit" ]] && query+=" LIMIT $limit"
[[ -n "$offset" ]] && query+=" OFFSET $offset"
[[ -n "$group_by" ]] && query+=" GROUP BY $group_by"

# Write output
$jq "$OUTPUT_FILE" -u success = true
$jq "$OUTPUT_FILE" -u message = "Fetch data from table '$table'"
$jq "$OUTPUT_FILE" -u database = "$SELECTED_DATABASE"
$jq "$OUTPUT_FILE" -u target.table = "$table"
$jq "$OUTPUT_FILE" -u operation = "QUERY"
$jq "$OUTPUT_FILE" -u query = "$query;"
