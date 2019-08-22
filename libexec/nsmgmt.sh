#!/usr/bin/env bash
set -e

readonly BIN_DIR=$(cd ${BASH_SOURCE[0]%/*} && pwd)
readonly LIB_DIR=${BIN_DIR}/../libexec
readonly DB_DIR=${BIN_DIR}/../var/db/nsmgmt
readonly STATUS_PATH=${DB_DIR}/zones.status
readonly STATUS_TMP_PATH=${DB_DIR}/zones.status.tmp
readonly ZONES_TMP_DIR=${DB_DIR}/zones

declare CONFIG_PATH=${BIN_DIR}/../etc/nsmgmt.conf

declare -a ADDED_ZONES
declare -a DELETED_ZONES
declare -a CHANGED_ZONES
declare NEED_TASKS=0

function read_global_config() {
    exec 1> >(awk '{print strftime("[%Y/%m/%d %H:%M:%S]"),$0;fflush()}')

    local OLDPWD=$(pwd)

    cd $(dirname ${CONFIG_PATH})
    . $(basename ${CONFIG_PATH})

    zones_src_path=$(cd ${zones_src_path:?} && pwd)
    zones_dst_path=$(cd ${zones_dst_path:?} && pwd)
    update_serial=${update_serial:=1}
    update_serial_cmdline=${update_serial_cmdline:="cat"}

    local len=${#tasks[@]}
    if [ ${len} -eq 0 ]; then
        tasks=()
    fi

    cd ${OLDPWD}
}

function pre_process() {
    set +e

    local retval=0

    if [ "${pre_process_cmdline}" != "" ]; then
        echo "running pre_process..."
        eval "${pre_process_cmdline}"
        retval=$?
    fi

    if [ ${retval} -ne 0 ]; then
        echo "pre_process command returns ${retval}"
        exit 1
    fi

    set -e
}

function _pre_detect() {
    [ -d ${DB_DIR} ] || mkdir -p ${DB_DIR}
    [ -f ${STATUS_PATH} ] || touch ${STATUS_PATH}
    [ -f ${STATUS_TMP_PATH} ] || touch ${STATUS_TMP_PATH}
    [ -d ${ZONES_TMP_DIR} ] || mkdir -p ${ZONES_TMP_DIR}

    rsync -av --delete --exclude .git ${zones_src_path}/ ${ZONES_TMP_DIR}/ 
    (cd ${ZONES_TMP_DIR} && ls | xargs -r sha256sum | awk '{print $2":"$1}') > ${STATUS_TMP_PATH}

    echo "detecting added/deleted/changed zones..."
}

function detect_added_zones() {
    local zone
    while read zone; do
        ADDED_ZONES+=("${zone}")
    done < <(comm -23 <(cut -d':' -f1 ${STATUS_TMP_PATH} | sort) <(cut -d':' -f1 ${STATUS_PATH} | sort))

    if [ ${#ADDED_ZONES[@]} -gt 0 ]; then
        echo "added: ${ADDED_ZONES[@]}"
    fi
}

function detect_deleted_zones() {
    local zone
    while read zone; do
        DELETED_ZONES+=("${zone}")
    done < <(comm -13 <(cut -d':' -f1 ${STATUS_TMP_PATH} | sort) <(cut -d':' -f1 ${STATUS_PATH} | sort))

    if [ ${#DELETED_ZONES[@]} -gt 0 ]; then
        echo "deleted: ${DELETED_ZONES[@]}"
    fi
}

function detect_changed_zones() {
    local -A hash_now
    local -A hash_prev

    local line
    local key
    local val
    local OLDIFS="${IFS}"
    IFS=':'
    while read line; do
        set -- ${line}
        key=${1}
        val=${2}
        hash_now["${key}"]="${val}"
    done < ${STATUS_TMP_PATH}
    while read line; do
        set -- ${line}
        key=${1}
        val=${2}
        hash_prev["${key}"]="${val}"
    done < ${STATUS_PATH}
    IFS="${OLDIFS}"

    local zone
    while read zone; do
        if [ "${hash_now["${zone}"]}" != "${hash_prev["${zone}"]}" ]; then
            CHANGED_ZONES+=("${zone}")
        fi
    done < <(comm -12 <(cut -d':' -f1 ${STATUS_TMP_PATH} | sort) <(cut -d':' -f1 ${STATUS_PATH} | sort))

    if [ ${#CHANGED_ZONES[@]} -gt 0 ]; then
        echo "changed: ${CHANGED_ZONES[@]}"
    fi
}

function update_added_zones() {
    local i=0
    local len=${#ADDED_ZONES[@]}
    if [ ${len} -gt 0 ]; then
        NEED_TASKS=1
    fi

    cd ${ZONES_TMP_DIR}

    if [ ${update_serial} -eq 1 ]; then
        while [ ${i} -lt ${len} ]; do
            cat ${ADDED_ZONES[${i}]} | eval "${update_serial_cmdline}" > ${zones_dst_path}/${ADDED_ZONES[${i}]}
            i=$((i + 1))
        done
    else
        while [ ${i} -lt ${len} ]; do
            cat ${ADDED_ZONES[${i}]} > ${zones_dst_path}/${ADDED_ZONES[${i}]}
            i=$((i + 1))
        done
    fi

    cd - >/dev/null
}

function update_deleted_zones() {
    local i=0
    local len=${#DELETED_ZONES[@]}
    if [ ${len} -gt 0 ]; then
        NEED_TASKS=1
    fi

    while [ ${i} -lt ${len} ]; do
        rm -f ${zones_dst_path}/${DELETED_ZONES[${i}]} || :
        i=$((i + 1))
    done
}

function update_changed_zones() {
    local i=0
    local len=${#CHANGED_ZONES[@]}
    if [ ${len} -gt 0 ]; then
        NEED_TASKS=1
    fi

    cd ${ZONES_TMP_DIR}

    if [ ${update_serial} -eq 1 ]; then
        while [ ${i} -lt ${len} ]; do
            cat ${CHANGED_ZONES[${i}]} | eval "${update_serial_cmdline}" > ${zones_dst_path}/${CHANGED_ZONES[${i}]}
            i=$((i + 1))
        done
    else
        while [ ${i} -lt ${len} ]; do
            cat ${CHANGED_ZONES[${i}]} > ${zones_dst_path}/${CHANGED_ZONES[${i}]}
            i=$((i + 1))
        done
    fi

    cd - >/dev/null
}

function save_zones_state() {
    if [ ${NEED_TASKS} -eq 0 ]; then
        return 0
    fi

    (cd ${ZONES_TMP_DIR} && ls | xargs -r sha256sum | awk '{print $2":"$1}') > ${STATUS_PATH}
    rm -f ${STATUS_TMP_PATH}
}

function run_tasks() {
    if [ ${NEED_TASKS} -eq 0 ]; then
        echo "zones have not been changed"
        return 0
    else
        echo "running tasks..."
    fi

    cd $(dirname ${CONFIG_PATH})

    local i=0
    local len=${#tasks[@]}
    while [ ${i} -lt ${len} ]; do
        set +e

        ${tasks[${i}]} | awk -v idx="[$((i + 1))]" '{print idx,$0;fflush()}'

        set -e

        i=$((i + 1))
    done

    cd - >/dev/null
}

function post_process() {
    set +e

    local retval=0

    if [ "${post_process_cmdline}" != "" ]; then
        echo "running post_process..."
        eval "${post_process_cmdline}"
        retval=$?
    fi

    if [ ${retval} -ne 0 ]; then
        echo "post_process command returns ${retval}"
        exit 1
    fi

    set -e
}

function exe_all() {
    read_global_config

    pre_process

    _pre_detect
    detect_added_zones
    detect_deleted_zones
    detect_changed_zones
    update_added_zones
    update_deleted_zones
    update_changed_zones
    save_zones_state

    run_tasks

    post_process
}

function exe_update() {
    read_global_config

    pre_process

    _pre_detect
    detect_added_zones
    detect_deleted_zones
    detect_changed_zones
    update_added_zones
    update_deleted_zones
    update_changed_zones
    save_zones_state

    post_process
}

function exe_tasks() {
    read_global_config

    pre_process

    NEED_TASKS=1
    run_tasks

    post_process
}

while [ "${1}" != "" ]; do
    case "${1}" in
        "all" )
            exe_all
            exit 0
            ;;
        "update" )
            exe_update
            exit 0
            ;;
        "tasks" )
            exe_tasks
            exit 0
            ;;
        "-c" )
            shift
            CONFIG_PATH="${1}"
            ;;
        "-v" )
            ${LIB_DIR}/nsmgmt-version.sh
            exit 0
            ;;
        * )
            echo -ne "$(${LIB_DIR}/nsmgmt-version.sh)\n\n$(${LIB_DIR}/nsmgmt-help.sh)\n"
            exit 0
            ;;
    esac
    shift
done
