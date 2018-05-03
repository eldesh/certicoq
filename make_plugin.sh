#!/usr/bin/env bash

if [ ! -f "plugin/extraction/astCommon.ml" ]
then
    sh clean_extraction.sh
else
    a=`stat --format="%Z" theories/Extraction/AstCommon.ml`
    b=`stat --format="%Z" plugin/extraction/astCommon.ml`
    if [ "$a" -gt "$b" ]
	then
	sh clean_extraction.sh
    fi
fi

cd plugin
exec make -f Makefile ${@}
