set(TEST_RESULT 0)
set(TEST_NUMBER 0)
set(FAIL_COUNT  0)

while(TEST_RESULT EQUAL "0")
    execute_process(
        COMMAND ${TEST_PROG} ${TEST_NUMBER}
        RESULT_VARIABLE TEST_RESULT
    )

    if(TEST_RESULT EQUAL "255" OR TEST_RESULT EQUAL "-1")
        break()
    endif()

    if(NOT TEST_RESULT EQUAL "0")
        math(EXPR FAIL_COUNT "${FAIL_COUNT}+1")
        message(STATUS "ERROR: Test ${TEST_NUMBER} failed.")
    endif()

    math(EXPR TEST_NUMBER "${TEST_NUMBER}+1")
endwhile()

if(FAIL_COUNT)
    message(FATAL_ERROR "Test failed.")
endif()
