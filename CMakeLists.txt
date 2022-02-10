# This make file supports build of Jemalloc
#
# 1. Create a build directory
#        sample command: mkdir build
#
# 2. Run cmake to generate project files
#        sample command: cd build && cmake ..
#
# 3. Then build the project
#        sample command: make
#

cmake_minimum_required (VERSION 3.4 FATAL_ERROR)

# Set policy based on the CMake version
cmake_policy(VERSION 3.4.3)

if(POLICY CMP0042)
  cmake_policy(SET CMP0042 NEW)
endif()

# The following config switches that mimic the original autoconf behavior are supported
# use -D to define cmd arguments, options may have values of ON/OFF

#  with-mangling=k:v,k:v... comma separated list of key:value pairs overrides specific function mangling
#  with-jemalloc-prefix=<prefix> override default je_ prefix
option(without-export "Ddisable export of public APIs" OFF)
#  with-private-namespace=<additional_prefix>
#  with-install-suffix=<suffix> added to public headers and the library
#  with-malloc-conf=lg_chunk:18 Embed <malloc_conf> as a run-time options string that is processed prior to
#       the malloc_conf global variable
option(enable-cxx "Enable C++ integration" OFF)
option(enable-debug "Enable debugging code" OFF)
option(enable-lazy-lock "Enable lazy locking (only lock when multi-threaded" OFF)
option(enable-utrace "Enable utrace(2)-based tracing" OFF)
option(enable-xmalloc "Support xmalloc option" OFF)
option(disable-stats "Disable stats calculation (on by default)" OFF)
option(disable-tcache "Disable thread-specific caching (on by default)" OFF)
option(disable-fill  "Disabling filling memory with junk on by default" OFF)
option(disable-cache-oblivious "Disable uniform distribution of large allocations" OFF)
#  with-lg-vaddr=<lg2 value or "detect"> number of significant virtual address bits
#  with-lg-quantum=<lg2 of the min allocation alignment>
#  with-lg-page=<lg2 of the page size> override system page size
#  with-lg-hugepage=<lg2 of the huge page size> override system huge page size
option(force_lazy_lock "Forcing lazy-lock to avoid allocator/threading bootstrap issues" OFF)
# install_prefix - installation directory prefix
# with-xslroot=<path>  XSL stylesheet root path

set (PACKAGE_NAME "jemalloc")
project (${PACKAGE_NAME} C)

include (CheckTypeSize)
include (CheckIncludeFiles)
include (TestBigEndian)
include (CheckCCompilerFlag)
include (CheckCXXCompilerFlag)
include (CheckCSourceCompiles)
include (CheckFunctionExists)

include(${CMAKE_CURRENT_SOURCE_DIR}/Utilities.cmake)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/build-aux")

# Set library revision
set(rev 2)

# Installation
# Munge install path variables.
# All of these can simply we be passed as
# Cmake arguments
if (NOT install_prefix)
  set(install_prefix "/usr/local")
endif()

if(NOT exec_prefix)
  set(exec_prefix $install_prefix)
endif()

set(PREFIX ${install_prefix})

# Support for building documentation.
# find_package(xsltproc)
# if(XSLTPROC_FOUND)
  # set(XSLTPROC ${XSLTPROC_EXECUTABLE})
# endif()

if(EXISTS "/usr/share/xml/docbook/stylesheet/docbook-xsl")
  set(DEFAULT_XSLROOT "/usr/share/xml/docbook/stylesheet/docbook-xsl")
elseif(EXISTS "/usr/share/sgml/docbook/xsl-stylesheets")
  set(DEFAULT_XSLROOT "/usr/share/sgml/docbook/xsl-stylesheets")
else()
  # Documentation building will fail if this default gets used.
  set(DEFAULT_XSLROOT "")
endif()

if(with_xslroot)
  set(XSLROOT "${with_xslroot}")
else()
  set(XSLROOT "${DEFAULT_XSLROOT}")
endif()

# Cmake will always have some CFLAGS set based on the compiler detection
# Until we discover it is not what we want
set(je_cv_cray_prgenv_wrapper False)

if(ENV${PE_ENV})
  # TODO: Check if MATCHES is OK with this syntax
  if(ENV${PE_ENV} MATCHES "CC|cc")
    set(je_cv_cray_prgenv_wrapper True)
  endif()
endif()

message(STATUS "CMAKE_C_COMPILER_ID: ${CMAKE_C_COMPILER_ID}")

# Whether cray compiler version is 8.4
set(je_cv_cray_84 False)
if(CMAKE_C_COMPILER_ID STREQUAL "Cray")
  set(je_cv_cray True)
  # If the version is defined then use it
  if(CMAKE_C_COMPILER_VERSION)
    set(VersionFound True)
    set(VERSION_84 "8.4.0.0")
    set(VERSION_85 "8.5.0.0")
    if(VERSION_84 VERSION_EQUAL ${CMAKE_C_COMPILER_VERSION})
      set(je_cv_cray_84 True)
    elseif(VERSION_84 VERSION_LESS ${CMAKE_C_COMPILER_VERSION} AND
           VERSION_85 VERSION_GREATER ${CMAKE_C_COMPILER_VERSION})
      set(je_cv_cray_84 True)
    endif()
  endif()
  # TODO: If the version is not defined then need to
  # if(NOT VersionFound) COmpile and build the program
endif()

if(NOT GFLAGS)
  if(CMAKE_COMPILER_IS_GNUCC)
    if(CFLAGS)
      set(GFLAGS "${CFLAGS}")
    endif(CFLAGS)
    JeCflagsAppend("-std=gnu11" "GFLAGS" "gnu11")
    if(gnu11)
      set (JEMALLOC_HAS_RESTRICT 1)
    else()
      JeCflagsAppend("-std=gnu99" "GFLAGS" "gnu99")
      if(gnu99)
        set (JEMALLOC_HAS_RESTRICT 1)
      endif()
    endif()

    JeCflagsAppend("-Wall" "GFLAGS" "Wall")
    JeCflagsAppend("-Wextra" "GFLAGS" "Wextra")
    JeCflagsAppend("-Wshorten-64-to-32" "GFLAGS" "Wshorten-64-to-32")
    JeCflagsAppend("-Wsign-compare" "GFLAGS" "Wsign-compare")
    JeCflagsAppend("-Wundef" "GFLAGS" "Wundef")
    JeCflagsAppend("-Wno-format-zero-length" "GFLAGS" "Wno-format-zero-length")
    JeCflagsAppend("-pipe" "GFLAGS" "pipe")
    JeCflagsAppend("-g3" "GFLAGS" "g3")
  endif()

  if(MSVC)
    JeCflagsAppend("-Zi" "GFLAGS" "Zi")
    JeCflagsAppend("-MT" "GFLAGS" "MT")
    JeCflagsAppend("-W3" "GFLAGS" "W3")
    JeCflagsAppend("-FS" "GFLAGS" "FS")
    include_directories(${CMAKE_CURRENT_SOURCE_DIR}/include/msvc_compat)
    # Restrict is #defined to _restrict
    set (JEMALLOC_HAS_RESTRICT 1)
    # The rest of MSVC flags are down below
  endif()

  if(je_cv_cray)
    # cray compiler 8.4 has an inlining bug
    if(je_cv_cray_84)
      set (GFLAGS "${GFLAGS} -hipa2 -hnognu")
    endif(je_cv_cray_84)

    if(enable_cc_silence)
      # ignore unreachable code warning
      set (GFLAGS "${GFLAGS} -hnomessage=128")
      # ignore redefinition of "malloc", "free", etc warning
      set (GFLAGS "${GFLAGS} -hnomessage=1357")
    endif(enable_cc_silence)
  endif(je_cv_cray)
endif(NOT GFLAGS)

if(enable-cxx)
  # Require at least c++14, which is the first version to support sized
  # deallocation.  C++ support is not compiled otherwise.
  set(enable_cxx 1)
  JeCxxflagsAppend("-std=c++14" "GXXFLAGS" "cxx14")
  if(cxx14)
    JeCxxflagsAppend("-Wall" "GXXFLAGS" "CXX-Wall")
    JeCxxflagsAppend("-Wextra" "GXXFLAGS" "CXX-Wextra")
    JeCxxflagsAppend("-g3" "GXXFLAGS" "CXX-g3")
    set(CMAKE_REQUIRED_FLAGS "${GFLAGS}")
    set(CMAKE_REQUIRED_LIBRARIES "${LIBS} stdc++")
    JeCompitable("libstdc++ linkage"
      "#include <stdlib.h>"
      "int *arr = (int *)malloc(sizeof(int) * 42);
       if (arr == NULL)
         return 1;"
      je_cv_libstdcxx)
    if(NOT je_cv_libstdcxx)
      set(CMAKE_REQUIRED_LIBRARIES "${LIBS}")
      set(enable_cxx 0)
    endif(NOT je_cv_libstdcxx)
  endif(cxx14)
endif()

set(CMAKE_REQUIRED_FLAGS "${GFLAGS}")

##################################################################
# Jemalloc version
execute_process (
  COMMAND cat "VERSION"
  WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
  OUTPUT_VARIABLE jemalloc_version
  ERROR_QUIET
  OUTPUT_STRIP_TRAILING_WHITESPACE
)
execute_process (
  COMMAND bash -c "echo -n ${jemalloc_version} | tr '.g-' ' ' | awk '{print \$1}'"
  OUTPUT_VARIABLE jemalloc_version_major
  ERROR_QUIET
  OUTPUT_STRIP_TRAILING_WHITESPACE
)
execute_process (
  COMMAND bash -c "echo -n ${jemalloc_version} | tr '.g-' ' ' | awk '{print \$2}'"
  OUTPUT_VARIABLE jemalloc_version_minor
  ERROR_QUIET
  OUTPUT_STRIP_TRAILING_WHITESPACE
)
execute_process (
  COMMAND bash -c "echo -n ${jemalloc_version} | tr '.g-' ' ' | awk '{print \$3}'"
  OUTPUT_VARIABLE jemalloc_version_bugfix
  ERROR_QUIET
  OUTPUT_STRIP_TRAILING_WHITESPACE
)
execute_process (
  COMMAND bash -c "echo -n ${jemalloc_version} | tr '.g-' ' ' | awk '{print \$4}'"
  OUTPUT_VARIABLE jemalloc_version_nrev
  ERROR_QUIET
  OUTPUT_STRIP_TRAILING_WHITESPACE
)
execute_process (
  COMMAND bash -c "echo -n ${jemalloc_version} | tr '.g-' ' ' | awk '{print \$5}'"
  OUTPUT_VARIABLE jemalloc_version_gid
  ERROR_QUIET
  OUTPUT_STRIP_TRAILING_WHITESPACE
)

find_package(Git)
GetAndParseVersion()

# We do not support exec_prefix until we find it is necessary

CHECK_INCLUDE_FILES (alloca.h HAS_ALLOCA_H)
if(HAS_ALLOCA_H)
  set(JEMALLOC_HAS_ALLOCA_H 1)
endif(HAS_ALLOCA_H)

# Whether malloc_usable_size definition can use const argument
set(JEMALLOC_USABLE_SIZE_CONST " ")
JeFileCompilable("malloc_usable_size use const argument"
  "usable_size_const"
  "${GFLAGS}"
  ""
  "#include <malloc.h>
   #include <stddef.h>
   size_t malloc_usable_size(const void *ptr);"
  ""
  USABLE_SIZE_CONST)
if(USABLE_SIZE_CONST)
  set(JEMALLOC_USABLE_SIZE_CONST "const")
endif(USABLE_SIZE_CONST)

CHECK_INCLUDE_FILES (inttypes.h HAVE_INTTYPES_H)

if(MSVC AND (NOT HAVE_INTTYPES_H))
  set(GXXFLAGS "${GXXFLAGS} -I${CMAKE_CURRENT_SOURCE_DIR}/include/msvc_compat/C99")
endif()

CHECK_INCLUDE_FILES (sys/time.h HAVE_SYSTIME_H)

#############################################################
# Check atomics

# Check for C11 atomics.
CHECK_INCLUDE_FILES (stdatomic.h je_cv_c11_atomics)
if(je_cv_c11_atomics)
  set(JEMALLOC_C11_ATOMICS 1)
endif()

# Check for GCC-style __atomic atomics.
JeCompilable ("GCC __atomic atomics"
  ""
  "int x = 0;
   int val = 1;
   int y = __atomic_fetch_add(&x, val, __ATOMIC_RELAXED);
   int after_add = x;
   return after_add == 1;"
  je_cv_gcc_atomic_atomics)
if (je_cv_gcc_atomic_atomics)
  set(JEMALLOC_GCC_ATOMIC_ATOMICS 1)
  JeCompilable ("GCC 8-bit __atomic atomics"
    ""
    "unsigned char x = 0;
     int val = 1;
     int y = __atomic_fetch_add(&x, val, __ATOMIC_RELAXED);
     int after_add = (int)x;
     return after_add == 1;"
    je_cv_gcc_u8_atomic_atomics)
  if(je_cv_gcc_u8_atomic_atomics)
    set(JEMALLOC_GCC_U8_ATOMIC_ATOMICS 1)
  endif(je_cv_gcc_u8_atomic_atomics)
endif (je_cv_gcc_atomic_atomics)

# Check for GCC-style __sync atomics.
JeCompilable ("GCC __sync atomics"
  ""
  "int x = 0;
   int before_add = __sync_fetch_and_add(&x, 1);
   int after_add = x;
   return (before_add == 0) && (after_add == 1);"
  je_cv_gcc_sync_atomics)
if (je_cv_gcc_sync_atomics)
  set(JEMALLOC_GCC_SYNC_ATOMICS 1)
  JeCompilable ("GCC 8-bit __sync atomics"
    ""
    "unsigned char x = 0;
     int before_add = __sync_fetch_and_add(&x, 1);
     int after_add = (int)x;
     return (before_add == 0) && (after_add == 1);"
    je_cv_gcc_u8_sync_atomics)
  if(je_cv_gcc_u8_sync_atomics)
    set(JEMALLOC_GCC_U8_SYNC_ATOMICS 1)
  endif(je_cv_gcc_u8_sync_atomics)
endif (je_cv_gcc_sync_atomics)
#############################################################

TEST_BIG_ENDIAN(ac_cv_big_endian)
if(ac_cv_big_endian)
  set(JEMALLOC_BIG_ENDIAN 1)
endif(ac_cv_big_endian)

UtilCheckTypeSize(void* SIZEOF_VOID_P)
if(SIZEOF_VOID_P)
  lg(${SIZEOF_VOID_P} "LG_SIZEOF_PTR")
  # The latest code hardcodes this on Windows
  # set(LG_SIZEOF_PTR_WIN ${LG_SIZEOF_PTR})
  if((NOT ${LG_SIZEOF_PTR} EQUAL 3) AND
     (NOT ${LG_SIZEOF_PTR} EQUAL 2))
    message(FATAL_ERROR "Unsupported pointer size :${LG_SIZEOF_PTR}")
  endif()
endif()

UtilCheckTypeSize(int SIZEOF_INT)
if(SIZEOF_INT)
  lg(${SIZEOF_INT} "LG_SIZEOF_INT")
  if((NOT ${LG_SIZEOF_INT} EQUAL 3) AND
     (NOT ${LG_SIZEOF_INT} EQUAL 2))
    message(FATAL_ERROR "Unsupported int size :${LG_SIZEOF_INT}")
  endif()
endif()

UtilCheckTypeSize(long SIZEOF_LONG)
if(SIZEOF_LONG)
  lg(${SIZEOF_LONG} "LG_SIZEOF_LONG")
  if((NOT ${LG_SIZEOF_LONG} EQUAL 3) AND
     (NOT ${LG_SIZEOF_LONG} EQUAL 2))
    message(FATAL_ERROR "Unsupported long size :${LG_SIZEOF_LONG}")
  endif()
endif()

UtilCheckTypeSize("long long" SIZEOF_LONG_LONG)
if(SIZEOF_LONG_LONG)
  lg(${SIZEOF_LONG_LONG} "LG_SIZEOF_LONG_LONG")
  if((NOT ${LG_SIZEOF_LONG_LONG} EQUAL 3) AND
     (NOT ${LG_SIZEOF_LONG_LONG} EQUAL 2))
    message(FATAL_ERROR "Unsupported long size :${LG_SIZEOF_LONG_LONG}")
  endif()
endif()

UtilCheckTypeSize(intmax_t SIZEOF_INTMAX_T)
if(SIZEOF_INTMAX_T)
  lg(${SIZEOF_INTMAX_T} "LG_SIZEOF_INTMAX_T")
  if((NOT ${LG_SIZEOF_INTMAX_T} EQUAL 4) AND
     (NOT ${LG_SIZEOF_INTMAX_T} EQUAL 3) AND
     (NOT ${LG_SIZEOF_INTMAX_T} EQUAL 2))
    message(FATAL_ERROR "Unsupported long size :${LG_SIZEOF_INTMAX_T}")
  endif()
endif()

# CPU-specific settings.
if(MSVC)
  JeCompilable("pause instruction MSVC" "" "_mm_pause();" je_cv_pause_msvc)
  if(je_cv_pause_msvc)
    set(CPU_SPINWAIT "_mm_pause()")
  else()
    JeCompilable("YieldProcessor() MSVC" "#include <Windows.h>" "YieldProcessor();" je_cv_pause_msvc)
    if(je_cv_pause_msvc)
      set (CPU_SPINWAIT "YieldProcessor()")
    endif()
  endif()
elseif(CMAKE_HOST_SYSTEM_PROCESSOR MATCHES "i686|x86_64")
  JeCompilable("pause instruction" "" "__asm__ volatile(\"pause\");" je_cv_pause)
  if(je_cv_pause)
    set(CPU_SPINWAIT "__asm__ volatile(\"pause\")")
  endif()
endif()

if(CPU_SPINWAIT)
  set(HAVE_CPU_SPINWAIT 1)
  message(STATUS "CPU spinwait statement: ${CPU_SPINWAIT}")
else()
  set(HAVE_CPU_SPINWAIT 0)
  set(CPU_SPINWAIT " ")
  message(STATUS "have CPU spinwait ... no")
endif()

set(jv_cv_lg_vaddr "detect")
if(with-lg-vaddr AND (NOT with-lg-vaddr STREQUAL "detect"))
  set(jv_cv_lg_vaddr "${with-lg-vaddr}")
endif()
if(jv_cv_lg_vaddr STREQUAL "detect")
  if(CMAKE_HOST_SYSTEM_PROCESSOR MATCHES "aarch64")
    if(LG_SIZEOF_PTR EQUAL 2)
      set(jv_cv_lg_vaddr 32)
    else()
      set(jv_cv_lg_vaddr 48)
    endif()
  elseif(CMAKE_HOST_SYSTEM_PROCESSOR MATCHES "x86_64")
    GetLgVaddrX64(jv_cv_lg_vaddr)
  else()
    if(LG_SIZEOF_PTR EQUAL 3)
      set(jv_cv_lg_vaddr 64)
    elseif(LG_SIZEOF_PTR EQUAL 2)
      set(jv_cv_lg_vaddr 32)
    elseif(LG_SIZEOF_PTR EQUAL LG_SIZEOF_PTR_WIN)
      math(EXPR jv_cv_lg_vaddr "1 << (${LG_SIZEOF_PTR_WIN} + 3)")
    else()
      message(FATAL_ERROR "failed to detect LG_VADDR")
    endif()
  endif()
endif()
if(jv_cv_lg_vaddr STREQUAL "error")
  message(FATAL_ERROR "failed to detect LG_VADDR for x86_64")
endif()
set(LG_VADDR ${jv_cv_lg_vaddr})
message(STATUS "number of significant virtual address bits ... ${LG_VADDR}")


# Platform-specific settings.  abi can probably be determined
# programmatically, but doing so is error-prone, which makes
# it generally not worth the trouble.
set(default_retain 0)
set(maps_coalesce 1)
set(DUMP_SYMS "nm -a")
set(abi "elf")
set(a "a")
set(so "so")
set(SOREV "${so}.${rev}")

if(MSVC)
  set(abi "pecoff")
  set(maps_coalesce 0)
  set(so "dll")
  set(a "lib")
  set(SOREV "${so}")
  set(DSO_LDFLAGS "-LD -link -DEBUG")
else()
  ## Support linux only now
  JeCflagsAppend("-D_GNU_SOURCE" "GFLAGS" "GNU_SOURCE")
  set(JEMALLOC_PURGE_MADVISE_DONTNEED_ZEROS 1)
  set(JEMALLOC_PROC_SYS_VM_OVERCOMMIT_MEMORY 1)
  set(JEMALLOC_THREADED_INIT 1)
  set(JEMALLOC_USE_CXX_THROW 1)
  set(DSO_LDFLAGS "-shared -Wl,-soname,libjemalloc.${so}")
  set(PIC_CFLAGS "-fPIC -DPIC")
endif(MSVC)

if(LG_SIZEOF_PTR EQUAL 3)
  set(default_retain 1)
endif()

# Determine whether libm must be linked to use e.g. log(3).
JeFindLibrary("m" LIBM)
if(LIBM)
  set(LIBS "${LIBS} -lm")
endif(LIBM)

JeCompilable("__attribute__ syntax"
  "static __attribute__((unused)) void foo(void){}"
  ""
  je_cv_attribute)
if(je_cv_attribute)
  set(JEMALLOC_HAVE_ATTR 1)
  if(CMAKE_COMPILER_IS_GNUCC AND abi STREQUAL "elf")
    JeCflagsAppend("-fvisibility=hidden" "GFLAGS" "visibility-hidden")
    if(enable_cxx)
      JeCxxflagsAppend("-fvisibility=hidden" "GXXFLAGS" "CXX-visibility-hidden")
    endif(enable_cxx)
  endif()
endif(je_cv_attribute)


########################################################
## Jemalloc build options

# Check for tls_model attribute support (clang 3.0 still lacks support).
JeFileCompilable("tls_model attribute"
  "tls_model"
  "${GFLAGS} -Werror"
  ""
  ""
  "static __thread int
   __attribute__((tls_model(\"initial-exec\"), unused)) foo;
   foo = 0;"
  je_cv_tls_model)

if(je_cv_tls_model)
  set(JEMALLOC_TLS_MODEL "__attribute__((tls_model(\"initial-exec\")))")
  message(STATUS "tls_mode statement: ${JEMALLOC_TLS_MODEL}")
else()
  set(JEMALLOC_TLS_MODEL " ")
endif(je_cv_tls_model)

# Check for alloc_size attribute support.
JeFileCompilable("alloc_size attribute"
  "alloc_size"
  "${GFLAGS} -Werror"
  ""
  "#include <stdlib.h>"
  "void *foo(size_t size) __attribute__((alloc_size(1)));"
  je_cv_alloc_size)

if(je_cv_alloc_size)
  set(JEMALLOC_HAVE_ATTR_ALLOC_SIZE 1)
endif(je_cv_alloc_size)

# Check for format(gnu_printf, ...) attribute support.
JeFileCompilable("format(gnu_printf, ...) attribute"
  "gnu_printf"
  "${GFLAGS} -Werror"
  ""
  "#include <stdlib.h>"
  "void *foo(const char *format, ...) __attribute__((format(gnu_printf, 1, 2)));"
  je_cv_format_gnu_printf)

if(je_cv_format_gnu_printf)
  set(JEMALLOC_HAVE_ATTR_FORMAT_GNU_PRINTF 1)
endif(je_cv_format_gnu_printf)

# Check for format(printf, ...) attribute support.
JeFileCompilable("format(printf, ...) attribute"
  "printf"
  "${GFLAGS} -Werror"
  ""
  "#include <stdlib.h>"
  "void *foo(const char *format, ...) __attribute__((format(printf, 1, 2)));"
  je_cv_format_printf)

if(je_cv_format_printf)
  set(JEMALLOC_HAVE_ATTR_FORMAT_PRINTF 1)
endif(je_cv_format_printf)

# Check for format_arg(...) attribute support.
JeFileCompilable("format_arg(...) attribute"
  "format_arg"
  "${GFLAGS} -Werror"
  ""
  "#include <stdlib.h>"
  "const char * __attribute__((__format_arg__(1))) foo(const char *format);"
  je_cv_format_arg)

if(je_cv_format_arg)
  set(JEMALLOC_HAVE_ATTR_FORMAT_ARG 1)
endif(je_cv_format_arg)

# Indicate whether adjacent virtual memory mappings automatically coalesce
# (and fragment on demand).
if(maps_coalesce)
  set(JEMALLOC_MAPS_COALESCE 1)
endif(maps_coalesce)

# Indicate whether to retain memory (rather than using munmap()) by default.
if(default_retain)
  set(JEMALLOC_RETAIN 1)
endif(default_retain)

if(with-mangling)
# We are expecting entries separated by a comma
# with individual entries split by a ':' as in n:m
# Convert that into a CMake list of ';' separated pairs
  string(REPLACE "," ";" MANGLING_MAP  ${with-mangling})
endif()

# Do not prefix public APIs by default.
if(with-jemalloc-prefix)
  set(JEMALLOC_PREFIX ${with-jemalloc-prefix})
elseif(abi STREQUAL "pecoff")
  set(JEMALLOC_PREFIX je_)
endif()

# Uppercase copy of the JEMALLOC_PREFIX
# Need  quotes so the preprocessor concats two strings
if(JEMALLOC_PREFIX)
  string(TOUPPER \"${JEMALLOC_PREFIX}\" JEMALLOC_CPREFIX)
else()
  set(JEMALLOC_IS_MALLOC 1)
endif()

# Protos are always je_ but are renamed by #defines according to prefix
set(je_ "je_")

# Disable exporting jemalloc public APIs
# We need to define the var to whitespace string
# as empty strings will not be defined in CMake
# Non-empty definition is necessary so
if(without-export)
    set(JEMALLOC_EXPORT " ")
endif()

# Prefix to prepend to all library-private APIs
# default is on
set(JEMALLOC_PRIVATE_NAMESPACE je_)
if(with-private-namespace)
    set(JEMALLOC_PRIVATE_NAMESPACE "${with-private-namespace}je_")
endif()

set(private_namespace ${JEMALLOC_PRIVATE_NAMESPACE})

# Default empty
# Specify default malloc_conf
set(JEMALLOC_CONFIG_MALLOC_CONF "\"\"")
if(with-malloc-conf)
  set(JEMALLOC_CONFIG_MALLOC_CONF "\"${with-malloc-conf}\"")
endif()

if(with-install-suffix)
  set(INSTALL_SUFFIX ${with-install-suffix})
  set(install_suffix ${with-install-suffix})
endif()

# Build debugging code
if(enable-debug)
  set(JEMALLOC_DEBUG 1)
endif()

# Only optimize if not debugging.
if(NOT JEMALLOC_DEBUG)
  if(CMAKE_COMPILER_IS_GNUCC)
    JeCflagsAppend("-O3" "GFLAGS" "O3")
    JeCflagsAppend("-funroll-loops" "GFLAGS" "funroll-loops")
    if(enable_cxx)
      JeCxxflagsAppend("-O3" "GXXFLAGS" "CXX-O3")
    endif(enable_cxx)
  elseif(MSVC)
    JeCflagsAppend("-O2" "GFLAGS" "O2")
    if(enable_cxx)
      JeCxxflagsAppend("-O2" "GXXFLAGS" "CXX-O2")
    endif(enable_cxx)
  else()
    JeCflagsAppend("-O" "GFLAGS" "O")
    if(enable_cxx)
      JeCxxflagsAppend("-O" "GXXFLAGS" "CXX-O")
    endif(enable_cxx)
  endif()
endif(NOT JEMALLOC_DEBUG)

# Enable stats by default
# Disable statistics calculation/reporting
if(NOT disable-stats)
  set(JEMALLOC_STATS 1)
endif()

# Enable thread-specific caching by default.
set(JEMALLOC_TCACHE 1)
if(disable-tcache)
  set(JEMALLOC_TCACHE 0)
endif()

set(JEMALLOC_PREFIX_JET jet_)

# Disabling dss allocation because sbrk is deprecated
check_function_exists("sbrk" have_sbrk)
if(have_sbrk)
  set(JEMALLOC_DSS 1)
endif(have_sbrk)

# Support the junk/zero filling option by default.
# Disable support for junk/zero filling, quarantine, and redzones
if(NOT disable-fill)
  set (JEMALLOC_FILL 1)
endif()

# Disable utrace(2)-based tracing by default.
if(enable-utrace)
  JeCompilable("utrace(2)"
  "#include <sys/types.h>
   #include <sys/param.h>
   #include <sys/time.h>
   #include <sys/uio.h>
   #include <sys/ktrace.h>"
  "utrace((void *)0, 0);"
  je_cv_utrace)
  if(je_cv_utrace)
    set(JEMALLOC_UTRACE 1)
  endif(je_cv_utrace)
endif(enable-utrace)

# Do not support the xmalloc option by default.
if(enable-xmalloc)
  set(JEMALLOC_XMALLOC 1)
endif()

# Support cache-oblivious allocation alignment by default.
# If defined, explicitly attempt to more uniformly distribute large allocation
# pointer alignments across all cache indices.
if(NOT disable-cache-oblivious)
  set(JEMALLOC_CACHE_OBLIVIOUS 1)
endif()

# Check for __builtin_unreachable
JeCompilable("a program using __builtin_unreachable"
  "void foo(void) { __builtin_unreachable(); }"
  "foo();"
  je_cv_gcc_builtin_unreachable)
if(je_cv_gcc_builtin_unreachable)
  set(JEMALLOC_INTERNAL_UNREACHABLE __builtin_unreachable)
else()
  set(JEMALLOC_INTERNAL_UNREACHABLE abort)
endif()

##############################################################################
# Check for  __builtin_ffsl(), then ffsl(3), and fail if neither are found.
# One of those two functions should (theoretically) exist on all platforms
# that jemalloc currently has a chance of functioning on without modification.
# We additionally assume ffs[ll]() or __builtin_ffs[ll]() are defined if
# ffsl() or __builtin_ffsl() are defined, respectively.
JeFileCompilable("a program using __builtin_ffsl"
  "builtin_ffsl"
  "${GFLAGS}"
  ""
  "#include <stdio.h>
   #include <strings.h>
   #include <string.h>"
  "int rv = __builtin_ffsl(0x08);
   printf(\"%d\\n\", rv);"
  je_cv_gcc_builtin_ffsl)
if(je_cv_gcc_builtin_ffsl)
  set(JEMALLOC_INTERNAL_FFSLL __builtin_ffsll)
  set(JEMALLOC_INTERNAL_FFSL __builtin_ffsl)
  set(JEMALLOC_INTERNAL_FFS __builtin_ffs)
else()
  JeFileCompilable("a program using ffsl"
    "ffsl"
    "${GFLAGS}"
    ""
    "#include <stdio.h>
     #include <strings.h>
     #include <string.h>"
    "int rv = ffsl(0x08);
     printf(\"%d\\n\", rv);"
    je_cv_function_ffsl)
  if(je_cv_function_ffsl)
    set(JEMALLOC_INTERNAL_FFSLL ffsll)
    set(JEMALLOC_INTERNAL_FFSL ffsl)
    set(JEMALLOC_INTERNAL_FFS ffs)
  else()
    message(FATAL_ERROR "Cannot build without ffsl(3) or __builtin_ffsl()")
  endif(je_cv_function_ffsl)
endif(je_cv_gcc_builtin_ffsl)

JeFileCompilable("a program using __builtin_popcountl"
  "builtin_popcountl"
  "${GFLAGS}"
  ""
  "#include <stdio.h>
   #include <strings.h>
   #include <string.h>"
  "int rv = __builtin_popcountl(0x08);
   printf(\"%d\\n\", rv);"
  je_cv_gcc_builtin_popcountl)
if(je_cv_gcc_builtin_popcountl)
  set(JEMALLOC_INTERNAL_POPCOUNT __builtin_popcount)
  set(JEMALLOC_INTERNAL_POPCOUNTL __builtin_popcountl)
endif(je_cv_gcc_builtin_popcountl)

########################################################################
# Detect system page size

# Base 2 log of minimum allocation alignment
set(LG_QUANTA 3 4)
if(with-lg-quantum)
  # Convert to a CMake list
  string(REPLACE "," ";" LG_QUANTA ${with-lg-quantum})
  set(LG_QUANTUM ${LG_QUANTA})
endif()

# Base 2 log of system page size
if(with-lg-page)
  set(LG_PAGE ${with-lg-page})
endif()
if(NOT LG_PAGE OR
   "${LG_PAGE}" STREQUAL "detect")
  GetSystemPageSize("SYSTEM_PAGE_SIZE")
  lg(${SYSTEM_PAGE_SIZE} "LG_PAGE")
endif()
message(STATUS "Base 2 log of system page size ${LG_PAGE}")

# Base 2 log of system huge page size
if(with-lg-hugepage)
  set(LG_HUGEPAGE ${with-lg-hugepage})
endif()
if(NOT LG_HUGEPAGE OR
   "${LG_HUGEPAGE}" STREQUAL "detect")
  GetSystemHugepageSize("SYSTEM_HUGEPAGE_SIZE")
  lg(${SYSTEM_HUGEPAGE_SIZE} "LG_HUGEPAGE")
endif()
if(LG_HUGEPAGE LESS LG_PAGE)
  message(FATAL_ERROR "Huge page size is less than page size")
endif()
message(STATUS "Base 2 log of system huge page size ${LG_HUGEPAGE}")


##########################################################
# Configure pthreads

if(NOT abi EQUAL "pecoff")
  CHECK_INCLUDE_FILES(pthread.h HAVE_PTHREAD_H)
  if(NOT HAVE_PTHREAD_H)
    message(FATAL_ERROR "pthread.h is missing")
  endif(NOT HAVE_PTHREAD_H)

  JeFindLibrary("pthread" HAVE_LIBPTHREAD)
  if(NOT HAVE_LIBPTHREAD)
    message(FATAL_ERROR "libpthread is missing")
  endif(NOT HAVE_LIBPTHREAD)

  set(LIBS "${LIBS} -lpthread")
  list (APPEND WRAP_SYM pthread_create)
  set(JEMALLOC_HAVE_PTHREAD 1)

  # Check if we have dlsym support.
  JeFileCompilable("dlsym(3)"
    "dlsym"
    "${GFLAGS}"
    "-ldl"
    "#include <dlfcn.h>"
    "dlsym((void *)0, (const char *)0);"
    je_cv_dlsym)
  if(je_cv_dlsym)
    set(JEMALLOC_HAVE_DLSYM 1)
    set(LIBS "${LIBS} -ldl")
  endif(je_cv_dlsym)

  JeFileCompilable("pthread_atfork(3)"
    "pthread_atfork"
    "${GFLAGS}"
    "-lpthread"
    "#include <pthread.h>"
    "pthread_atfork((void *)0, (void *)0, (void *)0);"
    je_cv_pthread_atfork)
  if(je_cv_pthread_atfork)
    set(JEMALLOC_HAVE_PTHREAD_ATFORK 1)
  endif(je_cv_pthread_atfork)

  JeFileCompilable("pthread_setname_np(3)"
    "pthread_setname_np"
    "${GFLAGS}"
    "-lpthread"
    "#include <pthread.h>"
    "pthread_setname_np(pthread_self(), \"setname_test\");"
    je_cv_pthread_setname_np)
  if(je_cv_pthread_setname_np)
    set(JEMALLOC_HAVE_PTHREAD_SETNAME_NP 1)
  endif(je_cv_pthread_setname_np)
endif()

JeCflagsAppend("-D_REENTRANT" "GFLAGS" "REENTRANT")

# Check whether clock_gettime(2) is in libc or librt.
set(CLOCK_GETTIME_LIB "")
check_function_exists(clock_gettime CLOCK_GETTIME_IN_LIBC)
if(NOT CLOCK_GETTIME_IN_LIBC)
  JeFileCompilable("clock_gettime(2) in librt"
    "clock_gettime"
    "${GFLAGS}"
    "-lrt"
    "#include <time.h>"
    "clock_gettime(0, (struct timespec *)0);"
    je_cv_clock_gettime)
  if(je_cv_clock_gettime)
    set(CLOCK_GETTIME_LIB "-lrt")
    set(LIBS "${LIBS} -lrt")
  endif(je_cv_clock_gettime)
endif(NOT CLOCK_GETTIME_IN_LIBC)

# Check for CLOCK_MONOTONIC_COARSE (Linux-specific).
JeFileCompilable("clock_gettime(CLOCK_MONOTONIC_COARSE, ...)"
  "CLOCK_MONOTONIC_COARSE"
  "${GFLAGS}"
  "${CLOCK_GETTIME_LIB}"
  "#include <time.h>"
  "struct timespec ts;
   clock_gettime(CLOCK_MONOTONIC_COARSE, &ts);"
  je_cv_clock_monotonic_coarse)
if(je_cv_clock_monotonic_coarse)
  set(JEMALLOC_HAVE_CLOCK_MONOTONIC_COARSE 1)
endif(je_cv_clock_monotonic_coarse)

# Check for CLOCK_MONOTONIC.
JeFileCompilable("clock_gettime(CLOCK_MONOTONIC, ...)"
  "CLOCK_MONOTONIC"
  "${GFLAGS}"
  "${CLOCK_GETTIME_LIB}"
  "#include <unistd.h>
   #include <time.h>"
  "struct timespec ts;
   clock_gettime(CLOCK_MONOTONIC, &ts);
#if !defined(_POSIX_MONOTONIC_CLOCK) || _POSIX_MONOTONIC_CLOCK < 0
#  error _POSIX_MONOTONIC_CLOCK missing/invalid
#endif"
  je_cv_clock_monotonic)
if(je_cv_clock_monotonic)
  set(JEMALLOC_HAVE_CLOCK_MONOTONIC 1)
endif(je_cv_clock_monotonic)

# Check for mach_absolute_time().
JeCompilable("mach_absolute_time"
  "#include <mach/mach_time.h>"
  "mach_absolute_time();"
  je_cv_mach_absolute_time)
if(je_cv_mach_absolute_time)
  set(JEMALLOC_HAVE_MACH_ABSOLUTE_TIME 1)
endif(je_cv_mach_absolute_time)

# Check if syscall(2) is usable.  Treat warnings as errors, so that e.g. OS X
# 10.12's deprecation warning prevents use.
JeFileCompilable("syscall(2)"
  "syscall"
  "${GFLAGS} -Werror"
  ""
  "#include <sys/syscall.h>
   #include <unistd.h>"
  "syscall(SYS_write, 2, \"hello\", 5);"
  HAVE_SYSCALL)
if(HAVE_SYSCALL)
  set(JEMALLOC_USE_SYSCALL 1)
endif()

# Check if the GNU-specific secure_getenv function exists.
check_function_exists(secure_getenv have_secure_getenv)
if(have_secure_getenv)
  set(JEMALLOC_HAVE_SECURE_GETENV 1)
endif(have_secure_getenv)
  
# Check if the GNU-specific sched_getcpu function exists.
check_function_exists(sched_getcpu have_sched_getcpu)
if(have_sched_getcpu)
  set(JEMALLOC_HAVE_SCHED_GETCPU 1)
endif(have_sched_getcpu)

# Check if the GNU-specific sched_setaffinity function exists.
check_function_exists(sched_setaffinity have_sched_setaffinity)
if(have_sched_setaffinity)
  set(JEMALLOC_HAVE_SCHED_SETAFFINITY 1)
endif(have_sched_setaffinity)

# Check if the Solaris/BSD issetugid function exists.
check_function_exists(issetugid have_issetugid)
if(have_issetugid)
  set(JEMALLOC_HAVE_ISSETUGID 1)
endif(have_issetugid)

# Check whether the BSD-specific _malloc_thread_cleanup() exists.  If so, use
# it rather than pthreads TSD cleanup functions to support cleanup during
# thread exit, in order to avoid pthreads library recursion during
# bootstrapping.
check_function_exists(_malloc_thread_cleanup have__malloc_thread_cleanup)
if(have__malloc_thread_cleanup)
  set(JEMALLOC_MALLOC_THREAD_CLEANUP 1)
  set(force_tls 1)
  list (APPEND WRAP_SYM _malloc_thread_cleanup)
endif(have__malloc_thread_cleanup)

# Check whether the BSD-specific _pthread_mutex_init_calloc_cb() exists. If
# so, mutex initialization causes allocation, and we need to implement this
# callback function in order to prevent recursive allocation.
check_function_exists(_pthread_mutex_init_calloc_cb have__pthread_mutex_init_calloc_cb)
if(have__pthread_mutex_init_calloc_cb)
  set(JEMALLOC_MUTEX_INIT_CB 1)
  list (APPEND WRAP_SYM _malloc_prefork _malloc_postfork)
endif(have__pthread_mutex_init_calloc_cb)

############################
# enable-lazy-lock
if(NOT enable-lazy-lock)
  if(force_lazy_lock)
    message(STATUS "Forcing lazy-lock to avoid allocator/threading bootstrap issues")
    set(enable-lazy-lock ON)
  endif()
endif()

if(enable-lazy-lock)
  if(${abi} STREQUAL "pecoff")
    message(STATUS "Forcing no lazy-lock because thread creation monitoring is unimplemented")
    set(enable-lazy-lock OFF)
  endif()
endif()

if(enable-lazy-lock)
  if(NOT JEMALLOC_HAVE_DLSYM)
    message(FATAL_ERROR "libdl is missing]")
  endif()
  set(JEMALLOC_LAZY_LOCK 1)
endif()

# Automatically configure TLS.
if(NOT force_tls EQUAL 0)
  set(enable_tls 1)
endif()
if(enable_tls)
  JeCompilable("for TLS"
    "__thread int x;"
    "x = 42;
     return 0;"
    je_cv_tls)
  if(je_cv_tls)
    set(JEMALLOC_TLS 1)
  else()
    set(enable_tls 0)
  endif(je_cv_tls)
endif(enable_tls)

# Enable background threads if possible.
if(JEMALLOC_HAVE_PTHREAD)
  set(JEMALLOC_BACKGROUND_THREAD 1)
endif(JEMALLOC_HAVE_PTHREAD)

# Check for glibc malloc hooks
JeFileCompilable("glibc malloc hook"
  "glibc_malloc_hook"
  "${GFLAGS}"
  ""
  "#include <stddef.h>
   extern void (* __free_hook)(void *ptr);
   extern void *(* __malloc_hook)(size_t size);
   extern void *(* __realloc_hook)(void *ptr, size_t size);"
  "void *ptr = 0L;
   if (__malloc_hook) ptr = __malloc_hook(1);
   if (__realloc_hook) ptr = __realloc_hook(ptr, 2);
   if (__free_hook && ptr) __free_hook(ptr);"
  je_cv_glibc_malloc_hook)
if(je_cv_glibc_malloc_hook AND NOT JEMALLOC_PREFIX)
  set(JEMALLOC_GLIBC_MALLOC_HOOK 1)
  list(APPEND WRAP_SYM __free_hook __malloc_hook __realloc_hook)
endif()

JeFileCompilable("glibc memalign hook"
  "glibc_memalign_hook"
  "${GFLAGS}"
  ""
  "#include <stddef.h>
   extern void *(* __memalign_hook)(size_t alignment, size_t size);"
  "void *ptr = 0L;
   if (__memalign_hook) ptr = __memalign_hook(16, 7);"
  je_cv_glibc_memalign_hook)
if(je_cv_glibc_memalign_hook AND NOT JEMALLOC_PREFIX)
  set(JEMALLOC_GLIBC_MEMALIGN_HOOK 1)
  list(APPEND WRAP_SYM __memalign_hook)
endif()

JeFileCompilable("pthreads adaptive mutexes"
  "pthreads_adaptive_mutexes"
  "${GFLAGS}"
  "-lpthread"
  "#include <pthread.h>"
  "pthread_mutexattr_t attr;
   pthread_mutexattr_init(&attr);
   pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_ADAPTIVE_NP);
   pthread_mutexattr_destroy(&attr);"
  je_cv_pthread_mutex_adaptive_np)
if(je_cv_pthread_mutex_adaptive_np)
  set(JEMALLOC_HAVE_PTHREAD_MUTEX_ADAPTIVE_NP 1)
endif(je_cv_pthread_mutex_adaptive_np)

JeFileCompilable("strerror_r returns char with gnu source"
  "strerror_r"
  "${GFLAGS} -D_GNU_SOURCE -Werror "
  ""
  "#include <errno.h>
   #include <stdio.h>
   #include <stdlib.h>
   #include <string.h>"
  "char *buffer = (char *) malloc(100);
   char *error = strerror_r(EINVAL, buffer, 100);
   printf(\"%s\\n\", error);"
  je_cv_strerror_r_returns_char_with_gnu_source)
if(je_cv_strerror_r_returns_char_with_gnu_source)
  set(JEMALLOC_STRERROR_R_RETURNS_CHAR_WITH_GNU_SOURCE 1)
endif(je_cv_strerror_r_returns_char_with_gnu_source)

###########################################################################
# Check for madvise(2).

JeCompilable("madvise(2)"
  "#include <sys/mman.h>"
  "madvise((void *)0, 0, 0);"
  je_cv_madvise)

if(je_cv_madvise)
  set(JEMALLOC_HAVE_MADVISE 1)

  # Check for madvise(..., MADV_FREE).
  JeFileCompilable("madvise(..., MADV_FREE)"
    "madv_free"
    "${GFLAGS}"
    ""
    "#include <sys/mman.h>"
    "madvise((void *)0, 0, MADV_FREE);"
    je_cv_madv_free)
  if(je_cv_madv_free)
    set(JEMALLOC_PURGE_MADVISE_FREE 1)
  elseif(CMAKE_SYSTEM_NAME MATCHES "Linux" AND
         CMAKE_HOST_SYSTEM_PROCESSOR MATCHES "i686|x86_64")
    set(JEMALLOC_PURGE_MADVISE_FREE 1)
    set(JEMALLOC_DEFINE_MADVISE_FREE 1)
  endif()

  # Check for madvise(..., MADV_DONTNEED).
  JeFileCompilable("madvise(..., MADV_DONTNEED)"
    "madv_dontneed"
    "${GFLAGS}"
    ""
    "#include <sys/mman.h>"
    "madvise((void *)0, 0, MADV_DONTNEED);"
    je_cv_madv_dontneed)
  if(je_cv_madv_dontneed)
    set(JEMALLOC_PURGE_MADVISE_DONTNEED 1)
  endif(je_cv_madv_dontneed)

  # Check for madvise(..., MADV_DO[NT]DUMP).
  JeFileCompilable("madvise(..., MADV_DO[[NT]]DUMP)"
    "madv_dontdump"
    "${GFLAGS}"
    ""
    "#include <sys/mman.h>"
    "madvise((void *)0, 0, MADV_DONTDUMP);
     madvise((void *)0, 0, MADV_DODUMP);"
    je_cv_madv_dontdump)
  if(je_cv_madv_dontdump)
    set(JEMALLOC_MADVISE_DONTDUMP 1)
  endif(je_cv_madv_dontdump)

  # Check for madvise(..., MADV_[NO]HUGEPAGE).
  JeFileCompilable("madvise(..., MADV_[[NO]]HUGEPAGE)"
    "madv_hugepage"
    "${GFLAGS}"
    ""
    "#include <sys/mman.h>"
    "madvise((void *)0, 0, MADV_HUGEPAGE);
     madvise((void *)0, 0, MADV_NOHUGEPAGE);"
    je_cv_thp)
  if(je_cv_thp)
    set(JEMALLOC_HAVE_MADVISE_HUGE 1)
  endif(je_cv_thp)
endif(je_cv_madvise)

# Check for __builtin_clz() and __builtin_clzl().
JeCompilable("__builtin_clz and __builtin_clzl"
  ""
  "{
     unsigned x = 0;
     int y = __builtin_clz(x);
   }
   {
     unsigned long x = 0;
     int y = __builtin_clzl(x);
   }"
  je_cv_builtin_clz)
if(je_cv_builtin_clz)
  set(JEMALLOC_HAVE_BUILTIN_CLZ 1)
endif(je_cv_builtin_clz)


###########################################################################
# Generate configured public headers for concatenation
# Public Headers in for configuring
set(PUBLIC_SYM
  aligned_alloc
  calloc dallocx
  free
  mallctl
  mallctlbymib
  mallctlnametomib
  malloc
  malloc_conf
  malloc_message
  malloc_stats_print
  malloc_usable_size
  mallocx
  smallocx_${jemalloc_version_gid}
  nallocx
  posix_memalign
  rallocx
  realloc
  sallocx
  sdallocx
  xallocx
)

check_function_exists (memalign OVERRIDE_MEMALIGN)
if (OVERRIDE_MEMALIGN)
  set(JEMALLOC_OVERRIDE_MEMALIGN 1)
  list (APPEND PUBLIC_SYM memalign)
endif ()
check_function_exists (valloc OVERRIDE_VALLOC)
if (OVERRIDE_VALLOC)
  set(JEMALLOC_OVERRIDE_VALLOC 1)
  list (APPEND PUBLIC_SYM valloc)
endif ()

set(PUBLIC_SYM_FILE "${CMAKE_CURRENT_SOURCE_DIR}/include/jemalloc/internal/public_symbols.txt")
GeneratePublicSymbolsList("${PUBLIC_SYM}" "${MANGLING_MAP}" "${JEMALLOC_PREFIX}" "${PUBLIC_SYM_FILE}")

if (NOT JEMALLOC_PREFIX)
  check_function_exists (__libc_calloc JEMALLOC_OVERRIDE___LIBC_CALLOC)
  if (JEMALLOC_OVERRIDE___LIBC_CALLOC)
    list (APPEND WRAP_SYM __libc_calloc)
  endif ()
  check_function_exists (__libc_free JEMALLOC_OVERRIDE___LIBC_FREE)
  if (JEMALLOC_OVERRIDE___LIBC_FREE)
    list (APPEND WRAP_SYM __libc_free)
  endif ()
  check_function_exists (__libc_malloc JEMALLOC_OVERRIDE___LIBC_MALLOC)
  if (JEMALLOC_OVERRIDE___LIBC_MALLOC)
    list (APPEND WRAP_SYM __libc_malloc)
  endif ()
  check_function_exists (__libc_memalign JEMALLOC_OVERRIDE___LIBC_MEMALIGN)
  if (JEMALLOC_OVERRIDE___LIBC_MEMALIGN)
    list (APPEND WRAP_SYM __libc_memalign)
  endif ()
  check_function_exists (__libc_realloc JEMALLOC_OVERRIDE___LIBC_REALLOC)
  if (JEMALLOC_OVERRIDE___LIBC_REALLOC)
    list (APPEND WRAP_SYM __libc_realloc)
  endif ()
  check_function_exists (__libc_valloc JEMALLOC_OVERRIDE___LIBC_VALLOC)
  if (JEMALLOC_OVERRIDE___LIBC_VALLOC)
    list (APPEND WRAP_SYM __libc_valloc)
  endif ()
  check_function_exists (__posix_memalign JEMALLOC_OVERRIDE___POSIX_MEMALIGN)
  if (JEMALLOC_OVERRIDE___POSIX_MEMALIGN)
    list (APPEND WRAP_SYM __posix_memalign)
  endif ()
endif (NOT JEMALLOC_PREFIX)

if(MSVC)
  list (APPEND WRAP_SYM tls_callback)
endif()

# Generate main public header
set(CFG_EXEC_FILE "${CMAKE_CURRENT_SOURCE_DIR}/include/jemalloc/internal/public_namespace.sh")
set(OUTPUT_HDR_FILE "${CMAKE_CURRENT_SOURCE_DIR}/include/jemalloc/internal/public_namespace.h")
GenerateFile("${CFG_EXEC_FILE}" "${PUBLIC_SYM_FILE}" "${OUTPUT_HDR_FILE}")
set(CFG_EXEC_FILE "${CMAKE_CURRENT_SOURCE_DIR}/include/jemalloc/internal/public_unnamespace.sh")
set(OUTPUT_HDR_FILE "${CMAKE_CURRENT_SOURCE_DIR}/include/jemalloc/internal/public_unnamespace.h")
GenerateFile("${CFG_EXEC_FILE}" "${PUBLIC_SYM_FILE}" "${OUTPUT_HDR_FILE}")

set(OUTPUT_HDR_FILE "${CMAKE_CURRENT_SOURCE_DIR}/include/jemalloc/jemalloc_protos_jet.h")
GenerateProtosJetHdrFile("${CMAKE_CURRENT_SOURCE_DIR}/include/jemalloc/jemalloc_protos.h.in" "${OUTPUT_HDR_FILE}")

set(CFG_EXEC_FILE "${CMAKE_CURRENT_SOURCE_DIR}/include/jemalloc/jemalloc_rename.sh")
set(OUTPUT_HDR_FILE "${CMAKE_CURRENT_SOURCE_DIR}/include/jemalloc/jemalloc_rename.h")
GenerateFile("${CFG_EXEC_FILE}" "${PUBLIC_SYM_FILE}" "${OUTPUT_HDR_FILE}")

set(CFG_EXEC_FILE "${CMAKE_CURRENT_SOURCE_DIR}/include/jemalloc/jemalloc_mangle.sh")
set(OUTPUT_HDR_FILE "${CMAKE_CURRENT_SOURCE_DIR}/include/jemalloc/jemalloc_mangle.h")
GenerateFile("${CFG_EXEC_FILE}" "${PUBLIC_SYM_FILE} je_" "${OUTPUT_HDR_FILE}")
set(OUTPUT_HDR_FILE "${CMAKE_CURRENT_SOURCE_DIR}/include/jemalloc/jemalloc_mangle_jet.h")
GenerateFile("${CFG_EXEC_FILE}" "${PUBLIC_SYM_FILE} jet_" "${OUTPUT_HDR_FILE}")

foreach (header_in jemalloc_defs.h jemalloc_macros.h jemalloc_protos.h jemalloc_typedefs.h
    internal/jemalloc_preamble.h internal/jemalloc_internal_defs.h)
  ConfigureFile("${CMAKE_CURRENT_SOURCE_DIR}/include/jemalloc/${header_in}.in"
    "${CMAKE_CURRENT_SOURCE_DIR}/include/jemalloc/${header_in}" True)
endforeach (header_in)

set(CFG_EXEC_FILE "${CMAKE_CURRENT_SOURCE_DIR}/include/jemalloc/jemalloc.sh")
set(JEMALLOC_HDR "${CMAKE_CURRENT_SOURCE_DIR}/include/jemalloc/jemalloc${install_suffix}.h")
GenerateFile("${CFG_EXEC_FILE}" "${CMAKE_CURRENT_SOURCE_DIR}/" "${JEMALLOC_HDR}")

# Generate private namespace header
set(CFG_EXEC_FILE "${CMAKE_CURRENT_SOURCE_DIR}/include/jemalloc/internal/private_symbols.sh")
set(OUTPUT_HDR_FILE "${CMAKE_CURRENT_SOURCE_DIR}/include/jemalloc/internal/private_symbols.awk")
GenerateAwkFile("${JEMALLOC_PREFIX}"
  "${JEMALLOC_PREFIX}"
  "${PUBLIC_SYM}"
  "${WRAP_SYM}"
  "${CFG_EXEC_FILE}"
  "${OUTPUT_HDR_FILE}")
set(OUTPUT_HDR_FILE "${CMAKE_CURRENT_SOURCE_DIR}/include/jemalloc/internal/private_symbols_jet.awk")
GenerateAwkFile("${JEMALLOC_PREFIX}"
  "jet_"
  "${PUBLIC_SYM}"
  "${WRAP_SYM}"
  "${CFG_EXEC_FILE}"
  "${OUTPUT_HDR_FILE}")
set(JEMALLOC_NO_PRIVATE_NAMESPACE 1)
set(GFLAGS "${GFLAGS} -DJEMALLOC_NO_PRIVATE_NAMESPACE=1")

set(C_SRCS
  src/arena.c
  src/background_thread.c
  src/base.c
  src/bin.c
  src/bitmap.c
  src/ckh.c
  src/ctl.c
  src/div.c
  src/extent.c
  src/extent_dss.c
  src/extent_mmap.c
  src/hash.c
  src/hook.c
  src/jemalloc.c
  src/jemalloc_cpp.cpp
  src/large.c
  src/log.c
  src/malloc_io.c
  src/mutex.c
  src/mutex_pool.c
  src/nstime.c
  src/pages.c
  src/prng.c
  src/prof.c
  src/rtree.c
  src/safety_check.c
  src/sc.c
  src/stats.c
  src/sz.c
  src/tcache.c
  src/test_hooks.c
  src/ticker.c
  src/tsd.c
  src/witness.c
)

if(CMAKE_SYSTEM_NAME MATCHES "Darwin")
  list(APPEND C_SRCS src/zone.c)
endif()

# The original library, delivery product
set(LIBJEMALLOCLIB jemalloc${install_suffix})
add_library(${LIBJEMALLOCLIB} STATIC ${C_SRCS})
set_target_properties(${LIBJEMALLOCLIB} PROPERTIES
  OUTPUT_NAME "jemalloc")
set_target_properties(${LIBJEMALLOCLIB} PROPERTIES
  COMPILE_FLAGS "${GFLAGS} ${PIC_CFLAGS}")

# Now add shared library.
set(LIBJEMALLOCSO jemallocso${install_suffix})
add_library(${LIBJEMALLOCSO} SHARED ${C_SRCS})
set_target_properties(${LIBJEMALLOCSO} PROPERTIES
  OUTPUT_NAME "jemalloc")
set_target_properties(${LIBJEMALLOCSO} PROPERTIES
  VERSION ${rev})
set_target_properties(${LIBJEMALLOCSO} PROPERTIES
  COMPILE_FLAGS "${GFLAGS} ${PIC_CFLAGS}")
set_target_properties(${LIBJEMALLOCSO} PROPERTIES
  LINK_FLAGS "${DSO_LDFLAGS}")

include_directories(${CMAKE_CURRENT_SOURCE_DIR}/include)
link_libraries(${LIBS})

if(with-jemalloc-prefix)
  target_compile_definitions(${LIBJEMALLOCLIB} PRIVATE
      JEMALLOC_MANGLE)
  target_compile_definitions(${LIBJEMALLOCSO} PRIVATE
      JEMALLOC_MANGLE)
endif()

#######################################################################
# Print out the results of configuration.
message(STATUS "===============================================================================")
message(STATUS "jemalloc version   : ${jemalloc_version}")
message(STATUS "library revision   : ${rev}")
message(STATUS "")
message(STATUS "CC                 : ${CMAKE_C_COMPILER}")
message(STATUS "CONFIGURE_CFLAGS   : ${GFLAGS}")
message(STATUS "SPECIFIED_CFLAGS   : ${CFLAGS}")
message(STATUS "PIC_CFLAGS         : ${PIC_CFLAGS}")
message(STATUS "CPPFLAGS           : ${CPPFLAGS}")
message(STATUS "CXX                : ${CMAKE_CXX_COMPILER}")
message(STATUS "CONFIGURE_CXXFLAGS : ${GXXFLAGS}")
message(STATUS "SPECIFIED_CXXFLAGS : ${CXXFLAGS}")
message(STATUS "DSO_LDFLAGS        : ${DSO_LDFLAGS}")
message(STATUS "STATIC_NAME        : libjemalloc.${a}")
message(STATUS "SO_NAME            : libjemalloc.${SOREV}")
message(STATUS "LIBS               : ${LIBS}")
message(STATUS "")
message(STATUS "PREFIX             : ${PREFIX}")
message(STATUS "srcroot            : ${CMAKE_CURRENT_SOURCE_DIR}")
message(STATUS "")
message(STATUS "JEMALLOC_PREFIX    : ${JEMALLOC_PREFIX}")
message(STATUS "JEMALLOC_PRIVATE_NAMESPACE:")
message(STATUS "                   : ${JEMALLOC_PRIVATE_NAMESPACE}")
message(STATUS "install_suffix     : ${install_suffix}")
message(STATUS "malloc_conf        : ${JEMALLOC_CONFIG_MALLOC_CONF}")
message(STATUS "debug              : ${JEMALLOC_DEBUG}")
message(STATUS "stats              : ${JEMALLOC_STATS}")
message(STATUS "fill               : ${JEMALLOC_FILL}")
message(STATUS "utrace             : ${JEMALLOC_UTRACE}")
message(STATUS "xmalloc            : ${JEMALLOC_XMALLOC}")
message(STATUS "lazy_lock          : ${JEMALLOC_LAZY_LOCK}")
message(STATUS "cache_oblivious    : ${JEMALLOC_CACHE_OBLIVIOUS}")
message(STATUS "cxx                : ${enable_cxx}")
message(STATUS "===============================================================================")
