# How to trick wifi into working

Currently our wifi can run DHCP and configure DNS once a connection is established. Establishing a connection requires wpa_supplicant to be configured first, and we currently have no proper way of configuring wpa_supplicant. However, there are three workarounds:

## Configure it in Android

This works for the Galaxy S2.

Simply configure your wifi in Android, and then flash B2G on to the phone. Do not wipe your data partition - the wifi configuration is stored there.

## Copy a configuration to the device

First, get a copy of wpa_supplicant.conf from your device:

    adb pull /system/etc/wifi/wpa_supplicant.conf

Then, add networks to the bottom of the file. Here are some examples:

```
network={
        ssid="Mozilla Guest"
        key_mgmt=NONE
        priority=1
}

network={
        ssid="MozillaAllHands-G"
        key_mgmt=NONE
        priority=2
}

network={
        ssid="PNS Airport"
        key_mgmt=NONE
        priority=3
}

network={
        ssid="some random wpa psk secured network"
        psk="the shared key goes here"
        key_mgmt=WPA-PSK
        priority=4
}
```

And then push the configuration to the right place.

On SGS2:

    adb push wpa_supplicant.conf /data/wifi/bcm_supp.conf

On Maguro/Akami:

    adb push wpa_supplicant.conf /data/misc/wifi/wpa_supplicant.conf

And then restart your device to pick up the changes:

    adb reboot

## Use wpa_cli to scan and configure

This is not recommended. I have never gotten this to work.

However, it should work in theory. So, here it is.

### Starting wpa_cli

Do not run wpa_cli directly from adb.

On SGS2:

    adb shell
    wpa_cli -ieth0 -p/data/misc/wifi

On Maguro/Akami:

    adb shell
    wpa_cli -iwlan0 -p/data/misc/wifi/wpa_supplicant

### Help

Run "help" for a list of commands.

Unfortunately, help is not very helpful, but it is a good place to start.

### Scanning

* "scan" to start a scan.
* "scan_results" to get results from a scan.

### Setting up a network

* "add_network" to make a new network to connect to. This will give you a number, which is the network id. Remember this.
* "list_network" will show you your configured networks
* "set_network [network id] ssid [ssid]" will let you configure your SSID
* "enable_network [network id]" should turn on that network
* "select_network [network id]" or maybe this command does
* "password [network id] [password]" set the password. may or may not work
* "status" is helpful while trying to connect.
