cmake_minimum_required(VERSION 3.5)

project(fastllm LANGUAGES CXX)

option(USE_CUDA "use CUDA" OFF)
option(CUDA_NO_TENSOR_CORE "Optimize for legacy CUDA GPUs which has Tensor Core." OFF)


if(NOT DEFINED CUDA_ARCH)
    set(CUDA_ARCH "native")
endif()

message(STATUS "USE_CUDA: ${USE_CUDA}")

message(STATUS "CUDA_ARCH: ${CUDA_ARCH}")

message(STATUS "For legacy CUDA GPUs: ${CUDA_NO_TENSOR_CORE}")

message(STATUS "MAKE_WHL_X86: ${MAKE_WHL_X86}")

set(CMAKE_BUILD_TYPE "Release")

string(REGEX REPLACE "^([0-9]+)\\.[0-9]+\\.[0-9]+$" "\\1" CXX_MAJOR_VERSION "${CMAKE_CXX_COMPILER_VERSION}")

set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -pthread --std=c++17 -O2 -march=native")
message(STATUS "CMAKE_SYSTEM_PROCESSOR: ${CMAKE_SYSTEM_PROCESSOR}")
if (CXX_MAJOR_VERSION GREATER_EQUAL 10 AND CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64")
    set_source_files_properties(
        "src/devices/cpu/avx512f.cpp"
        PROPERTIES
        COMPILE_OPTIONS "-mavx512f;-mavx512bw;-mavx512vl"
    )
        
    set_source_files_properties(
        "src/devices/cpu/avx512bf16.cpp"
        PROPERTIES
        COMPILE_OPTIONS "-mavx512bf16;-mavx512f;-mavx512bw;-mavx512vl"
    )
    set_source_files_properties(
        "src/devices/cpu/avx512vnni.cpp"
        PROPERTIES
        COMPILE_OPTIONS "-mavx512vnni;-mavx512f"
    )
    set(AMX_COMPILE_OPTIONS "-mavx512bf16;-mavx512f;-mavx512bw;-mavx512vl")
    if (CXX_MAJOR_VERSION GREATER_EQUAL 11)
        list(APPEND AMX_COMPILE_OPTIONS "-mamx-tile" "-mamx-bf16")
        message(STATUS "AMX support enabled (g++ >= 11)")
    endif()
    set_source_files_properties(
        "src/devices/cpu/amx.cpp"
        PROPERTIES
        COMPILE_OPTIONS "${AMX_COMPILE_OPTIONS}"
    )
endif()


message(STATUS "CMAKE_CXX_FLAGS: ${CMAKE_CXX_FLAGS}")
file(GLOB GRAPH_MODEL_FILES "src/models/graph/*.cpp")
file(GLOB CPU_DEVICE_FILES "src/devices/cpu/*.cpp")
set(FASTLLM_CXX_SOURCES src/fastllm.cpp src/device.cpp src/model.cpp src/executor.cpp src/template.cpp src/graph.cpp src/tokenizer.cpp
        src/devices/cpu/cpudevice.cpp src/devices/cpu/cpudevicebatch.cpp
        src/models/graphllm.cpp 
        src/models/chatglm.cpp 
        src/models/llama.cpp 
        src/models/basellm.cpp
        src/models/bert.cpp 
        src/models/moe.cpp 
        src/models/deepseekv2.cpp
        third_party/json11/json11.cpp
        third_party/gguf/gguf.cpp third_party/gguf/ggml-quant.cpp third_party/gguf/ggml-iqk.cpp third_party/gguf/ggml-dequantize.cpp
        third_party/gguf/gguf-adapter.cpp
        ${CPU_DEVICE_FILES}
        ${GRAPH_MODEL_FILES})

include_directories(include)
include_directories(include/utils)
include_directories(include/models)
include_directories(include/devices/cpu)
include_directories(third_party/json11)
include_directories(third_party/gguf)

if (USE_CUDA)
    enable_language(CUDA)
    add_compile_definitions(USE_CUDA)
    if (CUDA_NO_TENSOR_CORE)
        add_compile_definitions(CUDA_NO_TENSOR_CORE)
    endif()
    include_directories(include/devices/cuda)
    set(FASTLLM_CUDA_SOURCES src/devices/cuda/cudadevice.cpp src/devices/cuda/cudadevicebatch.cpp 
        src/devices/cuda/fastllm-cuda.cu src/devices/cuda/fastllm-ggml-cuda.cu)

    include_directories(include/devices/multicuda)
    set(FASTLLM_CUDA_SOURCES ${FASTLLM_CUDA_SOURCES} src/devices/multicuda/multicudadevice.cpp src/devices/multicuda/fastllm-multicuda.cu)

    set(FASTLLM_LINKED_LIBS ${FASTLLM_LINKED_LIBS} cublas)
    set(CMAKE_CUDA_ARCHITECTURES ${CUDA_ARCH})
endif()

if (USE_NUMA)
    add_compile_definitions(USE_NUMA)
    set(FASTLLM_CXX_SOURCES ${FASTLLM_CXX_SOURCES} src/devices/numa/numadevice.cpp src/devices/numa/fastllm-numa.cpp src/devices/numa/computeserver.cpp src/devices/numa/kvcache.cpp)
    include_directories(include/devices/numa)
    set(FASTLLM_LINKED_LIBS ${FASTLLM_LINKED_LIBS} numa)
endif()
if (USE_NUMAS)
    add_compile_definitions(USE_NUMAS)
    set(FASTLLM_CXX_SOURCES ${FASTLLM_CXX_SOURCES} src/devices/numas/numasdevice.cpp src/devices/numas/numas.cpp)
    include_directories(include/devices/numas)
    set(FASTLLM_LINKED_LIBS ${FASTLLM_LINKED_LIBS} numa)
endif()

add_library(fastllm OBJECT
            ${FASTLLM_CXX_SOURCES}
            ${FASTLLM_CUDA_SOURCES}
            ${FASTLLM_TFACC_SOURCES}
            ${FASTLLM_TOPS_SOURCES}
            )
target_link_libraries(fastllm PUBLIC ${FASTLLM_LINKED_LIBS})

add_executable(main main.cpp)
target_link_libraries(main fastllm)

add_executable(quant tools/src/quant.cpp)
target_link_libraries(quant fastllm)

add_library(fastllm_tools SHARED ${FASTLLM_CXX_SOURCES} ${FASTLLM_CUDA_SOURCES} ${FASTLLM_TFACC_SOURCES} ${FASTLLM_TOPS_SOURCES} tools/src/pytools.cpp)
target_link_libraries(fastllm_tools PUBLIC ${FASTLLM_LINKED_LIBS})

add_custom_command(
        TARGET fastllm_tools
        POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E make_directory tools
        COMMAND ${CMAKE_COMMAND} -E make_directory tools/ftllm
        COMMAND ${CMAKE_COMMAND} -E copy_directory ${CMAKE_CURRENT_SOURCE_DIR}/tools/fastllm_pytools ${CMAKE_BINARY_DIR}/tools/ftllm/.
        COMMAND ${CMAKE_COMMAND} -E copy_directory ${CMAKE_CURRENT_SOURCE_DIR}/tools/scripts ${CMAKE_BINARY_DIR}/tools/.
        COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_BINARY_DIR}/libfastllm_tools.* ${CMAKE_BINARY_DIR}/tools/ftllm/.
        COMMAND ${CMAKE_COMMAND} -E remove ${CMAKE_BINARY_DIR}/libfastllm_tools.*
)