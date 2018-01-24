#!/bin/sh

svctype=${1:-hbase}
zippath=${scvtype}-conf.zip
echo $svctype
if [ -s "${zippath}" ] ; then
    unzip ${zippath} && \
        mkdir -p /etc/${svctype}/conf && \
        mv ${svctype}-conf/* /etc/${svctype}/conf/
fi

rm -rf ${svctype}-conf && \
    rm -f ${zippath}

exit 0
