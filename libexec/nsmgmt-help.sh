#!/usr/bin/env bash

cat <<'___EOL___'
Usage:
  nsmgmt [option] command

Commands:
  all         run update, and run servers if necessary
  update      detect added/deleted/changed zone from `zones_src_path`,
              and apply to `zones_dst_path`
  servers     run servers tasks

Options:
  -c config   use `config` instead of ../etc/nsmgmt.conf
  -v          print version and exit
  -h          print this message and exit
___EOL___
