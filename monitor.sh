#!/bin/bash

# Script to check if Splunk is running and start it if not
# Created: $(date)

# Path to Splunk binary - modify as needed
SPLUNK_PATH="/opt/splunk/bin/splunk"
LOG_FILE="/opt/splunk/var/log/splunk_monitor.log"

# Log function
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Check if log file exists and is writable, create if not
if [ ! -f "$LOG_FILE" ]; then
    touch "$LOG_FILE" 2>/dev/null
    if [ $? -ne 0 ]; then
        # Fall back to splunk user's home directory if we can't write to the default location
        LOG_FILE="$HOME/splunk_monitor.log"
        touch "$LOG_FILE"
    fi
fi

# Verify Splunk path exists
if [ ! -f "$SPLUNK_PATH" ]; then
    log_message "ERROR: Splunk binary not found at $SPLUNK_PATH. Please update the script with the correct path."
    exit 1
fi

# Check if Splunk is running
if pgrep -f "splunkd" > /dev/null; then
    log_message "Splunk is running. No action needed."
else
    log_message "Splunk is not running. Attempting to start..."
    
    # Try to start Splunk
    $SPLUNK_PATH start
    
    # Check if start was successful
    if [ $? -eq 0 ]; then
        log_message "Successfully started Splunk."
    else
        log_message "Failed to start Splunk. Manual intervention may be required."
    fi
fi

exit 0
