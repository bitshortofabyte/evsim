#!/bin/bash

set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_DIR="$BASE_DIR/.runtime"
LOG_DIR="$RUNTIME_DIR/logs"
PID_FILE="$RUNTIME_DIR/pids.env"

PYTHON_BIN="$BASE_DIR/.venv/bin/python"
if [[ ! -x "$PYTHON_BIN" ]]; then
    PYTHON_BIN="python3"
fi

start_process() {
    local name="$1"
    local cmd="$2"
    local log_file="$LOG_DIR/$3"

    bash -c "$cmd" >"$log_file" 2>&1 &
    local pid=$!
    echo "$pid"
}

is_running() {
    local pid="$1"
    if [[ -z "${pid:-}" ]]; then
        return 1
    fi
    kill -0 "$pid" 2>/dev/null
}

ensure_dirs() {
    mkdir -p "$RUNTIME_DIR" "$LOG_DIR"
}

write_pid_file() {
    local ingestor_pid="$1"
    local django_pid="$2"
    local ev_pids_csv="$3"
    local ev_count="$4"

    cat >"$PID_FILE" <<EOF
INGESTOR_PID=$ingestor_pid
DJANGO_PID=$django_pid
EV_PIDS_CSV="$ev_pids_csv"
EV_COUNT=$ev_count
EOF
}

load_pids() {
    if [[ ! -f "$PID_FILE" ]]; then
        return 1
    fi
    # shellcheck disable=SC1090
    source "$PID_FILE"
    return 0
}

start_stack() {
    ensure_dirs

    if load_pids; then
        if is_running "${INGESTOR_PID:-}" || is_running "${DJANGO_PID:-}"; then
            echo "Stack appears to already be running. Run '$0 stop' first."
            exit 1
        fi
    fi

    local ev_count=$((RANDOM % 9 + 2))
    local ev_pids=()

    echo "Starting MQTT -> Mongo ingestor..."
    local ingestor_pid
    ingestor_pid=$(start_process "ingestor" "\"$PYTHON_BIN\" \"$BASE_DIR/mqtt_to_mongodb.py\"" "mqtt_to_mongodb.log")
    sleep 1

    echo "Starting $ev_count EV simulator instance(s)..."
    for i in $(seq 1 "$ev_count"); do
        local vehicle_id
        vehicle_id="EV-SIM-$i"
        local ev_pid
        ev_pid=$(start_process "ev-$i" "\"$PYTHON_BIN\" \"$BASE_DIR/ev.py\" --vehicle-id \"$vehicle_id\"" "ev_$i.log")
        ev_pids+=("$ev_pid")
    done

    echo "Starting Django server..."
    local django_pid
    django_pid=$(start_process "django" "\"$PYTHON_BIN\" \"$BASE_DIR/manage.py\" runserver 127.0.0.1:8000" "django.log")

    local ev_pids_csv
    ev_pids_csv="$(IFS=,; echo "${ev_pids[*]}")"
    write_pid_file "$ingestor_pid" "$django_pid" "$ev_pids_csv" "$ev_count"

    echo "Stack started."
    echo "  EV instances: $ev_count"
    echo "  Django URL: http://127.0.0.1:8000"
    echo "  Logs: $LOG_DIR"
}

stop_pid() {
    local pid="$1"
    if is_running "$pid"; then
        kill "$pid" 2>/dev/null || true
    fi
}

stop_stack() {
    if ! load_pids; then
        echo "No PID file found. Nothing to stop."
        return 0
    fi

    echo "Stopping Django..."
    stop_pid "${DJANGO_PID:-}"

    if [[ -n "${EV_PIDS_CSV:-}" ]]; then
        IFS=',' read -r -a ev_pids <<<"$EV_PIDS_CSV"
        echo "Stopping EV simulators..."
        for pid in "${ev_pids[@]}"; do
            stop_pid "$pid"
        done
    fi

    echo "Stopping MQTT -> Mongo ingestor..."
    stop_pid "${INGESTOR_PID:-}"

    rm -f "$PID_FILE"
    echo "Stack stopped."
}

status_stack() {
    if ! load_pids; then
        echo "Stack status: not running (no PID file)."
        return 0
    fi

    echo "Stack status:"
    if is_running "${INGESTOR_PID:-}"; then
        echo "  Ingestor: running (PID ${INGESTOR_PID})"
    else
        echo "  Ingestor: not running"
    fi

    if is_running "${DJANGO_PID:-}"; then
        echo "  Django: running (PID ${DJANGO_PID})"
    else
        echo "  Django: not running"
    fi

    if [[ -n "${EV_PIDS_CSV:-}" ]]; then
        IFS=',' read -r -a ev_pids <<<"$EV_PIDS_CSV"
        local running_count=0
        for pid in "${ev_pids[@]}"; do
            if is_running "$pid"; then
                running_count=$((running_count + 1))
            fi
        done
        echo "  EV simulators: $running_count/${#ev_pids[@]} running"
    else
        echo "  EV simulators: none tracked"
    fi
}

show_logs() {
    ensure_dirs
    echo "Log files:"
    ls -1 "$LOG_DIR"
}

case "${1:-}" in
    start)
        start_stack
        ;;
    stop)
        stop_stack
        ;;
    restart)
        stop_stack
        sleep 1
        start_stack
        ;;
    status)
        status_stack
        ;;
    logs)
        show_logs
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|logs}"
        exit 1
        ;;
esac
