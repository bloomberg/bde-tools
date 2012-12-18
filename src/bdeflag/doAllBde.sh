#!/usr/bin/env bash

cd
srcs=$(excl groups{Core,Bb}/???/*/*.{h,cpp} $(find adapters/* enterprise/* wrappers/* -name '*.h' -o -name '*.cpp' | grep -v -e unix- -e include) | sort)
time myBdeflag $srcs

echo "Last sources =" $(excl $srcs | tail -5)
