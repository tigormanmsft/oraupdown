# oraupdown
Script to manage a network port (default: 63000) based on value of DATABASE_ROLE in V$DATABASE.  The intention of this script is to enable the use of an Azure load balancer to act as a "virtual IP" (or VIP) for an Oracle DataGuard configuration.

# Description:

Script to be used with Azure load balancers to keep a specified port active when the specified database is an Oracle DataGuard PRIMARY.  If the database is not open and not a PRIMARY database, then the specified port is not to be active.

# Command-line Parameters:

Call syntax...

    oraupdown.sh ORACLE_SID [ sleepSecs [ lsnrName [ port ] ] ]

Parameters...
- ORACLE_SID      (mandatory - no default value) ORACLE_SID value for database
- sleepSecs       (optional - default value: 10 seconds) interval between database checks
- lsnrName        (optional - default value: LISTENER) name of Oracle TNS LISTENER process
- port            (optional - default value: 63000) port for Azure LB to monitor

# Suggested installation

Create an entry in the "crontab" of the OS account running the script (i.e. "oracle")...

    * * * * * if [[ "`ps -eaf | grep oraupdown | grep -v grep`" = "" ]]; then nohup ${HOME}/oraupdown.sh oradb01 > ${HOME}/oraupdown_out.txt 2> ${HOME}/oraupdown_err.txt; fi

To explain this command, every minute of every day the Linux "cron" utility will check to see if the "oraupdown.sh" script is running or not.  If the script is running, then no further action.  If the script is not running, then the script will be started so that all standard output and standard error output is logged in the "$HOME" directory of the "oracle" OS account.  Please be aware that the script itself is designed to run continuously, and that this "cron" entry is intended to ensure startup at the time of VM startup, and restart in the event the script is killed inadvertently.

This method of installation is suggested mainly because it is universal to all variants and versions of Linux (and UNIX), and because it easily illustrates the intention.  Modern utilities used in popular modern Linux variants, such as "systemctl", may be preferred over this admittedly out-of-date suggestion.

# Dependencies:

Installation of Linux "nc" command:  "sudo yum install -y nc" on Oracle Enterprise Linux (or equivalent on other Linux variant)

# Diagnostics:

- Log file "oraupdown.log" - located in $HOME directory of the OS account running the script.
- Log file "oraupdown_nc.log" contains output from Linux "nc" command.

On the database VM, entries in an OS account's "cron" table can be listed using the "crontab -l" command.  The existence of the running "oraupdown.sh" script can be verified using a Linux command like "ps -eaf | grep oraupdown".  The status of the designated network port can be verified using either the Linux command "netstat -a | grep 63000" or the Linux command "ps -eaf | grep nc".
