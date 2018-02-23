#!/bin/bash

qflag='' # Run quietly

while getopts fq flag; do
  case "${flag}" in
    q) qflag='true' ;;
    *) error "Unexpected option ${flag}" ;;
  esac
done

for i in $( ls -ap ./settings | grep -v '/$' )
do
  cp $([ ! $qflag ] && echo '-v') ./settings/$i ~/
done

exit 0
