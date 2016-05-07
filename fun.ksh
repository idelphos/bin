#!/bin/ksh

export DBBAKDIR=/home/yadelph/backup
export DBOUTPUT=/home/yadelph/output

##############alias part############################
alias grephcfg='egrep "^ACCOUNT_CODE=|^PROJECT_ID=|^SERVER_TYPE=|^DB_TYPE=|^APP_TYPE=|^SHC_TYPE=|^EMAIL_DBA=|^EMAIL_VERIFIER=|^EMAIL_HCTEAM=" ~/Security/db2shc.cfg ' 
alias db2shc="~/Security/db2shc -nm; grep -i violation ~/Security/*.out ~/Security/*.info"
alias clstat='/usr/sbin/cluster/clstat -a'
alias db2ls='/usr/local/bin/db2ls'
alias suroot='sudo /tempdb2/tmp/db2setup'
alias applysync='db2 "select apply_qual,set_name,whos_on_first,sleep_minutes,lastrun,lastsuccess,synchtime,synchpoint,status,activate from asn.ibmsnap_subs_set where status <> 0"'
alias applysync2='db2 "select APPLY_QUAL,SET_NAME,STATUS,ACTIVATE,LASTRUN,LASTSUCCESS,SYNCHTIME from ASN.IBMSNAP_SUBS_SET order by 5"'


set -o vi


convertxt()
{
        perl -pi -e 's/\r\n/\n/;' $1    
}


# return all the local database name 
#db2lsdb()
#{
#       db2 list db directory | grep -iE "database alias|directory entry type"| awk -F = '{print $2}'| \
#       while read dbName 
#       do 
#               read dirType
#               if [ $dirType = "Indirect" ];then
#                       echo $dbName 
#               else
#                       continue
#               fi
#       done 
#       unset dirType
#       unset dbName
#}

#backup db2 instance setting to /home/yadelph/backup 
db2bkconf()
{
        if  cd $DBBAKDIR ; then
                :
        else
                echo " the directory for backup is not existent "
                exit
        fi
        timeStamp=bak.$(date +%F)
        crontab -l > $USER.crontab.$timeStamp
        set > $USER.set.$timeStamp
        db2set -all > $USER.db2set.$timeStamp
        db2licm -l > $USER.db2licm.$timeStamp
        db2audit describe >$USER.audit.$timeStamp
        db2  get dbm cfg > $USER.dbmcfg.$timeStamp     
        for dbName in $(db2lsdb)
        do
                db2 get db cfg for $dbName >$USER.${dbName}cfg.bak.$timeStamp
        done

        db2 list node directory >$USER.nodecat.bak.$timeStamp
        db2 list db directory >$USER.dbcat.bak.$timeStamp
        echo
        echo "-----------------------------------------------------"
        #echo " amount of backuped configuration:$(ls *.bak | wc -l)"
        #echo "-----------------------------------------------------"
        head $USER.*bak.$timeStamp
        cd -
}

reporthc()
{
        /db/dbawork/dbtools/dbchkinf.sh -s  | tee  /tmp/$(hostname).$USER.HC
    uuencode /tmp/$(hostname).$USER.HC $(hostname).$USER.HC.out > /tmp/$(hostname).HC.out cat ~yadelph/output/deploynotification.txt /tmp/$(hostname).HC.out | mail  -s "[Successful Deployment Notification]-$(hostname)"  yjyuan@cn.ibm.com  
        rm /tmp/$(hostname).$USER.HC
}


printhelp()
{
cat<<HERE

usage:
$(basename $0) -d <dbName> -u <granterUser>
options:
-d  specify the dbName you want to create
-u  specify the username you want to grant access to

HERE
}

db2dbauth()
{
        #db2dbauth <userName>
        userName=$(echo $1 | tr '[a-z]' '[A-Z]')
        db2 "select substr(GRANTOR,1,10) as GRANTOR,substr(GRANTEE,1,10) as GRANTEE,BINDADDAUTH,CONNECTAUTH,CREATETABAUTH,DBADMAUTH,EXTERNALROUTINEAUTH,IMPLSCHEMAAUTH,LOADAUTH,SECURITYADMAUTH from SYSCAT.DBAUTH where grantee='$userName'"
}

db2lsdb()
{
    if [ `uname` = "AIX" ] ;then
       db2 list db directory | grep -p Indirect|grep "Database name"|cut -d "=" -f 2
    else
       db2 list db directory | grep -B 5 Indirect|grep "Database name"|cut -d "=" -f 2
    fi
}

db2startall()
{
         #run the scripts as an instance ID
        /usr/local/bin/db2ls|grep "/"|cut -d " " -f 1|while read installed_db_code_path; do
          os_name=`uname`
          lsdbdir_opt="-p"
          if [[ "$os_name" == "AIX" ]]; then
            lsdbdir_opt="-p"
          else
            lsdbdir_opt="-B 5"
          fi
        echo ""
        echo "Code path $installed_db_code_path"
        echo "    Instances under the path :`$installed_db_code_path/instance/db2ilist|tr '\n' ' '`"
          if [ "`$installed_db_code_path/instance/db2ilist`" != "" ]; then
          echo "`$installed_db_code_path/instance/db2ilist`"|while read cur_inst_name; do
          echo ""
          echo "    Check Process of instance $cur_inst_name :"
          echo "        `ps -ef |grep db2sysc|grep -v grep|grep $cur_inst_name`"
          if [ `ps -ef |grep db2sysc|grep -v grep|grep $cur_inst_name|wc -l|sed "s/ //g"` -lt 1 ]; then
            echo "        Try to start up instance  --->   /home/$cur_inst_name/sqllib/adm/db2start"
            echo `. /home/$cur_inst_name/sqllib/db2profile >/dev/null;/home/$cur_inst_name/sqllib/adm/db2start`
            echo "        Recheck Process of instance $cur_inst_name :"
            echo "        `ps -ef |grep db2sysc|grep -v grep|grep $cur_inst_name`"
          fi
          echo "    Check Filesystem of instance $cur_inst_name :"
          echo "        `df |grep $cur_inst_name`"
          dblist=`. /home/$cur_inst_name/sqllib/db2profile >/dev/null;db2 list db directory|grep $lsdbdir_opt Indirect|grep "Database name"|cut -d "=" -f 2|sed 's/ //g'`
          echo "$dblist"|while read var_dbname ; do
            echo "    Check Database Connectivity of instance $cur_inst_name :"
            echo "        Activating database $var_dbname : `. /home/$cur_inst_name/sqllib/db2profile;db2 activate db $var_dbname;db2 terminate`"
            echo "        Connecting database $var_dbname : `. /home/$cur_inst_name/sqllib/db2profile;db2 connect to $var_dbname;db2 terminate`"
            done
          done
          fi
        done
}

db2lsall()
{       
/usr/local/bin/db2ls | grep "/" | cut -d " " -f 1 |\
while read dbCodePath
do 
        echo "db2 code path: $dbCodePath:"
        echo
        $dbCodePath/instance/db2ilist | \
        while read curInstName
        do
                echo "$curInstName--DB name: "
                . /home/$curInstName/sqllib/db2profile >/dev/null
                db2lsdb
                echo
        done
done
}



db2stopall()
{
/usr/local/bin/db2ls | grep "/" | cut -d " " -f 1 |\
while read dbCodePath
do
    echo "db2 code path $dbCodePath:"
    echo
    $dbCodePath/instance/db2ilist | \
    while read curInstName
    do
        . /home/$curInstName/sqllib/db2profile >/dev/null
        echo `db2lsdb` | while read dbName; do
        echo "  deactivate database $dbName:" 
                db2 force application all
                db2 deactivate db $dbName
                db2 terminate 
                done

        db2stop
        echo
    done
done

echo "curently running db2 process:"
ps -ef | grep -E "db2sysc|asn" | grep -v grep | sort -k9 
}


db2revpublic()
{
for dbname in $@
do
        db2 connect to $dbname;
        db2 revoke createin on schema syspublic                              from public        ;    
        db2 revoke CREATEIN on schema SQLJ                                   from PUBLIC        ;
        db2 revoke CREATEIN on schema SYSTOOLS                               from PUBLIC        ;
        db2 revoke select on table SYSIBMADM.AUTHORIZATIONIDS                from PUBLIC        ;
        db2 revoke select on table SYSCAT.COLAUTH                            from PUBLIC        ;
        db2 revoke select on table SYSCAT.DBAUTH                             from PUBLIC        ;
        db2 revoke select on table SYSCAT.INDEXAUTH                          from PUBLIC        ;
        db2 revoke select on table SYSCAT.LIBRARYAUTH                        from PUBLIC        ;
        db2 revoke select on table SYSIBMADM.OBJECTOWNERS                    from PUBLIC        ;
        db2 revoke select on table SYSIBMADM.PRIVILEGES                      from PUBLIC        ;
        db2 revoke select on table SYSCAT.PACKAGEAUTH                        from PUBLIC        ;
        db2 revoke select on table SYSCAT.PASSTHRUAUTH                       from PUBLIC        ;
        db2 revoke select on table SYSCAT.ROLEAUTH                           from PUBLIC        ;
        db2 revoke select on table SYSCAT.ROUTINEAUTH                        from PUBLIC        ;
        db2 revoke select on table SYSCAT.SCHEMAAUTH                         from PUBLIC        ;
        db2 revoke select on table SYSCAT.SECURITYLABELACCESS                from PUBLIC        ;
        db2 revoke select on table SYSCAT.SECURITYPOLICYEXEMPTIONS           from PUBLIC        ;
        db2 revoke select on table SYSCAT.SEQUENCEAUTH                       from PUBLIC        ;
        db2 revoke select on table SYSCAT.SURROGATEAUTHIDS                   from PUBLIC        ;
        db2 revoke select on table SYSIBM.SYSCOLAUTH                         from PUBLIC        ;
        db2 revoke select on table SYSIBM.SYSDBAUTH                          from PUBLIC        ;
        db2 revoke select on table SYSIBM.SYSINDEXAUTH                       from PUBLIC        ;
        db2 revoke select on table SYSIBM.SYSLIBRARYAUTH                     from PUBLIC        ;
        db2 revoke select on table SYSIBM.SYSPASSTHRUAUTH                    from PUBLIC        ;
        db2 revoke select on table SYSIBM.SYSPLANAUTH                        from PUBLIC        ;
        db2 revoke select on table SYSIBM.SYSROLEAUTH                        from PUBLIC        ;
        db2 revoke select on table SYSIBM.SYSROUTINEAUTH                     from PUBLIC        ;
        db2 revoke select on table SYSIBM.SYSSCHEMAAUTH                      from PUBLIC        ;
        db2 revoke select on table SYSIBM.SYSSECURITYLABELACCESS             from PUBLIC        ;
        db2 revoke select on table SYSIBM.SYSSECURITYPOLICYEXEMPTIONS        from PUBLIC         ;
        db2 revoke select on table SYSIBM.SYSSEQUENCEAUTH                    from PUBLIC         ;
        db2 revoke select on table SYSIBM.SYSSURROGATEAUTHIDS                from PUBLIC         ;
        db2 revoke select on table SYSIBM.SYSTABAUTH                         from PUBLIC         ;
        db2 revoke select on table SYSIBM.SYSTBSPACEAUTH                     from PUBLIC         ;
        db2 revoke select on table SYSIBM.SYSUSERAUTH                        from PUBLIC         ;
        db2 revoke select on table SYSIBM.SYSVARIABLEAUTH                    from PUBLIC         ;
        db2 revoke select on table SYSIBM.SYSWORKLOADAUTH                    from PUBLIC         ;
        db2 revoke select on table SYSIBM.SYSXSROBJECTAUTH                   from PUBLIC         ;
        db2 revoke select on table SYSCAT.TABAUTH                            from PUBLIC         ;
        db2 revoke select on table SYSCAT.TBSPACEAUTH                        from PUBLIC         ;
        db2 revoke select on table SYSCAT.VARIABLEAUTH                       from PUBLIC         ;
        db2 revoke select on table SYSCAT.WORKLOADAUTH                       from PUBLIC         ;
        db2 revoke select on table SYSCAT.XSROBJECTAUTH                      from PUBLIC         ;
        db2 revoke select on table SYSCAT.MODULEAUTH                         from PUBLIC         ;
        db2 revoke select on table SYSCAT.SECURITYLABELCOMPONENTELEMENTS     from PUBLIC         ;
        db2 revoke select on table SYSCAT.SECURITYLABELCOMPONENTS            from PUBLIC         ;
        db2 revoke select on table SYSCAT.SECURITYLABELS                     from PUBLIC         ;
        db2 revoke select on table SYSCAT.SECURITYPOLICIES                   from PUBLIC         ;
        db2 revoke select on table SYSCAT.SECURITYPOLICYCOMPONENTRULES       from PUBLIC         ;
        db2 revoke select on table SYSIBM.SQLCOLPRIVILEGES                   from PUBLIC         ;
        db2 revoke select on table SYSIBM.SQLTABLEPRIVILEGES                 from PUBLIC         ;
        db2 revoke select on table SYSIBM.SYSMODULEAUTH                      from PUBLIC         ;
        db2 revoke select on table SYSIBM.SYSSECURITYLABELCOMPONENTELEMENTS  from PUBLIC         ;
        db2 revoke select on table SYSIBM.SYSSECURITYLABELCOMPONENTS         from PUBLIC         ;
        db2 revoke select on table SYSIBM.SYSSECURITYLABELS                  from PUBLIC         ;
        db2 revoke select on table SYSIBM.SYSSECURITYPOLICIES                from PUBLIC         ;
        db2 revoke select on table SYSIBM.SYSSECURITYPOLICYCOMPONENTRULES    from PUBLIC         ;
        db2 revoke select  on table SYSIBM.SYSMODULEAUTH                     from public;
        db2 revoke select  on table SYSCAT.MODULEAUTH                        from public;
        db2 revoke select  on table SYSIBM.SYSSURROGATEAUTHIDS               from public;
        db2 revoke select on table SYSCAT.CONTROLS                           from public;
        db2 revoke select on table SYSIBM.SYSCONTROLS                        from public;
        db2 revoke select on table SYSCAT.CONTROLS                           from PUBLIC         ;
        db2 revoke select on table SYSIBM.SYSCOLAUTH                         from PUBLIC         ;
        db2 revoke select on table SYSIBM.SYSCONTROLS                        from PUBLIC         ;
        db2 revoke select on table SYSIBM.SYSDBAUTH                          from PUBLIC         ;
        db2 revoke select on table SYSIBM.SYSINDEXAUTH                       from PUBLIC         ;
        db2 revoke select on table SYSIBM.SYSLIBRARYAUTH                     from PUBLIC         ;
        db2 revoke select on table SYSIBM.SYSPASSTHRUAUTH                    from PUBLIC         ;
        db2 revoke select on table SYSIBM.SYSPLANAUTH                        from PUBLIC         ;
        db2 revoke select on table SYSIBM.SYSROLEAUTH                        from PUBLIC         ;
        db2 revoke select on table SYSIBM.SYSROUTINEAUTH                     from PUBLIC         ;
        db2 revoke select on table SYSIBM.SYSSCHEMAAUTH                      from PUBLIC         ;
        db2 revoke select on table SYSIBM.SYSSECURITYLABELACCESS             from PUBLIC         ;
        db2 revoke select on table SYSIBM.SYSSECURITYPOLICYEXEMPTIONS        from PUBLIC         ;
        db2 revoke select on table SYSIBM.SYSSEQUENCEAUTH                    from PUBLIC         ;
        db2 revoke select on table SYSIBM.SYSSURROGATEAUTHIDS                from PUBLIC         ;
        db2 revoke select on table SYSIBM.SYSTABAUTH                         from PUBLIC         ;
        db2 revoke select on table SYSIBM.SYSTBSPACEAUTH                     from PUBLIC         ;
        db2 revoke select on table SYSIBM.SYSUSERAUTH                        from PUBLIC         ;
        db2 revoke select on table SYSIBM.SYSVARIABLEAUTH                    from PUBLIC         ;
        db2 revoke select on table SYSIBM.SYSWORKLOADAUTH                    from PUBLIC         ;
        db2 revoke select on table SYSIBM.SYSXSROBJECTAUTH                   from PUBLIC         ;
        db2 revoke select on table SYSIBM.SQLCOLPRIVILEGES                   from PUBLIC         ;
        db2 revoke select on table SYSIBM.SQLTABLEPRIVILEGES                 from PUBLIC         ;
        db2 revoke select on table SYSIBM.SYSMODULEAUTH                      from PUBLIC         ;
        db2 revoke select on table SYSIBM.SYSSECURITYLABELCOMPONENTELEMENTS  from PUBLIC         ;
        db2 revoke select on table SYSIBM.SYSSECURITYLABELCOMPONENTS         from PUBLIC         ;
        db2 revoke select on table SYSIBM.SYSSECURITYLABELS                  from PUBLIC         ;
        db2 revoke select on table SYSIBM.SYSSECURITYPOLICIES                from PUBLIC         ;
        db2 revoke select on table SYSIBM.SYSSECURITYPOLICYCOMPONENTRULES    from PUBLIC         ; 
        db2 terminate;
done
}


db2instupcheck()
{
        #run the scripts as an seperate instance ID, it's used to get CR evidence after upgrade
echo "db2 code path:" `db2ls | grep "/" | cut -d " " -f 1`
echo "----------------instance $USER info-------------"
echo "db2level:"
db2level
echo 
echo "db2licm -l:" 
db2licm -l
echo 
echo "db2shc:" 
~/Security/db2shc -nm; grep -i violation ~/Security/*.out ~/Security/*.info
grep -E  "^ACCOUNT_CODE=|^PROJECT_ID=|^SERVER_TYPE=|^DB_TYPE=|^APP_TYPE=|^SHC_TYPE=|^EMAIL_DBA=|^EMAIL_VERIFIER=|^EMAIL_HCTEAM=" ~/Security/db2shc.cfg
}

db2bind()
{
        #instance bind package to all DBs
        for dbName in `db2lsdb`
        do
              db2 connect to $dbName
              db2 "bind $HOME/sqllib/bnd/db2schema.bnd blocking all grant public SQLERROR continue"
              db2 bind $HOME/sqllib/bnd/@db2ubind.lst blocking all grant public action add
              db2 bind $HOME/sqllib/bnd/@db2cli.lst blocking all grant public action add
              db2 bind $HOME/sqllib/bnd/@capture.lst isolation ur blocking all
              db2 bind $HOME/sqllib/bnd/@applycs.lst isolation cs blocking all grant public
              db2 bind $HOME/sqllib/bnd/@applyur.lst isolation ur blocking all grant public
              db2 bind $HOME/sqllib/bnd/@qcapture.lst isolation ur blocking all
              db2 bind $HOME/sqllib/bnd/@qapply.lst isolation ur blocking all grant public
              db2 terminate
        done
        #cd -            
}

alias | grep db2
typeset +f
