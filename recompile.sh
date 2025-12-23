#!/bin/bash

# Check if the directory /public exists
if [ -d "./build-fastllm" ]; then
  # If it exists, delete the directory
  rm -rf ./build-fastllm
  echo "./build-fastllm directory has been deleted."
else
  # If it doesn't exist, print a message
  echo "./build-fastllm directory does not exist."
fi

bash install.sh -DUSE_CUDA=ON -D CMAKE_CUDA_COMPILER=$(which nvcc)