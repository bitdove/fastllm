#!/bin/bash
folder="build-fastllm"

# 创建工作文件夹
if [ ! -d "$folder" ]; then
    mkdir "$folder"
fi

cd $folder
cmake .. "$@"
make -j$(nproc)

#编译失败停止执行
if [ $? != 0 ]; then
    exit -1
fi

# 注意：这里进入的是 ./build-fastllm/tools 目录
cd tools
pip install .[all]
#python3 setup.py sdist build
#python3 setup.py bdist_wheel
#python3 setup.py install --all