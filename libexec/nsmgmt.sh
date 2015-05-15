#!/usr/bin/env bash
set -e

BIN_DIR=$(cd ${BASH_SOURCE[0]%/*} && pwd)
LIB_DIR=${BIN_DIR}/../libexec

command="${1}"
case "${command}" in
    "-v" )
        ${LIB_DIR}/nsmgmt-version.sh
        ;;
    * )
        echo -ne "$(${LIB_DIR}/nsmgmt-version.sh)\n\n$(${LIB_DIR}/nsmgmt-help.sh)\n"
        ;;
esac
