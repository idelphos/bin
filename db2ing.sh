#!/bin/ksh

#INFILE=/home/yadelph/output/serverlist.in
OUTPUT=~/db2running.$USER

ps_server()
{

until [ $# -eq 0 ]
do
  if [ $(expr substr "$1" 1 2 ) = "CR" ] ; then
    echo "$1---------------`date '+%F %R'`---------------"
  else
    echo "$1"
    ssh -l yadelph $(echo $1 | cut -d' ' -f1) 'ps -ef | grep -E "db2sysc|asn" | grep -v grep | sort -k9 -k1'
    echo 
  fi
  
  shift 
done

}


#main function

while getopts "f:" opt
do
  case ${opt} in
    f)  INFILE=${OPTARG} ;;
  esac
done
    

if [ -z "$INFILE" ] ; then 
  ps_server $* | tee -a $OUTPUT
else
  cat $INFILE |  while read line
  do
    ps_server $line | tee -a $OUTPUT
  done 
fi

echo " check the output in $OUTPUT"
