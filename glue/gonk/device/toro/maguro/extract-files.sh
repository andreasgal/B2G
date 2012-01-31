#!/bin/bash

# Copyright (C) 2010 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

DEVICE=maguro
COMMON=common
MANUFACTURER=toro

if [[ -z "${ANDROIDFS_DIR}" ]]; then
   DEVICE_BUILD_ID=`adb shell cat /system/build.prop | grep ro.build.display.id | sed -e 's/ro.build.display.id=//' | tr -d '\r'`
   case "$DEVICE_BUILD_ID" in
   "msm7627a_sku1-eng 2.3.5 GRJ90 eng.fsheng.20110915.182729 test-keys")
     FIRMWARE=20110915.182729 ;;
   *)
     echo Warning, your device has unknown firmware $DEVICE_BUILD_ID >&2
     FIRMWARE=unknown ;;
   esac
fi 

BASE_PROPRIETARY_COMMON_DIR=vendor/$MANUFACTURER/$COMMON/proprietary
PROPRIETARY_DEVICE_DIR=../../../vendor/$MANUFACTURER/$DEVICE/proprietary
PROPRIETARY_COMMON_DIR=../../../$BASE_PROPRIETARY_COMMON_DIR

mkdir -p $PROPRIETARY_DEVICE_DIR

for NAME in audio cameradat egl firmware hw keychars wifi etc
do
    mkdir -p $PROPRIETARY_COMMON_DIR/$NAME
done

# maguro

# common
(cat << EOF) | sed s/__DEVICE__/$DEVICE/g | sed s/__MANUFACTURER__/$MANUFACTURER/g > ../../../vendor/$MANUFACTURER/$DEVICE/$DEVICE-vendor-blobs.mk
# Copyright (C) 2010 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Prebuilt libraries that are needed to build open-source libraries
PRODUCT_COPY_FILES := \\

# All the blobs necessary for galaxys2 devices
PRODUCT_COPY_FILES += \\

EOF

COMMON_BLOBS_LIST=../../../vendor/$MANUFACTURER/$COMMON/vendor-blobs.mk

(cat << EOF) | sed s/__COMMON__/$COMMON/g | sed s/__MANUFACTURER__/$MANUFACTURER/g > $COMMON_BLOBS_LIST
# Copyright (C) 2010 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Prebuilt libraries that are needed to build open-source libraries
PRODUCT_COPY_FILES := \\
    vendor/__MANUFACTURER__/__COMMON__/proprietary/libcamera.so:obj/lib/libcamera.so \\
    vendor/__MANUFACTURER__/__COMMON__/proprietary/libril.so:obj/lib/libril.so \\
    vendor/__MANUFACTURER__/__COMMON__/proprietary/audio/libaudio.so:obj/lib/libaudio.so \\
    vendor/__MANUFACTURER__/__COMMON__/proprietary/audio/libaudiopolicy.so:obj/lib/libaudiopolicy.so

# TODO: The build system seems to want libaudio.so and libaudiopolicy.so in two
# locations.  Need to resolve this properly.
PRODUCT_COPY_FILES += \\
    vendor/__MANUFACTURER__/__COMMON__/proprietary/audio/libaudio.so:system/lib/libaudio.so \\
    vendor/__MANUFACTURER__/__COMMON__/proprietary/audio/libaudiopolicy.so:system/lib/libaudiopolicy.so

# All the blobs necessary for galaxys2 devices
PRODUCT_COPY_FILES += \\
EOF

# copy_files
# pulls a list of files from the device and adds the files to the list of blobs
#
# $1 = list of files
# $2 = directory path on device
# $3 = directory name in $PROPRIETARY_COMMON_DIR
copy_files()
{
    for NAME in $1
    do
        echo Pulling \"$NAME\"
        if [[ -z "${ANDROIDFS_DIR}" ]]; then
           adb pull /$2/$NAME $PROPRIETARY_COMMON_DIR/$3/$NAME
        else
           # Hint: Uncomment the next line to populate a fresh ANDROIDFS_DIR
           #       (TODO: Make this a command-line option or something.)
           # adb pull /$2/$NAME ${ANDROIDFS_DIR}/$2/$NAME
           cp ${ANDROIDFS_DIR}/$2/$NAME $PROPRIETARY_COMMON_DIR/$3/$NAME
        fi

        if [[ -f $PROPRIETARY_COMMON_DIR/$3/$NAME ]]; then
           echo   $BASE_PROPRIETARY_COMMON_DIR/$3/$NAME:$2/$NAME \\ >> $COMMON_BLOBS_LIST
        else
           echo Failed to pull $NAME.
#           exit -1
        fi
    done
}

COMMON_LIBS="
        libhardware.so
        libhardware_legacy.so
        libnetutils.so
	libcamera_client.so
	libcameraservice.so
	libcamera.so
	liboemcamera.so
	libmmjpeg.so
	libmmipl.so
	libexif.so
   libgsl.so
        libOmxAacDec.so
        libOmxAacEnc.so
        libOmxAdpcmDec.so
        libOmxAmrDec.so
        libOmxAmrEnc.so
        libOmxAmrRtpDec.so
        libOmxAmrwbDec.so
        libOmxCore.so
        libOmxEvrcDec.so
        libOmxEvrcEnc.so
        libOmxEvrcHwDec.so
        libOmxH264Dec.so
        libOmxMp3Dec.so
        libOmxMpeg4Dec.so
        libOmxOn2Dec.so
        libOmxQcelp13Dec.so
        libOmxQcelp13Enc.so
        libOmxQcelpHwDec.so
        libOmxVidEnc.so
        libOmxVp8Dec.so
        libOmxWmaDec.so
        libOmxWmvDec.so
        libOmxrv9Dec.so
        libOpenSLES.so
        libOpenVG.so
        libQWiFiSoftApCfg.so
        libRS.so
        libSR_AudioIn.so
        libchromatix_imx072_default_video.so
        libchromatix_imx072_preview.so
        libchromatix_imx074_default_video.so
        libchromatix_imx074_preview.so
        libchromatix_mt9e013_ar.so
        libchromatix_mt9e013_default_video.so
        libchromatix_mt9e013_preview.so
        libchromatix_mt9e013_video_hfr.so
        libchromatix_mt9p012_ar.so
        libchromatix_mt9p012_default_video.so
        libchromatix_mt9p012_km_default_video.so
        libchromatix_mt9p012_km_preview.so
        libchromatix_mt9p012_preview.so
        libchromatix_mt9t013_default_video.so
        libchromatix_mt9t013_preview.so
        libchromatix_ov2720_default_video.so
        libchromatix_ov2720_preview.so
        libchromatix_ov5647_ar.so
        libchromatix_ov5647_default_video.so
        libchromatix_ov5647_preview.so
        libchromatix_ov8810_default_video.so
        libchromatix_ov8810_preview.so
        libchromatix_ov9726_preview.so
        libchromatix_ov9726_video.so
        libchromatix_qs_mt9p017_preview.so
        libchromatix_qs_mt9p017_video.so
        libchromatix_s5k3e2fx_default_video.so
        libchromatix_s5k3e2fx_preview.so
        libchromatix_s5k4e1_ar.so
        libchromatix_s5k4e1_default_video.so
        libchromatix_s5k4e1_preview.so
        libchromatix_sn12m0pz_default_video.so
        libchromatix_sn12m0pz_preview.so
        libchromatix_vb6801_default_video.so
        libchromatix_vb6801_preview.so
        libchromatix_vx6953_default_video.so
        libchromatix_vx6953_preview.so
	libril.so
        libril-qc-1.so
        libril-qc-qmi-1.so
        libril-qcril-hook-oem.so
        liboncrpc.so
        libdsm.so
        libqueue.so
        libdiag.so
        libauth.so
        libcm.so
        libnv.so
        libpbmlib.so
        libwms.so
        libwmsts.so
        libqmi.so
        libdsutils.so
        libqmiservices.so
        libidl.so
        libdsi_netctrl.so
        libnetmgr.so
        libqdp.so
        libgps.so
        libgps.utils.so
        libcommondefs.so
        libloc_api-rpc-qc.so
        librpc.so
	"
copy_files "$COMMON_LIBS" "system/lib" ""

COMMON_BINS="
	rild
	rmt_storage
   hciattach
   abtfilt
   amploader
   hci_qcomm_init
   wlan_tool
   wmiconfig
   wpa_cli
   wpa_supplicant
   loc_api_app
	"

copy_files "$COMMON_BINS" "system/bin" ""

COMMON_EGL="
        egl.cfg
        eglsubAndroid.so
        libEGL_adreno200.so
        libGLES_android.so
        libGLESv1_CM_adreno200.so
        libGLESv2_adreno200.so
        libq3dtools_adreno200.so
	"
copy_files "$COMMON_EGL" "system/lib/egl" "egl"

COMMON_FIRMWARE="
        leia_pfp_470.fw
        leia_pm4_470.fw
        yamato_pfp.fw
        yamato_pm4.fw
	"
copy_files "$COMMON_FIRMWARE" "system/etc/firmware" "firmware"

COMMON_HW="
        copybit.msm7k.so
        gps.default.so
        gps.goldfish.so
        gralloc.default.so
        gralloc.msm7k.so
        libloc_eng_v01.default.so
        lights.msm7k.so
        sensors.default.so
        sensors.goldfish.so
	"

copy_files "$COMMON_HW" "system/lib/hw" "hw"

COMMON_KEYCHARS="
        7x27a_kp.kcm.bin
        qwerty.kcm.bin
        qwerty2.kcm.bin
        surf_keypad.kcm.bin
	"
copy_files "$COMMON_KEYCHARS" "system/usr/keychars" "keychars"


COMMON_ETC="
        AudioFilter.csv
        loc_parameter.ini
	"
copy_files "$COMMON_ETC" "system/etc" "etc"

COMMON_WIFI="
        hostapd.conf
        wpa_supplicant.conf
	"
copy_files "$COMMON_WIFI" "system/etc/wifi" "wifi"

COMMON_WIFI_DRIVER="
        ar6000.ko
	"
copy_files "$COMMON_WIFI_DRIVER" "system/wifi" ""

COMMON_WIFI_FIRMWARE="
        athtcmd_ram.bin
        athwlan_mobile.bin
        athwlan_tablet.bin
        data.patch.hw3_0.bin
        otp.bin
        athwlan.bin
        athwlan_router.bin
        bdata.SD31.bin
        device.bin
	"
copy_files "$COMMON_WIFI_FIRMWARE" "system/wifi/ath6k/AR6003/hw2.1.1" ""

COMMON_AUDIO="
        libaudio.so
        libaudioalsa.so
        libaudioeq.so
        libaudiopolicy.so
        liba2dp.so
	"
copy_files "$COMMON_AUDIO" "system/lib" "audio"

./setup-makefiles.sh
