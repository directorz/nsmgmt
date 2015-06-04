#!/usr/bin/env bash
set -e

BIN_DIR=$(cd ${BASH_SOURCE[0]%/*} && pwd)
LIB_DIR=${BIN_DIR}/../libexec
ETC_DIR=${BIN_DIR}/../etc
DB_DIR=${BIN_DIR}/../var/db/nsmgmt
STATUS_PATH=${DB_DIR}/zones.status
STATUS_TMP_PATH=${DB_DIR}/zones.status.tmp
ZONES_TMP_DIR=${DB_DIR}/zones

declare -a ADDED_ZONES
declare -a DELETED_ZONES
declare -a CHANGED_ZONES
declare NEED_UPDATE=0

function read_global_config() {
    exec 1> >(awk '{print strftime("[%Y/%m/%d %H:%M:%S]"),$0;fflush()}')

    cd ${ETC_DIR}
    . nsmgmt.conf

    zones_src_path=$(cd ${zones_src_path:?} && pwd)
    zones_dst_path=$(cd ${zones_dst_path:?} && pwd)
    update_serial=${update_serial:=1}
    update_serial_cmdline=${update_serial_cmdline:="cat"}

    local i=0
    local len=${#servers_tasks[@]}
    [ ${len} -eq 0 ] && servers_tasks=()
    while [ ${i} -lt ${len} ]; do
        servers_tasks[${i}]=$(readlink -f ${servers_tasks[${i}]})
        i=$((i + 1))
    done
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

    (cd ${ZONES_TMP_DIR} && find . -type f | xargs rm -f)
    (cd ${zones_src_path} && find . -type f | xargs cp -a -t ${ZONES_TMP_DIR})
    (cd ${ZONES_TMP_DIR} && ls | xargs sha256sum | awk '{print $2":"$1}') > ${STATUS_TMP_PATH}

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
    [ ${len} -gt 0 ] && NEED_UPDATE=1

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

    cd - >/dev/null 2>&1
}

function update_deleted_zones() {
    local i=0
    local len=${#DELETED_ZONES[@]}
    [ ${len} -gt 0 ] && NEED_UPDATE=1

    while [ ${i} -lt ${len} ]; do
        rm -f ${zones_dst_path}/${DELETED_ZONES[${i}]} || :
        i=$((i + 1))
    done
}

function update_changed_zones() {
    local i=0
    local len=${#CHANGED_ZONES[@]}
    [ ${len} -gt 0 ] && NEED_UPDATE=1

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

    cd - >/dev/null 2>&1
}

function save_zones_state() {
    [ ${NEED_UPDATE} -eq 0 ] && return 0

    (cd ${ZONES_TMP_DIR} && ls | xargs sha256sum | awk '{print $2":"$1}') > ${STATUS_PATH}
    rm -f ${STATUS_TMP_PATH}
}

function run_servers_tasks() {
    if [ ${NEED_UPDATE} -eq 0 ]; then
        echo "zones have not been changed"
        return 0
    else
        echo "running servers tasks..."
    fi

    local i=0
    local len=${#servers_tasks[@]}
    while [ ${i} -lt ${len} ]; do
        . ${servers_tasks[${i}]}

        set +e

        if type generate_config >/dev/null 2>&1; then
            echo "[$((i + 1))] running generate_config..."
            generate_config ${zones_dst_path}
        fi

        if type sync_config >/dev/null 2>&1; then
            echo "[$((i + 1))] running sync_config..."
            sync_config ${zones_dst_path}
        fi

        if type reload_ns >/dev/null 2>&1; then
            echo "[$((i + 1))] running reload_ns..."
            reload_ns
        fi

        unset -f generate_config
        unset -f sync_config
        unset -f reload_ns

        set -e

        i=$((i + 1))
    done
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

    run_servers_tasks

    post_process
}

function exe_servers() {
    read_global_config

    pre_process

    NEED_UPDATE=1
    run_servers_tasks

    post_process
}

command="${1}"
case "${command}" in
    "update" )
        exe_update
        ;;
    "servers" )
        exe_servers
        ;;
    "-v" )
        ${LIB_DIR}/nsmgmt-version.sh
        ;;
    * )
        echo -ne "$(${LIB_DIR}/nsmgmt-version.sh)\n\n$(${LIB_DIR}/nsmgmt-help.sh)\n"
        ;;
esac
