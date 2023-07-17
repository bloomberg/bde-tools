targets=$(get_dependers $@)
cd $BDE_CMAKE_BUILD_DIR
cmake --build . --target $(sed 's/,/ /g' <<< "$targets")
ctest -j8 --output-on-failure -L $(sed 's/,/|/g' <<< "$targets") 
