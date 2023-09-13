#!/bin/bash
#================================================================================
# Name: oraupdown.sh
# Type: bash script
# Date: 23-April 2020
# From: Customer Architecture & Engineering (CAE) - Microsoft
#
# Copyright and license:
#
#       Licensed under the Apache License, Version 2.0 (the "License"); you may
#       not use this file except in compliance with the License.
#
#       You may obtain a copy of the License at
#
#               http://www.apache.org/licenses/LICENSE-2.0
#
#       Unless required by applicable law or agreed to in writing, software
#       distributed under the License is distributed on an "AS IS" basis,
#       WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#
#       See the License for the specific language governing permissions and
#       limitations under the License.
#
#       Copyright (c) 2020 by Microsoft.  All rights reserved.
#
# Ownership and responsibility:
#
#       This script is offered without warranty by Microsoft.  Anyone using this
#       script accepts full responsibility for use, effect, and maintenance.
#       Please do not contact Microsoft support unless there is a problem with
#       a supported Azure or Linux component used in this script.
#
# Description:
#
#       Script to be used with Azure load balancers to keep a specified port active
#       when the specified database is an Oracle DataGuard PRIMARY.  If the database
#       is not a PRIMARY database, then the specified port is not to be active.
#
# Command-line Parameters:
#
#       Call syntax...
#
#               oraupdown.sh ORACLE_SID[,sid-list] [ sleepSecs [ lsnrName [ port ] ] ]
#
#       Parameters...
#               ORACLE_SID      (mandatory - no default) ORACLE_SID value for database instance
#               sid-list        (optional) - comma-separated list of ORACLE_SID values for database instances
#               sleepSecs       (optional - default 10 seconds) interval between database checks
#               lsnrName        (optional - default LISTENER) name of Oracle TNS LISTENER process
#               port            (optional - default 63000) port for Azure LB to monitor
#
# Dependencies:
#
#       Installation of Linux "nc" command:  sudo yum install -y nc
#
# Diagnostics:
#
#       Log file "oraupdown.log" in $HOME directory of account managed by script.
#
#       Log file "oraupdown_nc.log" contains output from Linux "nc" command.
#
#
# Modifications:
#       TGorman 23apr20 v0.1    written
#       TGorman 14jul23 v0.9    posted to Github
#       TGorman 13sep23 v1.0    added sid-list functionality
#================================================================================
#
#--------------------------------------------------------------------------------
# Set global environment variables with default values...
#--------------------------------------------------------------------------------
_progName="oraupdown"
_progVersion="1.0"
_hostName="`hostname | awk -F\. '{print $1}'`"
_outFile="/tmp/.${_progName}_sqlplus_output.tmp"
_logFile="${HOME}/${_progName}.log"
_ncLogFile="${HOME}/${_progName}_nc.log"
_portStatus="~~~"
#
#--------------------------------------------------------------------------------
# Set default values for command-line parameters...
#--------------------------------------------------------------------------------
_sleepSecs=10                   # default sleep period between iterations (in seconds) is 10 seconds
_lsnrName="LISTENER"            # default Oracle listener name is "LISTENER"
_port=63000                     # default port is "63000"
#
#--------------------------------------------------------------------------------
# Log the script version into the script logfile....
#--------------------------------------------------------------------------------
echo "`date` - INFO: ${_progName}.sh version ${_progVersion}..." | tee -a ${_logFile}
#
#--------------------------------------------------------------------------------
# Define shell function to start Linux "nc" listening on specified port...
#--------------------------------------------------------------------------------
start_socket ()
{
        nohup nc -l -k ${_port} > ${_ncLogFile} 2>&1 &
        _pid=`ps -eaf | grep "nc -l -k ${_port}" | grep -v grep | awk '{print $2}'`
        if [[ "${_pid}" != "" ]]
        then
                if [[ "${_portStatus}" != "up" ]]
                then
                        _portStatus="up"
                        echo "`date` - INFO: \"nc -l -k ${_port}\" started" | tee -a ${_logFile}
                fi
        else
                _portStatus="down"
                echo "`date` - FAIL: start \"nc -l -k ${_port}\" failed..." | tee -a ${_logFile}
        fi
} # ...end of shell function "start_socket"...
#
#--------------------------------------------------------------------------------
# Define shell function to kill Linux "nc" utility...
#--------------------------------------------------------------------------------
stop_socket ()
{
        _pid=`ps -eaf | grep "nc -l -k ${_port}" | grep -v grep | awk '{print $2}'`
        if [[ "${_pid}" != "" ]]
        then
                kill ${_pid} 2>&1 >> ${_logFile}
                _pid=`ps -eaf | grep "nc -l -k ${_port}" | grep -v grep | awk '{print $2}'`
                if [[ "${_pid}" = "" ]]
                then
                        if [[ "${_portStatus}" != "down" ]]
                        then
                                _portStatus="down"
                                echo "`date` - INFO: \"nc -l -k ${_port}\" stopped" | tee -a ${_logFile}
                        fi
                else
                        echo "`date` - FAIL: stop \"nc -l -k ${_port}\" failed..." | tee -a ${_logFile}
                fi
        fi
} # ...end of shell function "stop_socket"...
#
#--------------------------------------------------------------------------------
# If this script is "kill"ed, then be sure to close the socket first...
#--------------------------------------------------------------------------------
trap stop_socket EXIT
#
#--------------------------------------------------------------------------------
# Capture parameter values from command-line...
#--------------------------------------------------------------------------------
case $# in
        4)      export _oraSidList=$1
                typeset -i _sleepSecs=$2
                _lsnrName=$3
                _port=$4
                ;;
        3)      export _oraSidList=$1
                typeset -i _sleepSecs=$2
                _port=$3
                ;;
        2)      export _oraSidList=$1
                typeset -i _sleepSecs=$2
                ;;
        1)      export _oraSidList=$1
                ;;
        *)      echo "Usage:    \"${_progName}.sh ORACLE_SID[,sid-list] [ sleepSecs [ lsnrName [ port ] ] ]; aborting..." | tee -a ${_logFile}
                echo "  ORACLE_SID (mandatory - no default) ORACLE_SID value for database instance" | tee -a ${_logFile}
                echo "  sid-list (optional - no default) comma-separated list of ORACLE_SID values for database instances" | tee -a ${_logFile}
                echo "  default \"sleepSecs\" value is ${_sleepSecs} seconds" | tee -a ${_logFile}
                echo "  default \"lsnrName\" value is \"${_lsnrName}\"" | tee -a ${_logFile}
                echo "  default \"port\" value is ${_port}" | tee -a ${_logFile}
                exit 1
                ;;
esac
#
#--------------------------------------------------------------------------------
# Validate the comma-separated list of ORACLE_SID values specified on the
# command-line...
#
# The maximum value of 32 is an arbitrary limit, set because the author simply
# thinks it is a bad idea to have such a long list of ORACLE_SID values grouped
# together for a virtual IP.  There is no empirical evidence that a longer list
# is indeed a bad idea, and if you wish, please feel free to increase this limit.
#--------------------------------------------------------------------------------
IFS=',' read -r -a _oraSidArray <<< "${_oraSidList}"
typeset -i _nbrOraSidList=0
for ORACLE_SID in "${_oraSidArray[@]}"
do
        typeset -i _nbrOraSidList=${_nbrOraSidList}+1
done
if (( ${_nbrOraSidList} < 1 ))
then
        echo "Usage:    \"${_progName}.sh ORACLE_SID[,sid-list] [ sleepSecs [ lsnrName [ port ] ] ]; aborting..." | tee -a ${_logFile}
        echo "  at least one ORACLE_SID value should be provided in the ORACLE_SID \"sid-list\"" | tee -a ${_logFile}
        stop_socket
        exit 1
fi
if (( ${_nbrOraSidList} > 32 ))
then
        echo "Usage:    \"${_progName}.sh ORACLE_SID[,sid-list] [ sleepSecs [ lsnrName [ port ] ] ]; aborting..." | tee -a ${_logFile}
        echo "  too many (> 32) ORACLE_SID values provided in the \"sid-list\"" | tee -a ${_logFile}
        stop_socket
        exit 1
fi
#
#--------------------------------------------------------------------------------
# Validate the "sleepSecs" parameter value specified on the command-line...
#--------------------------------------------------------------------------------
if (( ${_sleepSecs} < 5 || ${_sleepSecs} > 86400 ))
then
        echo "Usage:    \"${_progName}.sh ORACLE_SID[,sid-list] [ sleepSecs [ lsnrName [ port ] ] ]; aborting..." | tee -a ${_logFile}
        echo "  (\"sleepSecs\" should be between 5 and 86400)" | tee -a ${_logFile}
        stop_socket
        exit 1
fi
#
#--------------------------------------------------------------------------------
# Validate the "port" parameter value specified on the command-line...
#--------------------------------------------------------------------------------
if (( ${_port} < 1025 || ${_sleepSecs} > 65535 ))
then
        echo "Usage:    \"${_progName}.sh ORACLE_SID[,sid-list] [ sleepSecs [ lsnrName [ port ] ] ]; aborting..." | tee -a ${_logFile}
        echo "  (\"port\" should be between 1025 and 65535)" | tee -a ${_logFile}
        stop_socket
        exit 1
fi
#
#--------------------------------------------------------------------------------
# Ensure that the directory "/usr/local/bin" is included in the session's PATH...
#--------------------------------------------------------------------------------
export PATH=/usr/local/bin:${PATH}
#
#--------------------------------------------------------------------------------
# Verify whether the standard Oracle "dbhome" script is found...
#--------------------------------------------------------------------------------
which dbhome > /dev/null 2>&1
if (( $? != 0 ))
then
        echo "Usage:    \"${_progName}.sh ORACLE_SID[,sid-list] [ sleepSecs [ lsnrName [ port ] ] ]; aborting..." | tee -a ${_logFile}
        echo "  (Oracle environment script \"dbhome\" not found; \"root.sh\" might not have been executed during RDBMS software installation)" | tee -a ${_logFile}
        stop_socket
        exit 1
fi
#
#--------------------------------------------------------------------------------
# Verify whether the standard Oracle "oraenv" script is found...
#--------------------------------------------------------------------------------
which oraenv > /dev/null 2>&1
if (( $? != 0 ))
then
        echo "Usage:    \"${_progName}.sh ORACLE_SID[,sid-list] [ sleepSecs [ lsnrName [ port ] ] ]; aborting..." | tee -a ${_logFile}
        echo "  (Oracle environment script \"oraenv\" not found)" | tee -a ${_logFile}
        echo "  (Please note that \"root.sh\" might not have been executed during RDBMS software installation)" | tee -a ${_logFile}
        stop_socket
        exit 1
fi
#
#--------------------------------------------------------------------------------
# Verify that all of the ORACLE_SID values specified on the command-line are
# present in the "/etc/oratab" configuration file...
#--------------------------------------------------------------------------------
for ORACLE_SID in "${_oraSidArray[@]}"
do
        #
        #------------------------------------------------------------------------
        # Validate the ORACLE_SID parameter value...
        #------------------------------------------------------------------------
        dbhome ${ORACLE_SID} > /dev/null 2>&1
        if (( $? != 0 ))
        then
                echo "Usage:    \"${_progName}.sh ORACLE_SID[,sid-list] [ sleepSecs [ lsnrName [ port ] ] ]; aborting..." | tee -a ${_logFile}
                echo "  (ORACLE_SID=\"${ORACLE_SID}\" not found in \"/etc/oratab\" configuration file)" | tee -a ${_logFile}
                stop_socket
                exit 1
        fi
        #
        #------------------------------------------------------------------------
        # Set the ORACLE_HOME and related environment variables based on the
        # current value of ORACLE_SID...
        #------------------------------------------------------------------------
        export ORAENV_ASK=NO
        . oraenv > /dev/null 2>&1
        if (( $? != 0 ))
        then
                echo "Usage:    \"${_progName}.sh ORACLE_SID[,sid-list] [ sleepSecs [ lsnrName [ port ] ] ]; aborting..." | tee -a ${_logFile}
                echo "  (\"oraenv\" script failed for \"${ORACLE_SID}\")" | tee -a ${_logFile}
                stop_socket
                exit 1
        fi
        unset ORAENV_ASK
        #
        #------------------------------------------------------------------------
        # Verify that the Linux and Oracle commands used in this script are
        # present, as well as the ORACLE_HOME directories and sub-directories...
        #------------------------------------------------------------------------
        if [ ! -d ${ORACLE_HOME} ]
        then
                echo "Usage:    \"${_progName}.sh ORACLE_SID[,sid-list] [ sleepSecs [ lsnrName [ port ] ] ]; aborting..." | tee -a ${_logFile}
                echo "  (ORACLE_HOME directory \"${ORACLE_HOME}\" for \"${ORACLE_SID}\" not found)" | tee -a ${_logFile}
                stop_socket
                exit 1
        fi
        #
        if [ ! -d ${ORACLE_HOME}/bin ]
        then
                echo "Usage:    \"${_progName}.sh ORACLE_SID[,sid-list] [ sleepSecs [ lsnrName [ port ] ] ]; aborting..." | tee -a ${_logFile}
                echo "  (ORACLE_HOME sub-directory \"${ORACLE_HOME}/bin\" for \"${ORACLE_SID}\" not found)" | tee -a ${_logFile}
                stop_socket
                exit 1
        fi
        #
        if [ ! -x ${ORACLE_HOME}/bin/tnslsnr ]
        then
                echo "Usage:    \"${_progName}.sh ORACLE_SID[,sid-list] [ sleepSecs [ lsnrName [ port ] ] ]; aborting..." | tee -a ${_logFile}
                echo "  (Oracle executable \"${ORACLE_HOME}/bin/tnslsnr\" for \"${ORACLE_SID}\" not found)" | tee -a ${_logFile}
                stop_socket
                exit 1
        fi
        #
        if [ ! -x ${ORACLE_HOME}/bin/sqlplus ]
        then
                echo "Usage:    \"${_progName}.sh ORACLE_SID[,sid-list] [ sleepSecs [ lsnrName [ port ] ] ]; aborting..." | tee -a ${_logFile}
                echo "  (Oracle executable \"${ORACLE_HOME}/bin/sqlplus\" for \"${ORACLE_SID}\" not found)" | tee -a ${_logFile}
                stop_socket
                exit 1
        fi
        #
done
#
#--------------------------------------------------------------------------------
# Verify that the Linux "nc" command has been installed...
#--------------------------------------------------------------------------------
_ncPath=`which nc > /dev/null 2>&1`
if (( $? != 0 ))
then
        echo "Usage:    \"${_progName}.sh ORACLE_SID[,sid-list] [ sleepSecs [ lsnrName [ port ] ] ]; aborting..." | tee -a ${_logFile}
        echo "  (Linux executable \"nc\" not found; run \"sudo yum install -y nc\" to install)" | tee -a ${_logFile}
        stop_socket
        exit 1
fi
if [ ! -x ${_ncPath} ]
then
        echo "Usage:    \"${_progName}.sh ORACLE_SID[,sid-list] [ sleepSecs [ lsnrName [ port ] ] ]; aborting..." | tee -a ${_logFile}
        echo "  (Linux executable \"${_ncPath}\" not found; run \"sudo yum -y nc\" to install)" | tee -a ${_logFile}
        stop_socket
        exit 1
fi
#
#
#--------------------------------------------------------------------------------
########## main loop of the script ##########
#--------------------------------------------------------------------------------
while true
do
        #------------------------------------------------------------------------
        # Reset the counts for open primary databases (for which the port should
        # be opened) and how many stopped or standby databases (for which the
        # port should be closed)...
        #------------------------------------------------------------------------
        typeset -i _nbrOpenPrimaryDB=0
        typeset -i _nbrOtherDB=0
        #
        for ORACLE_SID in "${_oraSidArray[@]}"
        do
                #----------------------------------------------------------------
                # Determine whether or not the specific Oracle database instance
                # is up and running, or not...
                #----------------------------------------------------------------
                if [[ `ps -eaf | grep ora_pmon_${ORACLE_SID} | grep -v grep` = "" ]]
                then
                        typeset -i _nbrOtherDB=${_nbrOtherDB}+1
                else
                        rm -f ${_outFile}
                        ${ORACLE_HOME}/bin/sqlplus -S -L /nolog << __EOF__ > ${_outFile} 2>&1
set pagesize 0 linesize 80 echo off feedback off trimout on trimspool on
whenever oserror exit 1
whenever sqlerror exit 1
connect / as sysdba
whenever oserror exit 2
whenever sqlerror exit 2
select 'ROLE='||database_role txt from v\$database;
exit success
__EOF__
                        typeset -i _exitStatus=$?
                        case ${_exitStatus} in
                                #------------------------------------------------
                                # Successful query, check output to determine if
                                # the database's role is PRIMARY or not...
                                #------------------------------------------------
                                0)      if [[ "`grep 'ROLE=' ${_outFile} | awk -F= '{print $2}'`" = "PRIMARY" ]]
                                        then typeset -i _nbrOpenPrimaryDB=${_nbrOpenPrimaryDB}+1
                                        else typeset -i _nbrOtherDB=${_nbrOtherDB}+1
                                        fi ;;
                                #------------------------------------------------
                                # Failed connection to SQL*Plus...
                                #------------------------------------------------
                                1)      echo "`date` - FAIL: \"SQL*Plus\" connect to \"${ORACLE_SID}\" failed; aborting..." | tee -a ${_logFile}
                                        cat ${_outFile} | tee -a ${_logFile}
                                        typeset -i _nbrOtherDB=${_nbrOtherDB}+1
                                        ;;
                                #------------------------------------------------
                                # Failed query on V$DATABASE...
                                #------------------------------------------------
                                2)      echo "`date` - FAIL: \"SQL*Plus\" query of V\$DATABASE failed; aborting..." | tee -a ${_logFile}
                                        cat ${_outFile} | tee -a ${_logFile}
                                        typeset -i _nbrOtherDB=${_nbrOtherDB}+1
                                        ;;
                                #------------------------------------------------
                                # Any other reason that SQL*Plus failed...
                                #------------------------------------------------
                                *)      echo "`date` - FAIL: \"SQL*Plus\" failed; aborting..." | tee -a ${_logFile}
                                        cat ${_outFile} | tee -a ${_logFile}
                                        typeset -i _nbrOtherDB=${_nbrOtherDB}+1
                                        ;;
                        esac    # ...end of conditional on SQL*Plus exit status...
                        #
                fi # ...end of conditional on "ora_pmon" process existing...
                #
        done
        #
        #------------------------------------------------------------------------
        # If none of the specified Oracle database instances are open and PRIMARY,
        # the close the port.  If any of the specified Oracle database instances
        # are open and PRIMARY, then open the port...
        #------------------------------------------------------------------------
        if (( ${_nbrOpenPrimaryDB} > 0 ))
        then
                start_socket
        else
                stop_socket
        fi
        #
        #------------------------------------------------------------------------
        # Log a warning message to the script's logfile to warn admins of a
        # non-usual situation, where not all of the specified database instances
        # are open/primary or not open/primary...
        #------------------------------------------------------------------------
        if (( ${_nbrOpenPrimaryDB} < ${_nbrOraSidList} && ${_nbrOtherDB} < ${_nbrOraSidList} ))
        then
                echo "`date` - WARN: ${_nbrOpenPrimaryDB} database instances are OPEN PRIMARY, and ${_nbrOtherDB} are not OPEN or not PRIMARY" | tee -a ${_logFile}
        fi
        #
        sleep ${_sleepSecs}
        #
done # ...end of endless loop...
