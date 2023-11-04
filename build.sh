#!/bin/sh

if [ $# -le 0 ]; then
  echo No parameter source file
  exit 1
fi

echo Compiling ...
nim c --outdir: ./bin --debugger:native --hints:off $1.nim
if [ $? -eq 0 ]; then
  echo "OK $1"
fi
