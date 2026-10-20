# Copyright (C) 2017, David PHAM-VAN <dev.nfet.net@gmail.com>
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may not
# use this file except in compliance with the License. You may obtain a copy of
# the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations under
# the License.

cmake_minimum_required(VERSION 3.15)
set(PROJECT_NAME "printing")
project(${PROJECT_NAME} LANGUAGES CXX)

string(REPLACE "windows-" "" TARGET_ARCH ${FLUTTER_TARGET_PLATFORM})
if(NOT TARGET_ARCH STREQUAL "x64")
  message(FATAL_ERROR "PDFium is verified for Windows x64 only; pin the archive and DLL hashes before adding another architecture.")
endif()
set(PDFIUM_URL "https://github.com/bblanchon/pdfium-binaries/releases/download/chromium/5200/pdfium-win-x64.tgz")
set(PDFIUM_ARCHIVE_SHA256 "8e900c3e5103ae9a3aa7800653e804575c687d132fcfb4deda7bb2ce04aca8d2")
# Optional developer cache. Users receive pdfium.dll in the Windows bundle.
set(STAMSOFER_PDFIUM_ARCHIVE "" CACHE FILEPATH "Local PDFium 5200 x64 archive (SHA-256 verified)")
if(STAMSOFER_PDFIUM_ARCHIVE)
  set(PDFIUM_URL "${STAMSOFER_PDFIUM_ARCHIVE}")
endif()

# Download pdfium
include(../windows/DownloadProject.cmake)
download_project(PROJ
                 pdfium
                 URL
                 "${PDFIUM_URL}"
                 URL_HASH "SHA256=${PDFIUM_ARCHIVE_SHA256}"
                 TLS_VERIFY ON)

# Check the extracted payload too, including when ExternalProject reuses it.
include("${CMAKE_CURRENT_LIST_DIR}/VerifyPdfium.cmake")
verify_pdfium_dll("${pdfium_SOURCE_DIR}/bin/pdfium.dll")

# This value is used when generating builds using this plugin, so it must not be
# changed
set(PLUGIN_NAME "printing_plugin")

include(${pdfium_SOURCE_DIR}/PDFiumConfig.cmake)

add_library(${PLUGIN_NAME} SHARED
            "printing.cpp"
            "printing.h"
            "printing_plugin.cpp"
            "include/printing/printing_plugin.h"
            "print_job.cpp"
            "print_job.h")

apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME}
                           INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME}
                      PRIVATE pdfium flutter flutter_wrapper_plugin)

# List of absolute paths to libraries that should be bundled with the plugin
set(printing_bundled_libraries "${PDFium_LIBRARY}" PARENT_SCOPE)

set(printing_pdfium_license "${pdfium_SOURCE_DIR}/LICENSE" PARENT_SCOPE)
