#
# This CMakeLists.txt goal is to be used with CMake's FetchContent function
# In your CMake script you should do :
#
# FetchContent_Declare(
#     QtAndroidCMake
#     GIT_REPOSITORY https://github.com/LaurentGomila/qt-android-cmake
#     GIT_TAG        master
# )
# FetchContent_MakeAvailable(QtAndroidCMake)
#
# Then you can call add_qt_android_apk when you want.
# This code snippet will download the repository if not already done and include the CMakeLists
# (that will include the script).
# Everything will be working out of the box.
#

cmake_minimum_required(VERSION 3.0.0 FATAL_ERROR)

include(${CMAKE_CURRENT_LIST_DIR}/AddQtAndroidApk.cmake)

set(QT_ANDROID_SOURCE_DIR ${QT_ANDROID_SOURCE_DIR} CACHE STRING "Source directory of AddQtAndroidApk.cmake")
set(QT_ANDROID_QT_ROOT ${QT_ANDROID_QT_ROOT} CACHE STRING "Qt SDK root folder")
set(QT_ANDROID_SDK_ROOT ${QT_ANDROID_SDK_ROOT} CACHE STRING "" FORCE)
set(QT_ANDROID_NDK_ROOT ${QT_ANDROID_NDK_ROOT} CACHE STRING "" FORCE)
