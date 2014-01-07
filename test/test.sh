#!/bin/bash

for f in *_test.lua
do
  luajit $f
done
