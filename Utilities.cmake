# Utilities.cmake
# Supporting functions to build Jemalloc

########################################################################
# CheckTypeSize
function(UtilCheckTypeSize type OUTPUT_VAR_NAME)

CHECK_TYPE_SIZE(${type} ${OUTPUT_VAR_NAME} LANGUAGE C)

if(${${OUTPUT_VAR_NAME}})
  message (STATUS "${type} size is ${${OUTPUT_VAR_NAME}}")
  set(${OUTPUT_VAR_NAME} ${${OUTPUT_VAR_NAME}} PARENT_SCOPE)
else()
  message(FATAL_ERROR "Can not determine ${type} size")
endif()

endfunction(UtilCheckTypeSize)

########################################################################
# Power of two
# returns result in a VAR whose name is in RESULT_NAME
function (pow2 e RESULT_NAME)
  set(pow2_result 1)
  while ( ${e} GREATER 0 )
    math(EXPR pow2_result "${pow2_result} + ${pow2_result}")
    math(EXPR e "${e} - 1")
  endwhile(${e} GREATER 0 )
  set(${RESULT_NAME} ${pow2_result} PARENT_SCOPE)
endfunction(pow2)

#########################################################################
# Logarithm base 2
# returns result in a VAR whose name is in RESULT_NAME
function (lg x RESULT_NAME)
  set(lg_result 0)
  while ( ${x} GREATER 1 )
    math(EXPR lg_result "${lg_result} + 1")
    math(EXPR x "${x} / 2")
  endwhile ( ${x} GREATER 1 )
  set(${RESULT_NAME} ${lg_result} PARENT_SCOPE)
endfunction(lg)


#############################################
# Read one file and append it to another
function (AppendFileContents input output)
file(READ ${input} buffer)
file(APPEND ${output} "${buffer}")
endfunction (AppendFileContents)


#############################################
# Generate public symbols list
function (GeneratePublicSymbolsList public_sym_list mangling_map symbol_prefix output_file)

file(REMOVE "${output_file}")

# First remove from public symbols those that appear in the mangling map
if(mangling_map)
  foreach(map_entry ${mangling_map})
    # Extract the symbol
    string(REGEX REPLACE "([^ \t]*):[^ \t]*" "\\1" sym ${map_entry})
    list(REMOVE_ITEM  public_sym_list ${sym})
    file(APPEND "${output_file}" "${map_entry}\n")
  endforeach(map_entry)
endif()  

foreach(pub_sym ${public_sym_list})
  file(APPEND "${output_file}" "${pub_sym}:${symbol_prefix}${pub_sym}\n")
endforeach(pub_sym)

endfunction(GeneratePublicSymbolsList)


############################################################################
# A function that configures a file_path and outputs
# end result into output_path
# ExpandDefine True/False if we want to process the file and expand
# lines that start with #undef DEFINE into what is defined in CMAKE
function (ConfigureFile file_path output_path ExpandDefine)

file(TO_NATIVE_PATH "${file_path}" ntv_file_path)

# This converts #undefs into #cmakedefines so configure_file can handle it
set(S_CMD "sed 's/^#undef[ \t]*\\([^ \t]*\\)/#cmakedefine \\1 @\\1@/g' ${ntv_file_path} > ${ntv_file_path}.cmake")

if(EXISTS ${file_path})
  if(NOT ${ExpandDefine})
    configure_file(${ntv_file_path} ${output_path} @ONLY NEWLINE_STYLE UNIX)
  else()
    file(REMOVE ${ntv_file_path}.cmake)
    # Convert autoconf .in into a cmake .in
    execute_process(COMMAND bash -c "${S_CMD}"
        RESULT_VARIABLE error_level
        ERROR_VARIABLE error_output)

    if(NOT ${error_level} EQUAL 0)
        message(FATAL_ERROR "Configure ${ntv_file_path} failed with ${error_level} : ${error_output}")
    endif()

    configure_file(${ntv_file_path}.cmake ${output_path} @ONLY NEWLINE_STYLE UNIX)
    file(REMOVE ${ntv_file_path}.cmake)
  endif()
else()
  message(FATAL_ERROR "${ntv_file_path} not found")
endif()

message(STATUS "Configure file ${output_path} ... ok")

endfunction(ConfigureFile)

############################################
# Run configure shell script

function (GenerateFile exec_path exec_args output_file)

file(REMOVE "${output_file}")

message(STATUS "${exec_path} ${exec_args} > ${output_file}")
execute_process (
  COMMAND bash -c "${exec_path} ${exec_args} > ${output_file}"
  RESULT_VARIABLE exec_result
)

if (NOT exec_result EQUAL 0)
  message(FATAL_ERROR "Failed to configure ${output_file}")
endif ()

endfunction (GenerateFile)

############################################################
# Generate awk file
# je_prefix   - global symbol prefix
# sym_prefix  - local symbol prefix
# pub_sym     - public symbol list
# wrap_sym    - wrapped symbol list
# exec_path   - path of generator shell script
# output_file - path of output file
function (GenerateAwkFile je_prefix sym_prefix pub_sym wrap_sym exec_path output_file)

file(REMOVE "${output_file}")

set(sym_arg "\"${je_prefix}\"")
foreach (sym IN LISTS pub_sym)
  set(sym_arg "${sym_arg} ${sym_prefix}${sym}")
endforeach (sym)
foreach (sym IN LISTS wrap_sym)
  set(sym_arg "${sym_arg} ${sym}")
endforeach (sym)

GenerateFile("${exec_path}" "${sym_arg}" "${output_file}")

endfunction (GenerateAwkFile)

###########################################################
# Generate protos_jet header file

function (GenerateProtosJetHdrFile in_file output_file)

file(REMOVE "${output_file}")

message(STATUS "cat ${in_file} | sed -e 's/@je_@/jet_/g' > ${output_file}")
execute_process (
  COMMAND bash -c "cat ${in_file} | sed -e 's/@je_@/jet_/g' > ${output_file}"
  RESULT_VARIABLE exec_result
)

if (NOT exec_result EQUAL 0)
  message(FATAL_ERROR "Failed to generate ${output_file}")
endif ()

endfunction (GenerateProtosJetHdrFile)


############################################################################################
## Run Git and parse the output to populate version settings above
function (GetAndParseVersion)

if (GIT_FOUND AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/.git")
    execute_process(COMMAND ${GIT_EXECUTABLE}
	-C "${CMAKE_CURRENT_SOURCE_DIR}" describe --long --abbrev=40 HEAD OUTPUT_VARIABLE jemalloc_version)
    
    # Figure out version components    
    string (REPLACE "\n" "" jemalloc_version  ${jemalloc_version})
    set(jemalloc_version ${jemalloc_version} PARENT_SCOPE)
    message(STATUS "Version is ${jemalloc_version}")

    # replace in this order to get a valid cmake list
    string (REPLACE "-g" "-" T_VERSION ${jemalloc_version})
    string (REPLACE "-" "." T_VERSION  ${T_VERSION})
    string (REPLACE "." ";" T_VERSION  ${T_VERSION})

    list(LENGTH T_VERSION L_LEN)

    if(${L_LEN} GREATER 0)
      list(GET T_VERSION 0 jemalloc_version_major)
      set(jemalloc_version_major ${jemalloc_version_major} PARENT_SCOPE)
      message(STATUS "jemalloc_version_major: ${jemalloc_version_major}")
    endif()

    if(${L_LEN} GREATER 1)
      list(GET T_VERSION 1 jemalloc_version_minor)
      set(jemalloc_version_minor ${jemalloc_version_minor} PARENT_SCOPE)
      message(STATUS "jemalloc_version_minor: ${jemalloc_version_minor}")
    endif()

    if(${L_LEN} GREATER 2)
      list(GET T_VERSION 2 jemalloc_version_bugfix)
      set(jemalloc_version_bugfix ${jemalloc_version_bugfix} PARENT_SCOPE)
      message(STATUS "jemalloc_version_bugfix: ${jemalloc_version_bugfix}")
    endif()

    if(${L_LEN} GREATER 3)
      list(GET T_VERSION 3 jemalloc_version_nrev)
      set(jemalloc_version_nrev ${jemalloc_version_nrev} PARENT_SCOPE)
      message(STATUS "jemalloc_version_nrev: ${jemalloc_version_nrev}")
    endif()

    if(${L_LEN} GREATER 4)
      list(GET T_VERSION 4 jemalloc_version_gid)
      set(jemalloc_version_gid ${jemalloc_version_gid} PARENT_SCOPE)
      message(STATUS "jemalloc_version_gid: ${jemalloc_version_gid}")
    endif()
endif()

endfunction (GetAndParseVersion)

#################################################################################
## Compile a progam and collect page size output from the OUTPUT_VAR_NAME
function (GetSystemPageSize OUTPUT_VAR_NAME)

# Direct all the files into one folder
set(WORK_FOLDER "${PROJECT_BINARY_DIR}/GetPageSize")
file(MAKE_DIRECTORY ${WORK_FOLDER})

set(SRC "${WORK_FOLDER}/getpagesize.c")
set(COMPILE_OUTPUT_FILE "${WORK_FOLDER}/getpagesize.log")

file(WRITE ${SRC}
"#ifdef _WIN32\n"
"#include <windows.h>\n"
"#else\n"
"#include <unistd.h>\n"
"#endif\n"
"#include <stdio.h>\n"
"int main(int argc, const char** argv) {\n"
"int result;\n"
"#ifdef _WIN32\n"
"SYSTEM_INFO si;\n"
"GetSystemInfo(&si);\n"
"result = si.dwPageSize;\n"
"#else\n"
"result = sysconf(_SC_PAGESIZE);\n"
"#endif\n"
"printf(\"%d\", result);\n"
"return 0;\n"
"}\n"
)

try_run(RUN_RESULT COMPILE_RESULT
        "${WORK_FOLDER}"
        "${SRC}"
        COMPILE_OUTPUT_VARIABLE COMPILE_OUTPUT
        RUN_OUTPUT_VARIABLE RUN_OUTPUT
        )

if(NOT COMPILE_RESULT)
    file(WRITE ${COMPILE_OUTPUT_FILE} ${COMPILE_OUTPUT})
    message(FATAL_ERROR "GetSystemPageSize failed compilation see ${COMPILE_OUTPUT_FILE}")
endif()

if("${RUN_RESULT}" STREQUAL "FAILED_TO_RUN")
    message(FATAL_ERROR "GetSystemPageSize failed to run executable")
endif()

message(STATUS "System pages size ${RUN_OUTPUT}")

set(${OUTPUT_VAR_NAME} ${RUN_OUTPUT} PARENT_SCOPE)

endfunction (GetSystemPageSize)

######################################################################
## Collect huge page size output from the OUTPUT_VAR_NAME
function (GetSystemHugepageSize OUTPUT_VAR_NAME)

  # Look in /proc/meminfo (Linux-specific) for information on the default huge
  # page size, if any.  The relevant line looks like:
  #
  #   Hugepagesize:       2048 kB
  if(EXISTS /proc/meminfo)
    execute_process(
      COMMAND bash -c "cat /proc/meminfo 2>/dev/null | \
                       grep -e '^Hugepagesize:[[:space:]]*[0-9]*[[:space:]]*kB$' | \
                       awk '{ print $2 }'"
      OUTPUT_VARIABLE je_cv_hugepage
      ERROR_QUIET
      OUTPUT_STRIP_TRAILING_WHITESPACE)
    if(je_cv_hugepage GREATER 0)
      math(EXPR je_cv_hugepage "${je_cv_hugepage} * 1024")
    endif()
  endif()

  # Set default if unable to automatically configure.
  if(NOT je_cv_hugepage)
    math(EXPR je_cv_hugepage "2^21")
  endif()

  set(${OUTPUT_VAR_NAME} ${je_cv_hugepage} PARENT_SCOPE)
  message(STATUS "System hugepage size ${je_cv_hugepage}")

endfunction(GetSystemHugepageSize)

######################################################################
## Compile a program and collect the number of significant virtual
# address bits output from the OUTPUT_VAR_NAME
function(GetLgVaddrX64 OUTPUT_VAR_NAME)

# Direct all the files into one folder
set(WORK_FOLDER "${PROJECT_BINARY_DIR}/GetLgVaddrX64")
file(MAKE_DIRECTORY ${WORK_FOLDER})

set(SRC "${WORK_FOLDER}/getlgvaddrx64.c")
set(COMPILE_OUTPUT_FILE "${WORK_FOLDER}/getlgvaddrx64.log")

file(WRITE ${SRC}
"#include <stdio.h>\n"
"#ifdef _WIN32\n"
"#include <limits.h>\n"
"#include <intrin.h>\n"
"typedef unsigned __int32 uint32_t;\n"
"#else\n"
"#include <stdint.h>\n"
"#endif\n"
"int main(int argc, const char** argv) {\n"
"  uint32_t r[4];\n"
"  uint32_t eax_in = 0x80000008U;\n"
"#ifdef _WIN32\n"
"  __cpuid((int *)r, (int)eax_in);\n"
"#else\n"
"  asm volatile (\"cpuid\"\n"
"    : \"=a\" (r[0]), \"=b\" (r[1]), \"=c\" (r[2]), \"=d\" (r[3])\n"
"    : \"a\" (eax_in), \"c\" (0)\n"
"  );\n"
"#endif\n"
"  uint32_t eax_out = r[0];\n"
"  uint32_t vaddr = ((eax_out & 0x0000ff00U) >> 8);\n"
"  if (vaddr > (sizeof(void *) << 3)) {\n"
"    vaddr = sizeof(void *) << 3;\n"
"  }\n"
"  printf(\"%u\", vaddr);\n"
"  return 0;\n"
"}\n"
)

try_run(RUN_RESULT COMPILE_RESULT
        "${WORK_FOLDER}"
        "${SRC}"
        COMPILE_OUTPUT_VARIABLE COMPILE_OUTPUT
        RUN_OUTPUT_VARIABLE RUN_OUTPUT
        )

if(NOT COMPILE_RESULT)
  file(WRITE ${COMPILE_OUTPUT_FILE} ${COMPILE_OUTPUT})
  set(${OUTPUT_VAR_NAME} 57 PARENT_SCOPE)
elseif("${RUN_RESULT}" STREQUAL "FAILED_TO_RUN")
  set(${OUTPUT_VAR_NAME} "error" PARENT_SCOPE)
else()
  set(${OUTPUT_VAR_NAME} ${RUN_OUTPUT} PARENT_SCOPE)
endif()

endfunction(GetLgVaddrX64)

######################################################
## This function attemps to compile a one liner
# with compiler flags to append. If the compiler flags
# are supported they are appended to the variable which names
# is supplied in the APPEND_TO_VAR and the RESULT_VAR is set to
# True, otherwise to False
function(JeCflagsAppend cflags APPEND_TO_VAR RESULT_VAR)

  # Combine the result to try
  set(TFLAGS "${${APPEND_TO_VAR}} ${cflags}")
  CHECK_C_COMPILER_FLAG(${TFLAGS} "${RESULT_VAR}")
 
  if(${RESULT_VAR})
    set(${APPEND_TO_VAR} "${TFLAGS}" PARENT_SCOPE)
  endif()

endfunction(JeCflagsAppend)

######################################################
# Similar to JeCflagsAppend
# This function try to append C++ compiler flags
function(JeCxxflagsAppend cxxflags APPEND_TO_VAR RESULT_VAR)

  set(TFLAGS "${${APPEND_TO_VAR}} ${cxxflags}")
  CHECK_CXX_COMPILER_FLAG(${TFLAGS} "${RESULT_VAR}")

  if(${RESULT_VAR})
    set(${APPEND_TO_VAR} "${TFLAGS}" PARENT_SCOPE)
  endif()

endfunction(JeCxxflagsAppend)

#############################################
# JeCompilable checks if the code supplied in the hcode
# is compilable 
# label - part of the message
# hcode - code prolog such as definitions
# mcode - body of the main() function
#
# It sets rvar to yes or no depending on the result
#
# TODO: Make sure that it does expose linking problems
function (JeCompilable label hcode mcode rvar)

set(SRC 
 "${hcode}
  
  int main(int argc, char* argv[]) {
    ${mcode}
    return 0;
  }")

  # We may want a stronger check here
  CHECK_C_SOURCE_COMPILES("${SRC}" "${rvar}")
  
  if(${rvar})
    message(STATUS "whether ${label} is compilable ... yes")
  else()
    message(STATUS "whether ${label} is compilable ... no")
  endif()
 
endfunction(JeCompilable)

########################################################
# JeFileCompilable writes the code into a file
# and checks if it is compilable
# label - part of the message
# proj  - project name
# flg   - compile flags
# libs  - link libraries
# hcode - code prolog such as definitions
# mcode - body of the main() function
#
# It sets rvar to yes or no depending on the result
function (JeFileCompilable label proj flg libs hcode mcode rvar)

# Direct all the files into one folder
set(WORK_FOLDER "${PROJECT_BINARY_DIR}/${proj}")
file(MAKE_DIRECTORY ${WORK_FOLDER})

set(SRC_FILE "${WORK_FOLDER}/${proj}.c")
set(COMPILE_OUTPUT_FILE "${WORK_FOLDER}/${proj}.log")

set(SRC
  "${hcode}
  
  int main(int argc, char* argv[]) {
    ${mcode}
    return 0;
  }")

file(WRITE ${SRC_FILE} "${SRC}")

try_compile("${rvar}"
            "${WORK_FOLDER}"
            "${SRC_FILE}"
            CMAKE_FLAGS "${flg}"
            LINK_LIBRARIES "${libs}"
            OUTPUT_VARIABLE COMPILE_OUTPUT
            )

if(${${rvar}})
  message(STATUS "whether ${label} is compilable ... yes")
else()
  file(WRITE ${COMPILE_OUTPUT_FILE} ${COMPILE_OUTPUT})
  message(STATUS "whether ${label} is compilable ... no")
endif()

endfunction(JeFileCompilable)

##############################################
# JeFindLibrary checks if library exists
function (JeFindLibrary libname rvar)

message(STATUS "Looking for library ${libname}")

find_library("${rvar}" "${libname}")

if(${rvar})
  message(STATUS "Looking for library ${libname} - ${${rvar}}")
else()
  message(STATUS "Looking for library ${libname} - not found")
endif()

endfunction(JeFindLibrary)
