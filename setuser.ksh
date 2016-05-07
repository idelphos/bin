#!/bin/ksh
# set personal  environment 

if [ `uname` = "Linux" ] ; then 
	rm -f .bash_profile .bash_login	
fi
cp -f  ~/bin/.profile ~/

CreateDir()
{
    if [ ! -e backup ];then
        mkdir backup && chmod 777 backup
    fi

    if [ ! -e output ];then
        mkdir output && chmod 777 output
    fi

    if [ ! -e bin ];then
        mkdir bin && chmod 777 bin
    fi
}

CreateDir

cp -f ~/bin/suroot /tmp ; chmod 777 /tmp/suroot

echo "-----the user $USER was setup----------"
echo
