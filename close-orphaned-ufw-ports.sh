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
        UFW_STATUS=$(ufw status)
        # Get Listing ports from netstat
        LISTING_PORTS_V4=$(netstat -tulpn4 | grep "LISTEN" | awk 'BEGIN{OFS="/"} { print $4,$1}' | grep -oP '\d{1,5}\/(tcp|udp)')
        LISTING_PORTS_V6=$(netstat -tulpn6 | grep "LISTEN" | awk 'BEGIN{OFS="/"} { print $4,$1}' | grep -oP '\d{1,5}\/(tcp|udp)')

        # Get opened ports from UFW 
        # Check for ports with protocol
        OPENED_PORTS_UFW_V4_WP=$(echo "$UFW_STATUS" | grep -P 'ALLOW\s+Anywhere' | grep -v '(v6)' | grep -oP '^\d{1,5}(\/tcp|\/udp)')
        OPENED_PORTS_UFW_V6_WP=$(echo "$UFW_STATUS" | grep -P 'ALLOW\s+Anywhere' | grep '(v6)' | grep -oP '^\d{1,5}(\/tcp|\/udp)')
        PORTS_TO_CLOSE_V4_WP=$(diff -wB <(echo "$LISTING_PORTS_V4") <(echo "$OPENED_PORTS_UFW_V4_WP") | grep -oP '^>.*' | cut -d' ' -f2)
        PORTS_TO_CLOSE_V6_WP=$(diff -wB <(echo "$LISTING_PORTS_V6") <(echo "$OPENED_PORTS_UFW_V4_WP") | grep -oP '^>.*' | cut -d' ' -f2)

        # Also check against rules without protocol 
        OPENED_PORTS_UFW_V4_WOP=$(echo "$UFW_STATUS" | grep -P 'ALLOW\s+Anywhere' | grep -v '(v6)' | grep -oP '^\d{1,5}\s')
        OPENED_PORTS_UFW_V6_WOP=$(echo "$UFW_STATUS" | grep -P 'ALLOW\s+Anywhere' | grep '(v6)' | grep -oP '^\d{1,5}\s')
        OPENED_PORTS_UFW_V4_WOP=$(while IFS= read -r line ; do port=$(tr -d '[:blank:]' <<< ${line}); echo -e "${port}/tcp\n${port}/udp"; done <<< $OPENED_PORTS_UFW_V4_WOP)
        OPENED_PORTS_UFW_V6_WOP=$(while IFS= read -r line ; do port=$(tr -d '[:blank:]' <<< ${line}); echo -e "${port}/tcp\n${port}/udp"; done <<< $OPENED_PORTS_UFW_V6_WOP)
        PORTS_TO_CLOSE_V4_WOP=$(diff -wB <(echo "$LISTING_PORTS_V4") <(echo "$OPENED_PORTS_UFW_V4_WOP") | grep -oP '^>.*' | cut -d' ' -f2)
        PORTS_TO_CLOSE_V6_WOP=$(diff -wB <(echo "$LISTING_PORTS_V6") <(echo "$OPENED_PORTS_UFW_V6_WOP") | grep -oP '^>.*' | cut -d' ' -f2)
        PORTS_TO_CLOSE_V4=''
        for port in $(cut -d'/' -f1 <<< $PORTS_TO_CLOSE_V4_WOP | uniq); do
            if grep -q "${port}/tcp" <<< ${PORTS_TO_CLOSE_V4_WOP}; then
                if grep -q "${port}/udp" <<< ${PORTS_TO_CLOSE_V4_WOP}; then
                    PORTS_TO_CLOSE_V4=$(echo -e "$PORTS_TO_CLOSE_V4\n${port}")
                else
                    echo "WARNING: ${port}/tcp is used but ${port} is opened for any protocol!"
                fi
            else
                echo "WARNING: ${port}/upd is used but ${port} is opened for any protocol!"
            fi
        done
        PORTS_TO_CLOSE_V6=''
        for port in $(cut -d'/' -f1 <<< $PORTS_TO_CLOSE_V6_WOP | uniq); do
            if grep -q "${port}/tcp" <<< ${PORTS_TO_CLOSE_V6_WOP}; then
                if grep -q "${port}/udp" <<< ${PORTS_TO_CLOSE_V6_WOP}; then
                    PORTS_TO_CLOSE_V6=$(echo -e "$PORTS_TO_CLOSE_V6\n${port}")
                else
                    echo "WARNING: ${port}/tcp6 is used but ${port} (v6) is opened for any protocol!"
                fi
            else
                echo "WARNING: ${port}/upd6 is used but ${port} (v6) is opened for any protocol!"
            fi
        done
        PORTS_TO_CLOSE_V4=$(echo -e "$PORTS_TO_CLOSE_V4\n$PORTS_TO_CLOSE_V4_WP" | sed -r '/^\s*$/d')
        PORTS_TO_CLOSE_V6=$(echo -e "$PORTS_TO_CLOSE_V6\n$PORTS_TO_CLOSE_V6_WP" | sed -r '/^\s*$/d')

        # Mark / Close unused ports
        if [ ! -z "${PORTS_TO_CLOSE_V4}" ]; then 
            for port in ${PORTS_TO_CLOSE_V4}; do
                if ! grep -qP "${port}$" ${WHITELISTED_PORTS_FILE_V4}; then
                    if grep -qP "${port}$" ${ORPHANED_PORTS_FILE_V4}; then
                        first_apperance=$(grep ${port} ${ORPHANED_PORTS_FILE_V4} | awk '{print $1}')
                        if [[ $(( $(date +%s) - first_apperance )) -ge $GRACE_PERIOD ]]; then
                            echo "${port} is opend and unused for more than ${GRACE_PERIOD} Seconds."
                            rule=$(ufw status numbered | grep -v '(v6)' | grep -oP "(?<=\[)\s?\d(?=]\s$(sed 's#/#\\/#g' <<< ${port}))" | xargs)
                            ufw --force delete ${rule}
                            sed -i "\|${first_apperance} ${port}|d" ${ORPHANED_PORTS_FILE_V4}
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
                if ! grep -qP "${port}$" ${WHITELISTED_PORTS_FILE_V6}; then
                    if grep -qP "${port}$" ${ORPHANED_PORTS_FILE_V6}; then
                        first_apperance=$(grep -P "${port}$" ${ORPHANED_PORTS_FILE_V6} | awk '{print $1}')
                        if [[ $(( $(date +%s) - first_apperance )) -ge $GRACE_PERIOD ]]; then
                            echo "${port} (v6) is opend and unused for more than ${GRACE_PERIOD} Seconds."
                            rule=$(ufw status numbered | grep '(v6)' | grep -oP "(?<=\[)\s?\d(?=]\s$(sed 's#/#\\/#g' <<< ${port}))" | xargs)
                            ufw --force delete ${rule}
                            sed -i "\|${first_apperance} ${port}|d" ${ORPHANED_PORTS_FILE_V6}
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
            if grep -qP "${port}$" ${ORPHANED_PORTS_FILE_V4}; then
                if ! $(echo ${PORTS_TO_CLOSE_V4} | grep -qP "${port}$"); then
                    echo "${port} has recovered within grace period."
                    first_apperance=$(grep -P "${port}$" ${ORPHANED_PORTS_FILE_V4} | awk '{print $1}')
                    sed -i "\|${first_apperance} ${port}|d" ${ORPHANED_PORTS_FILE_V4}
                fi
            fi
        done
        for port in ${LISTING_PORTS_6}; do
            if grep -q "${port}$" ${ORPHANED_PORTS_FILE_V6}; then
                if ! $(echo ${PORTS_TO_CLOSE_V6} | grep -qP "${port}$"); then
                    echo "${port} has recovered within grace period."
                    first_apperance=$(grep -P "${port}$" ${ORPHANED_PORTS_FILE_V6} | awk '{print $1}')
                    sed -i "\|${first_apperance} ${port}|d" ${ORPHANED_PORTS_FILE_V6}
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
