#!/usr/bin/env bash
# Start, stop, or connect to a local MariaDB sandbox with mariadb-shell, without an agent.
#
# Usage:
#   ./sandbox.sh up <port> <version>    deploy a sandbox, for example: ./sandbox.sh up 3412 12.3.3
#   ./sandbox.sh down <port>            stop and delete it
#   ./sandbox.sh sql <port> [args...]   run the mariadb client against it (reads stdin)
#
# The server binaries come from ~/.local/share/mariadb-sandbox-server/<version>, where the
# MariaDB AI Plugins' sandbox.deploy tool downloads them. If a version is missing there,
# ask your agent once to "deploy a MariaDB <version> sandbox", or point MARIADBD_HOME at
# any MariaDB installation directory.
#
# Every sandbox gets the same settings the tests used: root password "sandbox", TLS off,
# LOAD DATA LOCAL on, a 2 GB vector index cache, and a 4 GB InnoDB buffer pool.
set -euo pipefail

PASS=sandbox
cmd=${1:?usage: sandbox.sh up|down|sql <port> [...]}
port=${2:?port required}

case $cmd in
  up)
    version=${3:?version required, for example 12.3.3}
    home=${MARIADBD_HOME:-$HOME/.local/share/mariadb-sandbox-server/$version}
    mariadb-shell -- sandbox deploy "$port" --password=$PASS --ssl=false --mariadbdPath="$home" \
      --mariadbdOptions=local_infile=1,mhnsw_max_cache_size=2147483648,innodb_buffer_pool_size=4294967296
    ;;
  down)
    mariadb-shell -- sandbox stop "$port" --password=$PASS
    mariadb-shell -- sandbox delete "$port"
    ;;
  sql)
    shift 2
    exec mariadb --skip-ssl --local-infile=1 -h127.0.0.1 -P"$port" -uroot -p$PASS --table "$@"
    ;;
  *)
    echo "unknown command: $cmd" >&2
    exit 2
    ;;
esac
