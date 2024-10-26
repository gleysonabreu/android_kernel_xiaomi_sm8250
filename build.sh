#!/usr/bin/env bash
# shellcheck disable=SC2199
# shellcheck source=/dev/null
#
# Copyright (C) 2020-22 UtsavBalar1231 <utsavbalar1231@gmail.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

if ! [ -d "$HOME/tc/aosp-clang" ]; then
  echo "aosp clang not found! Cloning..."
  if ! git clone -q https://gitlab.com/ThankYouMario/android_prebuilts_clang-standalone.git --depth=1 ~/tc/aosp-clang; then
    echo "Cloning failed! Aborting..."
    exit 1
  fi
fi

if ! [ -d "$HOME/tc/aarch64-linux-android-4.9" ]; then
  echo "aarch64-linux-android-4.9 not found! Cloning..."
  if ! git clone -q https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-android-4.9.git --depth=1 --single-branch ~/tc/aarch64-linux-android-4.9; then
    echo "Cloning failed! Aborting..."
    exit 1
  fi
fi

GCC_64_DIR="$HOME/tc/aarch64-linux-android-4.9"
KBUILD_COMPILER_STRING=$($HOME/tc/aosp-clang/bin/clang --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')
KBUILD_LINKER_STRING=$($HOME/tc/aosp-clang/bin/ld.lld --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//' | sed 's/(compatible with [^)]*)//')
export KBUILD_COMPILER_STRING
export KBUILD_LINKER_STRING

read -p "Update kernelSU? (y/n): " choice

if [ "$choice" = "y" ]; then
  rm -rf KernelSU

  read -p "Selection kernelsu version (dev/stable) : (1/0): " channel

  if [ "$channel" = "1" ]; then
    echo "Selected dev branch"
    curl -LSs curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh" | bash -s v0.9.5
  elif [ "$channel" = "0" ]; then
    echo "Selected main branch"
    curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh" | bash -s v0.9.5
  else
    echo "Invalid selection"
    exit 1
  fi
fi

read -p "Select device: (alioth=0, apollo=1, lmi=2, munch=3, psyche=4): " device

if [ "$device" = "0" ]; then
  DEVICE=alioth
elif [ "$device" = "1" ]; then
  DEVICE=apollo
elif [ "$device" = "2" ]; then
  DEVICE=lmi
elif [ "$device" = "3" ]; then
  DEVICE=munch
elif [ "$device" = "4" ]; then
  DEVICE=psyche
else
  echo "Invalid device"
  exit 1
fi

if [ "${DEVICE}" = "alioth" ]; then
  DEFCONFIG=vendor/alioth_defconfig
elif [ "${DEVICE}" = "apollo" ]; then
  DEFCONFIG=vendor/apollo_defconfig
elif [ "${DEVICE}" = "lmi" ]; then
  DEFCONFIG=vendor/lmi_defconfig
elif [ "${DEVICE}" = "munch" ]; then
  DEFCONFIG=vendor/munch_defconfig
elif [ "${DEVICE}" = "psyche" ]; then
  DEFCONFIG=vendor/psyche_defconfig
fi

#
# Enviromental Variables
#

DATE=$(date '+%Y%m%d-%H%M')

# Set our directory
OUT_DIR=out/

# Boot original image dir
export BOOT_DIR=/mnt/c/Users/aberforth/Downloads/boot.img

# New boot image dir
export NEW_BOOT_DIR=/mnt/c/Users/aberforth/Downloads/out

export KERNEL_DIR=$(pwd)

VERSION="Uvite-${DEVICE}-${DATE}"

# Export Zip name
export ZIPNAME="${VERSION}.zip"

# How much kebabs we need? Kanged from @raphielscape :)
if [[ -z "${KEBABS}" ]]; then
  COUNT="$(grep -c '^processor' /proc/cpuinfo)"
  export KEBABS="$((COUNT + 2))"
fi

echo "Jobs: ${KEBABS}"

ARGS="ARCH=arm64 \
O=${OUT_DIR} \
CC=clang \
LLVM=1 \
LLVM_IAS=1 \
CLANG_TRIPLE=aarch64-linux-gnu- \
CROSS_COMPILE=$GCC_64_DIR/bin/aarch64-linux-android- \
-j${KEBABS}"

dts_source=arch/arm64/boot/dts/vendor/qcom

START=$(date +"%s")

# Set compiler Path
export PATH="$HOME/tc/aosp-clang/bin:$PATH"
export LD_LIBRARY_PATH=${HOME}/tc/aosp-clang/lib64:$LD_LIBRARY_PATH

echo "------ Starting Compilation ------"

# Make defconfig
make -j${KEBABS} ${ARGS} ${DEFCONFIG}

# Make olddefconfig
cd ${OUT_DIR} || exit
make -j${KEBABS} ${ARGS} CC="ccache clang" HOSTCC="ccache gcc" HOSTCXX="cache g++" olddefconfig
cd ../ || exit

make -j${KEBABS} ${ARGS} CC="ccache clang" HOSTCC="ccache gcc" HOSTCXX="ccache g++" 2>&1 | tee build.log

find ${OUT_DIR}/$dts_source -name '*.dtb' -exec cat {} + >${OUT_DIR}/arch/arm64/boot/dtb

git checkout arch/arm64/boot/dts/vendor &>/dev/null

echo "------ Finishing Build ------"

END=$(date +"%s")
DIFF=$((END - START))
zipname="$VERSION.zip"
if [ -f "out/arch/arm64/boot/Image" ] && [ -f "out/arch/arm64/boot/dtbo.img" ] && [ -f "out/arch/arm64/boot/dtb" ]; then

  cd out/arch/arm64/boot
  wget https://github.com/dibin666/toolchains/releases/download/magiskboot/magiskbootx86_64
  chmod +x magiskbootx86_64

  cp $BOOT_DIR ./
  ./magiskbootx86_64 unpack boot.img

  mv -f Image kernel
  ./magiskbootx86_64 repack boot.img

  cp new-boot.img $NEW_BOOT_DIR

  cd $KERNEL_DIR
  rm -rf out

  curl -F "file=@${NEW_BOOT_DIR}/new-boot.img" https://temp.sh/upload
else
  echo -e "\n Compilation Failed!"
fi
