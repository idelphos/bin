#!/bin/ksh
BSIZE=1024

printsize()
{
    echo "size is $[$1/$BSIZE] " 
}


while getopts "b:k:m:g:t:"
do
    case ${opt} in
        b) echo "size is $[$1/$BSIZE] KB"
           echo "size is $[$1/($BZIS
