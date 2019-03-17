cmake_minimum_required(VERSION 3.0)
cmake_policy(SET CMP0026 OLD) # allow use of the LOCATION target property

# store the current source directory for future use
set(QT_ANDROID_SOURCE_DIR ${CMAKE_CURRENT_LIST_DIR})

# check the JAVA_HOME environment variable
# (I couldn't find a way to set it from this script, it has to be defined outside)
set(JAVA_HOME $ENV{JAVA_HOME})
if(NOT JAVA_HOME)
    message(FATAL_ERROR "The JAVA_HOME environment variable is not set. Please set it to the root directory of the JDK.")
endif()

# make sure that the Android toolchain is used
if(NOT ANDROID)
    message(FATAL_ERROR "Trying to use the CMake Android package without the Android toolchain. Please use the provided toolchain (toolchain/android.toolchain.cmake)")
endif()

# find the Qt root directory
if(NOT Qt5Core_DIR)
    find_package(Qt5Core REQUIRED)
endif()
get_filename_component(QT_ANDROID_QT_ROOT "${Qt5Core_DIR}/../../.." ABSOLUTE)
message(STATUS "Found Qt for Android: ${QT_ANDROID_QT_ROOT}")

# find the Android SDK
if(NOT QT_ANDROID_SDK_ROOT)
    set(QT_ANDROID_SDK_ROOT $ENV{ANDROID_SDK})
    if(NOT QT_ANDROID_SDK_ROOT)
        message(FATAL_ERROR "Could not find the Android SDK. Please set either the ANDROID_SDK environment variable, or the QT_ANDROID_SDK_ROOT CMake variable to the root directory of the Android SDK")
    endif()
endif()
string(REPLACE "\\" "/" QT_ANDROID_SDK_ROOT ${QT_ANDROID_SDK_ROOT}) # androiddeployqt doesn't like backslashes in paths
message(STATUS "Found Android SDK: ${QT_ANDROID_SDK_ROOT}")

# find the Android NDK
if(NOT QT_ANDROID_NDK_ROOT)
    set(QT_ANDROID_NDK_ROOT $ENV{ANDROID_NDK})
    if(NOT QT_ANDROID_NDK_ROOT)
        set(QT_ANDROID_NDK_ROOT ${ANDROID_NDK})
        if(NOT QT_ANDROID_NDK_ROOT)
        message(FATAL_ERROR "Could not find the Android NDK. Please set either the ANDROID_NDK environment or CMake variable, or the QT_ANDROID_NDK_ROOT CMake variable to the root directory of the Android NDK")
        endif()
    endif()
endif()
string(REPLACE "\\" "/" QT_ANDROID_NDK_ROOT ${QT_ANDROID_NDK_ROOT}) # androiddeployqt doesn't like backslashes in paths
message(STATUS "Found Android NDK: ${QT_ANDROID_NDK_ROOT}")

include(CMakeParseArguments)

# define a macro to create an Android APK target
#
# example:
# add_qt_android_apk(my_app_apk my_app
#     NAME "My App"
#     VERSION_CODE 12
#     PACKAGE_NAME "org.mycompany.myapp"
#     PACKAGE_SOURCES ${CMAKE_CURRENT_LIST_DIR}/my-android-sources
#     KEYSTORE ${CMAKE_CURRENT_LIST_DIR}/mykey.keystore myalias
#     KEYSTORE_PASSWORD xxxx
#     DEPENDS a_linked_target "path/to/a_linked_library.so" ...
#     INSTALL
#)
# 
macro(add_qt_android_apk TARGET SOURCE_TARGET)

    # parse the macro arguments
    cmake_parse_arguments(ARG "INSTALL" "NAME;VERSION_NAME;VERSION_CODE;PACKAGE_NAME;PACKAGE_SOURCES;KEYSTORE_PASSWORD;EXTRA_QML" "DEPENDS;KEYSTORE;ANDROID_MANIFEST_IN_PATH;VERBOSE" ${ARGN})

    # extract the full path of the source target binary
    if(CMAKE_BUILD_TYPE STREQUAL "Debug")
        get_property(QT_ANDROID_APP_PATH TARGET ${SOURCE_TARGET} PROPERTY DEBUG_LOCATION)
    else()
        get_property(QT_ANDROID_APP_PATH TARGET ${SOURCE_TARGET} PROPERTY LOCATION)
    endif()

    # define the application name
    if(ARG_NAME)
        set(QT_ANDROID_APP_NAME ${ARG_NAME})
    else()
        set(QT_ANDROID_APP_NAME ${SOURCE_TARGET})
    endif()

    # define the application package name
    if(ARG_PACKAGE_NAME)
        set(QT_ANDROID_APP_PACKAGE_NAME ${ARG_PACKAGE_NAME})
    else()
        set(QT_ANDROID_APP_PACKAGE_NAME org.qtproject.${SOURCE_TARGET})
    endif()

    # detect latest Android SDK build-tools revision
    set(QT_ANDROID_SDK_BUILDTOOLS_REVISION "0.0.0")
    file(GLOB ALL_BUILD_TOOLS_VERSIONS RELATIVE ${QT_ANDROID_SDK_ROOT}/build-tools ${QT_ANDROID_SDK_ROOT}/build-tools/*)
    foreach(BUILD_TOOLS_VERSION ${ALL_BUILD_TOOLS_VERSIONS})
        # find subfolder with greatest version
        if (${BUILD_TOOLS_VERSION} VERSION_GREATER ${QT_ANDROID_SDK_BUILDTOOLS_REVISION})
            set(QT_ANDROID_SDK_BUILDTOOLS_REVISION ${BUILD_TOOLS_VERSION})
        endif()
    endforeach()
    message(STATUS "Detected Android SDK build tools version ${QT_ANDROID_SDK_BUILDTOOLS_REVISION}")

    IF(ARGS_EXTRA_QML)
        SET(QT_ANDROID_QML_IMPORT_PATH ${ARGS_EXTRA_QML})
    ENDIF()

    SET(QT_ANDROID_APP_BINARY_DIR ${CMAKE_CURRENT_BINARY_DIR}/${SOURCE_TARGET}-${ANDROID_ABI})
    IF(ARG_ANDROID_MANIFEST_IN_PATH)
        SET(QT_ANDROID_MANIFEST_IN_REAL_PATH ${ARG_ANDROID_MANIFEST_IN_PATH})
    ELSE()
        SET(QT_ANDROID_MANIFEST_IN_REAL_PATH ${QT_ANDROID_SOURCE_DIR}/AndroidManifest.xml.in)
    ENDIF()
    MESSAGE(STATUS "Used input AndroidManifest file QT_ANDROID_MANIFEST_IN_REAL_PATH : ${QT_ANDROID_MANIFEST_IN_REAL_PATH}")

    # get version code from arguments, or generate a fixed one if not provided
    set(QT_ANDROID_APP_VERSION_CODE ${ARG_VERSION_CODE})
    if(NOT QT_ANDROID_APP_VERSION_CODE)
        set(QT_ANDROID_APP_VERSION_CODE 1)
    endif()
    
    IF(ARG_VERSION_NAME)
        set(QT_ANDROID_APP_VERSION ${ARG_VERSION_NAME})
        if(NOT QT_ANDROID_APP_VERSION)
            set(QT_ANDROID_APP_VERSION 1)
        endif()
    ELSE(ARG_VERSION_NAME)
        # try to extract the app version from the target properties, or use the version code if not provided
        get_property(QT_ANDROID_APP_VERSION TARGET ${SOURCE_TARGET} PROPERTY VERSION)
        if(NOT QT_ANDROID_APP_VERSION)
            set(QT_ANDROID_APP_VERSION ${QT_ANDROID_APP_VERSION_CODE})
        endif()
    ENDIF(ARG_VERSION_NAME)

    # define the application source package directory
    if(ARG_PACKAGE_SOURCES)
        IF(EXISTS ${ARG_PACKAGE_SOURCES}/AndroidManifest.xml)
            SET(QT_ANDROID_APP_PACKAGE_SOURCE_ROOT ${ARG_PACKAGE_SOURCES})
        ELSE()
        set(QT_ANDROID_MIX_SOURCE_DEPLOY ON)
        set(QT_ANDROID_APP_PACKAGE_SOURCE_IN ${ARG_PACKAGE_SOURCES})

        set(QT_ANDROID_APP_PACKAGE_SOURCE_ROOT "${CMAKE_CURRENT_BINARY_DIR}/package")
        set(QT_ANDROID_MANIFEST_SOURCE_IN "${CMAKE_CURRENT_BINARY_DIR}/packagein")

        configure_file(${QT_ANDROID_MANIFEST_IN_REAL_PATH} ${QT_ANDROID_MANIFEST_SOURCE_IN}/AndroidManifest.xml @ONLY)
        ENDIF()
   else()
        # create a subdirectory for the extra package sources
        set(QT_ANDROID_APP_PACKAGE_SOURCE_ROOT "${CMAKE_CURRENT_BINARY_DIR}/package")

        # generate a manifest from the template
        configure_file(${QT_ANDROID_MANIFEST_IN_REAL_PATH} ${QT_ANDROID_APP_PACKAGE_SOURCE_ROOT}/AndroidManifest.xml @ONLY)
    endif()

    if(ANDROID_STL)
        if(ANDROID_STL_PATH)
            set(QT_ANDROID_STL_PATH "${ANDROID_STL_PATH}/libs/${ANDROID_ABI}/lib${ANDROID_STL}.so")
        else()
            set(QT_ANDROID_STL_PATH "${ANDROID_NDK}/sources/cxx-stl/${ANDROID_STL_PREFIX}/libs/${ANDROID_ABI}/lib${ANDROID_STL}.so")
        endif()
    else()
        set(QT_ANDROID_STL_PATH)
        IF(ANDROID_STL_STATIC_LIBRARIES)
            MESSAGE(WARNING "ANDROID_STL_SHARED_LIBRARIES isn't defined, you might need to define ANDROID_STL (${ANDROID_STL}) to a shared stl library and not a static library")
        ELSE(ANDROID_STL_STATIC_LIBRARIES)
            MESSAGE(WARNING "ANDROID_STL_SHARED_LIBRARIES isn't defined, you might need to define ANDROID_STL (${ANDROID_STL}) to a shared stl library (for example c++_shared or gnustl_shared)")
        ENDIF(ANDROID_STL_STATIC_LIBRARIES)
    endif()

    # set the list of dependant libraries
    if(ARG_DEPENDS)
        foreach(LIB ${ARG_DEPENDS})
            if(TARGET ${LIB})
                # item is a CMake target, extract the library path
                if(CMAKE_BUILD_TYPE STREQUAL "Debug")
                    get_property(LIB_PATH TARGET ${LIB} PROPERTY DEBUG_LOCATION)
                else()
                    get_property(LIB_PATH TARGET ${LIB} PROPERTY LOCATION)
                endif()
                set(LIB ${LIB_PATH})
            endif()
        if(EXTRA_LIBS)
            set(EXTRA_LIBS "${EXTRA_LIBS},${LIB}")
        else()
            set(EXTRA_LIBS "${LIB}")
        endif()
        endforeach()
        set(QT_ANDROID_APP_EXTRA_LIBS "\"android-extra-libs\": \"${EXTRA_LIBS}\",")
    endif()

    # set some toolchain variables used by androiddeployqt;
    # unfortunately, Qt tries to build paths from these variables although these full paths
    # are already available in the toochain file, so we have to parse them
    string(REGEX MATCH "${ANDROID_NDK}/toolchains/(.*)-(.*)/prebuilt/.*" ANDROID_TOOLCHAIN_PARSED ${ANDROID_TOOLCHAIN_ROOT})
    if(ANDROID_TOOLCHAIN_PARSED)
        set(QT_ANDROID_TOOLCHAIN_PREFIX ${CMAKE_MATCH_1})
        set(QT_ANDROID_TOOLCHAIN_VERSION ${CMAKE_MATCH_2})
    else()
        message(FATAL_ERROR "Failed to parse ANDROID_TOOLCHAIN_ROOT to get toolchain prefix and version")
    endif()

    # make sure that the output directory for the Android package exists
    file(MAKE_DIRECTORY ${QT_ANDROID_APP_BINARY_DIR}/libs/${ANDROID_ABI})

    # create the configuration file that will feed androiddeployqt
    configure_file(${QT_ANDROID_SOURCE_DIR}/qtdeploy.json.in ${CMAKE_CURRENT_BINARY_DIR}/qtdeploy.json @ONLY)
    SET(QT_ANDROID_NATIVE_API_LEVEL ${ANDROID_NATIVE_API_LEVEL})
    configure_file(${QT_ANDROID_SOURCE_DIR}/build.gradle.in ${QT_ANDROID_APP_BINARY_DIR}/build.gradle @ONLY)

    # check if the apk must be signed
    if(ARG_KEYSTORE)
        set(SIGN_OPTIONS --release --sign ${ARG_KEYSTORE} --tsa http://timestamp.digicert.com)
        if(ARG_KEYSTORE_PASSWORD)
            set(SIGN_OPTIONS ${SIGN_OPTIONS} --storepass ${ARG_KEYSTORE_PASSWORD})
        endif()
    endif()

    # check if the apk must be installed to the device
    if(ARG_INSTALL)
        set(INSTALL_OPTIONS --reinstall)
    endif()

    # specify the Android API level
    if(ANDROID_PLATFORM_LEVEL)
        set(TARGET_LEVEL_OPTIONS --android-platform android-${ANDROID_PLATFORM_LEVEL})
    endif()

    IF(QT_ANDROID_MIX_SOURCE_DEPLOY)
        SET(QT_ANDROID_MIX_SOURCE_DEPLOY_COMMANDS

        COMMAND ${CMAKE_COMMAND} -E remove_directory ${QT_ANDROID_APP_PACKAGE_SOURCE_ROOT} # Remove every file in our dependencies
        COMMAND ${CMAKE_COMMAND} -E make_directory ${QT_ANDROID_APP_PACKAGE_SOURCE_ROOT} # Create the directory
        
        COMMAND ${CMAKE_COMMAND} -E copy ${QT_ANDROID_MANIFEST_SOURCE_IN}/AndroidManifest.xml ${QT_ANDROID_APP_PACKAGE_SOURCE_ROOT}/AndroidManifest.xml
        COMMAND ${CMAKE_COMMAND} -E copy_directory ${QT_ANDROID_APP_PACKAGE_SOURCE_IN} ${QT_ANDROID_APP_PACKAGE_SOURCE_ROOT} #will erase the first AndroidManifest if another one exist      
            )
    ENDIF(QT_ANDROID_MIX_SOURCE_DEPLOY)

    IF(${CMAKE_BUILD_TYPE} STREQUAL "Release" OR
        ${CMAKE_BUILD_TYPE} STREQUAL "MinSizeRel" OR
        ${CMAKE_BUILD_TYPE} STREQUAL "RelWithDebInfo")
        SET(QT_ANDROID_BUILD_TYPE --release)
    ELSEIF(${CMAKE_BUILD_TYPE} STREQUAL "Debug")
        SET(QT_ANDROID_BUILD_TYPE --debug)
    ELSE()
        MESSAGE(WARNING "CMAKE_BUILD_TYPE (${CMAKE_BUILD_TYPE}) isn't set to "
        "Release | MinSizeRel | RelWithDebInfo | Debug. No --release or --debug will be specified to androiddeployqt")
    ENDIF()

    IF(ARG_VERBOSE)
        SET(QT_ANDROID_VERBOSE --verbose)
    ENDIF(ARG_VERBOSE)

    # create a custom command that will run the androiddeployqt utility to prepare the Android package
    add_custom_target(
        ${TARGET}
        ALL
        DEPENDS ${SOURCE_TARGET}

        ${QT_ANDROID_MIX_SOURCE_DEPLOY_COMMANDS}
  
        COMMAND ${CMAKE_COMMAND} -E remove_directory ${QT_ANDROID_APP_BINARY_DIR}/libs/${ANDROID_ABI} # it seems that recompiled libraries are not copied if we don't remove them first
        COMMAND ${CMAKE_COMMAND} -E make_directory ${QT_ANDROID_APP_BINARY_DIR}/libs/${ANDROID_ABI}
        COMMAND ${CMAKE_COMMAND} -E echo package source in :  ${QT_ANDROID_STL_PATH}
        COMMAND ${CMAKE_COMMAND} -E copy ${QT_ANDROID_APP_PATH} ${QT_ANDROID_APP_BINARY_DIR}/libs/${ANDROID_ABI}
        COMMAND ${QT_ANDROID_QT_ROOT}/bin/androiddeployqt 
        ${QT_ANDROID_VERBOSE}
        --output ${QT_ANDROID_APP_BINARY_DIR} 
        --input ${CMAKE_CURRENT_BINARY_DIR}/qtdeploy.json 
        --gradle 
        ${QT_ANDROID_BUILD_TYPE}
        ${TARGET_LEVEL_OPTIONS} 
        ${INSTALL_OPTIONS} 
        ${SIGN_OPTIONS}
    )

endmacro()
