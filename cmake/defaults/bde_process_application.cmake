include(bde_standalone)

macro(process)
    bde_project_add_application(${ARGN})
endmacro()