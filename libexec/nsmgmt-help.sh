#!/usr/bin/env bash

cat <<'___EOL___'
Usage:
  nsmgmt all       run update, and run servers if necessary
  nsmgmt update    detect added/deleted/changed zone from `zones_src_path`,
                   and apply to `zones_dst_path`
  nsmgmt servers   run servers tasks

Help:
  nsmgmt -v        print version and exit
  nsmgmt -h        print this message and exit
___EOL___
