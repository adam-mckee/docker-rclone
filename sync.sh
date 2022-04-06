#!/bin/sh

set -e

function run_commands {
	COMMANDS=$1
	while IFS= read -r cmd; do echo $cmd && eval $cmd ; done < <(printf '%s\n' "$COMMANDS")
}

function run_exit_commands {
	set +e
	set +o pipefail
	run_commands "${POST_COMMANDS_EXIT:-}"
}

trap run_exit_commands EXIT

echo "INFO: Starting sync.sh pid $$ $(date)"

if [ `lsof | grep $0 | wc -l | tr -d ' '` -gt 1 ]
then
  echo "WARNING: A previous $RCLONE_CMD is still running. Skipping new $RCLONE_CMD command."
else
  run_commands "${PRE_COMMANDS:-}"

  # Delete logs by user request
  if [ ! -z "${ROTATE_LOG##*[!0-9]*}" ]
  then
    echo "INFO: Removing logs older than $ROTATE_LOG day(s)..."
    touch /logs/tmp.txt && find /logs/*.txt -mtime +$ROTATE_LOG -type f -delete && rm -f /logs/tmp.txt
  fi

  echo $$ > /tmp/sync.pid

  # Evaluate any sync options
  if [ ! -z "$SYNC_OPTS_EVAL" ]
  then
    SYNC_OPTS_EVALUALTED=$(eval echo $SYNC_OPTS_EVAL)
    echo "INFO: Evaluated SYNC_OPTS_EVAL to: ${SYNC_OPTS_EVALUALTED}"
    SYNC_OPTS_ALL="${SYNC_OPTS} ${SYNC_OPTS_EVALUALTED}"
  else
    SYNC_OPTS_ALL="${SYNC_OPTS}"
  fi

  if [ ! -z "$RCLONE_DIR_CHECK_SKIP" ]
  then
    echo "INFO: Skipping source directory check..."
    if [ ! -z "$OUTPUT_LOG" ]
    then
      d=$(date +%Y_%m_%d-%H_%M_%S)
      LOG_FILE="/logs/$d.txt"
      echo "INFO: Log file output to $LOG_FILE"
      echo "INFO: Starting rclone $RCLONE_CMD $SYNC_SRC $SYNC_DEST $RCLONE_OPTS $SYNC_OPTS_ALL --log-file=${LOG_FILE}"
      set +e
      eval "rclone $RCLONE_CMD $SYNC_SRC $SYNC_DEST $RCLONE_OPTS $SYNC_OPTS_ALL --log-file=${LOG_FILE}"
      export RETURN_CODE=$?
      set -e
    else
      echo "INFO: Starting rclone $RCLONE_CMD $SYNC_SRC $SYNC_DEST $RCLONE_OPTS $SYNC_OPTS_ALL"
      set +e
      eval "rclone $RCLONE_CMD $SYNC_SRC $SYNC_DEST $RCLONE_OPTS $SYNC_OPTS_ALL"
      export RETURN_CODE=$?
      set -e
    fi
  else
    set e+
    if test "$(rclone --max-depth $RCLONE_DIR_CMD_DEPTH $RCLONE_DIR_CMD "$(eval echo $SYNC_SRC)" $RCLONE_OPTS)"; then
    set e-
    echo "INFO: Source directory is not empty and can be processed without clear loss of data"
    if [ ! -z "$OUTPUT_LOG" ]
    then
      d=$(date +%Y_%m_%d-%H_%M_%S)
      LOG_FILE="/logs/$d.txt"
      echo "INFO: Log file output to $LOG_FILE"
      echo "INFO: Starting rclone $RCLONE_CMD $SYNC_SRC $SYNC_DEST $RCLONE_OPTS $SYNC_OPTS_ALL --log-file=${LOG_FILE}"
      set +e
      eval "rclone $RCLONE_CMD $SYNC_SRC $SYNC_DEST $RCLONE_OPTS $SYNC_OPTS_ALL --log-file=${LOG_FILE}"
      export RETURN_CODE=$?
      set -e
    else
      echo "INFO: Starting rclone $RCLONE_CMD $SYNC_SRC $SYNC_DEST $RCLONE_OPTS $SYNC_OPTS_ALL"
      set +e
      eval "rclone $RCLONE_CMD $SYNC_SRC $SYNC_DEST $RCLONE_OPTS $SYNC_OPTS_ALL"
      set -e
      export RETURN_CODE=$?
    fi
    else
      echo "WARNING: Source directory is empty. Skipping $RCLONE_CMD command."
    fi
  fi

  if [ $RETURN_CODE -ne 0 ]; then
    run_commands "${POST_COMMANDS_FAILURE:-}"
    exit $RETURN_CODE
  fi

  echo Backup successful

  rm -f /tmp/sync.pid
  run_commands "${POST_COMMANDS_SUCCESS:-}"
fi
