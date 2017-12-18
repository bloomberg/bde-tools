macro(process)
    message(FATAL_ERROR "Default processing of standalone packages is not yet supported")
    #bde_project_add_group(infoTarget "${groupFileName}" ${ARGN})
endmacro()