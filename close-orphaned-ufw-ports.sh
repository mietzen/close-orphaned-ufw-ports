#!/bin/bash

source /etc/close-orphaned-ufw-ports/config

function start {
    if [ -f ${PID_FILE} ]; then 
        if [ $(ps ${PID} > /dev/null) ]; then
            echo "close-orphaned-ufw-ports is already running, pid: $(cat ${PID_FILE})"
            exit 1
        fi
    fi
    # In case of ungraceful exit make sure tmp files are all cleared
    rm -rf ${ORPHANED_PORTS_FILE} ${STOP_FILE} ${PID_FILE}

    touch ${ORPHANED_PORTS_FILE}
    echo "$$" > ${PID_FILE}
    while [ ! -f ${STOP_FILE} ]; do
        # Get Listing ports from netstat
        LISTING_PORTS=$(netstat -tulpn4 | grep "LISTEN" | awk 'BEGIN{OFS="/"} { print $4,$1}' | cut -d':' -f2)
        # Get opened ports from UFW
        OPENED_PORTS_UFW=$(ufw status | grep -oP '^\d{1,5}/(tcp|udp)(?!\s\(v6\))')

        PORTS_TO_CLOSE=diff -wB <(echo "$LISTING_PORTS") <(echo "$OPENED_PORTS_UFW") | grep -oP '^<.*' | cut -d' ' -f2

        if [[ -z "${PORTS_TO_CLOSE}" ]]; then 
            for port in ${PORTS_TO_CLOSE}; do
                if ! grep -q ${port} ${WHITELISTED_PORTS_FILE}; then
                    if grep -q ${port} ${ORPHANED_PORTS_FILE}; then
                        first_apperance=$(grep ${port} ${ORPHANED_PORTS_FILE} | awk '{print $1}')
                        if [[ $(( first_apperance - $(date +%s) )) -ge $GRACE_PERIOD ]]; then
                            echo "${port} is opend and unused for more than ${GRACE_PERIOD} Seconds."
                            rule=$(ufw status numbered | grep -oP "(?<=\[)\s?\d(?=]\s$(sed 's#/#\\/#g' <<< ${port}))" | xargs)
                            ufw delete ${rule}
                            sed -i "/${first_apperance} ${port}/d" ${ORPHANED_PORTS_FILE}
                            echo "Closed Port ${port}"
                        fi
                    else
                        echo "$(date +%s) ${port}" >> ${ORPHANED_PORTS_FILE}
                    fi
                fi
            done
        fi
        sleep 5
    done
    rm -rf ${ORPHANED_PORTS_FILE} ${PID_FILE} ${STOP_FILE}
}

function stop {
    PID=$(cat ${PID_FILE})
    touch ${STOP_FILE}
    GRACEFUL_EXIT=false
    for i in {0..10}; do
        if [ ! $(ps ${PID} > /dev/null) ]; then
            GRACEFUL_EXIT=true
            break
        fi
        echo "wating for process to end gracefully"
        sleep 2
    done
    if [ ! ${GRACEFUL_EXIT} ] ; then
        kill -9 ${PID}
        rm -rf ${ORPHANED_PORTS_FILE} ${PID_FILE} ${STOP_FILE}
        echo "process was terminated ungracefully after 20 seconds"
        exit 1
    fi
}

case $1 in
    start)
        start()
        ;;
    stop) 
        stop()
        ;;
    *)
        echo "Unkown argument: $1"
        echo "Known arguments: start, stop"
        exit 1
        ;;
esac

exit 0
