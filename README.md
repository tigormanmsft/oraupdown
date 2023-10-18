# oraupdown.sh script

The overall intention of this bash shell script is to enable the use of an Azure load balancer to act as a "virtual IP" (or VIP) for an Oracle DataGuard configuration.  It should be noted that the Oracle DataGuard product itself lacks a "virtual IP" or VIP capability as supplied by Oracle, so this functionality covers that gap.

This bash shell script plays a small but important role by managing a network port (default: 63000) on the backend VMs on which the Oracle database instances reside, based on the value of the column DATABASE_ROLE in the Oracle data dictionary view V$DATABASE.   

# Script description:

This script is intended to be deployed on all Azure VMs running Oracle database instances which are part of an Oracle DataGuard "HA Cluster".  That is, if the VM contains a database instance that is either a PRIMARY database or a PHYSICAL STANDBY database related to the PRIMARY, whose IP address is included in the "backend pool" of the Azure load balancer acting as a VIP or virtual IP, then this bash shell script should be running continuously on the VM to maintain the specified network port (i.e. default 63000) as expected by the health probe rule referenced in the Azure load balancer.

If the database is not open or is not a PRIMARY database, then the specified network port is not to be active, and is to be kept closed.

# Script command-line parameters:

Call syntax...

    oraupdown.sh ORACLE_SID[,sid-list] [ sleepSecs [ lsnrName [ port ] ] ]

Parameters...
- ORACLE_SID      (<i>mandatory</i> - no default value) ORACLE_SID value for database
- sid-list        (<i>optional</i> - no default) comma-separated list of ORACLE_SID values for database instances
- sleepSecs       (<i>optional</i> - default value: 10) interval between database checks
- lsnrName        (<i>optional</i> - default value: LISTENER) name of Oracle TNS LISTENER process
- port            (<i>optional</i> - default value: 63000) port for Azure LB to monitor

# Suggested installation of script:

Create an entry in the "crontab" of the OS account running the script (i.e. "oracle")...

    * * * * * if [[ "`ps -eaf | grep oraupdown | grep -v grep`" = "" ]]; then nohup /home/oracle/oraupdown.sh oradb01 > /dev/null 2>&1; fi

To explain this command, every minute of every day the Linux "cron" utility will check to see if the "oraupdown.sh" script is running or not.  If the script is running, then no further action need be taken.

If the script is not running, then the script will be restarted so that all standard output and standard error output from the script is logged in the "$HOME" directory of the "oracle" OS account, where the script itself should reside.  Please be aware that the script itself is designed to run continuously, and that this "cron" entry is intended to ensure startup at the time of VM startup, or for restart in the event the script is killed or dies inadvertently.  Essentially, this script should always be running on the VM.

Using crontab in this manner is merely a suggestion, suggested mainly because it is universal to all variants and versions of Linux (and UNIX), and because it most easily illustrates the intention.  Modern utilities used in popular modern Linux variants, such as "systemctl", may be preferred over this admittedly out-of-date suggestion, and administrators familiar with more modern tools for maintaining constantly available services in Linux should by all means use those instead.

# Script Dependencies:

Installation of Linux "nc" command on the VM on which the Oracle database instances reside...

    sudo yum install -y nc

...on Oracle Enterprise Linux or Red Hat Enterprise Linux (or equivalent dnf, apt-get, or other Linux variant on the yum command).

# Script Diagnostics:

- Log file "oraupdown.log" - located in $HOME directory of the OS account running the script.
- Log file "oraupdown_nc.log" contains output from Linux "nc" command.

On the database VM, entries in an OS account's "cron" table can be listed using the "crontab -l" command.  The existence of the running "oraupdown.sh" script can be verified using a Linux command like "ps -eaf | grep oraupdown".  The status of the designated network port can be verified using either the Linux command "netstat -a | grep 63000" or the Linux command "ps -eaf | grep nc".

# Identifying DataGuard primary database using Oracle service names:

When people think about service names within Oracle database, they generally think about the initialization parameter SERVICE_NAMES which can be used to specify a comma-separated list of Oracle service names.  However, the SERVICE_NAMES parameter is no longer actively supported, and so it must not be used for high availability (HA) deployments and it is not supported for HA operations.  Instead, it is necessary to use the DBMS_SERVICE package to manage Oracle service names used to designate the primary Oracle database in a DataGuard environment.

There are several ways to accomplish this, but the simplest method is to employ an AFTER STARTUP database event trigger to call the DBMS_SERVICES.START_SERVICE and DBMS_SERVICES.STOP_SERVICE stored procedures as necessary...

    DBMS_SERVICE.CREATE_SERVICE('ORADB01_PRIMARY')
    CREATE OR REPLACE TRIGGER StartDgServices
        AFTER STARTUP
        ON DATABASE
    DECLARE
        DB_ROLE      VARCHAR2(30);
    BEGIN
        SELECT DATABASE_ROLE INTO DB_ROLE FROM V$DATABASE;
        IF DB_ROLE = 'PRIMARY' THEN
            DBMS_SESSION.START_SERVICE('ORADB01_PRIMARY');
        ELSE
            DBMS_SESSION.STOP_SERVICE('ORADB01_PRIMARY');
        END IF;
    END StartDgServices;
    /
    SHOW ERRORS

Please note that the Oracle service name being managed (i.e. "ORADB01_PRIMARY") is the service name that should be used in connection-strings, whether TNS or JDBC.

# !!!WARNING!!!

Using other Oracle service names in the database client's connect-string -- other than the one managed above -- could result in connection failures, or even worse in possible corruption by connecting to the wrong database instance, even if the Azure load balancer is working correctly, due to the Oracle client connecting to the wrong Oracle database instance.

To reiterate, the Oracle service name used in database client connect-strings *MUST* be managed using the DBMS_SESSION package using a database similar to the one specified above.

# One more thing - Oracle database "keepalive" functionality:

Azure load balancers include idle timeout functionality, so it is important to use keepalive functionality to ensure that the Azure load balancer does not close a database connection due to lack of activity.

To do this, please edit the Oracle networking configuration file named "sqlnet.ora", which is typically located in the subdirectory "$ORACLE_HOME/network/admin" on the VM on which the Oracle database instance resides, to set the configuration parameter "SQLNET.EXPIRE_TIME" so that the Oracle database instance will send a keepalive network packet  minutes...

    sqlnet.expire_time = 10

...if the parameter is already set, please ensure that the value is 10 minutes or less?

Please remember that this needs to be set on all of the VMs in the backend pool of the Azure load balancer, which are the VMs on which PRIMARY and PHYSICAL STANDBY database instances reside.  Please note that, if this parameter is not set, the VIP will work correctly initially, but idle connections will be automatically removed by the Azure load balancer after 20 minutes.  This could manifest as a wide variety of Oracle errors which indicate that the network connection dropped suddenly.

# Creation of the Azure load balancer:

These instructions will assume the use of the wizard for creating an Azure load balancer in the Azure Portal, which progresses through the following steps...

## 1. Basics
### Project Details
- Subscription (<i>enter name or ID of subscription</i>)
- Resource Group (<i>enter name of resource group in which the Oracle DataGuard VMs reside</i>)
### Instance Details
- Name (<i>enter the name of the new load balancer</i>)
- Region (<i>enter the region in which the Oracle DataGuard VMs reside</i>)
- SKU (<i>choose</i> "standard")
- Type (<i>most Oracle database VMs are "internal" only so choose</i> "internal"<i>, but if the Oracle databases are accessible by a public IP address, then choose "public" instead</i>)
- Tier (<i>choose</i> "regional")
- click NEXT to go to Frontend IP Configuration...
## 2. Frontend IP configuration
- Click "+" to add a frontend IP configuration, which will bring up a dialog box...
- Name (<i>enter the name of the LB frontend IP configuration, perhaps something like "</i>{LBname}<i>-front01"?</i>)
- Virtual Network (<i>choose the vnet on which the Oracle DataGuard VMs reside</i>)
- Subnet (<i>choose the subnet on which the Oracle DataGuard VMs reside</i>)
- Assignment (<i>choose</i> "static")
- IP address (<i>enter the static IP address to serve as the virtual IP or VIP</i>)
- Availability Zone (<i>choose</i> "Zone Redundant")
- click ADD
- click NEXT to go to Backend Pools...
## 3. Backend pools
- Click "+" to add a backend pool, which will bring up a dialog box...
- Name (<i>enter the name of the LB backend pool, perhaps something like "</i>{LBname}<i>-back01"?</i>)
- Virtual Network (<i>choose the vnet on which the Oracle DataGuard VMs reside</i>)
- Backend pool configuraton (<i>choose</i> "IP address")
- Backend address name (<i>should already be prepopulated and unchangeable</i>)
- IP address (<i>choose the IP address of one of the Oracle DataGuard VMs for each line</i>)
- <i>ensure that all of the Oracle DataGuard VMs are listed, one per line</i>
- click SAVE
- click NEXT to go to Inbound Rules...
## 4. Inbound Rules
- Click "+" to add a load balancing rule, which will bring up a dialog box...
- Name (<i>enter the name of the load balancing rule, perhaps something like "</i>{LBname}<i>-rule01"?</i>)
- IP Version (<i>choose</i> "IPv4")
- Frontend IP address (<i>choose the name of the Frontend IP Configuration added above</i>)
- Backend pool (<i>choose the name of the Backend pool added above</i>)
- High Availability Ports (<i>leave unchecked or blank</i>)
- Protocol (<i>choose</i> "TCP")
- Port (<i>specify the port number that the Oracle TNS Listener is listening upon on the Oracle DataGuard VMs - default port is 1521</i>)
- Backend port (<i>specify the port number that the Oracle TNS Listener is listening upon on the Oracle DataGuard VMs - default port is 1521</i>)
- Health probe (<i>select</i> "create new")
  - Name (<i>enter the name of the health probe, perhaps something like "</i>{LBname}<i>-probe01"?</i>)
  - Protocol (<i>choose</i> "TCP")
  - Port (<i>enter</i> "63000")
  - Interval (<i>enter</i> "10")
  - click SAVE
- Session persistence (<i>choose</i> "Client IP")
- Idle timeout (<i>enter</i> "100")
- Enable TCP Reset (<i>leave unchecked or blank</i>)
- Enable floating IP (<i>leave unchecked or blank</i>)
- click SAVE
## 4a. (optional) add Inbound Rule for testing purposes only
- Click "+" to add a load balancing rule, which will bring up a dialog box...
- Name (<i>enter the name of the load balancing rule, perhaps something like "</i>{LBname}<i>-rule02"?</i>)
- IP Version (<i>choose</i> "IPv4")
- Frontend IP address (<i>choose the name of the Frontend IP Configuration added above</i>)
- Backend pool (<i>choose the name of the Backend pool added above</i>)
- High Availability Ports (<i>leave unchecked or blank</i>)
- Protocol (<i>choose</i> "TCP")
- Port (<i>enter</i> "22" <i>which is the port number for SSH</i>)
- Backend port (<i>enter</i> "22")
- Health probe (<i>choose the name of the Health Probe added above</i>)
- Session persistence (<i>choose</i> "Client IP")
- Idle timeout (<i>enter</i> "100")
- Enable TCP Reset (<i>leave unchecked or blank</i>)
- Enable floating IP (<i>leave unchecked or blank</i>)
- click SAVE
- <i>skip past making any entries for Inbound NAT Rules, unless you know they are needed</i>
- click NEXT to go to Outbound Rules...
## 5. Outbound Rules
- <i>skip past making any entries for Outbound Rules, unless you know they are needed</i>
- click NEXT to go to Tags...
## 6. Tags
- <i>enter tags as desired, according to standards...</i>
- click NEXT to go to Review + Create...
## 7. Review + Create
- click CREATE once validation is completed successfully
