#!/usr/bin/env bash
set -e
#
#  build.sh - Automic kernel building script for Rosemary Kernel
#
#  Copyright (C) 2021-2023, Crepuscular's AOSP WorkGroup
#  Author: EndCredits <alicization.han@gmail.com>
#
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License version 2 as
#  published by the Free Software Foundation.
#
#  Add clang to your PATH before using this script.
#

LOCAL_VERSION_NUMBER=v2.1.0

ARCH=arm64;
CC=clang;
CLANG_TRIPLE=aarch64-linux-gnu-;
CROSS_COMPILE=aarch64-linux-gnu-;
CROSS_COMPILE_COMPAT=arm-linux-gnueabi-;
THREAD=$(nproc --all);
CC_ADDITION_FLAGS="";
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${ROOT_DIR}/out"

TARGET_KERNEL_FILE=arch/arm64/boot/Image;
TARGET_KERNEL_DTB=arch/arm64/boot/dtb;
TARGET_KERNEL_DTBO=arch/arm64/boot/dtbo.img
TARGET_KERNEL_NAME=Driftwood-Kernel;
TARGET_KERNEL_MOD_VERSION=$(make kernelversion)-$LOCAL_VERSION_NUMBER;

DEFCONFIG_PATH=arch/arm64/configs
DEFCONFIG_NAME=vendor/picasso_user_defconfig;

START_SEC=$(date +%s);
CURRENT_TIME=$(date '+%Y-%m%d%H%M');

ANYKERNEL_URL=https://codeload.github.com/EndCredits/AnyKernel3/zip/refs/heads/picasso;
ANYKERNEL_PATH=AnyKernel3-picasso;
ANYKERNEL_FILE=anykernel.zip;

link_all_dtb_files(){
    echo " Combining DTB files...";
    find $OUT/arch/arm64/boot/dts/vendor/qcom -name '*.dtb' -exec cat {} + > $OUT/arch/arm64/boot/dtb;
}

make_defconfig(){
    echo "------------------------------";
    echo " Building Kernel Defconfig..";
    echo "------------------------------";

    mkdir -p $OUT;
    make CC=$CC ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE CROSS_COMPILE_COMPAT=$CROSS_COMPILE_COMPAT CLANG_TRIPLE=$CLANG_TRIPLE $CC_ADDITION_FLAGS O=$OUT -j$THREAD $DEFCONFIG_NAME;
}

build_kernel(){
    echo "------------------------------";
    echo " Building Kernel ...........";
    echo "------------------------------";

    make CC=$CC ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE CROSS_COMPILE_COMPAT=$CROSS_COMPILE_COMPAT CLANG_TRIPLE=$CLANG_TRIPLE $CC_ADDITION_FLAGS O=$OUT -j$THREAD;

    if [ ! -f "$OUT/arch/arm64/boot/Image" ]; then
        echo "ERROR: Kernel compilation did not produce $OUT/arch/arm64/boot/Image!"
        exit 1
    fi

    END_SEC=$(date +%s);
    COST_SEC=$[ $END_SEC-$START_SEC ];
    echo "Kernel Build Costed $(($COST_SEC/60))min $(($COST_SEC%60))s"
}

generate_flashable(){
    echo "------------------------------";
    echo " Generating Flashable Kernel";
    echo "------------------------------";

    rm -rf $OUT/$ANYKERNEL_PATH
    mkdir -p $OUT/$ANYKERNEL_PATH

    if [ -d "$ROOT_DIR/anykernel3" ]; then
        echo ' Using bundled AnyKernel3 template ';
        cp -r "$ROOT_DIR/anykernel3/"* $OUT/$ANYKERNEL_PATH/
    else
        echo ' Getting AnyKernel ';
        curl -sL $ANYKERNEL_URL -o $OUT/$ANYKERNEL_FILE
        unzip -q -o $OUT/$ANYKERNEL_FILE -d $OUT/
    fi

    # Ensure dynamic block device detection for Pixel Experience / AOSP recoveries
    sed -i -e 's|block=.*|block=boot;|g' $OUT/$ANYKERNEL_PATH/anykernel.sh 2>/dev/null || sed -i '' -e 's|block=.*|block=boot;|g' $OUT/$ANYKERNEL_PATH/anykernel.sh
    sed -i -e 's|is_slot_device=.*|is_slot_device=0;|g' $OUT/$ANYKERNEL_PATH/anykernel.sh 2>/dev/null || sed -i '' -e 's|is_slot_device=.*|is_slot_device=0;|g' $OUT/$ANYKERNEL_PATH/anykernel.sh

    echo ' Copying Kernel Files '; 
    cp -f "$OUT/arch/arm64/boot/Image" "$OUT/$ANYKERNEL_PATH/Image"
    cp -f "$OUT/arch/arm64/boot/dtb" "$OUT/$ANYKERNEL_PATH/dtb" 2>/dev/null || true
    cp -f "$OUT/arch/arm64/boot/dtbo.img" "$OUT/$ANYKERNEL_PATH/dtbo.img" 2>/dev/null || true

    echo ' Packaging flashable AnyKernel3 zip ';
    (cd $OUT/$ANYKERNEL_PATH && zip -q -r $TARGET_KERNEL_NAME-$CURRENT_TIME-$TARGET_KERNEL_MOD_VERSION.zip *)

    echo ' Generating Fastboot boot.img ';
    RAMDISK_FILE="$ROOT_DIR/scripts/base_ramdisk.cpio"
    python3 "$ROOT_DIR/scripts/repack_boot.py" \
        --kernel "$OUT/arch/arm64/boot/Image" \
        --ramdisk "$RAMDISK_FILE" \
        --dtb "$OUT/arch/arm64/boot/dtb" \
        --output "$OUT/boot.img"

    echo " Target File:  $OUT/$ANYKERNEL_PATH/$TARGET_KERNEL_NAME-$CURRENT_TIME-$TARGET_KERNEL_MOD_VERSION.zip "
    echo " Fastboot Image: $OUT/boot.img "
}

save_defconfig(){
    echo "------------------------------";
    echo " Saving kernel config ........";
    echo "------------------------------";

    make CC=$CC ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE CROSS_COMPILE_COMPAT=$CROSS_COMPILE_COMPAT CLANG_TRIPLE=$CLANG_TRIPLE $CC_ADDITION_FLAGS O=$OUT -j$THREAD savedefconfig;
    END_SEC=$(date +%s);
    COST_SEC=$[ $END_SEC-$START_SEC ];
    echo "Finished. Kernel config saved to $OUT/defconfig"
    echo "Moving kernel defconfig to source tree"
    mv $OUT/defconfig $DEFCONFIG_PATH/$DEFCONFIG_NAME
    echo "Kernel Config Build Costed $(($COST_SEC/60))min $(($COST_SEC%60))s"

}

clean(){
    echo "Clean source tree and build files..."
    make mrproper -j$THREAD;
    make clean -j$THREAD;
    rm -rf $OUT;
}

main(){
    if [ $1 == "help" -o $1 == "-h" ]
    then
        echo "build.sh: A very simple Kernel build helper"
        echo "usage: build.sh <build option>"
        echo
        echo "Build options:"
        echo "    all             Perform a build without cleaning."
        echo "    cleanbuild      Clean the source tree and build files then perform a all build."
        echo
        echo "    flashable       Only generate the flashable zip file. Don't use it before you have built once."
        echo "    savedefconfig   Save the defconfig file to source tree."
        echo "    defconfig       Only build kernel defconfig"
        echo "    help ( -h )     Print help information."
        echo "    version         Display the version number."
        echo
    elif [ $1 == "savedefconfig" ]
    then
        save_defconfig;
    elif [ $1 == "cleanbuild" ]
    then
        clean;
        make_defconfig;
        build_kernel;
        link_all_dtb_files;
        generate_flashable;
    elif [ $1 == "flashable" ]
    then
        generate_flashable;
    elif [ $1 == "kernelonly" ]
    then
        make_defconfig
        build_kernel
    elif [ $1 == "all" ]
    then
        make_defconfig
        build_kernel
        link_all_dtb_files
        generate_flashable
    elif [ $1 == "defconfig" ]
    then
        make_defconfig;
    elif [ $1 == "version" ] 
    then 
        echo "Current version is: $LOCAL_VERSION_NUMBER"
    else
        echo "Incorrect usage. Please run: "
        echo "  bash build.sh help (or -h) "
        echo "to display help message."
    fi
}

main "$1";
