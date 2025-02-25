#!/bin/bash

# array of directories to monitor and their custom display names (example, change them)
declare -A DISK_MAP=(
    ["/dev/nvme0n1p2"]="System SSD"
    ["/dev/sda1"]="Backup HDD"
    ["/dev/sdb1"]="Main HDD"
)

# constants
THRESHOLDS=(70 80 90 95)                                              # disk space thresholds in %
COOLDOWN_PERIOD_MINUTES=120                                           # in minutes (notification cooldown, only for highest threshold)
NOTIFICATION_STATE_FILE="/var/tmp/disk_monitor_notification_state"    # temporary file for saving notifitacion state

# ntfy
NTFY_URL="<ntfy-topic-url>"
NTFY_AUTH="<ntfy-http-auth-header>"
NTFY_TITLE="Disk Space Alert"
NTFY_PRIORITY="high"
NTFY_TAGS="warning"


# initialize the notification state file if it doesn't exist
if [ ! -f "$NOTIFICATION_STATE_FILE" ]; then
    echo "Notification state file does not exist. Creating..."
    > "$NOTIFICATION_STATE_FILE"        # create an empty file
fi

# read the current notification states into an associative array
declare -A NOTIFICATION_STATES
while IFS= read -r line; do
    DIRECTORY=$(echo "$line" | cut -d '|' -f1)
    THRESHOLD=$(echo "$line" | cut -d '|' -f2)
    TIMESTAMP=$(echo "$line" | cut -d '|' -f3)
    NOTIFICATION_STATES["$DIRECTORY|$THRESHOLD"]=$TIMESTAMP
done < "$NOTIFICATION_STATE_FILE"

HIGHEST_THRESHOLD=${THRESHOLDS[-1]}
CURRENT_TIMESTAMP=$(date +%s)
COOLDOWN_PERIOD_SECONDS=$((COOLDOWN_PERIOD_MINUTES * 60))
DISKS_LOW_SPACE=""

echo "Checking disk space..."

# loop through each directory
for DIRECTORY in "${!DISK_MAP[@]}"; do
    # get current disk stats
    DISK_USAGE=$(df -h --output=pcent "$DIRECTORY" | tail -n 1 | tr -d ' %')
    AVAIL_SPACE=$(df -h -B 1G --output=avail "$DIRECTORY" | tail -n 1 | tr -d ' ')
    TOTAL_SPACE=$(df -h -B 1G --output=size "$DIRECTORY" | tail -n 1 | tr -d ' ')

    # find the highest crossed threshold for this disk
    HIGHEST_CROSSED_THRESHOLD=0
    for THRESHOLD in "${THRESHOLDS[@]}"; do
        if [ "$DISK_USAGE" -ge "$THRESHOLD" ]; then
            HIGHEST_CROSSED_THRESHOLD=$THRESHOLD
        fi
    done

    if [ "$HIGHEST_CROSSED_THRESHOLD" -gt 0 ]; then
        KEY="$DIRECTORY|$HIGHEST_CROSSED_THRESHOLD"
        LAST_NOTIFICATION_TIMESTAMP=${NOTIFICATION_STATES["$KEY"]:-0}

        if (( HIGHEST_CROSSED_THRESHOLD == HIGHEST_THRESHOLD )); then
            # continuous notification for the highest threshold
            if (( CURRENT_TIMESTAMP - LAST_NOTIFICATION_TIMESTAMP >= COOLDOWN_PERIOD_SECONDS )); then
                echo "Disk \"${DIRECTORY}\" is above the maximum threshold of ${HIGHEST_CROSSED_THRESHOLD}%"
                DISKS_LOW_SPACE+="${DISK_MAP[$DIRECTORY]}: $DISK_USAGE% [$AVAIL_SPACE GB / $TOTAL_SPACE GB]"$'\n'
                NOTIFICATION_STATES["$KEY"]=$CURRENT_TIMESTAMP
                NTFY_PRIORITY="highest"         # optional
            fi
        else
            # notify only once for smaller thresholds
            if (( LAST_NOTIFICATION_TIMESTAMP == 0 )); then
                echo "Disk \"${DIRECTORY}\" crossed the threshold of ${HIGHEST_CROSSED_THRESHOLD}%"
                DISKS_LOW_SPACE+="${DISK_MAP[$DIRECTORY]}: $DISK_USAGE% [$AVAIL_SPACE GB / $TOTAL_SPACE GB]"$'\n'
                NOTIFICATION_STATES["$KEY"]=$CURRENT_TIMESTAMP
            fi
        fi
    fi


    # reset notification states for thresholds not crossed
    for THRESHOLD in "${THRESHOLDS[@]}"; do
        if [ "$THRESHOLD" -gt "$HIGHEST_CROSSED_THRESHOLD" ]; then
            NOTIFICATION_STATES["$DIRECTORY|$THRESHOLD"]=0
        fi
    done
done

# send notification if any disks have low disk space
if [ -n "$DISKS_LOW_SPACE" ]; then
    # add format info (optional)
    # DISKS_LOW_SPACE="Disk: Usage [Available / Total]"$'\n\n'$DISKS_LOW_SPACE
    echo "Sending notification about disk usage..."

    # send notification
    curl -s -o "/dev/null" \
    -H "Authorization: $NTFY_AUTH" \
    -H "Priority: $NTFY_PRIORITY" \
    -H "Tags: $NTFY_TAGS" \
    -H "Title: $NTFY_TITLE" \
    -d "$DISKS_LOW_SPACE" \
    "$NTFY_URL"

    if [ $? -eq 0 ]; then
        echo "Notification sent successfully"
    else
        echo "Notification failed to be sent"
    fi
fi

# update the notification state file
> "$NOTIFICATION_STATE_FILE"
for KEY in "${!NOTIFICATION_STATES[@]}"; do
    echo "$KEY|${NOTIFICATION_STATES[$KEY]}" >> "$NOTIFICATION_STATE_FILE"
done
