#!/bin/bash

source /etc/close-orphaned-ufw-ports/config

function start_service {
    if [ -f ${PID_FILE} ]; then 
        if ps -p $(cat ${PID_FILE}) > /dev/null; then
            echo "close-orphaned-ufw-ports is already running, pid: $(cat ${PID_FILE})"
            exit 1
        fi
    fi
    # In case of ungraceful exit make sure tmp files are all cleared
    rm -rf ${ORPHANED_PORTS_FILE_V4} ${ORPHANED_PORTS_FILE_V6} ${STOP_FILE} ${PID_FILE}

    touch ${ORPHANED_PORTS_FILE_V4}
    touch ${ORPHANED_PORTS_FILE_V6}
    echo "$$" > ${PID_FILE}
    while [ ! -f ${STOP_FILE} ]; do
        # Get Listing ports from netstat
        LISTING_PORTS_V4=$(netstat -tulpn4 | grep "LISTEN" | awk 'BEGIN{OFS="/"} { print $4,$1}' | grep -oP '\d{1,5}\/(tcp|udp)')
        LISTING_PORTS_V6=$(netstat -tulpn6 | grep "LISTEN" | awk 'BEGIN{OFS="/"} { print $4,$1}' | grep -oP '\d{1,5}\/(tcp|udp)')
        # Get opened ports from UFW
        OPENED_PORTS_UFW_V4=$(ufw status | grep -v '(v6)' | grep -oP '^\d{1,5}(\/tcp|\/udp)?')
        OPENED_PORTS_UFW_V6=$(ufw status | grep '(v6)' | grep -oP '^\d{1,5}(\/tcp|\/udp)?')

        PORTS_TO_CLOSE_V4=$(diff -wB <(echo "$LISTING_PORTS_V4") <(echo "$OPENED_PORTS_UFW_V4") | grep -oP '^>.*' | cut -d' ' -f2)
        PORTS_TO_CLOSE_V6=$(diff -wB <(echo "$LISTING_PORTS_V6") <(echo "$OPENED_PORTS_UFW_V6") | grep -oP '^>.*' | cut -d' ' -f2)
        
        # Mark / Close unused ports
        if [ ! -z "${PORTS_TO_CLOSE_V4}" ]; then 
            for port in ${PORTS_TO_CLOSE_V4}; do
                if ! grep -q ${port} ${WHITELISTED_PORTS_FILE_V4}; then
                    if grep -q ${port} ${ORPHANED_PORTS_FILE_V4}; then
                        first_apperance=$(grep ${port} ${ORPHANED_PORTS_FILE_V4} | awk '{print $1}')
                        if [[ $(( $(date +%s) - first_apperance )) -ge $GRACE_PERIOD ]]; then
                            echo "${port} is opend and unused for more than ${GRACE_PERIOD} Seconds."
                            rule=$(ufw status numbered | grep -v '(v6)' | grep -oP "(?<=\[)\s?\d(?=]\s$(sed 's#/#\\/#g' <<< ${port}))" | xargs)
                            ufw --force delete ${rule}
                            sed -i "/${first_apperance} ${port}/d" ${ORPHANED_PORTS_FILE_V4}
                            echo "Closed Port ${port}"
                        fi
                    else
                        echo "$(date +%s) ${port}" >> ${ORPHANED_PORTS_FILE_V4}
                    fi
                fi
            done
        fi
        if [ ! -z "${PORTS_TO_CLOSE_V6}" ]; then 
            for port in ${PORTS_TO_CLOSE_V6}; do
                if ! grep -q ${port} ${WHITELISTED_PORTS_FILE_V6}; then
                    if grep -q ${port} ${ORPHANED_PORTS_FILE_V6}; then
                        first_apperance=$(grep ${port} ${ORPHANED_PORTS_FILE_V6} | awk '{print $1}')
                        if [[ $(( $(date +%s) - first_apperance )) -ge $GRACE_PERIOD ]]; then
                            echo "${port} (v6) is opend and unused for more than ${GRACE_PERIOD} Seconds."
                            rule=$(ufw status numbered | grep '(v6)' | grep -oP "(?<=\[)\s?\d(?=]\s$(sed 's#/#\\/#g' <<< ${port}))" | xargs)
                            ufw --force delete ${rule}
                            sed -i "/${first_apperance} ${port}/d" ${ORPHANED_PORTS_FILE_V6}
                            echo "Closed Port ${port} (v6)"
                        fi
                    else
                        echo "$(date +%s) ${port}" >> ${ORPHANED_PORTS_FILE_V6}
                    fi
                fi
            done
        fi

        # Delte recovered service ports from db
        for port in ${LISTING_PORTS_V4}; do
            if grep -q ${port} ${ORPHANED_PORTS_FILE_V4}; then
                if ! $(echo ${PORTS_TO_CLOSE_V4} | grep -q ${port}); then
                    echo "${port} has recovered within grace period."
                    first_apperance=$(grep ${port} ${ORPHANED_PORTS_FILE_V4} | awk '{print $1}')
                    echo "$first_apperance"
                    echo "$port"
                    sed -i "/${first_apperance} ${port}/d" ${ORPHANED_PORTS_FILE_V4}
                fi
            fi
        done
        for port in ${LISTING_PORTS_6}; do
            if grep -q ${port} ${ORPHANED_PORTS_FILE_V6}; then
                if ! $(echo ${PORTS_TO_CLOSE_V6} | grep -q ${port}); then
                    echo "${port} has recovered within grace period."
                    first_apperance=$(grep ${port} ${ORPHANED_PORTS_FILE_V6} | awk '{print $1}')
                    sed -i "/${first_apperance} ${port}/d" ${ORPHANED_PORTS_FILE_V6}
                fi
            fi
        done

        sleep 5
    done
    rm -rf ${ORPHANED_PORTS_FILE_V4} ${ORPHANED_PORTS_FILE_V6} ${PID_FILE} ${STOP_FILE}
}

function stop_service {
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
        rm -rf ${ORPHANED_PORTS_FILE_V4} ${ORPHANED_PORTS_FILE_V6} ${PID_FILE} ${STOP_FILE}
        echo "process was terminated ungracefully after 20 seconds"
        exit 1
    fi
}

case $1 in
    start)
        start_service
        ;;
    stop) 
        stop_service
        ;;
    *)
        echo "Unkown argument: $1"
        echo "Known arguments: start, stop"
        exit 1
        ;;
esac

exit 0
