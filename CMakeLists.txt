cmake_minimum_required(VERSION 3.21)
project(Cutrix VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Quick QuickControls2 Multimedia Widgets)
qt_standard_project_setup(REQUIRES 6.5)

qt_add_executable(cutrix
    src/main.cpp
    src/ProjectStore.cpp
    src/ProjectStore.h
    src/MediaTools.cpp
    src/MediaTools.h
)

qt_add_qml_module(cutrix
    URI Cutrix
    VERSION 1.0
    QML_FILES qml/Main.qml
)

target_link_libraries(cutrix PRIVATE Qt6::Quick Qt6::QuickControls2 Qt6::Multimedia Qt6::Widgets)

install(TARGETS cutrix RUNTIME DESTINATION bin)
