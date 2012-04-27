#!/bin/sh

qemu/bin/emulator \
   -kernel qemu/kernel-qemu-armv7 \
   -sysdir qemu/generic/ \
   -data qemu/generic/userdata.img \
   -memory 512 \
   -partition-size 512 \
   -skindir qemu/skins \
   -skin WVGA854 \
   -verbose \
   -qemu -cpu 'cortex-a8'

