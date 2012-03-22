# Advice

This file contains various things we've found out while getting B2G
working on various devices.

# Samsung Galaxy S2

## Device Enters Reboot Loop on Factory Reset of Stock Firmware

If you run a factory reset on the stock firmware, the restored
/data/system directory receives the wrong permissions. This will cause
the device to enter a boot loop. To fix this, adb shell into the phone
(the boot loop doesn't effect adb), and change the /data/system
directory permissions to 700. This should cause the phone to continue
boot through to the GUI.

## Samsung Galaxy S2 (GT-I9100G) Model is Unsupported 

The Samsung Galaxy S2 (GT-I9100G) uses different chip from generic SGS2 GT-I9100 phones.
Hence B2G doesn't support this model yet.