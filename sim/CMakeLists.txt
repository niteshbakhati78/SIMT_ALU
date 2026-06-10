cmake_minimum_required(VERSION 3.16)
project(simt_alu_sim CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(MSVC)
    add_compile_options(/W4 /O2)
else()
    add_compile_options(-Wall -Wextra -O2)
endif()

# ── Core simulation library ────────────────────────────────────────────────────
add_library(simt_core
    src/simt_types.cpp
    src/scoreboard.cpp
    src/warp_table.cpp
    src/warp_scheduler.cpp
    src/exec_pipe.cpp
    src/mini_sm.cpp
    src/pdom_ctrl.cpp
)
target_include_directories(simt_core PUBLIC include)

# ── Tests ──────────────────────────────────────────────────────────────────────
enable_testing()

add_executable(test_scoreboard tests/test_scoreboard.cpp)
target_link_libraries(test_scoreboard PRIVATE simt_core)
add_test(NAME scoreboard COMMAND test_scoreboard)

add_executable(test_warp_table tests/test_warp_table.cpp)
target_link_libraries(test_warp_table PRIVATE simt_core)
add_test(NAME warp_table COMMAND test_warp_table)

add_executable(test_mini_sm tests/test_mini_sm.cpp)
target_link_libraries(test_mini_sm PRIVATE simt_core)
add_test(NAME mini_sm COMMAND test_mini_sm)

add_executable(test_divergence tests/test_divergence.cpp)
target_link_libraries(test_divergence PRIVATE simt_core)
add_test(NAME divergence COMMAND test_divergence)

# ── Simulation CLI ─────────────────────────────────────────────────────────────
add_executable(mini_sm_sim src/main.cpp)
target_link_libraries(mini_sm_sim PRIVATE simt_core)
