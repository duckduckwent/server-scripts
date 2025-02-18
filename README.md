# Server monitoring
Everyday monitoring scripts for your server

## Prerequisites
### Script constants
Each script has certain configurable constants at the top of the file, most of them are okay to be left as is, but some of them need to be changed.

overheat-monitor:
  - NTFY_URL and NTFY_AUTH need to be changed (explained in the next chapter)
  - TEMP_THRESHOLD specifies the temperature at which notfication publishing starts
  - OVERHEATING_DURATION specifies how long overheating needs to occur for notifications to start getting published
  - CHECK_TEMP_INTERVAL specifies the time between temperature checks (shouldn't be too high)
  - NOTIFICATION_COOLDOWN specifies how much time needs to pass inbetween notifications, before getting another one (prevent spamming)

disk-monitor:
  - DISK_MAP array needs to be configured in order to specify which disks to monitor and have their display names set for notification purposes
  - NTFY_URL and NTFY_AUTH need to be changed (explained in the next chapter)
  - THRESHOLDS specifies multiple thresholds at which notification is triggered, but the highest threshold sends notifications indefinitely
  - COOLDOWN_PERIOD_MINUTES specifies the notification cooldown (only applies when sending notifications for the highest threshold)

### NTFY
Since all scripts use ntfy as the notification service, you need to change the NTFY_URL constant in your script to your topic url, also change NTFY_AUTH if you need authentication for that topic (can be basic or bearer).

If you want access control for your topic, but don't have it configured, follow this ntfy documentation: https://docs.ntfy.sh/config/#access-control

Once access control is set up, follow this ntfy documentation to generate the http authorization header (basic of bearer) and save it in the scripts NTFY_AUTH variable: https://docs.ntfy.sh/publish/?h=basic+auth#authentication

If you don't use ntfy at the moment, consider selfhosting using docker (or baremetal if you wish): https://docs.ntfy.sh/install/#docker

### sensors
This is needed for overheat-monitor script to work (you can still modify the script to use something else).

To install it on Ubuntu/Debian:
```
sudo apt install lm-sensors
```

Next step is scanning your system for hardware monitoring chips to use (this is an interactive command):
```
sudo sensors-detect
```

Once that's configured it should work. It can simply be tested by looking at the output of the 'sensors' command in the terminal.

## Systemd setup
### overheat-monitor
Create a systemd service configuration file:
```
sudo nano /etc/systemd/system/overheat-monitor.service
```

Add the following content (change ExecStart path to script):
```
[Unit]
Description=Overheat Monitoring Service
After=network-online.target

[Service]
ExecStart=/path/to/overheat-monitor.sh
Restart=always

[Install]
WantedBy=multi-user.target
```

Then enable the service and start it:
```
sudo systemctl daemon-reload
sudo systemctl enable overheat-monitor.service
sudo systemctl start overheat-monitor.service
```

To check the service logs:
```
journalctl -u overheat-monitor
```

### disk-monitor
Create a systemd service configuration file:
```
sudo nano /etc/systemd/system/disk-monitor.service
```

Add the following content (change ExecStart path to script):
```
[Unit]
Description=Disk space monitoring service
After=network-online.target

[Service]
ExecStart=/path/to/disk-monitor.sh
```

Now create a timer file for that systemd service:
```
sudo nano /etc/systemd/system/disk-monitor.timer
```

And add the following:
```
[Unit]
Description=Run disk space monitoring service periodically

[Timer]
OnBootSec=1m
OnUnitActiveSec=5m
Unit=disk-monitor.service

[Install]
WantedBy=timers.target
```

OnBootSec specifies how long after boot it should trigger and OnUnitActiveSec specifies the interval after the last execution before the timer triggers the service again.

Then enable the service and start it:
```
sudo systemctl daemon-reload
sudo systemctl enable overheat-monitor.timer
sudo systemctl start overheat-monitor.timer
```

To verify the timer:
```
systemctl list-timers --all
```
