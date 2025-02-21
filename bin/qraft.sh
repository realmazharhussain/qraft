#!/bin/bash

export ROOT=$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")") # path to this project root dir
export SRC_DIR=$ROOT/src
export WORK_DIR=$PWD

# imports
source "$ROOT"/.env
source "$ROOT"/src/logger.sh
source "$ROOT"/src/utils.sh
export jq="$ROOT/src/qj/qj"

# general syntax: qraft <filter> <operator> <operands>

main() {
    export pre_args=""
    action=""
    post_args=()

    initialize      # setup environment and check for missing files
    parse "$@"      # break input for analysis
    read_cache      # read values remembered into the cache
    dispatch "$@"   # execute the operation
    terminate       # execute post-script tasks regardless of operation
}

initialize() {
  # load list of cached databases and tables
  # attempt connection to $DATABASE
  # other verifications making sure its working
  # DO NOT put existence tests and validity tests outside this function
  # cat "$JSON_OUTPUT_FILE"
  create_cache_file  # non-output meta data stored here
  reset_output_file  # final output
}

create_cache_file() {
    [[ ! -d "$CACHE" ]] && mkdir -p "$CACHE" && dbug no cache directory, created new one
    [[ ! -f $CACHE_FILE ]] && echo '{}' > "$CACHE_FILE"
}

reset_output_file() {
    db_file=$($jq $CACHE_FILE database.file)
    target_table=$($jq $CACHE_FILE target.table)

    cp $OUTPUT_TEMPLATE_FILE $OUTPUT_FILE
    $jq $OUTPUT_FILE -u database = $db_file
    $jq $OUTPUT_FILE -u target.table = $target_table
}

parse() {
    ## Immediate actions
    contains -h "$@" && print_help && exit 0
    contains --help "$@" && print_help && exit 0
    contains -v "$@" && print_version && exit 0
    contains --version "$@" && print_version && exit 0

    ## Strip out options that can be placed anywhere
    debug=false
    args=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --debug) debug=true ;;
            *) args+=("$1") ;;
        esac

        shift
    done
    set -- "${args[@]}"

    ## Parse out subcommand/action, and any arguments that occur before the action
    ## For example, in the command `qraft TABLE FILTER... set COLUMN=VALUE...`,
    ## `TABLE FILTER...` are pre_args, `set` is action, and `COLUMN=VALUE...` are
    ## post_args.
    while [[ $# -gt 0 && -z "$action" ]]; do
        case "$1" in
            connect|load|db) action="connect" ;;
            protect) action="protect" ;;
            create) action="create" ;;
            alter) action="alter" ;;
            drop) action="drop" ;;
            list) action="list" ;;
            desc) action="desc" ;;
            target|select) action="target" ;;
            lim) action="limit" ;;
            shift|offset) action="shift" ;;
            add|insert) action="insert" ;;
            mod|set|update) action="update" ;;
            del|delete|rm) action="delete" ;;
            transac|transaction) action="transaction" ;;
            pragma) action="pragma" ;;
            export) action="export" ;;
            import) action="import" ;;
            tables) action="tables" ;;
            hide) action="hide" ;;
            *)
                filename=$(real_path "${1%/*}")
                if [[ -e "$filename" ]]; then
                    action="connect"
                    continue # Prevent `shift` && Preserve $1 in $post_args
                else
                    pre_args+=" ${1@Q}"
                fi
                ;;
        esac
        shift
    done

    ## All arguments after the action are post_args
    post_args=("$@")
}

read_cache() {
    export SELECTED_DATABASE=$($jq "$CACHE_FILE" database.file)
    export SELECTED_TABLE=$($jq "$CACHE_FILE" database.table)
}

dispatch() {
    echo "HERE! db is $SELECTED_DATABASE" >&2

    cd "$SRC_DIR" || return $?

    case "$action" in
        connect) ./load_database.sh "${post_args[@]}" ;;
        target) ./target.sh "${post_args[@]}" ;;
        protect) ./protect.sh "${post_args[@]}" ;;
        create) ./create.sh "${post_args[@]}" ;;
        alter) ./alter.sh "${post_args[@]}" ;;
        drop) ./drop.sh "${post_args[@]}" ;;
        insert) ./insert.sh "${post_args[@]}" ;;
        update) ./update.sh "${post_args[@]}" ;;
        delete) ./delete.sh "${post_args[@]}" ;;
        transaction) ./transaction.sh "${post_args[@]}" ;;
        pragma) ./pragma.sh "${post_args[@]}" ;;
        export) ./export.sh "${post_args[@]}" ;;
        import) ./import.sh "${post_args[@]}" ;;
        tables) ./tables.sh "${post_args[@]}" ;;
        desc) ./desc.sh "${post_args[@]}" ;;
        hide) ./hide.sh "${post_args[@]}" ;;
        '')
            if [[ $pre_args == "" ]]; then
                ./default.sh
            else
                ./select.sh
            fi
            ;;
        *) err "Internal error!" && exit 1 ;;
    esac
}

terminate() {

    # final_message=
    # error_number=

    # if debug is true, reveal variables
    is_true ${ARG[debug]} && reveal_variables

    # # if there are any errors, print
    # [[ $error_number -gt 0 ]] && echo -e "$error_msg"

    # # if there are any final messages, print
    # [[ -n "$final_message" ]] && echo -e "\n$final_message"

    # exit $error_number

    # print results
    $jq $OUTPUT_FILE
}

print_help() {
    echo 'read README.md'
}

print_version() {
    echo 'qraft 0.1-alpha'
}

# Loop through the keys of the associative array and print key-value pairs
reveal_variables() {
    local yellow="\033[33m"
    local green="\033[32m"
    local red="\033[31m"
    local purple="\033[35m"
    local cyan="\033[36m"
    local reset="\033[0m"

    for key in "${!ARG[@]}"; do
        value="${ARG[$key]}"
        value="${value%"${value##*[![:space:]]}"}"  # Trim trailing whitespace
        value="${value#"${value%%[![:space:]]*}"}"  # Trim leading whitespace
        color="$reset"

        if [[ $value == 'null' ]]; then
            value=""  # Null value
        elif [[ -z $value ]]; then
            value="EMPTY"  # Empty string
            color=$cyan    # Empty value
        elif [[ $value == '1' ]]; then
            color=$green   # True value
        elif [[ $value == '0' ]]; then
            color=$red     # False value
        fi

        printf "${yellow}%-20s${reset} : ${color}%s${reset}\n" "$key" "$value"
    done
}

main "$@"
