#!/bin/sh

SERIAL=$(cat /sys/firmware/devicetree/base/serial-number)

ID_VENDOR="0x1d6b"
ID_PRODUCT="0x0104"

# Eventually we want to disable the serial interface by default
# As it can be used as a persistence exploitation vector
CONFIGURE_USB_SERIAL=false
CONFIGURE_USB_WEBCAM=true
CONFIGURE_USB_NETWORK=false

USB_NETWORK_FILE=/boot/enable-usb-network
USB_NETWORK_TYPE=ECM
if [ -f "$USB_NETWORK_FILE" ] ; then
  CONFIGURE_USB_NETWORK=true
  _USB_NETWORK_TYPE=$(head -n1 "$USB_NETWORK_FILE")
  case "$_USB_NETWORK_TYPE" in
    RNDIS)
      # Quirk: See https://github.com/RoganDawes/P4wnP1/blob/9c8cc09a6503f10309c04310c3bba9c07caab8b7/boot/init_usb.sh#L150
      ID_PRODUCT="0x0106"
      USB_NETWORK_TYPE=RNDIS
      ;;
    *)
      # Default: ECM
      ;;
  esac
fi

# Now apply settings from the boot config
if [ -f "/boot/enable-serial-debug" ] ; then
  CONFIGURE_USB_SERIAL=true
fi

VIDEO_FORMATS_FILE=/etc/video_formats.txt

# location of video_formats.txt file if overwritten by the user
VIDEO_FORMATS_USER_FILE=/boot/video_formats.txt

# TODO: Needed this sentinel as a workaround
# to enable networking on Windows, for now.
if [ -f "/boot/disable-webcam" ] ; then
  echo "Disabling usb webcam functionalities"
  CONFIGURE_USB_WEBCAM=false
fi

config_usb_network_rndis () {
  mkdir -p functions/rndis.usb0
  echo "$1" > functions/rndis.usb0/host_addr
  echo "$2" > functions/rndis.usb0/dev_addr

  mkdir -p os_desc
  echo "1"        > os_desc/use
  echo "0xbc"     > os_desc/b_vendor_code
  echo "MSFT100"  > os_desc/qw_sign

  mkdir -p functions/rndis.usb0/os_desc/interface.rndis
  echo "RNDIS"    > functions/rndis.usb0/os_desc/interface.rndis/compatible_id
  echo ""         > functions/rndis.usb0/os_desc/interface.rndis/sub_compatible_id

  ln -s functions/rndis.usb0 configs/c.1/
}

postconfig_usb_network_rndis () {
  # This has to be done last after all the usb configs have been set up
  ln -s configs/c.1/ os_desc
}

config_usb_network_ecm () {
  mkdir -p functions/ecm.usb0
  echo "$1" > functions/ecm.usb0/host_addr
  echo "$2" > functions/ecm.usb0/dev_addr
  ln -s functions/ecm.usb0 configs/c.1/
}

config_usb_network () {
  MAC_PREFIX_PI="ca:ff" # No one has taken this prefix yet
  MAC_PREFIX_HOST="ca:fe" # No one has taken this prefix yet
  MAC_SUFFIX=$(echo "${SERIAL}" | sed 's/\(\w\w\)/:\1/g' | cut -b 7-)
  MAC_HOST="${MAC_PREFIX_HOST}${MAC_SUFFIX}" # Mac address for host PC
  MAC_PI="${MAC_PREFIX_PI}${MAC_SUFFIX}" # MAC address for PiCam

  case "$USB_NETWORK_TYPE" in
    RNDIS)
      config_usb_network_rndis "$MAC_HOST" "$MAC_PI"
      ;;
    ECM)
      config_usb_network_ecm "$MAC_HOST" "$MAC_PI"
      ;;
    *)
      echo "Sorry, $USB_NETWORK_TYPE is not a valid USB Network type"
      ;;
  esac
}

config_usb_serial () {
  mkdir -p functions/acm.usb0
  ln -s functions/acm.usb0 configs/c.1/acm.usb0
}


config_frame () {
  FORMAT=$1
  NAME=$2
  WIDTH=$3
  HEIGHT=$4

  FRAMEDIR="functions/uvc.usb0/streaming/$FORMAT/$NAME/${HEIGHT}p"

  mkdir -p "$FRAMEDIR"

  echo "$WIDTH"                    > "$FRAMEDIR"/wWidth
  echo "$HEIGHT"                   > "$FRAMEDIR"/wHeight
  echo 333333                      > "$FRAMEDIR"/dwDefaultFrameInterval
  echo $((WIDTH * HEIGHT * 80))    > "$FRAMEDIR"/dwMinBitRate
  echo $((WIDTH * HEIGHT * 160))   > "$FRAMEDIR"/dwMaxBitRate
  echo $((WIDTH * HEIGHT * 2))     > "$FRAMEDIR"/dwMaxVideoFrameBufferSize
  cat <<EOF > "$FRAMEDIR"/dwFrameInterval
333333
400000
666666
EOF
}

config_usb_webcam () {
  mkdir -p functions/uvc.usb0/control/header/h

  if [ -r $VIDEO_FORMATS_USER_FILE ] ; then
    FORMATS_FILE=$VIDEO_FORMATS_USER_FILE
  else
    FORMATS_FILE=$VIDEO_FORMATS_FILE
  fi

  grep -E "^(mjpeg|uncompressed)[[:space:]]+[[:digit:]]+[[:space:]]+[[:digit:]]+" $FORMATS_FILE | while read -r line
  do
    VIDEO_FORMAT=$(echo "$line" | awk '{print $1}')
    HDR_DESC=$(echo "$VIDEO_FORMAT" | cut -c 1)
    X=$(echo "$line" | awk '{print ($2+0)}')
    Y=$(echo "$line" | awk '{print ($3+0)}')
    echo "Enabling video format ${X}x${Y} ($VIDEO_FORMAT)"
    config_frame "$VIDEO_FORMAT" "$HDR_DESC" "$X" "$Y"
  done

  mkdir -p functions/uvc.usb0/streaming/header/h
  ln -s functions/uvc.usb0/streaming/mjpeg/m        functions/uvc.usb0/streaming/header/h
  # ln -s functions/uvc.usb0/streaming/uncompressed/u functions/uvc.usb0/streaming/header/h # Not working !
  ln -s functions/uvc.usb0/streaming/header/h       functions/uvc.usb0/streaming/class/fs
  ln -s functions/uvc.usb0/streaming/header/h       functions/uvc.usb0/streaming/class/hs
  ln -s functions/uvc.usb0/control/header/h         functions/uvc.usb0/control/class/fs

  ln -s functions/uvc.usb0 configs/c.1/uvc.usb0
}

config_usb_params () {
  echo "$ID_VENDOR"  > idVendor
  echo "$ID_PRODUCT" > idProduct

  echo 0x0100 > bcdDevice # set device version 1.0.0
  echo 0x0200 > bcdUSB    # set USB mode to USB 2.0


  echo 0xEF > bDeviceClass
  echo 0x02 > bDeviceSubClass
  echo 0x01 > bDeviceProtocol
  #echo 0x40 > bMaxPacketSize0

  mkdir -p strings/0x409
  mkdir -p configs/c.1/strings/0x409

  echo "$SERIAL"                > strings/0x409/serialnumber
  echo "Show-me Webcam Project" > strings/0x409/manufacturer
  echo "Piwebcam"               > strings/0x409/product
  echo 500                      > configs/c.1/MaxPower
  echo "Piwebcam"               > configs/c.1/strings/0x409/configuration
  echo "0x80"                   > configs/c.1/bmAttributes #  USB_OTG_SRP | USB_OTG_HNP
}


CONFIG=/sys/kernel/config/usb_gadget/piwebcam
mkdir -p "$CONFIG"
cd "$CONFIG" || exit 1

# First configure general params
config_usb_params

# Check if camera is installed correctly
if [ ! -e /dev/video0 ] ; then
  echo "I did not detect a camera connected to the Pi. Please check your hardware."
  CONFIGURE_USB_WEBCAM=false
  # Nobody can read the error if we don't have serial enabled!
  CONFIGURE_USB_SERIAL=true
fi

if [ "$CONFIGURE_USB_WEBCAM" = true ] ; then
  echo "Configuring USB gadget webcam interface"
  config_usb_webcam
fi

if [ "$CONFIGURE_USB_NETWORK" = true ] ; then
  echo "Configuring USB gadget network interface ($USB_NETWORK_TYPE)"
  config_usb_network
fi

if [ "$CONFIGURE_USB_SERIAL" = true ] ; then
  echo "Configuring USB gadget serial interface"
  config_usb_serial
fi

# Quirk: Windows requires us to give it os_desc for rndis
if [ "$CONFIGURE_USB_NETWORK" = true ]  && [ "$USB_NETWORK_TYPE" = "RNDIS" ] ; then
  echo "Post-configuring RNDIS USB gadget network interface"
  postconfig_usb_network_rndis
fi

ls /sys/class/udc > UDC

# Ensure any configfs changes are picked up
udevadm settle -t 5 || :
