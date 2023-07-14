#!/bin/bash
#================================================================================
# Name:	oraupdown.sh
# Type:	bash script
# Date:	23-April 2020
# From: Customer Architecture & Engineering (CAE) - Microsoft
#
# Copyright and license:
#
#	Licensed under the Apache License, Version 2.0 (the "License"); you may
#	not use this file except in compliance with the License.
#
#	You may obtain a copy of the License at
#
#		http://www.apache.org/licenses/LICENSE-2.0
#
#	Unless required by applicable law or agreed to in writing, software
#	distributed under the License is distributed on an "AS IS" basis,
#	WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#
#	See the License for the specific language governing permissions and
#	limitations under the License.
#
#	Copyright (c) 2020 by Microsoft.  All rights reserved.
#
# Ownership and responsibility:
#
#	This script is offered without warranty by Microsoft.  Anyone using this
#	script accepts full responsibility for use, effect, and maintenance.
#	Please do not contact Microsoft support unless there is a problem with
#	a supported Azure or Linux component used in this script.
#
# Description:
#
#	Script to be used with Azure load balancers to keep a specified port active
#	when the specified database is an Oracle DataGuard PRIMARY.  If the database
#	is not a PRIMARY database, then the specified port is not to be active.
#
# Command-line Parameters:
#
#	Call syntax...
#
#		oraupdown.sh ORACLE_SID [ sleepSecs [ lsnrName [ port ] ] ]
#
#	Parameters...
#		ORACLE_SID	(mandatory - no default) ORACLE_SID value for database
#		sleepSecs	(optional - default 10 seconds) interval between database checks
#		lsnrName	(optional - default LISTENER) name of Oracle TNS LISTENER process
#		port		(optional - default 63000) port for Azure LB to monitor
#
# Dependencies:
#
#	Installation of Linux "nc" command:  sudo yum install -y nc
#
# Diagnostics:
#
#	Log file "oraupdown.log" in $HOME directory of account managed by script.
#
#	Log file "oraupdown_nc.log" contains output from Linux "nc" command.
#
#
# Modifications:
#	TGorman	23apr20	v0.1	written
#	TGorman	14jul23	v0.9	posted to Github
#================================================================================
#
#--------------------------------------------------------------------------------
# Set global environment variables with default values...
#--------------------------------------------------------------------------------
_prog="oraupdown"
_progVersion="0.9"
_hostName="`hostname | awk -F\. '{print $1}'`"
_outFile="/tmp/.${_prog}_sqlplus_output.tmp"
_logFile="${HOME}/${_prog}.log"
_ncLogFile="${HOME}/${_prog}_nc.log"
_portStatus="~~~"
#
#--------------------------------------------------------------------------------
# Set default values for command-line parameters...
#--------------------------------------------------------------------------------
_sleepSecs=10			# default sleep period between iterations (in seconds) is 10 seconds
_lsnrName="LISTENER"		# default Oracle listener name is "LISTENER"
_port=63000			# default port is "63000"
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
	4)	export ORACLE_SID=$1
		typeset -i _sleepSecs=$2
		_lsnrName=$3
		_port=$4
		;;
	3)	export ORACLE_SID=$1
		typeset -i _sleepSecs=$2
		_port=$3
		;;
	2)	export ORACLE_SID=$1
		typeset -i _sleepSecs=$2
		;;
	1)	export ORACLE_SID=$1
		;;
	*)	echo "Usage:	\"${_prog}.sh ORACLE_SID [ sleepSecs [ lsnrName [ port ] ] ]; aborting..." | tee -a ${_logFile}
		echo "	default \"sleepSecs\" value is ${_sleepSecs} seconds" | tee -a ${_logFile}
		echo "	default \"lsnrName\" value is \"${_lsnrName}\"" | tee -a ${_logFile}
		echo "	default \"port\" value is ${_port}" | tee -a ${_logFile}
		exit 1
		;;
esac
#
#--------------------------------------------------------------------------------
# Validate the "sleepSecs" parameter value...
#--------------------------------------------------------------------------------
if (( ${_sleepSecs} < 5 || ${_sleepSecs} > 86400 ))
then
	echo "Usage:	\"${_prog}.sh ORACLE_SID [ sleepSecs [ lsnrName [ port ] ] ]; aborting..." | tee -a ${_logFile}
	echo "	(\"sleepSecs\" should be between 5 and 86400)" | tee -a ${_logFile}
	stop_socket
	exit 1
fi
#
#--------------------------------------------------------------------------------
# Validate the "port" parameter value...
#--------------------------------------------------------------------------------
if (( ${_port} < 1025 || ${_sleepSecs} > 65535 ))
then
	echo "Usage:	\"${_prog}.sh ORACLE_SID [ sleepSecs [ lsnrName [ port ] ] ]; aborting..." | tee -a ${_logFile}
	echo "	(\"port\" should be between 1025 and 65535)" | tee -a ${_logFile}
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
	echo "Usage:	\"${_prog}.sh ORACLE_SID [ sleepSecs [ lsnrName [ port ] ] ]; aborting..." | tee -a ${_logFile}
	echo "	(Oracle environment script \"dbhome\" not found; was \"root.sh\" run during installation?)" | tee -a ${_logFile}
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
	echo "Usage:	\"${_prog}.sh ORACLE_SID [ sleepSecs [ lsnrName [ port ] ] ]; aborting..." | tee -a ${_logFile}
	echo "	(Oracle environment script \"oraenv\" not found; was \"root.sh\" run during installation?)" | tee -a ${_logFile}
	stop_socket
	exit 1
fi
#
#--------------------------------------------------------------------------------
# Validate the ORACLE_SID parameter value.  If the value is valid, then set the
# script environment using the standard Oracle "oraenv" script...
#--------------------------------------------------------------------------------
dbhome ${ORACLE_SID} > /dev/null 2>&1
if (( $? != 0 ))
then
	echo "Usage:	\"${_prog}.sh ORACLE_SID [ sleepSecs [ lsnrName [ port ] ] ]; aborting..." | tee -a ${_logFile}
	echo "	(\"ORACLE_SID\" not found in \"/etc/oratab\" configuration file)" | tee -a ${_logFile}
	stop_socket
	exit 1
fi
export ORAENV_ASK=NO
. oraenv > /dev/null 2>&1
if (( $? != 0 ))
then
	echo "Usage:	\"${_prog}.sh ORACLE_SID [ sleepSecs [ lsnrName [ port ] ] ]; aborting..." | tee -a ${_logFile}
	echo "	(\"oraenv\" script failed)" | tee -a ${_logFile}
	stop_socket
	exit 1
fi
unset ORAENV_ASK
#
#--------------------------------------------------------------------------------
# Verify that the Linux and Oracle commands used in this script are present, as
# well as the ORACLE_HOME directories and sub-directories...
#--------------------------------------------------------------------------------
if [ ! -d ${ORACLE_HOME} ]
then
	echo "Usage:	\"${_prog}.sh ORACLE_SID [ sleepSecs [ lsnrName [ port ] ] ]; aborting..." | tee -a ${_logFile}
	echo "	(ORACLE_HOME directory \"${ORACLE_HOME}\" not found)" | tee -a ${_logFile}
	stop_socket
	exit 1
fi
#
if [ ! -d ${ORACLE_HOME}/bin ]
then
	echo "Usage:	\"${_prog}.sh ORACLE_SID [ sleepSecs [ lsnrName [ port ] ] ]; aborting..." | tee -a ${_logFile}
	echo "	(ORACLE_HOME binary sub-directory \"${ORACLE_HOME}/bin\" not found)" | tee -a ${_logFile}
	stop_socket
	exit 1
fi
#
if [ ! -x ${ORACLE_HOME}/bin/tnslsnr ]
then
	echo "Usage:	\"${_prog}.sh ORACLE_SID [ sleepSecs [ lsnrName [ port ] ] ]; aborting..." | tee -a ${_logFile}
	echo "	(Oracle executable \"${ORACLE_HOME}/bin/tnslsnr\" not found)" | tee -a ${_logFile}
	stop_socket
	exit 1
fi
#
if [ ! -x ${ORACLE_HOME}/bin/sqlplus ]
then
	echo "Usage:	\"${_prog}.sh ORACLE_SID [ sleepSecs [ lsnrName [ port ] ] ]; aborting..." | tee -a ${_logFile}
	echo "	(Oracle executable \"${ORACLE_HOME}/bin/sqlplus\" not found)" | tee -a ${_logFile}
	stop_socket
	exit 1
fi
#
#--------------------------------------------------------------------------------
# Verify that the Linux "nc" command has been installed...
#--------------------------------------------------------------------------------
_ncPath=`which nc > /dev/null 2>&1`
if (( $? != 0 ))
then
	echo "Usage:	\"${_prog}.sh ORACLE_SID [ sleepSecs [ lsnrName [ port ] ] ]; aborting..." | tee -a ${_logFile}
	echo "	(Linux executable \"nc\" not found; run \"sudo yum install -y nc\" to install)" | tee -a ${_logFile}
	stop_socket
	exit 1
fi
if [ ! -x ${_ncPath} ]
then
	echo "Usage:	\"${_prog}.sh ORACLE_SID [ sleepSecs [ lsnrName [ port ] ] ]; aborting..." | tee -a ${_logFile}
	echo "	(Linux executable \"${_ncPath}\" not found; run \"sudo yum -y nc\" to install)" | tee -a ${_logFile}
	stop_socket
	exit 1
fi
#
echo "`date` - INFO: ${_progName}.sh version ${_progVersion}..." | tee -a ${_logFile}
#
#
#--------------------------------------------------------------------------------
########## main loop of the script ##########
#--------------------------------------------------------------------------------
while true
do
	if [[ `ps -eaf | grep ora_pmon_${ORACLE_SID} | grep -v grep` = "" ]]
	then
		stop_socket
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
		case $? in
			#------------------------------------------------
			# Successful query, check output to determine if
			# the database's role is PRIMARY or not...
			#------------------------------------------------
			0)	if [[ "`grep 'ROLE=' ${_outFile} | awk -F= '{print $2}'`" = "PRIMARY" ]]
				then start_socket
				else stop_socket
				fi ;;
			#------------------------------------------------
			# Failed connection to SQL*Plus...
			#------------------------------------------------
			1)	echo "`date` - FAIL: \"SQL*Plus\" connect to \"${ORACLE_SID}\" failed; aborting..." | tee -a ${_logFile}
				cat ${_outFile} | tee -a ${_logFile}
				stop_socket
				;;
			#------------------------------------------------
			# Failed query on V$DATABASE...
			#------------------------------------------------
			2)	echo "`date` - FAIL: \"SQL*Plus\" query of V\$DATABASE failed; aborting..." | tee -a ${_logFile}
				cat ${_outFile} | tee -a ${_logFile}
				stop_socket
				;;
			#------------------------------------------------
			# Any other reason that SQL*Plus failed...
			#------------------------------------------------
			*)	echo "`date` - FAIL: \"SQL*Plus\" failed; aborting..." | tee -a ${_logFile}
				cat ${_outFile} | tee -a ${_logFile}
				stop_socket
				;;
		esac	# ...end of conditional on SQL*Plus exit status...
		#
	fi # ...end of conditional on "ora_pmon" process existing...
	#
	sleep ${_sleepSecs}
	#
done # ...end of endless loop...
