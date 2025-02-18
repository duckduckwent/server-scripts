#!/bin/bash

# constants
TEMP_THRESHOLD=85               # overheating temperature threshold in Celsius
OVERHEATING_DURATION=15         # time in minutes to trigger the first notification alert
CHECK_TEMP_INTERVAL=30          # time in seconds between temperature checks
NOTIFICATION_COOLDOWN=60        # time in minutes between notifications

# ntfy
NTFY_URL="<ntfy-topic-url>"          # CHANGE ME
NTFY_AUTH="<ntfy-http-auth-header>"  # CHANGE ME
NTFY_TITLE="Server Overheat Alert"
NTFY_MESSAGE="$(hostname) is overheating!"
NTFY_PRIORITY="high"
NTFY_TAGS="fire"

# auxilary constants (do not touch)
OVERHEAT_COUNT=0
OVERHEAT_COUNT_LIMIT=$((${OVERHEATING_DURATION:-10} * 60 / ${CHECK_TEMP_INTERVAL:-30}))
LAST_NOTIFICATION_TIME=0
NOTIFICATION_COOLDOWN_SEC=$((${NOTIFICATION_COOLDOWN:-60} * 60))

# initial info
echo "Started monitoring temperature."

send_notification() {
    local temperature=$1
    local current_time=$(date +%s)

    # check cooldown
    if (( current_time - LAST_NOTIFICATION_TIME >= NOTIFICATION_COOLDOWN_SEC )); then
        curl \
          -H "Authorization: ${NTFY_AUTH}" \
          -H "Title: ${NTFY_TITLE}" \
          -H "Priority: ${NTFY_PRIORITY}" \
          -H "Tags: ${NTFY_TAGS}" \
          -d "${NTFY_MESSAGE}"$'\n'"Current temperature: ${temperature}°C" \
          "${NTFY_URL}"

        # if curl failed
        if [ $? -ne 0 ]; then
            echo "Notification couldn't be sent. Retrying after a while..."
        else
            LAST_NOTIFICATION_TIME=$current_time
            echo "Notification sent for overheating."
        fi
    else
        echo "Notification skipped due to cooldown."
    fi
}

# monitor temperatures
while true; do
    # get CPU temperature
    temperature=$(sensors | awk '/^Package id 0:/ {print $4}' | tr -d '+°C')

    if [ -z "$temperature" ]; then
        echo "Unable to fetch temperature. Check 'sensors' configuration."
        exit 1
    fi

    # check if temperature exceeds threshold
    if (( $(echo "$temperature >= ${TEMP_THRESHOLD:-85}" | bc -l) )); then
        echo "Overheating detected! Temp: ${temperature}°C (Count: ${OVERHEAT_COUNT}/${OVERHEAT_COUNT_LIMIT})"
        ((OVERHEAT_COUNT++))
    else
        OVERHEAT_COUNT=0 # reset if temperature is normal
    fi

    # if overheating persists for the specified duration
    if (( OVERHEAT_COUNT >= OVERHEAT_COUNT_LIMIT )); then
        send_notification "$temperature"
        OVERHEAT_COUNT=OVERHEAT_COUNT_LIMIT     # limit max OVERHEAT_COUNT
    fi

    sleep "${CHECK_TEMP_INTERVAL:-30}"
done
