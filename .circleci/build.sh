#!/usr/bin/env bash
# Copyright (C) 2020 Saalim Quadri (iamsaalim)
# SPDX-License-Identifier: GPL-3.0-or-later

# Login to Git
echo -e "machine github.com\n  login $GITHUB_TOKEN" > ~/.netrc

# Set tg var.
function sendTG() {
    curl -s "https://api.telegram.org/bot$token/sendmessage" --data "text=${*}&chat_id=-1001278854279&parse_mode=HTML" > /dev/null
}

function trackTG() {
    curl -s "https://api.telegram.org/bot$token/sendmessage" --data "text=${*}&chat_id=@stormbreakerci&parse_mode=HTML&disable_web_page_preview=True" > /dev/null
}

# Setup arguments
PROJECT_DIR="$HOME"
ORG="https://github.com/stormbreaker-project"
KERNEL_DIR="$PROJECT_DIR/kernelsource"
TOOLCHAIN="$PROJECT_DIR/toolchain"
DEVICE="$1"
BRANCH="$2"
CHAT_ID="-1001278854279"

# Create kerneldir
mkdir -p "$PROJECT_DIR/kernelsource"

# Clone up the source
git clone $ORG/$DEVICE -b $BRANCH $KERNEL_DIR/$DEVICE --depth 1 || { sendTG "Your device is not officially supported or wrong branch"; exit 0;}

# Find defconfig
echo "Checking if defconfig exist ($DEVICE)"

if [ -f $KERNEL_DIR/$DEVICE/arch/arm64/configs/$DEVICE-perf_defconfig ]
then
    echo "Starting build"
elif [ -f $KERNEL_DIR/$DEVICE/arch/arm64/configs/vendor/$DEVICE-perf_defconfig ]
then
    echo "Starting build"
else
    sendTG "Defconfig not found"
    exit 0
fi

# Clone toolchain
echo "Cloning toolchains"
git clone --depth=1 https://github.com/stormbreaker-project/aarch64-linux-android-4.9 $TOOLCHAIN/gcc > /dev/null 2>&1
git clone --depth=1 https://github.com/stormbreaker-project/arm-linux-androideabi-4.9 $TOOLCHAIN/gcc_32 > /dev/null 2>&1
git clone --depth 1 https://github.com/sreekfreak995/Clang-11.0.3.git $TOOLCHAIN/clang

# Set Env
PATH="${TOOLCHAIN}/clang/bin:${TOOLCHAIN}/gcc/bin:${TOOLCHAIN}/gcc_32/bin:${PATH}"
export ARCH=arm64
export KBUILD_BUILD_HOST=danascape
export KBUILD_BUILD_USER="stormCI"
export KBUILD_COMPILER_STRING="${TOOLCHAIN}/clang/bin/clang --version | head -n 1 | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')";

# Build
cd "$KERNEL_DIR/$DEVICE"
sendTG "Build Started

Device :- ${DEVICE}
Branch :- ${BRANCH}

<a href=\"${CIRCLE_BUILD_URL}\">circleci</a>"

trackTG "Build Started

Device :- ${DEVICE}
Branch :- ${BRANCH}

${CIRCLE_BUILD_URL}"

if [ -f $KERNEL_DIR/$DEVICE/arch/arm64/configs/$DEVICE-perf_defconfig ]
then
     make O=out ARCH=arm64 $DEVICE-perf_defconfig
elif [ -f $KERNEL_DIR/$DEVICE/arch/arm64/configs/vendor/$DEVICE-perf_defconfig ]
then
    make O=out ARCH=arm64 vendor/$DEVICE-perf_defconfig
fi

START=$(date +"%s")
if [[ "$DEVICE" == "phoenix" ]];
then
     PATH="${TOOLCHAIN}/clang/bin:${PATH}"
     make -j$(nproc --all) O=out ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnueabi- CC=clang AR=llvm-ar OBJDUMP=llvm-objdump STRIP=llvm-strip NM=llvm-nm OBJCOPY=llvm-objcopy LD=ld.lld
else
     make -j$(nproc --all) O=out ARCH=arm64 CC=clang CLANG_TRIPLE=aarch64-linux-gnu- CROSS_COMPILE=aarch64-linux-android- CROSS_COMPILE_ARM32=arm-linux-androideabi-
fi

END=$(date +"%s")
DIFF=$(($END - $START))

if [ -f $KERNEL_DIR/$DEVICE/out/arch/arm64/boot/Image.gz-dtb ]
then
    sendTG "Build Completed in $DIFF seconds, Uploading zip"
else
    sendTG "Build Failed"
    exit 1
fi

# Clone Anykernel
git clone -b $DEVICE https://github.com/stormbreaker-project/AnyKernel3 --depth 1 || { sendTG "Branch not found in Anykernel repo"; exit 0;}
cp $KERNEL_DIR/$DEVICE/out/arch/arm64/boot/Image.gz-dtb AnyKernel3/

# Build dtbo
if [ -f $KERNEL_DIR/$DEVICE/out/arch/arm64/boot/dts/xiaomi/*.dtbo ]
then
    sendTG "Building DTBO"
    git clone https://android.googlesource.com/platform/system/libufdt "$KERNEL_DIR"/scripts/ufdt/libufdt

if [[ "$DEVICE" == "phoenix" ]];
then
    python scripts/ufdt/libufdt/utils/src/mkdtboimg.py create AnyKernel3/dtbo.img --page_size=4096 out/arch/arm64/boot/dts/xiaomi/phoenix-sdmmagpie-overlay.dtbo
else
    python scripts/ufdt/libufdt/utils/src/mkdtboimg.py create AnyKernel3/dtbo.img --page_size=4096 out/arch/arm64/boot/dts/qcom/*.dtbo
fi
fi

cd AnyKernel3 && make normal

ZIP=$(echo *.zip)
curl -F chat_id="${CHAT_ID}" -F document=@"$ZIP" "https://api.telegram.org/bot${token}/sendDocument"
curl -F chat_id="-1001273051289" -F document=@"$ZIP" "https://api.telegram.org/bot${token}/sendDocument"
sendTG "Join @Stormbreakerci to track your build"
