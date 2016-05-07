PATH=$PATH:~/bin

export BACKUP=$HOME/backup	#keep backup before update
export OUTPUT=$HOME/output	#keep result of update
export PS1="$LOGNAME@`uname -n`:\$PWD/>"

if [ -s "$MAIL" ]; then         # This is at Shell startup.  In normal
	echo "$MAILMSG"        # operation, the Shell checks
fi                          # periodically.

convertxt()
{
	perl -pi -e 's/\r\n/\n/;' $1	
}


umask 002
set -o vi

#######################alias part######################
alias ll='ls -ltr'
alias grephcfg='egrep "^ACCOUNT_CODE=|^PROJECT_ID=|^SERVER_TYPE=|^DB_TYPE=|^APP_TYPE=|^SHC_TYPE=|^EMAIL_DBA=|^EMAIL_VERIFIER=|^EMAIL_HCTEAM=" '
alias db2ing='ps -ef | grep -E "db2sysc|asn" | grep -v grep | sort -k9 | tee /tmp/db2running.out ; chmod 755 /tmp/db2running.out'

chmod 777 *
if [ -e ~/bin/fun.ksh ]; then
	. ~/bin/fun.ksh 
fi

if [ `uname` = "AIX" ]; then
	echo  "\033[31m"
else
	PS1="\[\e[31m\]$PS1\[\e[0m\]"
fi

if [ -x /tempdb2/tmp/db2setup ]; then
  alias suroot='sudo /tempdb2/tmp/db2setup'
fi
