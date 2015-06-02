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

function read_global_config() {
    cd ${ETC_DIR}
    . nsmgmt.conf

    zones_src_path=$(cd ${zones_src_path:?} && pwd)
    zones_dst_path=$(cd ${zones_dst_path:?} && pwd)
    update_serial=${update_serial:=1}
    update_serial_cmdline=${update_serial_cmdline:="cat"}
}

function pre_process() {
    set +e

    local retval=0

    if [ "${pre_process_cmdline}" != "" ]; then
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

    (cd ${ZONES_TMP_DIR} && ls | xargs -P 5 -n 1000 -i rm -f {})
    (cd ${zones_src_path} && find . -type f | xargs -P 5 -n 1000 -i cp -a {} ${ZONES_TMP_DIR})
    (cd ${ZONES_TMP_DIR} && ls | xargs -P 5 -n 1000 -i sha256sum {} | awk '{print $2":"$1}') > ${STATUS_TMP_PATH}
}

function detect_added_zones() {
    local zone
    while read zone; do
        ADDED_ZONES+=("${zone}")
    done < <(comm -23 <(cut -d':' -f1 ${STATUS_TMP_PATH} | sort) <(cut -d':' -f1 ${STATUS_PATH} | sort))
}

function detect_deleted_zones() {
    local zone
    while read zone; do
        DELETED_ZONES+=("${zone}")
    done < <(comm -13 <(cut -d':' -f1 ${STATUS_TMP_PATH} | sort) <(cut -d':' -f1 ${STATUS_PATH} | sort))
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
}

function update_added_zones() {
    local n
    n=${#ADDED_ZONES[@]}
    n=$((n - 1))

    cd ${ZONES_TMP_DIR}

    if [ ${update_serial} -eq 1 ]; then
        while [ ${n} -ge 0 ]; do
            cat ${ADDED_ZONES[${n}]} | eval "${update_serial_cmdline}" > ${zones_dst_path}/${ADDED_ZONES[${n}]}
            n=$((n - 1))
        done
    else
        while [ ${n} -ge 0 ]; do
            cat ${ADDED_ZONES[${n}]} > ${zones_dst_path}/${ADDED_ZONES[${n}]}
            n=$((n - 1))
        done
    fi

    cd - >/dev/null 2>&1
}

function update_deleted_zones() {
    local n
    n=${#DELETED_ZONES[@]}
    n=$((n - 1))
    while [ ${n} -ge 0 ]; do
        rm -f ${zones_dst_path}/${DELETED_ZONES[${n}]} || :
        n=$((n - 1))
    done
}

function update_changed_zones() {
    local n
    n=${#CHANGED_ZONES[@]}
    n=$((n - 1))

    cd ${ZONES_TMP_DIR}

    if [ ${update_serial} -eq 1 ]; then
        while [ ${n} -ge 0 ]; do
            cat ${CHANGED_ZONES[${n}]} | eval "${update_serial_cmdline}" > ${zones_dst_path}/${CHANGED_ZONES[${n}]}
            n=$((n - 1))
        done
    else
        while [ ${n} -ge 0 ]; do
            cat ${CHANGED_ZONES[${n}]} > ${zones_dst_path}/${CHANGED_ZONES[${n}]}
            n=$((n - 1))
        done
    fi

    cd - >/dev/null 2>&1
}

function save_zones_state() {
    (cd ${ZONES_TMP_DIR} && ls | xargs -P 5 -n 1000 -i sha256sum {} | awk '{print $2":"$1}') > ${STATUS_PATH}
    rm -f ${STATUS_TMP_PATH}
}

function run_servers_tasks() {
    #generate_config
    #sync_config
    #reload_ns
    :
}

function post_process() {
    set +e

    local retval=0

    if [ "${post_process_cmdline}" != "" ]; then
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

command="${1}"
case "${command}" in
    "update" )
        exe_update
        ;;
    "-v" )
        ${LIB_DIR}/nsmgmt-version.sh
        ;;
    * )
        echo -ne "$(${LIB_DIR}/nsmgmt-version.sh)\n\n$(${LIB_DIR}/nsmgmt-help.sh)\n"
        ;;
esac
