#!/bin/sh
B2G_HOME=$(pwd)

DBG_CMD=""
if [ x"$DBG" != x"" ]; then
   DBG_CMD="gdb -args"
fi
TAIL_ARGS=""
if [ x"$GDBSERVER" != x"" ]; then
   TAIL_ARGS="$TAIL_ARGS -s -S"
fi

${DBG_CMD} $B2G_HOME/glue/gonk/out/host/linux-x86/bin/emulator \
   -kernel $B2G_HOME/boot/kernel-android-qemu/arch/arm/boot/zImage \
   -sysdir $B2G_HOME/glue/gonk/out/target/product/generic/ \
   -data $B2G_HOME/glue/gonk/out/target/product/generic/userdata.img \
   -memory 512 \
   -partition-size 512 \
   -skin 480x800 \
   -verbose \
   -qemu -cpu 'cortex-a8' $TAIL_ARGS
