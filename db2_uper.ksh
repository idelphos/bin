#!/bin/ksh

#
#  Patch Helper
#  Mason Hua @ IBM 16th Nov 2015
#
# @------------------------  Change Activity  -----------------------------@
# Date          Pgmr    Description     
# -----------   ----    --------------------------------------------------
# 22/03/2016    Mason   update to make sure never change permission for /tmp
# @------------------------------------------------------------------------@

umask 0002
export OS=`uname -s | tr [a-z] [A-Z]`

# RPATH for report path
# WPATH for work path, where the $0 puts
RPATH="/tmp/upher`date "+%j"`"
if [ `echo "$0" | grep -c '^\./'` -eq 1 ]; then
  # use it by this way: ./istop.ksh
  WPATH=`pwd`
  PROGM=${0#./}
else
  # use it with full path
  WPATH=${0%/*}
  PROGM=${0##*/}
fi
# cmd output temporary file
CMD_TMPFILE="${RPATH}/.cmd_tempfile_use_internal"

# if run it with root, make all instances have access to this script
if [ `id -u` -eq 0 ]; then
  # Never change the permission for /tmp
  if [ ! $WPATH = "/tmp" ]; then
    chmod 755 $WPATH >/dev/null 2>&1
    chmod 755 $WPATH/$PROGM >/dev/null 2>&1
    chmod 777 $RPATH >/dev/null 2>&1
    chmod 777 $CMD_TMPFILE >/dev/null 2>&1
  fi
fi

if [ ! -d $RPATH ]; then
  mkdir $RPATH
  chmod 777 $RPATH >/dev/null 2>&1
fi

Usage ( ) {
  echo " "
  echo "Run it as root "
  echo "Usage: $0 -i <instances, use comma(,) to separate each instance> 
                  -b <the code path you use to upgrade the instances> 
                  -l <preserve, for further use. license file>
                  -t START_INST | STOP_INST | BIND_DB | HC | CE | UPGRADE_DB
                      # TART_INST  start instances only
                      # STOP_INST  stop instances only
                      # BIND_DB    do rebind on databases only
                      # HC         run health check and fix violations automatically
                      # CE         collect evidences
                      # UPGRADE_DB run upgrade database on databases
                  -w <preserve, for further use. work directory, /tmp/pher$date as default>

        Note: Make sure every instance have access to the work directory    
  "
  echo " "
  exit 1
}

#---------------------------------------------------------------------------
# Parse Parms passed into script
#---------------------------------------------------------------------------
#
#Check for the use of the following command line parms
# -? -HELP -N -DEBUG
#
parmlist="${*}"
for parm in ${parmlist};   do
  case ${parm} in 
      '-?') script_help='Y' ;;
      '-DEBUG') echo " debug is turned on "; set -x ;;
      '-HELP') script_help='Y' ;;
  esac
done

############################################################
# task functions
############################################################
#
# start instance
# run it with instance id
__start_instance() {
  if [ "$INST" == "" ]; then
    INST=$USER
  fi

  # check if any local DB cataloged first
  if [[ $OS == "AIX" ]]; then
    db_count=`db2 list db directory | grep -p 'Indirect' | grep 'Database name' | sort -u | wc -l`
  else
    db_count=`db2 list db directory | grep -B 5 'Indirect' | grep 'Database name' | sort -u | wc -l`
  fi

  if [[ $db_count -eq  0 ]]; then
    echo "NO local DB cataloged in instance $INST"
    echo "start instance will be skipped"
    echo "REPORT STATUS, START INSTANCE: ${INST}#--"
    exit 0
  fi

  if [ `ps -ef | grep db2sys | grep -i -w $INST | grep -cv grep` -lt 1 ]; then
    echo "starting instance $INST"
    db2start | tee ${CMD_TMPFILE}
    # SQL1026N  The database manager is already active.
    # SQL1063N  DB2START processing was successful.
    if [[ `grep -E -c '(SQL1026N|SQL1063N)' ${CMD_TMPFILE}` -gt 0 ]]; then
      echo "REPORT STATUS, START INSTANCE: ${INST}#OK"
    else
      echo "Start Instance $INST failed!"
      echo "REPORT STATUS, START INSTANCE: ${INST}#X"
      exit 1
    fi
  else
    echo "Instance $INST is already up, not action required"
    echo "REPORT STATUS, START INSTANCE: ${INST}#OK"
  fi

  if [[ $OS == "AIX" ]]; then
    for db in `db2 list db directory | grep -p 'Indirect' | grep 'Database name' | sort -u | awk -F'=' '{print $2}'`
    do
      db2 activate db $db
    done
  else
    for db in `db2 list db directory | grep -B 5 'Indirect' | grep 'Database name' | sort -u | awk -F'=' '{print $2}'`
    do
      db2 activate db $db
    done
  fi

  exit 0
}

start_instance ( ) {

  if [ `id -u` -ne 0 ]; then
    echo "going to start current instance $USER"
    __start_instance
    exit 0
  elif [ "$INSTS" == "" ]; then
    echo "Pls specify the instance names when running by root"
    Usage
    exit 1
  fi

  echo "==========================================="
  echo "= start instances : $INSTS                 "
  echo "==========================================="
  count=2
  INSTS_TMP="${INSTS},"
  INST=`echo "$INSTS_TMP"|cut -d, -f 1`
  while [ "$INST" != "" ]
  do
    INST=`echo $INST | tr [A-Z] [a-z]`
    echo "++ start instance $INST"
    id $INST >/dev/null 2>&1
    if [ $? -ne 0 ]; then 
      echo "Instance $INST is not exists, please check it!!!"                       
    else
      echo ""
      su - $INST -c "$WPATH/$PROGM -t start_use_internal -i $INST"                                                                          
    fi
    echo ""
    echo ""

    INST=`echo "$INSTS_TMP"|cut -d, -f $count`
    (( count=$count + 1 ))
  done

  exit 0
}

# end of start instance

#
# stop_instance
# run it with instance id
__stop_instance ( ) {

  if [ "$INST" == "" ]; then
    INST=$USER
  fi

  if [ `ps -ef | grep db2sys | grep -i -w $INST | grep -cv grep` -ge 1 ]; then
    echo "stopping Instances $INST"
    if [[ $OS == "AIX" ]]; then
      db2 force application all
      db2 force application all
      for db in `db2 list db directory | grep -p 'Indirect'  | grep 'Database name' | awk -F'=' '{print $2}'`
      do
        db2 deactivate db $db
      done
    else
      db2 force application all
      db2 force application all
      for db in `db2 list db directory | grep -B 5 'Indirect'  | grep 'Database name' | awk -F'=' '{print $2}'`
      do
        db2 deactivate db $db
      done
    fi

    (db2stop force && ipclean) | tee ${CMD_TMPFILE}
    # SQL1064N  DB2STOP processing was successful.
    # SQL1032N  No start database manager command was issued.  SQLSTATE=57019
    if [[ `grep -E -c '(SQL1064N|SQL1032N)' ${CMD_TMPFILE}` -gt 0 ]]; then
      echo "REPORT STATUS, STOP INSTANCE: ${INST}#OK"
    else
      STOP_INST_STATUS="${STOP_INST_STATUS}NO,"
      echo "REPORT STATUS, STOP INSTANCE: ${INST}#X"
      exit 1
    fi
  else
    echo "Instance $INST is already stopped, no action required"
    echo "REPORT STATUS, STOP INSTANCE: ${INST}#OK"
  fi

  exit 0
}

stop_instance ( ) {

  if [ `id -u` -ne 0 ]; then
    echo "going to stop current instance $USER"
    __stop_instance
    exit 0
  elif [ "$INSTS" == "" ]; then
    echo "Pls specify the instance names when running by root"
    Usage
    exit 1
  fi

  echo "==========================================="
  echo "= stop instances : $INSTS                 "
  echo "==========================================="
  count=2
  INSTS_TMP="${INSTS},"
  INST=`echo "$INSTS_TMP"|cut -d, -f 1`
  while [ "$INST" != "" ]
  do
    INST=`echo $INST | tr [A-Z] [a-z]`
    echo "++ stop instance $INST"
    id $INST >/dev/null 2>&1
    if [ $? -ne 0 ]; then 
      echo "Instance $INST is not exists, please check it!!!"                       
    else
      echo ""
      su - $INST -c "$WPATH/$PROGM -t stop_use_internal -i $INST"                                                                          
    fi
    echo ""
    echo ""

    INST=`echo "$INSTS_TMP"|cut -d, -f $count`
    (( count=$count + 1 ))
  done

  exit 0
}
# end of stop instance

#
# function rebind_all
# run it with instance id
__rebind_all () {
  if [ "$INST" == "" ]; then
    INST=$USER
  fi

  # check if any local DB cataloged first
  if [[ $OS == "AIX" ]]; then
    db_count=`db2 list db directory | grep -p 'Indirect' | grep 'Database name' | sort -u | wc -l`
  else
    db_count=`db2 list db directory | grep -B 5 'Indirect' | grep 'Database name' | sort -u | wc -l`
  fi

  if [[ $db_count -eq  0 ]]; then
    echo "NO local DB cataloged in instance $INST"
    echo "rebind DB will be skipped"
    echo "REPORT STATUS, BIND DB: ${INST}#--"
    exit 0
  fi

  if [ `ps -ef | grep db2sys | grep -i -w $INST | grep -cv grep` -lt 1 ]; then
    echo "Issuing: db2start"
    db2start
  fi

  if [[ $OS == "AIX" ]]; then
    for db in `db2 list db directory | grep -p 'Indirect' | grep 'Database name' | sort -u | awk -F'=' '{print $2}'`
    do
      db2 activate db $db
    done
  else
    for db in `db2 list db directory | grep -B 5 'Indirect' | grep 'Database name' | sort -u | awk -F'=' '{print $2}'`
    do
      db2 activate db $db
    done
  fi

  TMP_BIND_DB_STATUS="-"
  echo "do rebind $INST"
  if [[ $OS == "AIX" ]]; then
    for db in `db2 list db directory | grep -p 'Indirect'  | grep 'Database name' | awk -F'=' '{print $2}'`
    do
      cd $HOME/sqllib/bnd
      db2 connect to $db
      db2 bind  db2schema.bnd blocking all grant public SQLERROR continue   | tee $CMD_TMPFILE
      db2 bind  @db2ubind.lst BLOCKING ALL sqlerror continue grant public   | tee -a $CMD_TMPFILE
      db2 bind  @db2cli.lst blocking all grant public action add            | tee -a $CMD_TMPFILE

    # for capture and apply
      db2 bind @capture.lst isolation ur blocking all                       | tee -a $CMD_TMPFILE
      db2 bind @applycs.lst isolation cs blocking all grant public          | tee -a $CMD_TMPFILE
      db2 bind @applyur.lst isolation ur blocking all grant public          | tee -a $CMD_TMPFILE
    
    # for Qcapture and Qapply
      db2 bind @qcapture.lst isolation ur blocking all                      | tee -a $CMD_TMPFILE
      db2 bind @qapply.lst isolation ur blocking all grant public           | tee -a $CMD_TMPFILE
      db2 terminate
      if [ `grep 'Binding was ended with' $CMD_TMPFILE | tail -1 | awk -F'"' '{print $2}'` -eq 0 ]; then
        echo "rebind on database $db successful"
        TMP_BIND_DB_STATUS="${TMP_BIND_DB_STATUS}OK-"
      else
        echo "rebind on database $db failed"
        TMP_BIND_DB_STATUS="${TMP_BIND_DB_STATUS}X-"
      fi
    done
  else
    for db in `db2 list db directory | grep -B 5 'Indirect'  | grep 'Database name' | awk -F'=' '{print $2}'`
    do
      cd $HOME/sqllib/bnd
      db2 connect to $db
      db2 bind  db2schema.bnd blocking all grant public SQLERROR continue   | tee $CMD_TMPFILE
      db2 bind  @db2ubind.lst BLOCKING ALL sqlerror continue grant public   | tee -a $CMD_TMPFILE
      db2 bind  @db2cli.lst blocking all grant public action add            | tee -a $CMD_TMPFILE

      # for capture and apply
      db2 bind @capture.lst isolation ur blocking all                       | tee -a $CMD_TMPFILE
      db2 bind @applycs.lst isolation cs blocking all grant public          | tee -a $CMD_TMPFILE
      db2 bind @applyur.lst isolation ur blocking all grant public          | tee -a $CMD_TMPFILE
    
      # for Qcapture and Qapply
      db2 bind @qcapture.lst isolation ur blocking all                      | tee -a $CMD_TMPFILE
      db2 bind @qapply.lst isolation ur blocking all grant public           | tee -a $CMD_TMPFILE
      db2 terminate
      if [ `grep 'Binding was ended with' $CMD_TMPFILE | tail -1 | awk -F'"' '{print $2}'` -eq 0 ]; then
        echo "rebind on database $db successful"
        TMP_BIND_DB_STATUS="${TMP_BIND_DB_STATUS}OK-"
      else
        echo "rebind on database $db failed"
        TMP_BIND_DB_STATUS="${TMP_BIND_DB_STATUS}X-"
      fi
    done
  fi

  echo "REPORT STATUS, BIND DB: ${INST}#${TMP_BIND_DB_STATUS}"

  exit 0
}

rebind_all ( ) {

  if [ `id -u` -ne 0 ]; then
    echo "going to rebind databases in current instance $USER"
    __rebind_all
    exit 0
  elif [ "$INSTS" == "" ]; then
    echo "Pls specify the instance names when running by root"
    Usage
    exit 1
  fi

  echo "==========================================="
  echo "= rebind databases in instances : $INSTS   "
  echo "==========================================="
  count=2
  INSTS_TMP="${INSTS},"
  INST=`echo "$INSTS_TMP"|cut -d, -f 1`
  while [ "$INST" != "" ]
  do
    INST=`echo $INST | tr [A-Z] [a-z]`
    echo "++ rebind databases in instance $INST"
    id $INST >/dev/null 2>&1
    if [ $? -ne 0 ]; then 
      echo "Instance $INST is not exists, please check it!!!"                       
    else
      echo ""
      su - $INST -c "$WPATH/$PROGM -t r_use_internal -i $INST"                                                                          
    fi
    echo ""
    echo ""

    INST=`echo "$INSTS_TMP"|cut -d, -f $count`
    (( count=$count + 1 ))
  done

  exit 0
}

# end of rebind_all

#
# update/upgrade instance
# run it with root
# use $code_path/bin/db2greg -dump to get the current DB2 version, and the new version. 
# Then dicide to use db2iupdt or db2iupgrade
__update_instance () {

  if [ "$INST" == "" ]; then
    INST=$USER
  fi

  # check if run as root
  if [ `id -u` -ne 0 ]; then
    echo "You are run into the upgrade/update part, root access is required"
    Usage
    exit 1
  fi

  if [ "$INST" ==  "" ]; then
    echo "-i <instances> is mandatory when calling update instance"
    Usage
    exit 1
  fi

  if [ "$CPATH" ==  "" ]; then
    echo "-b <code path> is mandatory when calling update instance"
    Usage
    exit 1
  fi
  echo "update instance: $INST"

  if [[ -f $CPATH/instance/db2iupdt ]]; then
    echo "$CPATH/instance/db2iupdt -k $INST"
    $CPATH/instance/db2iupdt -k $INST  | tee $CMD_TMPFILE
    if [[ `grep -c 'db2iupdt completed successfully' $CMD_TMPFILE` -ne 0 ]]; then
      echo "Update instance $INST successfully!"
      echo "REPORT STATUS, UPDATE INSTANCE: ${INST}#OK"
    else
      echo "Update instance $INST failed!"
      echo "REPORT STATUS, UPDATE INSTANCE: ${INST}#X"
    fi
  else
    echo "db2iupdt is not exist on $CPATH/instance..."
    echo "REPORT STATUS, UPDATE INSTANCE: ${INST}#X"
  fi
  echo "end of upgrade instance: $INST"
}

update_instance () {
  if [ `id -u` -ne 0 ]; then
    echo "going to apply fixpack for current instance $USER"
    __update_instance
    exit 0
  elif [ "$INSTS" == "" ]; then
    echo "Pls specify the instance names when running by root"
    Usage
    exit 1
  fi

  echo "==========================================="
  echo "= apply fixpack for instances : $INSTS     "
  echo "==========================================="
  count=2
  INSTS_TMP="${INSTS},"
  INST=`echo "$INSTS_TMP"|cut -d, -f 1`
  while [ "$INST" != "" ]
  do
    INST=`echo $INST | tr [A-Z] [a-z]`
    echo "++ apply fixpack for instance $INST"
    id $INST >/dev/null 2>&1
    if [ $? -ne 0 ]; then 
      echo "Instance $INST is not exists, please check it!!!"                       
    else
      echo ""
      __update_instance
    fi
    echo ""
    echo ""

    INST=`echo "$INSTS_TMP"|cut -d, -f $count`
    (( count=$count + 1 ))
  done
}
# end of update_instance

# upgrade instance
__upgrade_instance () {

  if [ "$INST" == "" ]; then
    INST=$USER
  fi

  if [ `id -u` -ne 0 ]; then
    echo "You are run into the upgrade/update part, root access is required"
    Usage
    exit 1
  fi

  if [ "$INST" ==  "" ]; then
    echo "-i <instances> is mandatory when calling upgrade instance"
    Usage
    exit 1
  fi

  if [ "$CPATH" ==  "" ]; then
    echo "-b <code path> is mandatory when calling upgrade instance"
    Usage
    exit 1
  fi
  echo "upgrade instance: $INST"

  if [[ -f $CPATH/instance/db2iupdt ]]; then
    echo "$CPATH/instance/db2iupgrade -k $INST"
    $CPATH/instance/db2iupgrade -k $INST  | tee $CMD_TMPFILE
    if [[ `grep -c 'db2iupgrade completed successfully' $CMD_TMPFILE` -ne 0 ]]; then
      echo "Upgrade instance $INST successfully!"
      echo "REPORT STATUS, UPGRADE INSTANCE: ${INST}#OK"
    else
      echo "Upgrade instance $INST failed!"
      echo "REPORT STATUS, UPGRADE INSTANCE: ${INST}#X"
    fi
  else
    echo "db2iupgrade is not exist on $CPATH/instance..."
    echo "REPORT STATUS, UPGRADE INSTANCE: ${INST}#X"
  fi
  echo "end of upgrade instance: $INST"
}

upgrade_instance () {
  if [ `id -u` -ne 0 ]; then
    echo "going to upgrade current instance $USER"
    __upgrade_instance
    exit 0
  elif [ "$INSTS" == "" ]; then
    echo "Pls specify the instance names when running by root"
    Usage
    exit 1
  fi

  echo "==========================================="
  echo "= upgrade instances : $INSTS               "
  echo "==========================================="
  count=2
  INSTS_TMP="${INSTS},"
  INST=`echo "$INSTS_TMP"|cut -d, -f 1`
  while [ "$INST" != "" ]
  do
    INST=`echo $INST | tr [A-Z] [a-z]`
    echo "++ upgrade instance $INST"
    id $INST >/dev/null 2>&1
    if [ $? -ne 0 ]; then 
      echo "Instance $INST is not exists, please check it!!!"                       
    else
      echo ""
      __upgrade_instance
    fi
    echo ""
    echo ""

    INST=`echo "$INSTS_TMP"|cut -d, -f $count`
    (( count=$count + 1 ))
  done
}
# end of upgrade_instance

# upgrade database
__upgrade_database () {
  if [ "$INST" == "" ]; then
    INST=$USER
  fi

  echo "upgrade databases in instance $INST"

  if [[ $OS == "AIX" ]]; then
    if [ `db2 list db directory | grep -p 'Indirect' | grep -c 'Database name'` -eq 0 ]; then
      echo "No database cataloged this instance $USER"
      echo "No upgrade database is needed"
      echo "REPORT STATUS, UPGRADE DB: ${INST}#--"
      exit 0
    fi
  else
    if [ `db2 list db directory | grep -B 5 'Indirect' | grep -c 'Database name'` -eq 0 ]; then
      echo "No database cataloged this instance $USER"
      echo "No upgrade database is needed"
      echo "REPORT STATUS, UPGRADE DB: ${INST}#--"
      exit 0
    fi
  fi

  if [ `ps -ef | grep db2sys | grep -i -w $INST | grep -cv grep` -lt 1 ]; then
    echo "Issuing: db2start"
    db2start
  fi

  TMP_DB_UPGRADE_STATUS="-"
  if [[ $OS == "AIX" ]]; then
    for db in `db2 list db directory | grep -p 'Indirect' | grep 'Database name' | sort -u | awk -F'=' '{print $2}'`
    do
      echo "db2 upgrade db $db"
      db2 deactivate db $db
      db2 upgrade db $db  | tee $CMD_TMPFILE
      if [[ `grep -i -c 'UPGRADE DATABASE command completed successfully' $CMD_TMPFILE` -ne 0 ]]; then
        echo "Upgrade DB $INST:$db successfully"
        TMP_DB_UPGRADE_STATUS="${TMP_DB_UPGRADE_STATUS}OK-"
      else
        echo "Upgrade DB $INST:$db failed"
        TMP_DB_UPGRADE_STATUS="${TMP_DB_UPGRADE_STATUS}X-"
      fi
    done
  else
    for db in `db2 list db directory | grep -B 5 'Indirect' | grep 'Database name' | sort -u | awk -F'=' '{print $2}'`
    do
      echo "db2 upgrade db $db"
      db2 deactivate db $db
      db2 upgrade db $db  | tee $CMD_TMPFILE
      if [[ `grep 'UPGRADE DATABASE' $CMD_TMPFILE | grep -c 'successfully'` -ne 0 ]]; then
        echo "Upgrade DB $INST:$db successfully"
        TMP_DB_UPGRADE_STATUS="${TMP_DB_UPGRADE_STATUS}OK-"
      else
        echo "Upgrade DB $INST:$db failed"
        TMP_DB_UPGRADE_STATUS="${TMP_DB_UPGRADE_STATUS}X-"
      fi
    done
  fi

  echo "REPORT STATUS, UPGRADE DB: ${INST}#${TMP_DB_UPGRADE_STATUS}"

  exit 0
}

upgrade_database ( ) {

  if [ `id -u` -ne 0 ]; then
    echo "going to upgrade databass in instance $USER"
    __upgrade_database
    exit 0
  elif [ "$INSTS" == "" ]; then
    echo "Pls specify the instance names when running by root"
    Usage
    exit 1
  fi

  echo "==========================================="
  echo "= upgrade databases in instances : $INSTS  "
  echo "==========================================="
  count=2
  INSTS_TMP="${INSTS},"
  INST=`echo "$INSTS_TMP"|cut -d, -f 1`
  while [ "$INST" != "" ]
  do
    INST=`echo $INST | tr [A-Z] [a-z]`
    echo "++ upgrade databases in instance $INST"
    id $INST >/dev/null 2>&1
    if [ $? -ne 0 ]; then 
      echo "Instance $INST is not exists, please check it!!!"                       
    else
      echo ""
      # start the instance first before upgrade the DB
      # su - $INST -c "$WPATH/$PROGM -t START_INST -i $INST"
      su - $INST -c "$WPATH/$PROGM -t UPGRADE_DB -i $INST"                                                                          
    fi
    echo ""
    echo ""

    INST=`echo "$INSTS_TMP"|cut -d, -f $count`
    (( count=$count + 1 ))
  done

  exit 0
}
# end of upgrade database

# apply license, preserv, not used yet
apply_license () {
  if [ -f "$LFILE" ]; then
    echo "apply license"
    echo "$CPATH/adm/db2licm -a $LFILE"
    $CPATH/adm/db2licm -a $LFILE
  fi
}
# end of apply_license

#
# Healthcheck functions
#
Fix_A020 ( ) {

  # cat *.info | grep -w 'VIOLATION' | grep A020
  # A020  |DBAUTH              |PUBLIC   |IMPLSCHEMA  |VIOLATION
  # A020  |DBAUTH              |PUBLIC  |CONNECT     |VIOLATION

  echo "Fixing Violation: $1"
  priv=`echo $1 | awk -F'|' '{print $4}' | awk 'gsub(" ","",$0)'`

  if [ "$priv" == "CONNECT" ]; then
    cmd="db2 revoke CONNECT on database from PUBLIC"
  fi

  if [ "$priv" == "IMPLSCHEMA" ]; then
    cmd="db2 revoke IMPLICIT_SCHEMA on database from PUBLIC"
  fi

  db2 connect to $db_name
  echo ${cmd} | tee -a $vscript
  ${cmd}
  db2 terminate

} # end of Fix_A020

Fix_A021 ( ) {

  # cat *.info | grep -w 'VIOLATION' | grep A021
  # A021  |Schema-JEBRUNSG                            |PUBLIC           |CREATEIN           |VIOLATION

  #cmd=`echo $1 | awk '{print $2 " " $3}' | sed 's/[\|]/ /g' | cut -d "-" -f2 | awk '{print "db2 revoke " $2 " on schema " $1 " from public" '}`
  echo "Fixing Violation: $1"

  cmd=`echo $1 | awk '{print $2 " " $3}' | sed 's/[\|]/ /g' | cut -d "-" -f2 | awk '{print "db2 revoke CREATEIN on schema " $1 " from public" '}`

  db2 connect to $db_name
  echo ${cmd} | tee -a $vscript
  ${cmd}
  db2 terminate

} # end of Fix_A021

Fix_A026 ( ) {

  # cat *.info | grep -w 'VIOLATION' | grep A026
  # A026  |SYSIBM.SYSSECURITYLABELCOMPONENTELEMENTS  |PUBLIC           |SELECT             |VIOLATION

  echo "Fixing Violation: $1"
  cmd=`echo $1 | awk '{print $2 " " $3}' | sed 's/[\|]/ /g' | cut -d "-" -f2 | awk '{print "db2 revoke select on table " $1 " from public" '}`

  db2 connect to $db_name
  echo ${cmd} | tee -a $vscript
  ${cmd}
  db2 terminate

} # end of Fix_A026


# A045|A050|A055|A058|A060|A062|A065|A066|A070
# For A070, need root access
Fix_A065 ( ) {

  # A065  |775  |F:775  |instptx1  |staff    |/home/instptx1/.profile                                                      |VIOLATION-Grp
  # A065  |775  |F:666  |instptx1  |dbadmin  |/home/instptx1/core.20150412.075515.22741002.dmp                             |VIOLATION

  echo "Fixing Violation: $1"
  cmd=`echo $1 | grep -w 'VIOLATION' | egrep 'A045|A050|A055|A058|A060|A062|A065|A066|A070' | awk -F'|' '{print "chmod " $2 $6}'`

  echo ${cmd} | tee -a $vscript
  ${cmd}

  # for VIOLATION-Grp
  mgroup=`id -ng $USER`
  #cmd=`echo $1 | grep -w 'VIOLATION-Grp' | egrep 'A045|A050|A055|A058|A060|A062|A065|A066|A070' | awk -F'|' '{gsub(" ","",$4);print "chown "$4":"$5 $6}'`
  cmd=`echo $1 | grep -w 'VIOLATION-Grp' | egrep 'A045|A050|A055|A058|A060|A062|A065|A066|A070' |awk -F'|' -vg="$mgroup" '{gsub(" ","",$4);print "chown "$4":"g" "$6}'`

  echo ${cmd} | tee -a $vscript
  ${cmd}
}

# fix violations
__fix_vio () {

  if [ ! -f $HOME/Security/db2shc ]; then
    echo "db2shc is not exists in instance $USER"
    exit 1
  fi

  SHOME="$HOME/Security/"
  vtmp="$SHOME/.vtmp.out"
  hostname=`hostname`

  if [ "$INST" == "" ]; then
    INST=$USER
  fi
  
  cd $SHOME

  echo "Going to run db2shc -nm, it may take minutes, please be patient!"
  $SHOME/db2shc -nm >/dev/null 2>&1
  hcfiles=$(ls $SHOME/*$hostname-$USER*.out)
  if [[ $? -ne 0 ]]; then
    echo "Pls check if #SHC_TYPE=SERVER, pls be sure DB2 instance is running"
    echo "Exit Health Check, if needed, run it with -t HC later"
    echo "REPORT STATUS, HEALTH CHECK: ${INST}#X"
    exit 1
  fi

  TMP_HC_STATUS="-"

  for hcfile in $hcfiles
  do
    viols=$(awk -F\| '/TOTAL VIOLATIONS/ { print $5 }' $hcfile)
    db_name=$(ls -l $hcfile | awk -F':' '{print $2}' | awk -F'-' '{print $5}')
    echo $db_name : $viols

    if [[ $viols -gt 0 ]]
    then
      echo "Violations before we run this script $db_name: totally $viols type(s)" 
      cat $SHOME/*$hostname-$USER-$db_name*.info | grep -w 'VIOLATION' | head -10 
      echo "......" 
      echo ""       
      echo "going to fix those violations."
      cat $SHOME/*$hostname-$USER-$db_name*.info | grep -w 'VIOLATION' > $vtmp
      while read line
      do
        vtype=`echo $line | awk -F'|' '{gsub(" ","",$1);print $1}'`
        case $vtype in
          "A020") Fix_A020 "$line" ;;
          "A021") Fix_A021 "$line" ;;
          "A026") Fix_A026 "$line" ;;
          "A045"|"A050"|"A055"|"A058"|"A060"|"A062"|"A065"|"A066")  Fix_A065 "$line" ;;
          #"A070")  Fix_A070 "$line" ;;
        esac
      done < $vtmp
    else
      echo "No violations found for $db_name" 
      echo "Exit Health Check, if needed, run it with -t HC later"
    fi
  done

  # run it again
  echo "Going to run db2shc -nm again, it may take minutes, please be patient!"
  $SHOME/db2shc -nm >/dev/null 2>&1
  hcfiles=$(ls $SHOME/*$hostname-$USER*.out)

  for hcfile in $hcfiles
  do
    viols=$(awk -F\| '/TOTAL VIOLATIONS/ { print $5 }' $hcfile)
    db_name=$(ls -l $hcfile | awk -F':' '{print $2}' | awk -F'-' '{print $5}')
    echo $db_name : $viols

    if [[ $viols -gt 0 ]]
    then
      echo "Violations after we run this script $db_name: totally $viols type(s)" 
      cat $SHOME/*$hostname-$USER-$db_name*.info | grep -w 'VIOLATION' | head -10 
      echo "......" 
      echo "Those violations that need root access to fix, Pls fix them manually."
      echo "Exit Health Check, if needed, run it with '-t HC' later"
      TMP_HC_STATUS="${TMP_HC_STATUS}X-"
    else
      echo "Violations after we run this script for $db_name: totally $viols type(s)" 
      echo "ALL violations fixed!!" 
      TMP_HC_STATUS="${TMP_HC_STATUS}OK-"
      echo "cat $hcfile | grep -w 'TOTAL VIOLATIONS"
      cat $hcfile | grep -w 'TOTAL VIOLATIONS'
    fi
  done

  echo "REPORT STATUS, HEALTH CHECK: ${INST}#${TMP_HC_STATUS}"

  \rm $vtmp  2>/dev/null

  exit 0
}

# end of fix violations

health_check( ) {

  if [ `id -u` -ne 0 ]; then
    echo "going to fix violations for current instance $USER"
    __fix_vio
    exit 0
  elif [ "$INSTS" == "" ]; then
    echo "Pls specify the instance names when running by root"
    Usage
    exit 1
  fi

  echo "==========================================="
  echo "= run health check for instances : $INSTS  "
  echo "==========================================="
  count=2
  INSTS_TMP="${INSTS},"
  INST=`echo "$INSTS_TMP"|cut -d, -f 1`
  while [ "$INST" != "" ]
  do
    INST=`echo $INST | tr [A-Z] [a-z]`
    echo "++ do health check for instance $INST"
    id $INST >/dev/null 2>&1
    if [ $? -ne 0 ]; then 
      echo "Instance $INST is not exists, please check it!!!"                       
    else
      echo ""
      su - $INST -c "$WPATH/$PROGM -t h_use_internal -i $INST"                                                                          
    fi
    echo ""
    echo ""

    INST=`echo "$INSTS_TMP"|cut -d, -f $count`
    (( count=$count + 1 ))
  done

  exit 0
}
# end of health check

# collect_evidence
__collect_evidence ( ) {
  if [ ! -f $HOME/Security/db2shc ]; then
    echo "db2shc is not exists..."
  else
    $HOME/Security/db2shc -nm  > /dev/null 2>&1
    cat $HOME/Security/*.out | grep -i 'TOTAL VIOLATIONS'
  fi
  echo "db2level"
  db2level
  echo "db2licm -l"
  db2licm -l
  echo "db2ilist:"
  db2ilist

  exit 0
}

collect_evidence () {

  if [ `id -u` -ne 0 ]; then
    echo "going to collect evidence for instance $USER"
    __collect_evidence
    exit 0
  elif [ "$INSTS" == "" ]; then
    echo "Pls specify the instance names when running by root"
    Usage
    exit 1
  fi

  echo "==========================================="
  echo "= collect evidence for instances : $INSTS  "
  echo "==========================================="

  count=2
  INSTS_TMP="${INSTS},"
  INST=`echo "$INSTS_TMP"|cut -d, -f 1`
  while [ "$INST" != "" ]
  do
    INST=`echo $INST | tr [A-Z] [a-z]`
    echo "++ collect evidence for instance $INST"
    id $INST > /dev/null 2>&1
    if [ $? -ne 0 ]; then 
      echo "Instance $INST is not exists, please check it!!!"                       
    else
      echo ""
      su - $INST -c "$WPATH/$PROGM -t e_use_internal -i $INST"                                                                          
    fi
    echo ""
    echo ""

    INST=`echo "$INSTS_TMP"|cut -d, -f $count`
    (( count=$count + 1 ))
  done

  exit 0
}
# end of add_evidence

# task

OPTIND=1
while getopts ":t:b:i:" opt
do
  case ${opt} in
    t )  op=${OPTARG} ;;
    b )  CPATH=${OPTARG} ;;
    i )  INSTS=${OPTARG} ;;
  esac
done

case $op in
  u_use_internal )
    upgrade_instance ;;
  r_use_internal )
    __rebind_all ;;
  h_use_internal )
    __fix_vio ;;
  e_use_internal )
    __collect_evidence ;;
  stop_use_internal )
    __stop_instance ;;
  start_use_internal )
    __start_instance ;;
  START_INST )
    start_instance ;;
  STOP_INST )
    stop_instance ;;
  BIND_DB )
    rebind_all ;;
  HC )
    health_check ;;
  CE )
    collect_evidence ;;
  UPGRADE_DB )
    upgrade_database ;;
  esac
# end of task

############################################################
# end of task functions
############################################################

# You are run into the upgrade/update part, root access is needed
if [ `id -u` -ne 0 ]; then
  echo "You are run into the upgrade/update part, root access is required"
  Usage
  exit 1
fi
#
#Check script specific parms
#
OPTIND=1
while getopts ":i:b:w:" opt
do
  case ${opt} in
    i )  INSTS=${OPTARG} ;;
    b )  CPATH=${OPTARG} ;;
    w )  WPATH=${OPTARG} ;;
  esac
done

if [[ "$INSTS" == "" ]]; then
  echo "Instances name must be specific when upgrade/update instances"
  Usage
  exit 1
fi

if [[ "$CPATH" == "" ]]; then
  echo "DB2 code path must be specific when upgrade/update instances"
  Usage
  exit 1
fi

if [[ ! -f $CPATH/instance/db2iupdt ]]; then
  echo "db2iupdt is not exist on $CPATH/instance..."
  echo "Pls specify the right DB2 code path"
  Usage
  exit 1
fi

INSTS_TMP=`echo $INSTS | sed -e 's/,/./g'`
RFILE="$RPATH/${INSTS_TMP}.`date "+%H%M%S"`.log"

# erase the / in the code path if any, in case, with / , we can't match the code path
CPATH=$(echo $CPATH | sed -e 's/\/$//')

echo "@&@&@&@&@&@&@&@&@&@&@&@&@&@&@&@&@&@&@&@&@&@&@&@&@&@&@&@&@&@&@&@&@&@&"        | tee $RFILE
echo "@ Instances going to upgrade/update: $INSTS                       "          | tee -a $RFILE
echo "@ Using code: $CPATH                                              "          | tee -a $RFILE
echo "@ Working directory: $WPATH                                       "          | tee -a $RFILE
echo "@ Output file:       $RFILE                                       "          | tee -a $RFILE
echo "@&@&@&@&@&@&@&@&@&@&@&@&@&@&@&@&@&@&@&@&@&@&@&@&@&@&@&@&@&@&@&@&@&@&"        | tee -a $RFILE

# check it's upgrade or update
count=2
INSTS_TMP="${INSTS},"
INST=`echo "$INSTS_TMP"|cut -d, -f 1`
while [ "$INST" != "" ]
do
  id $INST > /dev/null 2>&1
  if [[ $? -eq 0 ]]; then
    current_version=$($CPATH/bin/db2greg -dump | grep ^I | grep -w $INST |\
                    grep -v 'DB2INSTDEF' | awk -F',' '{print $3}' | cut -d'.' -f 1 | tail -1)
    new_version=$($CPATH/bin/db2greg -dump | grep ^S | grep -w "$CPATH" |\
                awk -F',' '{print $3}' | cut -d'.' -f 1 | tail -1 )

    #echo "new_version: $new_version"
    #echo "current_version: $current_version"
    break
  fi
  INST=`echo "$INSTS_TMP"|cut -d, -f $count`
  (( count=$count + 1 ))
done

task_step=1
# main function
echo "task #${task_step}: stop instances"                                           | tee -a $RFILE
$WPATH/$PROGM -t STOP_INST -i $INSTS                                                | tee -a $RFILE

((task_step=task_step+1))
if [[ "$current_version" == "$new_version" ]]; then
  echo "task #${task_step}: apply fixpack for instances"                            | tee -a $RFILE
  update_instance                                                                   | tee -a $RFILE
else
  echo "task #${task_step}: upgrade instances"                                      | tee -a $RFILE
  upgrade_instance                                                                  | tee -a $RFILE

  ((task_step=task_step+1))                                        
  echo "task #${task_step} upgrade databases"                                       | tee -a $RFILE
  $WPATH/$PROGM -t UPGRADE_DB -i $INSTS                                             | tee -a $RFILE
fi

((task_step=task_step+1))                                                         
echo "task #${task_step}: rebind databases"                                         | tee -a $RFILE
$WPATH/$PROGM -t BIND_DB -i $INSTS                                                  | tee -a $RFILE

((task_step=task_step+1))
echo "task #${task_step}: health check on instances"                                | tee -a $RFILE
$WPATH/$PROGM -t HC -i $INSTS                                                       | tee -a $RFILE

((task_step=task_step+1))
echo "task #${task_step}: collect evidence for instances"                           | tee -a $RFILE
$WPATH/$PROGM -t CE -i $INSTS                                                       | tee -a $RFILE
# end of main function

# Final report
echo "####################################################################"         | tee -a $RFILE
echo "@ Details output:       $RFILE                                      "         | tee -a $RFILE
echo "@ Summary report:                                                   "         | tee -a $RFILE


printf "%-15s%-15s%-15s%-15s%-15s%-15s%-15s%-15s\n" "@ instance" "stop_inst" "applyfp" "upgrade_inst" \
       "upgrade_db" "bind_db" "health_check" "collect_evidence"                     | tee -a $RFILE

count=2
INSTS_TMP="${INSTS},"
INST=`echo "$INSTS_TMP"|cut -d, -f 1`
while [ "$INST" != "" ]
do
  INST=`echo $INST | tr [A-Z] [a-z]`
  id $INST > /dev/null 2>&1
 
  stop_instance_status=`grep 'REPORT STATUS, STOP INSTANCE' $RFILE | grep "${INST}#" | awk -F'#' '{print $2}'`
  [ -z $stop_instance_status ] && stop_instance_status="--"

  applyf_instance_status=`grep 'REPORT STATUS, UPDATE INSTANCE' $RFILE | grep "${INST}#" | awk -F'#' '{print $2}'`
  [ -z $applyf_instance_status ] && applyf_instance_status="--"

  upgrade_instance_status=`grep 'REPORT STATUS, UPGRADE INSTANCE' $RFILE | grep "${INST}#" | awk -F'#' '{print $2}'`
  [ -z $upgrade_instance_status ] && upgrade_instance_status="--"

  upgrade_dbs_status=`grep 'REPORT STATUS, UPGRADE DB' $RFILE | grep "${INST}#" | awk -F'#' '{print $2}'`
  [ -z $upgrade_dbs_status ] && upgrade_dbs_status="--"

  bind_dbs_status=`grep 'REPORT STATUS, BIND DB' $RFILE | grep "${INST}#" | awk -F'#' '{print $2}'`
  [ -z $bind_dbs_status ] && bind_dbs_status="--"

  health_check_status=`grep 'REPORT STATUS, HEALTH CHECK' $RFILE | grep "${INST}#" | awk -F'#' '{print $2}'`
  [ -z $health_check_status ] && health_check_status="--"

  printf "@ %-15s%-15s%-15s%-15s%-15s%-15s%-15s%-15s\n" "$INST" "$stop_instance_status" "$applyf_instance_status" \
          "$upgrade_instance_status" "$upgrade_dbs_status" "$bind_dbs_status" "$health_check_status" "OK"    | tee -a $RFILE

  INST=`echo "$INSTS_TMP"|cut -d, -f $count`
  (( count=$count + 1 ))
done
echo "####################################################################"        | tee -a $RFILE
echo "Note: OK for successful, X for fail, -- for skip or no action"               | tee -a $RFILE
echo "      for upgrade_db, bind_db and health_check, each DB has its status"      | tee -a $RFILE

# end of Final report


# end of script
