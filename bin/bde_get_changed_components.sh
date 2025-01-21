#!/usr/bin/env bash

origPwd=$PWD
if [ $# -gt 0 ] ; then
    cd $1
fi
git diff --name-only $(git merge-base $(git branch --show-current) main) | xargs -r -L1 basename | sed 's/\.[^.]*$//' | paste -sd "," -
if [ $# -gt 0 ] ; then
    cd $origPwd
fi