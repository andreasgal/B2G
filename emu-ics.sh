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

export PATH=$PATH:$B2G_HOME/glue/gonk-ics/out/host/linux-x86/bin
${DBG_CMD} $B2G_HOME/glue/gonk-ics/out/host/linux-x86/bin/emulator \
   -kernel $B2G_HOME/glue/gonk-ics/prebuilts/qemu-kernel/arm/kernel-qemu-armv7 \
   -sysdir $B2G_HOME/glue/gonk-ics/out/target/product/generic/ \
   -data $B2G_HOME/glue/gonk-ics/out/target/product/generic/userdata.img \
   -memory 512 \
   -partition-size 512 \
   -skindir $B2G_HOME/glue/gonk-ics/development/tools/emulator/skins \
   -skin WVGA854 \
   -verbose \
   -qemu -cpu 'cortex-a8' $TAIL_ARGS
