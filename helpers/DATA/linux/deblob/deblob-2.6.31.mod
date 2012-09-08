#!/bin/sh

#    Copyright (C) 2008, 2009 Alexandre Oliva <lxoliva@fsfla.org>
#    Copyright (C) 2008 Jeff Moe
#    Copyright (C) 2009 Rubén Rodríguez <ruben@gnu.org>
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301 USA


# deblob - remove non-free blobs from the vanilla linux kernel

# http://www.fsfla.org/svn/fsfla/software/linux-libre


# This script, suited for the kernel version named below, in kver,
# attempts to remove only non-Free Software bits, without removing
# Free Software that happens to be in the same file.

# Drivers that currently require non-Free firmware are retained, but
# firmware included in GPLed sources is replaced with /*(DEBLOBBED)*/
# if the deblob-check script, that knows how to do this, is present.
# -lxoliva


# See also:
# http://wiki.debian.org/KernelFirmwareLicensing
# svn://svn.debian.org/kernel/dists/trunk/linux-2.6/debian/patches/debian/dfsg/files-1
# http://svn.gnewsense.svnhopper.net/gnewsense/builder/trunk/firmware/firmware-removed
# http://svn.gnewsense.svnhopper.net/gnewsense/builder/trunk/gen-kernel

# Thanks to Brian Brazil @ gnewsense


# For each kver release, start extra with an empty string, then count
# from 1 if changes are needed that require rebuilding the tarball.
kver=2.6.31 extra=2

filelist="/tmp/filelist"

case $1 in
--force)
  echo "WARNING: Using the force, ignored errors will be" >&2
  die () {
    echo ERROR: "$@" >&2
    errors=:
  }
  forced=: errors=false
  shift
  ;;
*)
  die () {
    echo ERROR: "$@" >&2
    echo Use --force to ignore
    exit 1
  }
  forced=false errors=false
  ;;
esac

check=`echo "$0" | sed 's,[^/]*$,,;s,^$,.,;s,/*$,,'`/deblob-check
if [ ! -f $check ] ; then
  if $forced; then
    die deblob-check script missing, will remove entire files
  else
    die deblob-check script missing
  fi
  have_check=false
else
  have_check=:
fi

filetest () {
        export FILES=$1
        if ! [ -f $1 ]
        then
                if [ $( basename $1) = Makefile ] || [ $( basename $1) = Kconfig ]
                then
                        die File not found: $1
                        return 1
                fi

                file=$( basename $1)
                [ -f $filelist ] || find > $filelist
                if FILES=$(egrep  /$file$ $filelist)
                then
                        die File not found: $1
                        echo WARNING: Alternative\(s\) to $1 found: $FILES
                        echo WARNING: Deblobbing alternative\(s\)
                        return 0
                else
                        die File not found: $1, no alternatives found
                fi
                return 1
        fi
}

announce () {
  echo
  echo "$@"
}

clean_file () {
  #$1 = filename
  filetest $1 || return
  rm $FILES
  echo WARNING: Removing $FILES
}

check_changed () {
  #$1 = filename
  if cmp $1.deblob $1 > /dev/null; then
    rm $1.deblob
    die $1 did not change, something is wrong && return 1
  fi
  mv $1.deblob $1
}

clean_blob () {
  #$1 = filename
  filetest $1 || return
  for FILE in $FILES
  do
    if $have_check; then
      name=$FILE
      set fnord "$@" -d
      shift 2
      $check "$@" -i linux-$kver $name > $name.deblob
      check_changed $name && echo $name: removed blobs
    else
      clean_file $FILE
    fi
  done
}

dummy_blob () {
  #$1 = filename
  if test -f $1; then
    die $1 exists, something is wrong && return
  elif test ! -f firmware/Makefile; then
    die firmware/Makefile does not exist, something is wrong && return
  fi

  clean_sed "s,`echo $1 | sed s,^firmware/,,`,\$(DEBLOBBED),g" \
    firmware/Makefile "dropped $1"
}

clean_fw () {
  #$1 = firmware text input, $2 = firmware output
  filetest $1 || return
  for FILE in $FILES
  do
    if test -f $2; then
      die $2 exists, something is wrong && return
    fi
    clean_blob $FILE -s 4
    dummy_blob $2
  done
}

drop_fw_file () {
  #$1 = firmware text input, $2 = firmware output
  filetest $1 || return
  for FILE in $FILES
  do
    if test -f $2; then
      die $2 exists, something is wrong && return
    fi
    clean_file $FILE
    dummy_blob $2
  done
}

clean_kconfig () {
  #$1 = filename $2 = things to remove
  case $1 in
  -f)
    shift
    ;;
  *)
    if $have_check; then
      return
    fi
    ;;
  esac
  filetest $1 || return
  for FILE in $FILES
  do
    sed "/^config \\($2\\)\$/{p;i\
	depends on NONFREE
d;}" $FILE > $FILE.deblob
    check_changed $FILE && echo $FILE: marked config $2 as depending on NONFREE
  done
}

clean_mk () {
  #$1 = config $2 = Makefile name
  # We don't clean up Makefiles any more --lxoliva
  # sed -i "/\\($1\\)/d" $2
  # echo $2: removed $1 support
  # check_changed $2
  filetest $2 || return
  if sed -n "/\\($1\\)/p" $2 | grep . > /dev/null; then
    :
  else
    die $2 does not contain matches for $1
  fi
}

clean_sed () {
  #$1 = sed-script $2 = file $3 = comment
  filetest $2 || return
  for FILE in $FILES
  do
    sed -e "$1" "$FILE" > "$FILE".deblob || {
      die $2: failed: ${3-applied sed script $1} && return 1; }
    check_changed $FILE && echo $FILE: ${3-applied sed script $1} 
  done
}

reject_firmware () {
  #$1 = file
  filetest $1 || return
  for FILE in $FILES
  do
    clean_sed '
s,request\(_ihex\)\?_firmware\(_nowait\)\?,reject_firmware\2,g
' "$FILE" 'disabled non-Free firmware-loading machinery'
  done
}

maybe_reject_firmware () {
  #$1 = file
  filetest $1 || return
  for FILE in $FILES
  do
    clean_sed '
s,request_firmware\(_nowait\)\?,maybe_reject_firmware\1,g
' "$FILE" 'retain Free firmware-loading machinery, disabling non-Free one'
  done
}

undefine_macro () {
  #$1 - macro name
  #$2 - substitution
  #$3 - message
  #rest - file names
  macro=$1 repl=$2 msg=$3; shift 3
  for f in "$@"; do
    clean_sed "
s,^#define $macro .*\$,/*(DEBLOBBED)*/,;
s,$macro,$repl,g;
" "$f" "$msg"
  done
}

undefault_firmware () {
  #$1 - pattern such that $1_DEFAULT_FIRMWARE is #defined to non-Free firmware
  #$@ other than $1 - file names
  macro="$1"_DEFAULT_FIRMWARE; shift
  undefine_macro "$macro" "\"/*(DEBLOBBED)*/\"" \
    "disabled non-Free firmware" "$@"
}

# First, check that files that contain firmwares and their
# corresponding sources are present.

for f in \
  drivers/char/ser_a2232fw.h \
    drivers/char/ser_a2232fw.ax \
  drivers/net/ixp2000/ixp2400_rx.ucode \
    drivers/net/ixp2000/ixp2400_rx.uc \
  drivers/net/ixp2000/ixp2400_tx.ucode \
    drivers/net/ixp2000/ixp2400_rx.uc \
  drivers/net/wan/wanxlfw.inc_shipped \
    drivers/net/wan/wanxlfw.S \
  drivers/net/wireless/atmel.c \
    drivers/net/wireless/atmel.c \
  drivers/scsi/53c700_d.h_shipped \
    drivers/scsi/53c700.scr \
  drivers/scsi/aic7xxx/aic79xx_seq.h_shipped \
    drivers/scsi/aic7xxx/aic79xx.seq \
  drivers/scsi/aic7xxx/aic7xxx_seq.h_shipped \
    drivers/scsi/aic7xxx/aic7xxx.seq \
  drivers/scsi/aic7xxx_old/aic7xxx_seq.c \
    drivers/scsi/aic7xxx_old/aic7xxx.seq \
  drivers/scsi/53c7xx_d.h_shipped \
    drivers/scsi/53c7xx.scr \
  drivers/scsi/sym53c8xx_2/sym_fw1.h \
    drivers/scsi/sym53c8xx_2/sym_fw1.h \
  drivers/scsi/sym53c8xx_2/sym_fw2.h \
    drivers/scsi/sym53c8xx_2/sym_fw2.h \
  firmware/dsp56k/bootstrap.bin.ihex \
    firmware/dsp56k/bootstrap.asm \
  firmware/keyspan_pda/keyspan_pda.HEX \
    firmware/keyspan_pda/keyspan_pda.S \
  firmware/keyspan_pda/xircom_pgs.HEX \
    firmware/keyspan_pda/xircom_pgs.S \
  sound/pci/cs46xx/imgs/cwcdma.h \
    sound/pci/cs46xx/imgs/cwcdma.asp \
; do
  if test ! $f; then
    die $f is not present, something is amiss && return
  fi
done

# Identify the tarball.
grep -q 'EXTRAVERSION.*-libre' Makefile ||
clean_sed "s,^EXTRAVERSION.*,&-libre$extra,
" Makefile 'added -libre to EXTRAVERSION'

# Add reject_firmware and maybe_reject_firmware
grep -q _LINUX_LIBRE_FIRMWARE_H include/linux/firmware.h ||
clean_sed '$i\
#ifndef _LINUX_LIBRE_FIRMWARE_H\
#define _LINUX_LIBRE_FIRMWARE_H\
\
#include <linux/device.h>\
\
#define NONFREE_FIRMWARE "/*(DEBLOBBED)*/"\
\
static inline int\
report_missing_free_firmware(const char *name, const char *what)\
{\
	printk(KERN_ERR "%s: Missing Free %s\\n", name,\
	       what ? what : "firmware");\
	return -EINVAL;\
}\
static inline int\
reject_firmware(const struct firmware **fw,\
		const char *name, struct device *device)\
{\
	const struct firmware *xfw = NULL;\
	int retval;\
	report_missing_free_firmware(dev_name(device), NULL);\
	retval = request_firmware(&xfw, NONFREE_FIRMWARE, device);\
	if (!retval)\
		release_firmware(xfw);\
	return -EINVAL;\
}\
static inline int\
maybe_reject_firmware(const struct firmware **fw,\
		      const char *name, struct device *device)\
{\
	if (strstr (name, NONFREE_FIRMWARE))\
		return reject_firmware(fw, name, device);\
	else\
		return request_firmware(fw, name, device);\
}\
static inline void\
discard_rejected_firmware(const struct firmware *fw, void *context)\
{\
	release_firmware(fw);\
}\
static inline int\
reject_firmware_nowait(struct module *module, int uevent,\
		       const char *name, struct device *device,\
		       void *context,\
		       void (*cont)(const struct firmware *fw,\
				    void *context))\
{\
	int retval;\
	report_missing_free_firmware(dev_name(device), NULL);\
	retval = request_firmware_nowait(module, uevent, NONFREE_FIRMWARE,\
					 device, NULL,\
					 discard_rejected_firmware);\
	if (retval)\
		return retval;\
	return -EINVAL;\
}\
static inline int\
maybe_reject_firmware_nowait(struct module *module, int uevent,\
			     const char *name, struct device *device,\
			     void *context,\
			     void (*cont)(const struct firmware *fw,\
					  void *context))\
{\
	if (strstr (name, NONFREE_FIRMWARE))\
		return reject_firmware_nowait(module, uevent, name,\
					      device, context, cont);\
	else\
		return request_firmware_nowait(module, uevent, name,\
					       device, context, cont);\
}\
\
#endif /* _LINUX_LIBRE_FIRMWARE_H */\
' include/linux/firmware.h 'added non-Free firmware notification support'

########
# Arch #
########

# x86

announce MICROCODE_AMD - "AMD microcode patch loading support"
reject_firmware arch/x86/kernel/microcode_amd.c
clean_blob arch/x86/kernel/microcode_amd.c
clean_kconfig arch/x86/Kconfig 'MICROCODE_AMD'
clean_mk CONFIG_MICROCODE_AMD arch/x86/kernel/Makefile

announce MICROCODE_INTEL - "Intel microcode patch loading support"
reject_firmware arch/x86/kernel/microcode_intel.c
clean_blob arch/x86/kernel/microcode_intel.c
clean_kconfig arch/x86/Kconfig 'MICROCODE_INTEL'
clean_mk CONFIG_MICROCODE_INTEL arch/x86/kernel/Makefile

# arm

announce IXP4XX_NPE - "IXP4xx Network Processor Engine support"
reject_firmware arch/arm/mach-ixp4xx/ixp4xx_npe.c
clean_blob Documentation/arm/IXP4xx

announce ARCH_NETX - "Hilscher NetX based"
clean_sed '
s,\([" ]\)request_firmware(,\1reject_firmware(,
' arch/arm/mach-netx/xc.c 'disabled non-Free firmware-loading machinery'
clean_blob arch/arm/mach-netx/xc.c
clean_kconfig arch/arm/Kconfig 'ARCH_NETX'
clean_mk CONFIG_ARCH_NETX arch/arm/Makefile

###########
# Chipset #
###########

announce STLC45XX - "stlc4550/4560 chipset support"
reject_firmware drivers/staging/stlc45xx/stlc45xx.c
clean_blob drivers/staging/stlc45xx/stlc45xx.c
clean_kconfig drivers/staging/stlc45xx/Kconfig 'STLC45XX'
clean_mk CONFIG_STLC45XX drivers/staging/stlc45xx/Makefile

#######
# ATM #
#######

announce ATM_AMBASSADOR - "Madge Ambassador, Collage PCI 155 Server"
reject_firmware drivers/atm/ambassador.c
clean_blob drivers/atm/ambassador.c
clean_fw firmware/atmsar11.HEX firmware/atmsar11.fw
clean_kconfig drivers/atm/Kconfig 'ATM_AMBASSADOR'
clean_mk CONFIG_ATM_AMBASSADOR drivers/atm/Makefile

announce ATM_FORE200E - "FORE Systems 200E-series"
reject_firmware drivers/atm/fore200e.c
clean_blob drivers/atm/fore200e.c
clean_blob Documentation/networking/fore200e.txt
clean_blob drivers/atm/.gitignore
clean_blob Documentation/dontdiff
clean_kconfig drivers/atm/Kconfig 'ATM_FORE200E'
clean_mk CONFIG_ATM_FORE200E drivers/atm/Makefile

announce ATM_SOLOS - "Solos ADSL2+ PCI Multiport card driver"
reject_firmware drivers/atm/solos-pci.c
clean_blob drivers/atm/solos-pci.c
clean_kconfig drivers/atm/Kconfig 'ATM_SOLOS'
clean_mk CONFIG_ATM_SOLOS drivers/atm/Makefile

########
# char #
########

announce COMPUTONE - "Computone IntelliPort Plus serial"
drop_fw_file firmware/intelliport2.bin.ihex firmware/intelliport2.bin
reject_firmware drivers/char/ip2/ip2main.c
clean_blob drivers/char/ip2/ip2main.c
clean_kconfig drivers/char/Kconfig 'COMPUTONE'
clean_mk CONFIG_COMPUTONE drivers/char/Makefile

announce CYCLADES - "Cyclades async mux support"
reject_firmware drivers/char/cyclades.c
clean_blob drivers/char/cyclades.c
clean_kconfig drivers/char/Kconfig 'CYCLADES'
clean_mk CONFIG_CYCLADES drivers/char/Makefile

announce ISI - "Multi-Tech multiport card support"
reject_firmware drivers/char/isicom.c
clean_blob drivers/char/isicom.c
clean_kconfig drivers/char/Kconfig 'ISI'
clean_mk CONFIG_ISI drivers/char/Makefile

announce MOXA_INTELLIO - "Moxa Intellio support"
reject_firmware drivers/char/moxa.c
clean_blob drivers/char/moxa.c
clean_kconfig drivers/char/Kconfig 'MOXA_INTELLIO'
clean_mk CONFIG_MOXA_INTELLIO drivers/char/Makefile

# gpu drm

announce DRM_MGA - "Matrox g200/g400"
clean_blob drivers/gpu/drm/mga/mga_ucode.h
clean_blob drivers/gpu/drm/mga/mga_warp.c
clean_kconfig -f drivers/gpu/drm/Kconfig 'DRM_MGA'
clean_mk CONFIG_DRM_MGA drivers/gpu/drm/Makefile

announce DRM_R128 - "ATI Rage 128"
clean_sed '
/^static void r128_cce_load_microcode(drm_r128_private_t \* dev_priv)/i\
#define r128_cce_load_microcode(dev_priv) \\\
  do { \\\
    DRM_ERROR("Missing Free microcode!\\n"); \\\
    dev->dev_private = (void *)dev_priv; \\\
    r128_do_cleanup_cce(dev); \\\
    return -EINVAL; \\\
  } while (0)
' drivers/gpu/drm/r128/r128_cce.c 'report missing Free microcode'
clean_blob drivers/gpu/drm/r128/r128_cce.c
clean_kconfig -f drivers/gpu/drm/Kconfig 'DRM_R128'
clean_mk CONFIG_DRM_R128 drivers/gpu/drm/Makefile

announce DRM_RADEON - "ATI Radeon"
clean_sed '
/^static void radeon_cp_load_microcode(drm_radeon_private_t \* dev_priv)/i\
#define radeon_cp_load_microcode(dev_priv) \\\
  do { \\\
    DRM_ERROR("Missing Free microcode!\\n"); \\\
    radeon_do_cleanup_cp(dev); \\\
    return -EINVAL; \\\
  } while (0)
' drivers/gpu/drm/radeon/radeon_cp.c 'report missing Free microcode'
clean_blob drivers/gpu/drm/radeon/radeon_cp.c
clean_blob drivers/gpu/drm/radeon/radeon_microcode.h
clean_sed '
/^static void r100_cp_load_microcode(struct radeon_device \*rdev)/i\
#define r100_cp_load_microcode(rdev) \\\
  do { \\\
    DRM_ERROR("Missing Free microcode!\\n"); \\\
    return -EINVAL; \\\
  } while (0)
' drivers/gpu/drm/radeon/r100.c 'report missing Free microcode'
clean_blob drivers/gpu/drm/radeon/r100.c
clean_sed '
/^static void r600_cp_load_microcode(drm_radeon_private_t \*dev_priv)/i\
#define r600_cp_load_microcode(dev_priv) \\\
  do { \\\
    DRM_ERROR("Missing Free microcode!\\n"); \\\
    r600_do_cleanup_cp(dev); \\\
    return -EINVAL; \\\
  } while (0)
' drivers/gpu/drm/radeon/r600_cp.c 'report missing Free r600 microcode'
clean_sed '
/^static void r700_cp_load_microcode(drm_radeon_private_t \*dev_priv)/i\
#define r700_cp_load_microcode(dev_priv) \\\
  do { \\\
    DRM_ERROR("Missing Free microcode!\\n"); \\\
    r600_do_cleanup_cp(dev); \\\
    return -EINVAL; \\\
  } while (0)
' drivers/gpu/drm/radeon/r600_cp.c 'report missing Free r700 microcode'
clean_blob drivers/gpu/drm/radeon/r600_cp.c
clean_blob drivers/gpu/drm/radeon/r600_microcode.h
clean_kconfig -f drivers/gpu/drm/Kconfig 'DRM_RADEON'
clean_mk CONFIG_DRM_RADEON drivers/gpu/drm/Makefile


#########
# Media #
#########

# media/tuner

announce MEDIA_TUNER_XC2028 - "XCeive xc2028/xc3028 tuners"
undefault_firmware 'XC\(2028\|3028L\)' \
  drivers/media/common/tuners/tuner-xc2028.h \
  drivers/media/video/saa7134/saa7134-cards.c \
  drivers/media/video/ivtv/ivtv-driver.c \
  drivers/media/video/cx18/cx18-driver.c \
  drivers/media/video/cx18/cx18-dvb.c \
  drivers/media/video/cx23885/cx23885-dvb.c \
  drivers/media/video/cx88/cx88-dvb.c \
  drivers/media/video/cx88/cx88-cards.c \
  drivers/media/video/em28xx/em28xx-cards.c \
  drivers/media/dvb/dvb-usb/dib0700_devices.c \
  drivers/media/dvb/dvb-usb/cxusb.c
reject_firmware drivers/media/common/tuners/tuner-xc2028.c
clean_kconfig drivers/media/common/tuners/Kconfig 'MEDIA_TUNER_XC2028'
clean_mk CONFIG_MEDIA_TUNER_XC2028 drivers/media/common/tuners/Makefile

announce MEDIA_TUNER_XC5000 - "Xceive XC5000 silicon tuner"
undefine_macro 'XC5000_DEFAULT_FIRMWARE_SIZE' 0 \
  'removed non-Free firmware size' drivers/media/common/tuners/xc5000.c
undefault_firmware 'XC5000' \
  drivers/media/common/tuners/xc5000.c \
  drivers/media/video/cx231xx/cx231xx-cards.c
reject_firmware drivers/media/common/tuners/xc5000.c
clean_kconfig drivers/media/common/tuners/Kconfig 'MEDIA_TUNER_XC5000'
clean_mk CONFIG_MEDIA_TUNER_XC5000 drivers/media/common/tuners/Makefile

announce DVB_USB - "Support for various USB DVB devices"
reject_firmware drivers/media/dvb/dvb-usb/dvb-usb-firmware.c
clean_kconfig drivers/media/dvb/dvb-usb/Kconfig 'DVB_USB'
clean_mk CONFIG_DVB_USB drivers/media/dvb/dvb-usb/Makefile

announce DVB_USB_AF9005 - "Afatech AF9005 DVB-T USB1.1"
clean_file drivers/media/dvb/dvb-usb/af9005-script.h
clean_sed '
s,^	deb_info("load init script\\n");$,	{\n		err("Missing Free init script\\n");\n		return scriptlen = ret = -EINVAL;\n		,;
' drivers/media/dvb/dvb-usb/af9005-fe.c 'report missing Free init script'
clean_blob drivers/media/dvb/dvb-usb/af9005-fe.c
clean_kconfig drivers/media/dvb/dvb-usb/Kconfig 'DVB_USB_AF9005'
clean_mk CONFIG_DVB_USB_AF9005 drivers/media/dvb/dvb-usb/Makefile

announce DVB_B2C2_FLEXCOP - "Technisat/B2C2 FlexCopII(b) and FlexCopIII adapters"
reject_firmware drivers/media/dvb/b2c2/flexcop-fe-tuner.c

announce DVB_BT8XX - "BT8xx based PCI cards"
reject_firmware drivers/media/dvb/bt8xx/dvb-bt8xx.c

announce DVB_USB_A800 - "AVerMedia AverTV DVB-T USB 2.0 (A800)"
clean_blob drivers/media/dvb/dvb-usb/a800.c
clean_kconfig drivers/media/dvb/dvb-usb/Kconfig 'DVB_USB_A800'
clean_mk CONFIG_DVB_USB_A800 drivers/media/dvb/dvb-usb/Makefile

announce DVB_USB_AF9005 - "Afatech AF9005 DVB-T USB1.1 support"
clean_blob drivers/media/dvb/dvb-usb/af9005.c
clean_kconfig drivers/media/dvb/dvb-usb/Kconfig 'DVB_USB_AF9005'
clean_mk CONFIG_DVB_USB_AF9005 drivers/media/dvb/dvb-usb/Makefile

announce DVB_USB_AF9015 - "Afatech AF9015 DVB-T USB2.0 support"
clean_blob drivers/media/dvb/dvb-usb/af9015.c
clean_kconfig drivers/media/dvb/dvb-usb/Kconfig 'DVB_USB_AF9015'
clean_mk CONFIG_DVB_USB_AF9015 drivers/media/dvb/dvb-usb/Makefile

announce DVB_USB_CXUSB - "Conexant USB2.0 hybrid reference design support"
clean_blob drivers/media/dvb/dvb-usb/cxusb.c
clean_kconfig drivers/media/dvb/dvb-usb/Kconfig 'DVB_USB_CXUSB'
clean_mk CONFIG_DVB_USB_CXUSB drivers/media/dvb/dvb-usb/Makefile

announce DVB_USB_DIB0700 - "DiBcom DiB0700 USB DVB devices"
clean_blob drivers/media/dvb/dvb-usb/dib0700_devices.c
clean_kconfig drivers/media/dvb/dvb-usb/Kconfig 'DVB_USB_DIB0700'
clean_mk CONFIG_DVB_USB_DIB0700 drivers/media/dvb/dvb-usb/Makefile

announce DVB_USB_DIBUSB_MB - "DiBcom USB DVB-T devices (based on the DiB3000M-B)"
clean_blob drivers/media/dvb/dvb-usb/dibusb-mb.c
clean_kconfig drivers/media/dvb/dvb-usb/Kconfig 'DVB_USB_DIBUSB_MB'
clean_mk CONFIG_DVB_USB_DIBUSB_MB drivers/media/dvb/dvb-usb/Makefile

announce DVB_USB_DIBUSB_MC - "DiBcom USB DVB-T devices (based on the DiB3000M-C/P)"
clean_blob drivers/media/dvb/dvb-usb/dibusb-mc.c
clean_kconfig drivers/media/dvb/dvb-usb/Kconfig 'DVB_USB_DIBUSB_MC'
clean_mk CONFIG_DVB_USB_DIBUSB_MC drivers/media/dvb/dvb-usb/Makefile

announce DVB_USB_DIGITV - "Nebula Electronics uDigiTV DVB-T USB2.0 support"
clean_blob drivers/media/dvb/dvb-usb/digitv.c
clean_kconfig drivers/media/dvb/dvb-usb/Kconfig 'DVB_USB_DIGITV'
clean_mk CONFIG_DVB_USB_DIGITV drivers/media/dvb/dvb-usb/Makefile

announce DVB_USB_DTT200U - "WideView WT-200U and WT-220U (pen) DVB-T USB2.0 support (Yakumo/Hama/Typhoon/Yuan)"
clean_blob drivers/media/dvb/dvb-usb/dtt200u.c
clean_kconfig drivers/media/dvb/dvb-usb/Kconfig 'DVB_USB_DTT200U'
clean_mk CONFIG_DVB_USB_DTT200U drivers/media/dvb/dvb-usb/Makefile

announce DVB_USB_DW2102 - "DvbWorld DVB-S/S2 USB2.0 support"
reject_firmware drivers/media/dvb/dvb-usb/dw2102.c
clean_blob drivers/media/dvb/dvb-usb/dw2102.c
clean_kconfig drivers/media/dvb/dvb-usb/Kconfig 'DVB_USB_DW2102'
clean_mk CONFIG_DVB_USB_DW2102 drivers/media/dvb/dvb-usb/Makefile

announce DVB_USB_GP8PSK - "GENPIX 8PSK->USB module support"
reject_firmware drivers/media/dvb/dvb-usb/gp8psk.c
clean_blob drivers/media/dvb/dvb-usb/gp8psk.c
clean_kconfig drivers/media/dvb/dvb-usb/Kconfig 'DVB_USB_GP8PSK'
clean_mk CONFIG_DVB_USB_GP8PSK drivers/media/dvb/dvb-usb/Makefile

announce DVB_USB_M920X - "Uli m920x DVB-T USB2.0 support"
reject_firmware drivers/media/dvb/dvb-usb/m920x.c
clean_blob drivers/media/dvb/dvb-usb/m920x.c
clean_kconfig drivers/media/dvb/dvb-usb/Kconfig 'DVB_USB_M920X'
clean_mk CONFIG_DVB_USB_M920X drivers/media/dvb/dvb-usb/Makefile

announce DVB_USB_NOVA_T_USB2 - "Hauppauge WinTV-NOVA-T usb2 DVB-T USB2.0 support"
clean_blob drivers/media/dvb/dvb-usb/nova-t-usb2.c
clean_kconfig drivers/media/dvb/dvb-usb/Kconfig 'DVB_USB_NOVA_T_USB2'
clean_mk CONFIG_DVB_USB_NOVA_T_USB2 drivers/media/dvb/dvb-usb/Makefile

announce DVB_USB_OPERA1 - "Opera1 DVB-S USB2.0 receiver"
reject_firmware drivers/media/dvb/dvb-usb/opera1.c
clean_blob drivers/media/dvb/dvb-usb/opera1.c
clean_kconfig drivers/media/dvb/dvb-usb/Kconfig 'DVB_USB_OPERA1'
clean_mk CONFIG_DVB_USB_OPERA1 drivers/media/dvb/dvb-usb/Makefile

announce DVB_USB_TTUSB2 - "Pinnacle 400e DVB-S USB2.0 support"
clean_blob drivers/media/dvb/dvb-usb/ttusb2.c
clean_kconfig drivers/media/dvb/dvb-usb/Kconfig 'DVB_USB_TTUSB2'
clean_mk CONFIG_DVB_USB_TTUSB2 drivers/media/dvb/dvb-usb/Makefile

announce DVB_USB_UMT_010 - "HanfTek UMT-010 DVB-T USB2.0 support"
clean_blob drivers/media/dvb/dvb-usb/umt-010.c
clean_kconfig drivers/media/dvb/dvb-usb/Kconfig 'DVB_USB_UMT_010'
clean_mk CONFIG_DVB_USB_UMT_010 drivers/media/dvb/dvb-usb/Makefile

announce DVB_USB_VP702X - "TwinhanDTV StarBox and clones DVB-S USB2.0 support"
clean_blob drivers/media/dvb/dvb-usb/vp702x.c
clean_kconfig drivers/media/dvb/dvb-usb/Kconfig 'DVB_USB_VP702X'
clean_mk CONFIG_DVB_USB_VP702X drivers/media/dvb/dvb-usb/Makefile

announce DVB_USB_VP7045 - "TwinhanDTV Alpha/MagicBoxII, DNTV tinyUSB2, Beetle USB2.0 support"
clean_blob drivers/media/dvb/dvb-usb/vp7045.c
clean_kconfig drivers/media/dvb/dvb-usb/Kconfig 'DVB_USB_VP7045'
clean_mk CONFIG_DVB_USB_VP7045 drivers/media/dvb/dvb-usb/Makefile

# dvb/frontends

announce DVB_AF9013 - "Afatech AF9013 demodulator"
undefault_firmware 'AF9013' \
  drivers/media/dvb/frontends/af9013.c \
  drivers/media/dvb/frontends/af9013_priv.h
reject_firmware drivers/media/dvb/frontends/af9013.c
clean_kconfig drivers/media/dvb/frontends/Kconfig 'DVB_AF9013'
clean_mk CONFIG_DVB_AF9013 drivers/media/dvb/frontends/Makefile

announce DVB_BCM3510 - "Broadcom BCM3510"
undefault_firmware 'BCM3510' drivers/media/dvb/frontends/bcm3510.c
reject_firmware drivers/media/dvb/frontends/bcm3510.c
reject_firmware drivers/media/dvb/frontends/bcm3510.h
clean_sed '
/You.ll need a firmware/,/dvb-fe-bcm/d;
' drivers/media/dvb/frontends/bcm3510.c \
  "removed non-Free firmware notes"
clean_kconfig drivers/media/dvb/frontends/Kconfig 'DVB_BCM3510'
clean_mk CONFIG_DVB_BCM3510 drivers/media/dvb/frontends/Makefile

announce DVB_NXT200X - "NxtWave Communications NXT2002/NXT2004 based"
undefault_firmware 'NXT200[24]' drivers/media/dvb/frontends/nxt200x.c
reject_firmware drivers/media/dvb/frontends/nxt200x.c
clean_blob drivers/media/dvb/frontends/nxt200x.c
clean_kconfig drivers/media/dvb/frontends/Kconfig 'DVB_NXT200X'
clean_mk CONFIG_DVB_NXT200X drivers/media/dvb/frontends/Makefile

announce DVB_OR51132 - "Oren OR51132 based"
reject_firmware drivers/media/dvb/frontends/or51132.c
clean_blob drivers/media/dvb/frontends/or51132.c
clean_kconfig drivers/media/dvb/frontends/Kconfig 'DVB_OR51132'
clean_mk CONFIG_DVB_OR51132 drivers/media/dvb/frontends/Makefile

announce DVB_OR51211 - "Oren OR51211 based"
undefault_firmware 'OR51211' drivers/media/dvb/frontends/or51211.c
reject_firmware drivers/media/dvb/frontends/or51211.c
reject_firmware drivers/media/dvb/frontends/or51211.h
clean_blob drivers/media/dvb/frontends/or51211.c
clean_kconfig drivers/media/dvb/frontends/Kconfig 'DVB_OR51211'
clean_mk CONFIG_DVB_OR51211 drivers/media/dvb/frontends/Makefile

announce DVB_SP8870 - "Spase sp8870"
undefault_firmware 'SP8870' drivers/media/dvb/frontends/sp8870.c
reject_firmware drivers/media/dvb/frontends/sp8870.c
reject_firmware drivers/media/dvb/frontends/sp8870.h
clean_blob drivers/media/dvb/frontends/sp8870.c
clean_kconfig drivers/media/dvb/frontends 'DVB_SP8870'
clean_mk CONFIG_DVB_SP8870 drivers/media/dvb/frontends/Makefile

announce DVB_CX24116 - "Conexant CX24116 based"
undefault_firmware CX24116 drivers/media/dvb/frontends/cx24116.c
reject_firmware drivers/media/dvb/frontends/cx24116.c
clean_kconfig drivers/media/dvb/frontends/Kconfig 'DVB_CX24116'
clean_mk CONFIG_DVB_CX24116 drivers/media/dvb/frontends/Makefile

announce DVB_SP887X - "Spase sp887x based"
undefault_firmware 'SP887X' drivers/media/dvb/frontends/sp887x.c
reject_firmware drivers/media/dvb/frontends/sp887x.c
reject_firmware drivers/media/dvb/frontends/sp887x.h
clean_blob drivers/media/dvb/frontends/sp887x.c
clean_kconfig drivers/media/dvb/frontends/Kconfig 'DVB_SP887X'
clean_mk CONFIG_DVB_SP887X drivers/media/dvb/frontends/Makefile

announce DVB_TDA10048 - "Philips TDA10048HN based"
undefine_macro 'TDA10048_DEFAULT_FIRMWARE_SIZE' 0 \
  'removed non-Free firmware size' drivers/media/dvb/frontends/tda10048.c
undefault_firmware 'TDA10048' drivers/media/dvb/frontends/tda10048.c
reject_firmware drivers/media/dvb/frontends/tda10048.c
clean_kconfig drivers/media/dvb/frontends/Kconfig 'DVB_TDA10048'
clean_mk CONFIG_DVB_TDA10048 drivers/media/dvb/frontends/Makefile

announce DVB_TDA1004X - "Philips TDA10045H/TDA10046H"
undefault_firmware 'TDA1004[56]' drivers/media/dvb/frontends/tda1004x.c
reject_firmware drivers/media/dvb/frontends/tda1004x.c
reject_firmware drivers/media/dvb/frontends/tda1004x.h
clean_blob drivers/media/dvb/frontends/tda1004x.c
clean_kconfig drivers/media/dvb/frontends 'DVB_TDA1004X'
clean_mk CONFIG_DVB_TDA1004X drivers/media/dvb/frontends/Makefile

# dvb

announce DVB_AV7110 - "AV7110 cards"
reject_firmware drivers/media/dvb/ttpci/av7110.c
clean_blob drivers/media/dvb/ttpci/av7110.c
clean_kconfig drivers/media/dvb/ttpci/Kconfig 'DVB_AV7110'
clean_mk CONFIG_DVB_AV7110 drivers/media/dvb/ttpci/Makefile

announce DVB_BUDGET - "Budget cards"
reject_firmware drivers/media/dvb/ttpci/budget.c
reject_firmware drivers/media/dvb/frontends/tdhd1.h

announce DVB_BUDGET_AV - "Budget cards with analog video inputs"
reject_firmware drivers/media/dvb/ttpci/budget-av.c

announce DVB_BUDGET_CI - "Budget cards with onboard CI connector"
reject_firmware drivers/media/dvb/ttpci/budget-ci.c

announce DVB_DRX397XD - "Micronas DRX3975D/DRX3977D based"
reject_firmware drivers/media/dvb/frontends/drx397xD.c
clean_blob drivers/media/dvb/frontends/drx397xD_fw.h
clean_kconfig drivers/media/dvb/frontends/Kconfig 'DVB_DRX397XD'
clean_mk CONFIG_DVB_DRX397XD drivers/media/dvb/frontends/Makefile

announce DVB_PLUTO2 - "Pluto2 cards"
reject_firmware drivers/media/dvb/pluto2/pluto2.c

announce SMS_SIANO_MDTV - "Siano SMS1xxx based MDTV receiver"
reject_firmware drivers/media/dvb/siano/smscoreapi.c
clean_blob drivers/media/dvb/siano/smscoreapi.c
clean_blob drivers/media/dvb/siano/sms-cards.c
clean_kconfig drivers/media/dvb/siano/Kconfig 'SMS_SIANO_MDTV'
clean_mk CONFIG_SMS_SIANO_MDTV drivers/media/dvb/siano/Makefile

announce SMS_USB_DRV - "Siano's USB interface support"
reject_firmware drivers/media/dvb/siano/smsusb.c
clean_blob drivers/media/dvb/siano/smsusb.c
clean_kconfig drivers/media/dvb/siano/Kconfig 'SMS_USB_DRV'
clean_mk CONFIG_SMS_USB_DRV drivers/media/dvb/siano/Makefile

announce DVB_TTUSB_BUDGET - "Technotrend/Hauppauge Nova-USB devices"
drop_fw_file firmware/ttusb-budget/dspbootcode.bin.ihex firmware/ttusb-budget/dspbootcode.bin
reject_firmware drivers/media/dvb/ttusb-budget/dvb-ttusb-budget.c
clean_blob drivers/media/dvb/ttusb-budget/dvb-ttusb-budget.c
clean_kconfig drivers/media/dvb/ttusb-budget/Kconfig 'DVB_TTUSB_BUDGET'
clean_mk CONFIG_DVB_TTUSB_BUDGET drivers/media/dvb/ttusb-budget/Makefile

announce DVB_TTUSB_DEC - "Technotrend/Hauppauge USB DEC devices"
reject_firmware drivers/media/dvb/ttusb-dec/ttusb_dec.c
clean_blob drivers/media/dvb/ttusb-dec/ttusb_dec.c
clean_kconfig drivers/media/dvb/ttusb-dec/Kconfig 'DVB_TTUSB_DEC'
clean_mk CONFIG_DVB_TTUSB_DEC drivers/media/dvb/ttusb-dec/Makefile

# video

announce VIDEO_BT848 - "BT848 Video For Linux"
reject_firmware drivers/media/video/bt8xx/bttv-cards.c
clean_kconfig drivers/media/video/bt8xx/Kconfig 'VIDEO_BT848'
clean_mk CONFIG_VIDEO_BT848 drivers/media/video/bt8xx/Makefile

announce VIDEO_CPIA2 - "CPiA2 Video For Linux"
clean_fw firmware/cpia2/stv0672_vp4.bin.ihex firmware/cpia2/stv0672_vp4.bin
reject_firmware drivers/media/video/cpia2/cpia2_core.c
clean_blob drivers/media/video/cpia2/cpia2_core.c
clean_kconfig drivers/media/video/cpia2/Kconfig 'VIDEO_CPIA2'
clean_mk CONFIG_VIDEO_CPIA2 drivers/media/video/cpia2/Makefile

announce VIDEO_CX18 - "Conexant cx23418 MPEG encoder support"
reject_firmware drivers/media/video/cx18/cx18-av-firmware.c
reject_firmware drivers/media/video/cx18/cx18-dvb.c
reject_firmware drivers/media/video/cx18/cx18-firmware.c
clean_blob drivers/media/video/cx18/cx18-av-firmware.c
clean_blob drivers/media/video/cx18/cx18-dvb.c
clean_blob drivers/media/video/cx18/cx18-firmware.c
clean_kconfig drivers/media/video/cx18/Kconfig 'VIDEO_CX18'
clean_mk CONFIG_VIDEO_CX18 drivers/media/video/cx18/Makefile

announce VIDEO_CX23885 - "Conexant cx23885 (2388x successor) support"
reject_firmware drivers/media/video/cx23885/cx23885-417.c
clean_blob drivers/media/video/cx23885/cx23885-417.c
clean_kconfig drivers/media/video/cx23885/Kconfig 'VIDEO_CX23885'
clean_mk CONFIG_VIDEO_CX23885 drivers/media/video/cx23885/Makefile

announce VIDEO_CX25840 - "Conexant CX2584x audio/video decoders"
reject_firmware drivers/media/video/cx25840/cx25840-firmware.c
clean_blob drivers/media/video/cx25840/cx25840-firmware.c
clean_kconfig drivers/media/video/cx25840/Kconfig 'VIDEO_CX25840'
clean_mk CONFIG_VIDEO_CX25840 drivers/media/video/cx25840/Makefile

announce VIDEO_CX88_BLACKBIRD - "Blackbird MPEG encoder support (cx2388x + cx23416)"
reject_firmware drivers/media/video/cx88/cx88-blackbird.c
clean_kconfig drivers/media/video/cx88/Kconfig 'VIDEO_CX88_BLACKBIRD'
clean_mk CONFIG_VIDEO_CX88_BLACKBIRD drivers/media/video/cx88/Makefile

announce VIDEO_IVTV - "Conexant cx23416/cx23415 MPEG encoder/decoder support"
reject_firmware drivers/media/video/ivtv/ivtv-firmware.c
clean_blob drivers/media/video/ivtv/ivtv-firmware.c
clean_kconfig drivers/media/video/ivtv/Kconfig 'VIDEO_IVTV'
clean_mk CONFIG_VIDEO_IVTV drivers/media/video/ivtv/Makefile

announce VIDEO_PVRUSB2 - "Hauppauge WinTV-PVR USB2 support"
reject_firmware drivers/media/video/pvrusb2/pvrusb2-hdw.c
clean_blob drivers/media/video/pvrusb2/pvrusb2-devattr.c
clean_kconfig drivers/media/video/pvrusb2/Kconfig 'VIDEO_PVRUSB2'
clean_mk CONFIG_VIDEO_PVRUSB2 drivers/media/video/pvrusb2/Makefile

announce "VIDEO_CX23885, VIDEO_CX88_BLACKBIRD, VIDEO_IVTV, VIDEO_PVRUSB2" - "See above"
clean_blob include/media/cx2341x.h

announce VIDEO_GO7007 - "Go 7007 support"
reject_firmware drivers/staging/go7007/go7007-driver.c
clean_blob drivers/staging/go7007/go7007-driver.c
reject_firmware drivers/staging/go7007/go7007-fw.c
clean_blob drivers/staging/go7007/go7007-usb.c
clean_blob drivers/staging/go7007/saa7134-go7007.c
clean_kconfig drivers/staging/go7007/Kconfig 'VIDEO_GO7007'
clean_mk CONFIG_VIDEO_GO7007 drivers/staging/go7007/Makefile

announce VIDEO_GO7007_USB_S2250_BOARD - "Sensoray 2250/2251 support"
reject_firmware drivers/staging/go7007/s2250-loader.c
clean_blob drivers/staging/go7007/s2250-loader.c
clean_kconfig drivers/staging/go7007/Kconfig 'VIDEO_GO7007_USB_S2250_BOARD'
clean_mk CONFIG_VIDEO_GO7007_USB_S2250_BOARD drivers/staging/go7007/Makefile

announce VIDEO_SAA7134_DVB - "DVB/ATSC Support for saa7134 based TV cards"
reject_firmware drivers/media/video/saa7134/saa7134-dvb.c
clean_kconfig drivers/media/video/saa7134/Kconfig 'VIDEO_SAA7134_DVB'
clean_mk CONFIG_VIDEO_SAA7134_DVB drivers/media/video/saa7134/Makefile

announce USB_DABUSB - "DABUSB driver"
clean_fw firmware/dabusb/bitstream.bin.ihex firmware/dabusb/bitstream.bin
clean_fw firmware/dabusb/firmware.HEX firmware/dabusb/firmware.fw
reject_firmware drivers/media/video/dabusb.c
clean_blob drivers/media/video/dabusb.c
clean_kconfig drivers/media/Kconfig 'USB_DABUSB'
clean_mk CONFIG_USB_DABUSB drivers/media/video/Makefile

announce USB_S2255 - "USB Sensoray 2255 video capture device"
reject_firmware drivers/media/video/s2255drv.c
clean_blob drivers/media/video/s2255drv.c
clean_kconfig drivers/media/video/Kconfig 'USB_S2255'
clean_mk CONFIG_USB_S2255 drivers/media/video/Makefile

announce USB_VICAM - "USB 3com HomeConnect, AKA vicam"
drop_fw_file firmware/vicam/firmware.H16 firmware/vicam/firmware.fw
reject_firmware drivers/media/video/usbvideo/vicam.c
clean_blob drivers/media/video/usbvideo/vicam.c
clean_kconfig drivers/media/video/usbvideo/Kconfig 'USB_VICAM'
clean_mk CONFIG_USB_VICAM drivers/media/video/usbvideo/Makefile


#######
# net #
#######

announce ACENIC - "Alteon AceNIC/3Com 3C985/NetGear GA620 Gigabit"
drop_fw_file firmware/acenic/tg1.bin.ihex firmware/acenic/tg1.bin
drop_fw_file firmware/acenic/tg2.bin.ihex firmware/acenic/tg2.bin
reject_firmware drivers/net/acenic.c
clean_blob drivers/net/acenic.c
clean_kconfig drivers/net/Kconfig 'ACENIC'
clean_mk CONFIG_ACENIC drivers/net/Makefile

announce ADAPTEC_STARFIRE - "Adaptec Starfire/DuraLAN support"
clean_fw firmware/adaptec/starfire_rx.bin.ihex firmware/adaptec/starfire_rx.bin
clean_fw firmware/adaptec/starfire_tx.bin.ihex firmware/adaptec/starfire_tx.bin
reject_firmware drivers/net/starfire.c
clean_blob drivers/net/starfire.c
clean_kconfig drivers/net/Kconfig 'ADAPTEC_STARFIRE'
clean_mk CONFIG_ADAPTEC_STARFIRE drivers/net/Makefile

announce BNX2 - "Broadcom NetXtremeII"
drop_fw_file firmware/bnx2/bnx2-mips-09-4.6.17.fw.ihex firmware/bnx2/bnx2-mips-09-4.6.17.fw
drop_fw_file firmware/bnx2/bnx2-rv2p-09-4.6.15.fw.ihex firmware/bnx2/bnx2-rv2p-09-4.6.15.fw
drop_fw_file firmware/bnx2/bnx2-mips-06-4.6.16.fw.ihex firmware/bnx2/bnx2-mips-06-4.6.16.fw
drop_fw_file firmware/bnx2/bnx2-rv2p-06-4.6.16.fw.ihex firmware/bnx2/bnx2-rv2p-06-4.6.16.fw
reject_firmware drivers/net/bnx2.c
clean_blob drivers/net/bnx2.c
clean_kconfig drivers/net/Kconfig 'BNX2'
clean_mk CONFIG_BNX2 drivers/net/Makefile

announce BNX2X - "Broadcom NetXtremeII 10Gb support"
drop_fw_file firmware/bnx2x-e1-4.8.53.0.fw.ihex firmware/bnx2x-e1-4.8.53.0.fw
drop_fw_file firmware/bnx2x-e1h-4.8.53.0.fw.ihex firmware/bnx2x-e1h-4.8.53.0.fw
reject_firmware drivers/net/bnx2x_main.c
clean_sed '
/^#include "bnx2x_init\.h"/,/^$/{
  /^$/i\
#define bnx2x_init_block(bp, start, end) \\\
  return (printk(KERN_ERR PFX "%s: Missing Free firmware\\n", bp->dev->name),\\\
	  -EINVAL)
}' drivers/net/bnx2x_main.c 'report missing Free firmware'
clean_blob drivers/net/bnx2x_main.c
clean_blob drivers/net/bnx2x_hsi.h
clean_blob drivers/net/bnx2x_init_ops.h
clean_kconfig drivers/net/Kconfig 'BNX2X'
clean_mk CONFIG_BNX2X drivers/net/Makefile

announce CASSINI - "Sun Cassini"
drop_fw_file firmware/sun/cassini.bin.ihex firmware/sun/cassini.bin
reject_firmware drivers/net/cassini.c
clean_blob drivers/net/cassini.c
clean_kconfig drivers/net/Kconfig 'CASSINI'
clean_mk CONFIG_CASSINI drivers/net/Makefile

announce CHELSIO_T3 - "Chelsio AEL 2005 support"
drop_fw_file firmware/cxgb3/t3b_psram-1.1.0.bin.ihex firmware/cxgb3/t3b_psram-1.1.0.bin
drop_fw_file firmware/cxgb3/t3c_psram-1.1.0.bin.ihex firmware/cxgb3/t3c_psram-1.1.0.bin
drop_fw_file firmware/cxgb3/t3fw-7.4.0.bin.ihex firmware/cxgb3/t3fw-7.4.0.bin
reject_firmware drivers/net/cxgb3/cxgb3_main.c
clean_sed '
/^static int ael2005_setup_\(sr\|twinax\)_edc([^;]*$/,/^}$/{
  /for.*ARRAY_SIZE(\(sr\|twinax\)_edc)/i\
	CH_ERR(phy->adapter, "Missing Free firwmare\\n");\
	err = -EINVAL;
}' drivers/net/cxgb3/ael1002.c 'report missing Free firmware'
clean_blob drivers/net/cxgb3/cxgb3_main.c
clean_blob drivers/net/cxgb3/ael1002.c
clean_kconfig drivers/net/Kconfig 'CHELSIO_T3'
clean_mk CONFIG_CHELSIO_T3 drivers/net/cxgb3/Makefile

announce E100 - "Intel PRO/100+"
drop_fw_file firmware/e100/d101m_ucode.bin.ihex firmware/e100/d101m_ucode.bin
drop_fw_file firmware/e100/d101s_ucode.bin.ihex firmware/e100/d101s_ucode.bin
drop_fw_file firmware/e100/d102e_ucode.bin.ihex firmware/e100/d102e_ucode.bin
reject_firmware drivers/net/e100.c
clean_sed '
/^static const struct firmware \*e100_\(reject\|request\)_firmware(/,/^}$/{
  s:^\(.*\)return ERR_PTR(err);$:\1DPRINTK(PROBE,ERR, "Proceeding without firmware\\n");\n\1return NULL;:
}' drivers/net/e100.c 'proceed without firmware'
clean_blob drivers/net/e100.c
clean_kconfig drivers/net/Kconfig 'E100'
clean_mk CONFIG_E100 drivers/net/Makefile

announce MYRI_SBUS - "MyriCOM Gigabit Ethernet"
drop_fw_file firmware/myricom/lanai.bin.ihex firmware/myricom/lanai.bin
reject_firmware drivers/net/myri_sbus.c
clean_blob drivers/net/myri_sbus.c
clean_kconfig drivers/net/Kconfig 'MYRI_SBUS'
clean_mk CONFIG_MYRI_SBUS drivers/net/Makefile

announce MYRI10GE - "Myricom Myri-10G Ethernet support"
reject_firmware drivers/net/myri10ge/myri10ge.c
clean_blob drivers/net/myri10ge/myri10ge.c
clean_kconfig drivers/net/Kconfig 'MYRI10GE'
clean_mk CONFIG_MYRI10GE drivers/net/myri10ge/Makefile

announce NETXEN_NIC - "NetXen Multi port (1/10) Gigabit Ethernet NIC"
reject_firmware drivers/net/netxen/netxen_nic.h
reject_firmware drivers/net/netxen/netxen_nic_main.c
reject_firmware drivers/net/netxen/netxen_nic_init.c
clean_blob drivers/net/netxen/netxen_nic_init.c
clean_kconfig drivers/net/Kconfig 'NETXEN_NIC'
clean_mk CONFIG_NETXEN_NIC drivers/net/Makefile

announce SLICOSS - "Alacritech Gigabit IS-NIC cards"
reject_firmware drivers/staging/slicoss/slicoss.c
clean_blob drivers/staging/slicoss/slicoss.c
clean_kconfig drivers/staging/slicoss/Kconfig 'SLICOSS'
clean_mk CONFIG_SLICOSS drivers/staging/slicoss/Makefile

announce SPIDER_NET - "Spider Gigabit Ethernet driver"
reject_firmware drivers/net/spider_net.c
clean_sed 's,spider_fw\.bin,DEBLOBBED.bin,g' \
  drivers/net/spider_net.c 'removed non-Free firmware notes'
clean_blob drivers/net/spider_net.h
clean_kconfig drivers/net/Kconfig 'SPIDER_NET'
clean_mk CONFIG_SPIDER_NET drivers/net/Makefile

announce SXG - "Alacritech SLIC Technology Non-Accelerated 10Gbe cards"
clean_file drivers/staging/sxg/sxgphycode-1.2.h
reject_firmware drivers/staging/sxg/sxg.c
clean_sed '
/^static int sxg_phy_init(/,/^}$/{
  /for (p = PhyUcode/i\
		printk("%s: missing Free firmware\\n", __func__);\
		return (STATUS_FAILURE);\
#define PhyUcode NULL		
}' drivers/staging/sxg/sxg.c 'report missing Free firmware'
clean_blob drivers/staging/sxg/sxg.c
clean_kconfig drivers/staging/sxg/Kconfig 'SXG'
clean_mk CONFIG_SXG drivers/staging/sxg/Makefile

announce TEHUTI - "Tehuti Networks 10G Ethernet"
drop_fw_file firmware/tehuti/bdx.bin.ihex firmware/tehuti/bdx.bin
reject_firmware drivers/net/tehuti.c
clean_blob drivers/net/tehuti.c
clean_kconfig drivers/net/Kconfig 'TEHUTI'
clean_mk CONFIG_TEHUTI drivers/net/Makefile

announce TIGON3 - "Broadcom Tigon3"
drop_fw_file firmware/tigon/tg3.bin.ihex firmware/tigon/tg3.bin
drop_fw_file firmware/tigon/tg3_tso.bin.ihex firmware/tigon/tg3_tso.bin
drop_fw_file firmware/tigon/tg3_tso5.bin.ihex firmware/tigon/tg3_tso5.bin
reject_firmware drivers/net/tg3.c
clean_blob drivers/net/tg3.c
clean_kconfig drivers/net/Kconfig 'TIGON3'
clean_mk CONFIG_TIGON3 drivers/net/Makefile

announce TYPHOON - "3cr990 series Typhoon"
drop_fw_file firmware/3com/typhoon.bin.ihex firmware/3com/typhoon.bin
reject_firmware drivers/net/typhoon.c
clean_blob drivers/net/typhoon.c
clean_kconfig drivers/net/Kconfig 'TYPHOON'
clean_mk CONFIG_TYPHOON drivers/net/Makefile

# appletalk

announce COPS - "COPS LocalTalk PC"
clean_sed '
/sizeof(\(ff\|lt\)drv_code)/{
  i\
		printk(KERN_INFO "%s: Missing Free firmware.\\n", dev->name);\
		return;
}
/\(ff\|lt\)drv_code/d;
' drivers/net/appletalk/cops.c 'report missing Free firmware'
clean_blob drivers/net/appletalk/cops.c
clean_file drivers/net/appletalk/cops_ffdrv.h
clean_file drivers/net/appletalk/cops_ltdrv.h
clean_kconfig drivers/net/appletalk/Kconfig 'COPS'
clean_mk CONFIG_COPS drivers/net/appletalk/Makefile

# hamradio

announce YAM - "YAM driver for AX.25"
drop_fw_file firmware/yam/1200.bin.ihex firmware/yam/1200.bin
drop_fw_file firmware/yam/9600.bin.ihex firmware/yam/9600.bin
reject_firmware drivers/net/hamradio/yam.c
clean_blob drivers/net/hamradio/yam.c
clean_kconfig drivers/net/hamradio/Kconfig 'YAM'
clean_mk CONFIG_YAM drivers/net/hamradio/Makefile

# irda

announce USB_IRDA - "IrDA USB dongles"
reject_firmware drivers/net/irda/irda-usb.c
clean_blob drivers/net/irda/irda-usb.c
clean_kconfig drivers/net/irda/Kconfig 'USB_IRDA'
clean_mk CONFIG_USB_IRDA drivers/net/irda/Makefile

# pcmcia

announce PCMCIA_SMC91C92 - "SMC 91Cxx PCMCIA"
drop_fw_file firmware/ositech/Xilinx7OD.bin.ihex firmware/ositech/Xilinx7OD.bin
reject_firmware drivers/net/pcmcia/smc91c92_cs.c
clean_blob drivers/net/pcmcia/smc91c92_cs.c
clean_kconfig drivers/net/pcmcia/Kconfig 'PCMCIA_SMC91C92'
clean_mk CONFIG_PCMCIA_SMC91C92 drivers/net/pcmcia/Makefile

announce PCCARD - "PCCard (PCMCIA/CardBus) support"
reject_firmware drivers/pcmcia/ds.c
clean_kconfig drivers/pcmcia/Kconfig 'PCCARD'
clean_mk CONFIG_PCCARD drivers/pcmcia/Makefile

announce PCMCIA_3C574 - "3Com 3c574 PCMCIA support"
drop_fw_file firmware/cis/3CCFEM556.cis.ihex firmware/cis/3CCFEM556.cis
clean_blob drivers/net/pcmcia/3c574_cs.c
clean_kconfig drivers/net/pcmcia/Kconfig 'PCMCIA_3C574'
clean_mk CONFIG_PCMCIA_3C574 drivers/net/pcmcia/Makefile

announce PCMCIA_3C589 - "3Com 3c589 PCMCIA support"
drop_fw_file firmware/cis/3CXEM556.cis.ihex firmware/cis/3CXEM556.cis
clean_blob drivers/net/pcmcia/3c589_cs.c
clean_kconfig drivers/net/pcmcia/Kconfig 'PCMCIA_3C589'
clean_mk CONFIG_PCMCIA_3C589 drivers/net/pcmcia/Makefile

announce PCMCIA_PCNET - "NE2000 compatible PCMCIA support"
drop_fw_file firmware/cis/LA-PCM.cis.ihex firmware/cis/LA-PCM.cis
clean_blob drivers/net/pcmcia/pcnet_cs.c
clean_kconfig drivers/net/pcmcia/Kconfig 'PCMCIA_PCNET'
clean_mk CONFIG_PCMCIA_PCNET drivers/net/pcmcia/Makefile

# tokenring

announce 3C359 - "3Com 3C359 Token Link Velocity XL adapter"
drop_fw_file firmware/3com/3C359.bin.ihex firmware/3com/3C359.bin
clean_blob drivers/net/tokenring/3c359.c
clean_kconfig drivers/net/tokenring/Kconfig '3C359'
clean_mk CONFIG_3C359 drivers/net/tokenring/Makefile

announce SMCTR - "SMC ISA/MCA adapter"
drop_fw_file firmware/tr_smctr.bin.ihex firmware/tr_smctr.bin
reject_firmware drivers/net/tokenring/smctr.c
clean_blob drivers/net/tokenring/smctr.c
clean_kconfig drivers/net/tokenring/Kconfig 'SMCTR'
clean_mk CONFIG_SMCTR drivers/net/tokenring/Makefile

announce TMS380TR - "Generic TMS380 Token Ring ISA/PCI adapter support"
reject_firmware drivers/net/tokenring/tms380tr.c
clean_blob drivers/net/tokenring/tms380tr.c
clean_kconfig drivers/net/tokenring/Kconfig 'TMS380TR'
clean_mk CONFIG_TMS380TR drivers/net/tokenring/Makefile

# usb

announce USB_KAWETH - "USB KLSI KL5USB101-based ethernet device support"
drop_fw_file firmware/kaweth/new_code.bin.ihex firmware/kaweth/new_code.bin
drop_fw_file firmware/kaweth/new_code_fix.bin.ihex firmware/kaweth/new_code_fix.bin
drop_fw_file firmware/kaweth/trigger_code.bin.ihex firmware/kaweth/trigger_code.bin
drop_fw_file firmware/kaweth/trigger_code_fix.bin.ihex firmware/kaweth/trigger_code_fix.bin
reject_firmware drivers/net/usb/kaweth.c
clean_blob drivers/net/usb/kaweth.c
clean_kconfig drivers/net/usb/Kconfig 'USB_KAWETH'
clean_mk CONFIG_USB_KAWETH drivers/net/usb/Makefile

# wireless

announce ATMEL "Atmel at76c50x chipset  802.11b support"
reject_firmware drivers/net/wireless/atmel.c
clean_blob drivers/net/wireless/atmel.c
clean_kconfig drivers/net/wireless/Kconfig 'ATMEL'
clean_mk CONFIG_ATMEL drivers/net/wireless/Makefile

announce AT76C50X_USB - "Atmel at76c503/at76c505/at76c505a USB cards"
reject_firmware drivers/net/wireless/at76c50x-usb.c
clean_blob drivers/net/wireless/at76c50x-usb.c
clean_kconfig drivers/net/wireless/Kconfig 'AT76C50X_USB'
clean_mk CONFIG_AT76C50X_USB drivers/net/wireless/Makefile

announce USB_ATMEL - "Atmel at76c503/at76c505/at76c505a USB cards (in staging)"
reject_firmware drivers/staging/at76_usb/at76_usb.c
clean_blob drivers/staging/at76_usb/at76_usb.c
clean_kconfig drivers/staging/at76_usb/Kconfig 'USB_ATMEL'
clean_mk CONFIG_USB_ATMEL drivers/staging/at76_usb/Makefile

announce B43 - "Broadcom 43xx wireless support (mac80211 stack)"
maybe_reject_firmware drivers/net/wireless/b43/main.c
clean_sed '
/^static int b43_upload_microcode(/,/^}$/{
  /	if (dev->fw\.opensource) {$/i\
	if (!dev->fw.opensource) {\
		b43err(dev->wl, "Rejected non-Free firmware\\n");\
		err = -EOPNOTSUPP;\
		goto error;\
	}
}' drivers/net/wireless/b43/main.c 'double-check and reject non-Free firmware'
# Major portions of firmware filenames not deblobbed.
clean_blob drivers/net/wireless/b43/main.c
clean_kconfig drivers/net/wireless/b43/Kconfig 'B43'
clean_mk CONFIG_B43 drivers/net/wireless/b43/Makefile

announce B43LEGACY - "Broadcom 43xx-legacy wireless support (mac80211 stack)"
reject_firmware drivers/net/wireless/b43legacy/main.c
# Major portions of firwmare filenames not deblobbed.
clean_blob drivers/net/wireless/b43legacy/main.c
clean_kconfig drivers/net/wireless/b43legacy/Kconfig 'B43LEGACY'
clean_mk CONFIG_B43LEGACY drivers/net/wireless/b43legacy/Makefile

announce HERMES - "Hermes chipset 802.11b support (Orinoco/Prism2/Symbol)"
reject_firmware drivers/net/wireless/orinoco/fw.c
clean_blob drivers/net/wireless/orinoco/fw.c
clean_kconfig drivers/net/wireless/Kconfig 'HERMES'
clean_mk CONFIG_HERMES drivers/net/wireless/orinoco/Makefile

announce IPW2100 - "Intel PRO/Wireless 2100 Network Connection"
reject_firmware drivers/net/wireless/ipw2x00/ipw2100.c
clean_blob drivers/net/wireless/ipw2x00/ipw2100.c
clean_kconfig drivers/net/wireless/Kconfig 'IPW2100'
clean_mk CONFIG_IPW2100 drivers/net/wireless/ipw2x00/Makefile

announce IPW2200 - "Intel PRO/Wireless 2200BG and 2915ABG Network Connection"
reject_firmware drivers/net/wireless/ipw2x00/ipw2200.c
clean_blob drivers/net/wireless/ipw2x00/ipw2200.c
clean_kconfig drivers/net/wireless/Kconfig 'IPW2200'
clean_mk CONFIG_IPW2200 drivers/net/wireless/ipw2x00/Makefile

announce IWL3945 - "Intel PRO/Wireless 3945ABG/BG Network Connection"
reject_firmware drivers/net/wireless/iwlwifi/iwl3945-base.c
clean_blob drivers/net/wireless/iwlwifi/iwl3945-base.c
clean_blob drivers/net/wireless/iwlwifi/iwl-3945.h
clean_kconfig drivers/net/wireless/iwlwifi/Kconfig 'IWL3945'
clean_mk CONFIG_IWL3945 drivers/net/wireless/iwlwifi/Makefile

announce IWLAGN - "Intel Wireless WiFi Next Gen AGN"
reject_firmware drivers/net/wireless/iwlwifi/iwl-agn.c
clean_blob drivers/net/wireless/iwlwifi/iwl-agn.c
clean_kconfig drivers/net/wireless/iwlwifi/Kconfig 'IWLAGN'
clean_mk CONFIG_IWLAGN drivers/net/wireless/iwlwifi/Makefile

announce IWL4965 - "Intel Wireless WiFi 4965AGN"
clean_blob drivers/net/wireless/iwlwifi/iwl-4965.c
clean_kconfig drivers/net/wireless/iwlwifi/Kconfig 'IWL4965'
clean_mk CONFIG_IWL4965 drivers/net/wireless/iwlwifi/Makefile

announce IWL5000 - "Intel Wireless WiFi 5000AGN"
clean_blob drivers/net/wireless/iwlwifi/iwl-5000.c
clean_blob drivers/net/wireless/iwlwifi/iwl-6000.c
clean_blob drivers/net/wireless/iwlwifi/iwl-1000.c
clean_kconfig drivers/net/wireless/iwlwifi/Kconfig 'IWL5000'
clean_mk CONFIG_IWL5000 drivers/net/wireless/iwlwifi/Makefile

announce IWM - "Intel Wireless Multicomm 3200 WiFi driver"
reject_firmware drivers/net/wireless/iwmc3200wifi/fw.c
clean_blob drivers/net/wireless/iwmc3200wifi/sdio.c
clean_kconfig drivers/net/wireless/iwmc3200wifi/Kconfig 'IWM'
clean_mk CONFIG_IWM drivers/net/wireless/iwmc3200wifi/Makefile

announce LIBERTAS_CS - "Marvell Libertas 8385 CompactFlash 802.11b/g cards"
reject_firmware drivers/net/wireless/libertas/if_cs.c
clean_blob drivers/net/wireless/libertas/if_cs.c
clean_kconfig drivers/net/wireless/Kconfig 'LIBERTAS_CS'
clean_mk CONFIG_LIBERTAS_CS drivers/net/wireless/libertas/Makefile

announce LIBERTAS_SDIO - "Marvell Libertas 8385 and 8686 SDIO 802.11b/g cards"
reject_firmware drivers/net/wireless/libertas/if_sdio.c
clean_blob drivers/net/wireless/libertas/if_sdio.c
clean_kconfig drivers/net/wireless/Kconfig 'LIBERTAS_SDIO'
clean_mk CONFIG_LIBERTAS_SDIO drivers/net/wireless/libertas/Makefile

announce LIBERTAS_SPI - "Marvell Libertas 8686 SPI 802.11b/g cards"
reject_firmware drivers/net/wireless/libertas/if_spi.c
clean_blob drivers/net/wireless/libertas/if_spi.c
clean_kconfig drivers/net/wireless/Kconfig 'LIBERTAS_SPI'
clean_mk CONFIG_LIBERTAS_SPI drivers/net/wireless/libertas/Makefile

announce LIBERTAS_USB - "Marvell Libertas 8388 USB 802.11b/g cards"
reject_firmware drivers/net/wireless/libertas/if_usb.c
clean_blob drivers/net/wireless/libertas/if_usb.c
clean_blob drivers/net/wireless/libertas/README
clean_kconfig drivers/net/wireless/Kconfig 'LIBERTAS_USB'
clean_mk CONFIG_LIBERTAS_USB drivers/net/wireless/libertas/Makefile

announce LIBERTAS_THINFIRM_USB - "Marvell Libertas 8388 USB 802.11b/g cards with thin firmware"
reject_firmware drivers/net/wireless/libertas_tf/if_usb.c
clean_blob drivers/net/wireless/libertas_tf/if_usb.c
clean_kconfig drivers/net/wireless/Kconfig 'LIBERTAS_THINFIRM_USB'
clean_mk CONFIG_LIBERTAS_THINFIRM_USB drivers/net/wireless/libertas_tf/Makefile

announce MWL8K - 'Marvell 88W8xxx PCI/PCIe Wireless support'
reject_firmware drivers/net/wireless/mwl8k.c
clean_blob drivers/net/wireless/mwl8k.c
clean_kconfig drivers/net/wireless/Kconfig 'MWL8K'
clean_mk CONFIG_MWL8K drivers/net/wireless/Makefile

announce OTUS - "Atheros OTUS 802.11n USB wireless support"
clean_blob drivers/staging/otus/hal/hpDKfwu.c
clean_blob drivers/staging/otus/hal/hpfw2.c
clean_blob drivers/staging/otus/hal/hpfwbu.c
clean_blob drivers/staging/otus/hal/hpfwspiu.c
clean_blob drivers/staging/otus/hal/hpfwu.c
clean_blob drivers/staging/otus/hal/hpfwu.c.drv_ba_resend
clean_blob drivers/staging/otus/hal/hpfwu_2k.c
clean_blob drivers/staging/otus/hal/hpfwu_BA.c
clean_blob drivers/staging/otus/hal/hpfwu_FB50_mdk.c
clean_blob drivers/staging/otus/hal/hpfwu_OTUS_RC.c
clean_blob drivers/staging/otus/hal/hpfwu_txstream.c
clean_blob drivers/staging/otus/hal/hpfwuinit.c
clean_sed '
/^u16_t zfFirmwareDownload\(NotJump\)\?(.*)$/,/^}$/ {
  /    image = (u8_t\*) fw;/i\
    zm_msg0_init(ZM_LV_0, "Missing Free firmware");\
    ret = ZM_ERR_FIRMWARE_WRONG_TYPE;\
    goto exit;\

}
' drivers/staging/otus/hal/hpusb.c \
  'disabled non-Free firmware-loading machinery'
clean_sed 's/^extern u16_t \(zfFirmwareDownload\(NotJump\)\?\)([^;]*);/&\n#define \1(dev,fw,len,offset) (\1)(dev,NULL,0,offset)/
' drivers/staging/otus/hal/hpmain.c \
  'disabled non-Free firmware-loading machinery'
clean_blob drivers/staging/otus/hal/hpmain.c
clean_kconfig drivers/staging/otus/Kconfig OTUS
clean_mk CONFIG_OTUS drivers/staging/otus/Makefile

announce PRISM2_USB - "Prism2.5/3 USB driver"
reject_firmware drivers/staging/wlan-ng/prism2fw.c
clean_blob drivers/staging/wlan-ng/prism2fw.c
clean_kconfig drivers/staging/wlan-ng/Kconfig PRISM2_USB
clean_mk CONFIG_PRISM2_USB drivers/staging/wlan-ng/Makefile

announce P54_PCI - "Prism54 PCI support"
reject_firmware drivers/net/wireless/p54/p54pci.c
clean_blob drivers/net/wireless/p54/p54pci.c
clean_kconfig drivers/net/wireless/p54/Kconfig 'P54_PCI'
clean_mk CONFIG_P54_PCI drivers/net/wireless/p54/Makefile

announce P54_SPI - "Prism54 SPI (stlc45xx) support"
# There's support for loading custom 3826.eeprom here, with a default
# eeprom that is clearly pure data.  Without Free 3826.arm, there's
# little point in trying to retain the ability to load 3826.eeprom, so
# we drop it altogether.
reject_firmware drivers/net/wireless/p54/p54spi.c
clean_blob drivers/net/wireless/p54/p54spi.c
clean_kconfig drivers/net/wireless/p54/Kconfig 'P54_SPI'
clean_mk CONFIG_P54_SPI drivers/net/wireless/p54/Makefile

announce P54_USB - "Prism54 USB support"
reject_firmware drivers/net/wireless/p54/p54usb.c
clean_blob drivers/net/wireless/p54/p54usb.c
clean_blob drivers/net/wireless/p54/p54usb.h
clean_kconfig drivers/net/wireless/p54/Kconfig 'P54_USB'
clean_mk CONFIG_P54_USB drivers/net/wireless/p54/Makefile

announce PRISM54 - 'Intersil Prism GT/Duette/Indigo PCI/Cardbus'
reject_firmware drivers/net/wireless/prism54/islpci_dev.c
clean_blob drivers/net/wireless/prism54/islpci_dev.c
clean_sed '
/^config PRISM54$/,/^config /{
  /If you enable this/,/^$/d;
}' drivers/net/wireless/Kconfig 'removed firmware notes'
clean_kconfig drivers/net/wireless/Kconfig 'PRISM54'
clean_mk CONFIG_PRISM54 drivers/net/wireless/prism54/Makefile

announce RT2X00_LIB_FIRMWARE - "Ralink driver firmware support"
reject_firmware drivers/net/wireless/rt2x00/rt2x00firmware.c
clean_kconfig drivers/net/wireless/rt2x00/Kconfig 'RT2X00_LIB_FIRMWARE'
clean_mk CONFIG_RT2X00_LIB_FIRMWARE drivers/net/wireless/rt2x00/Makefile

announce RT61PCI - "Ralink rt2501/rt61 (PCI/PCMCIA) support"
clean_blob drivers/net/wireless/rt2x00/rt61pci.h
clean_blob drivers/net/wireless/rt2x00/rt61pci.c
clean_kconfig drivers/net/wireless/rt2x00/Kconfig 'RT61PCI'
clean_mk CONFIG_RT61PCI drivers/net/wireless/rt2x00/Makefile

announce RT73USB - "Ralink rt2501/rt73 (USB) support"
clean_blob drivers/net/wireless/rt2x00/rt73usb.h
clean_blob drivers/net/wireless/rt2x00/rt73usb.c
clean_kconfig drivers/net/wireless/rt2x00/Kconfig 'RT73USB'
clean_mk CONFIG_RT73USB drivers/net/wireless/rt2x00/Makefile

announce RT2800USB - "Ralink rt2800 (USB) support"
clean_blob drivers/net/wireless/rt2x00/rt2800usb.h
clean_blob drivers/net/wireless/rt2x00/rt2800usb.c
clean_kconfig drivers/net/wireless/rt2x00/Kconfig RT2800USB
clean_mk CONFIG_RT2800USB drivers/net/wireless/rt2x00/Makefile

announce RT2860 - "Ralink 2860 wireless support"
clean_file drivers/staging/rt2860/common/firmware.h
clean_blob drivers/staging/rt2860/rt_linux.h
clean_sed '
/^NDIS_STATUS NICLoadFirmware(/,/^}$/{
  s/^\(	*\)pFirmwareImage = .*FirmwareImage.*;/\1printk("%s: missing Free firmware\\n", __func__);\n\1return NDIS_STATUS_FAILURE;\n&/
}' drivers/staging/rt2860/common/rtmp_init.c 'report missing Free firmware'
clean_blob drivers/staging/rt2860/common/rtmp_init.c
clean_sed '
/^INT[	]set_eFuseLoadFromBin_Proc(/,/^}$/{
  /src = kmalloc/i\
	printk("%s: missing Free firmware\\n", __func__);\
	return FALSE;	
}' drivers/staging/rt2860/common/eeprom.c 'report missing Free firmware'
clean_blob drivers/staging/rt2860/common/eeprom.c
clean_kconfig drivers/staging/rt2860/Kconfig RT2860
clean_mk CONFIG_RT2860 drivers/staging/rt2860/Makefile

announce RT2870 - "Ralink 2870 wireless support"
clean_file drivers/staging/rt2870/common/firmware.h
clean_kconfig drivers/staging/rt2870/Kconfig RT2870
clean_mk CONFIG_RT2870 drivers/staging/rt2870/Makefile

announce RT3070 - "Ralink 3070 wireless support"
clean_file drivers/staging/rt3070/firmware.h
clean_kconfig drivers/staging/rt3070/Kconfig RT3070
clean_mk CONFIG_RT3070 drivers/staging/rt3070/Makefile

announce RTL8192SU - "RealTek RTL8192SU Wireless LAN NIC driver"
reject_firmware drivers/staging/rtl8192su/r819xU_firmware.c
reject_firmware drivers/staging/rtl8192su/r8192S_firmware.c
clean_blob drivers/staging/rtl8192su/r8192SU_HWImg.c
clean_blob drivers/staging/rtl8192su/r8192S_FwImgDTM.h
clean_blob drivers/staging/rtl8192su/r8192S_firmware.c
clean_blob drivers/staging/rtl8192su/r819xU_firmware_img.c
clean_blob drivers/staging/rtl8192su/r819xU_firmware.c
clean_kconfig drivers/staging/rtl8192su/Kconfig 'RTL8192SU'
clean_mk CONFIG_RTL8192SU drivers/staging/rtl8192su/Makefile

announce WL12XX - "TI wl1251/wl1271 support"
reject_firmware drivers/net/wireless/wl12xx/main.c
clean_blob drivers/net/wireless/wl12xx/wl1251.h
clean_kconfig drivers/net/wireless/wl12xx/Kconfig 'WL12XX'
clean_mk CONFIG_WL12XX drivers/net/wireless/wl12xx/Makefile

announce USB_ZD1201 - "USB ZD1201 based Wireless device support"
reject_firmware drivers/net/wireless/zd1201.c
clean_blob drivers/net/wireless/zd1201.c
clean_kconfig drivers/net/wireless/Kconfig 'USB_ZD1201'
clean_mk CONFIG_USB_ZD1201 drivers/net/wireless/Makefile

announce ZD1211RW - "ZyDAS ZD1211/ZD1211B USB-wireless support"
reject_firmware drivers/net/wireless/zd1211rw/zd_usb.c
clean_blob drivers/net/wireless/zd1211rw/zd_usb.c
clean_kconfig drivers/net/wireless/zd1211rw/Kconfig 'ZD1211RW'
clean_mk CONFIG_ZD1211RW drivers/net/wireless/zd1211rw/Makefile

# bluetooth

announce BT_HCIBCM203X - "HCI BCM203x USB driver"
reject_firmware drivers/bluetooth/bcm203x.c
clean_blob drivers/bluetooth/bcm203x.c
clean_kconfig drivers/bluetooth/Kconfig 'BT_HCIBCM203X'
clean_mk CONFIG_BT_HCIBCM203X drivers/bluetooth/Makefile

announce BT_HCIBFUSB - "HCI BlueFRITZ! USB driver"
reject_firmware drivers/bluetooth/bfusb.c
clean_blob drivers/bluetooth/bfusb.c
clean_kconfig drivers/bluetooth/Kconfig 'BT_HCIBFUSB'
clean_mk CONFIG_BT_HCIBFUSB drivers/bluetooth/Makefile

announce BT_HCIBT3C - "HCI BT3C (PC Card) driver"
reject_firmware drivers/bluetooth/bt3c_cs.c
clean_blob drivers/bluetooth/bt3c_cs.c
clean_kconfig drivers/bluetooth/Kconfig 'BT_HCIBT3C'
clean_mk CONFIG_BT_HCIBT3C drivers/bluetooth/Makefile

# wimax

announce WIMAX_I2400M - "Intel Wireless WiMAX Connection 2400"
reject_firmware drivers/net/wimax/i2400m/fw.c
clean_blob drivers/net/wimax/i2400m/sdio.c
clean_blob drivers/net/wimax/i2400m/usb.c
clean_blob Documentation/wimax/README.i2400m
clean_kconfig drivers/net/wimax/i2400m/Kconfig CONFIG_WIMAX_I2400M
clean_mk CONFIG_WIMAX_I2400M drivers/net/wimax/i2400m/Makefile

########
# ISDN #
########

announce ISDN_DIVAS - "Support Eicon DIVA Server cards"
clean_blob drivers/isdn/hardware/eicon/cardtype.h
clean_blob drivers/isdn/hardware/eicon/dsp_defs.h
clean_kconfig drivers/isdn/hardware/eicon/Kconfig 'ISDN_DIVAS'
clean_mk CONFIG_ISDN_DIVAS drivers/isdn/hardware/eicon/Makefile

##########
# Serial #
##########

announce SERIAL_8250_CS - "8250/16550 PCMCIA device support"
clean_blob drivers/serial/serial_cs.c
clean_kconfig drivers/serial/Kconfig 'SERIAL_8250_CS'
clean_mk CONFIG_SERIAL_8250_CS drivers/serial/Makefile

announce SERIAL_ICOM - "IBM Multiport Serial Adapter"
reject_firmware drivers/serial/icom.c
clean_blob drivers/serial/icom.c
clean_kconfig drivers/serial/Kconfig 'SERIAL_ICOM'
clean_mk CONFIG_SERIAL_ICOM drivers/serial/Makefile

announce SERIAL_QE - "Freescale QUICC Engine serial port support"
reject_firmware drivers/serial/ucc_uart.c
clean_blob drivers/serial/ucc_uart.c
clean_kconfig drivers/serial/Kconfig 'SERIAL_QE'
clean_mk CONFIG_SERIAL_QE drivers/serial/Makefile

####################
# Data acquisition #
####################

announce COMEDI_PCI_DRIVERS - "Data acquisition support Comedi PCI drivers"
reject_firmware drivers/staging/comedi/drivers/jr3_pci.c
clean_blob drivers/staging/comedi/drivers/jr3_pci.c
clean_kconfig drivers/staging/comedi/Kconfig 'COMEDI_PCI_DRIVERS'
clean_mk CONFIG_COMEDI_PCI_DRIVERS drivers/staging/comedi/drivers/Makefile

announce COMEDI_USB_DRIVERS - "Data acquisition support Comedi USB drivers"
reject_firmware drivers/staging/comedi/drivers/usbdux.c
clean_blob drivers/staging/comedi/drivers/usbdux.c
reject_firmware drivers/staging/comedi/drivers/usbduxfast.c
clean_blob drivers/staging/comedi/drivers/usbduxfast.c
clean_kconfig drivers/staging/comedi/Kconfig 'COMEDI_USB_DRIVERS'
clean_mk CONFIG_COMEDI_USB_DRIVERS drivers/staging/comedi/drivers/Makefile

announce ME4000 - "Meilhaus ME-4000 I/O board"
clean_file drivers/staging/me4000/me4000_firmware.h
clean_file drivers/staging/me4000/me4610_firmware.h
clean_sed '
/^static int me4000_xilinx_download([^;]*$/,/^}$/{
  /firm = .*xilinx_firm.*/i\
	printk(KERN_ERR "me4000: Missing Free firmware\\n");\
	return -EIO;
}
' drivers/staging/me4000/me4000.c 'report missing Free firmware'
clean_blob drivers/staging/me4000/me4000.c
clean_kconfig drivers/staging/me4000/Kconfig 'ME4000'
clean_mk CONFIG_ME4000 drivers/staging/me4000/Makefile

announce MEILHAUS - "Meilhaus support"
reject_firmware drivers/staging/meilhaus/mefirmware.c
clean_kconfig drivers/staging/meilhaus/Kconfig 'MEILHAUS'
clean_mk CONFIG_MEILHAUS drivers/staging/meilhaus/Makefile

announce ME4600 - "Meilhaus ME-4600 support"
clean_blob drivers/staging/meilhaus/me4600_device.c
clean_kconfig drivers/staging/meilhaus/Kconfig 'ME4600'
clean_mk CONFIG_ME4600 drivers/staging/meilhaus/Makefile

announce ME6000 - "Meilhaus ME-6000 support"
clean_blob drivers/staging/meilhaus/me6000_device.c
clean_kconfig drivers/staging/meilhaus/Kconfig 'ME6000'
clean_mk CONFIG_ME6000 drivers/staging/meilhaus/Makefile


########
# SCSI #
########

announce SCSI_QLOGICPTI - "PTI Qlogic, ISP Driver"
drop_fw_file firmware/qlogic/isp1000.bin.ihex firmware/qlogic/isp1000.bin
reject_firmware drivers/scsi/qlogicpti.c
clean_blob drivers/scsi/qlogicpti.c
clean_kconfig drivers/scsi/Kconfig 'SCSI_QLOGICPTI'
clean_mk CONFIG_SCSI_QLOGICPTI drivers/scsi/Makefile

announce SCSI_ADVANSYS - "AdvanSys SCSI"
drop_fw_file firmware/advansys/mcode.bin.ihex firmware/advansys/mcode.bin
drop_fw_file firmware/advansys/3550.bin.ihex firmware/advansys/3550.bin
drop_fw_file firmware/advansys/38C0800.bin.ihex firmware/advansys/38C0800.bin
drop_fw_file firmware/advansys/38C1600.bin.ihex firmware/advansys/38C1600.bin
reject_firmware drivers/scsi/advansys.c
clean_blob drivers/scsi/advansys.c
clean_kconfig drivers/scsi/Kconfig 'SCSI_ADVANSYS'
clean_mk CONFIG_SCSI_ADVANSYS drivers/scsi/Makefile

announce SCSI_QLOGIC_1280 - "Qlogic QLA 1240/1x80/1x160 SCSI"
drop_fw_file firmware/qlogic/1040.bin.ihex firmware/qlogic/1040.bin
drop_fw_file firmware/qlogic/1280.bin.ihex firmware/qlogic/1280.bin
drop_fw_file firmware/qlogic/12160.bin.ihex firmware/qlogic/12160.bin
reject_firmware drivers/scsi/qla1280.c
clean_blob drivers/scsi/qla1280.c
clean_kconfig drivers/scsi/Kconfig 'SCSI_QLOGIC_1280'
clean_mk CONFIG_SCSI_QLOGIC_1280 drivers/scsi/Makefile

announce SCSI_AIC94XX - "Adaptec AIC94xx SAS/SATA support"
reject_firmware drivers/scsi/aic94xx/aic94xx_seq.c
clean_blob drivers/scsi/aic94xx/aic94xx_seq.c
clean_blob drivers/scsi/aic94xx/aic94xx_seq.h
clean_kconfig drivers/scsi/aic94xx/Kconfig 'SCSI_AIC94XX'
clean_mk CONFIG_SCSI_AIC94XX drivers/scsi/aic94xx/Makefile

announce SCSI_QLA_FC - "QLogic QLA2XXX Fibre Channel Support"
reject_firmware drivers/scsi/qla2xxx/qla_gbl.h
reject_firmware drivers/scsi/qla2xxx/qla_init.c
reject_firmware drivers/scsi/qla2xxx/qla_os.c
clean_sed '
/^config SCSI_QLA_FC$/,/^config /{
  /^	By default, firmware/i\
	/*(DEBLOBBED)*/
  /^	By default, firmware/,/ftp:[/][/].*firmware[/]/d
}' drivers/scsi/qla2xxx/Kconfig 'removed firmware notes'
clean_blob drivers/scsi/qla2xxx/qla_os.c
clean_kconfig drivers/scsi/qla2xxx/Kconfig 'SCSI_QLA_FC'
clean_mk CONFIG_SCSI_QLA_FC drivers/scsi/qla2xxx/Makefile


#######
# USB #
#######

# atm

announce USB_CXACRU - "Conexant AccessRunner USB support"
reject_firmware drivers/usb/atm/cxacru.c
clean_blob drivers/usb/atm/cxacru.c
clean_kconfig drivers/usb/atm/Kconfig 'USB_CXACRU'
clean_mk CONFIG_USB_CXACRU drivers/usb/atm/Makefile

announce USB_SPEEDTOUCH - "Speedtouch USB support"
reject_firmware drivers/usb/atm/speedtch.c
clean_blob drivers/usb/atm/speedtch.c
clean_kconfig drivers/usb/atm/Kconfig 'USB_SPEEDTOUCH'
clean_mk CONFIG_USB_SPEEDTOUCH drivers/usb/atm/Makefile

announce USB_UEAGLEATM - "ADI 930 and eagle USB DSL modem"
reject_firmware drivers/usb/atm/ueagle-atm.c
clean_blob drivers/usb/atm/ueagle-atm.c
clean_kconfig drivers/usb/atm/Kconfig 'USB_UEAGLEATM'
clean_mk CONFIG_USB_UEAGLEATM drivers/usb/atm/Makefile

# misc

announce USB_EMI26 - "EMI 2|6 USB Audio interface"
# These files are not under the GPL, better remove them all.
drop_fw_file firmware/emi26/bitstream.HEX firmware/emi26/bitstream.fw
drop_fw_file firmware/emi26/firmware.HEX firmware/emi26/firmware.fw
drop_fw_file firmware/emi26/loader.HEX firmware/emi26/loader.fw
reject_firmware drivers/usb/misc/emi26.c
clean_blob drivers/usb/misc/emi26.c
clean_kconfig drivers/usb/misc/Kconfig 'USB_EMI26'
clean_mk CONFIG_USB_EMI26 drivers/usb/misc/Makefile

announce USB_EMI62 - "EMI 6|2m USB Audio interface"
# These files are probably not under the GPL, better remove them all.
drop_fw_file firmware/emi62/bitstream.HEX firmware/emi62/bitstream.fw
drop_fw_file firmware/emi62/loader.HEX firmware/emi62/loader.fw
drop_fw_file firmware/emi62/midi.HEX firmware/emi62/midi.fw
drop_fw_file firmware/emi62/spdif.HEX firmware/emi62/spdif.fw
reject_firmware drivers/usb/misc/emi62.c
clean_blob drivers/usb/misc/emi62.c
clean_kconfig drivers/usb/misc/Kconfig 'USB_EMI62'
clean_mk CONFIG_USB_EMI62 drivers/usb/misc/Makefile

announce USB_ISIGHTFW - "iSight firmware loading support"
reject_firmware drivers/usb/misc/isight_firmware.c
clean_blob drivers/usb/misc/isight_firmware.c
clean_kconfig drivers/usb/misc/Kconfig 'USB_ISIGHTFW'
clean_mk CONFIG_USB_ISIGHTFW drivers/usb/misc/Makefile

# serial

announce USB_SERIAL_KEYSPAN - "USB Keyspan USA-xxx Serial Driver"
drop_fw_file firmware/keyspan/mpr.HEX firmware/keyspan/mpr.fw
clean_kconfig drivers/usb/serial/Kconfig 'USB_SERIAL_KEYSPAN_MPR'
drop_fw_file firmware/keyspan/usa18x.HEX firmware/keyspan/usa18x.fw
clean_kconfig drivers/usb/serial/Kconfig 'USB_SERIAL_KEYSPAN_USA18X'
drop_fw_file firmware/keyspan/usa19.HEX firmware/keyspan/usa19.fw
clean_kconfig drivers/usb/serial/Kconfig 'USB_SERIAL_KEYSPAN_USA19'
drop_fw_file firmware/keyspan/usa19qi.HEX firmware/keyspan/usa19qi.fw
clean_kconfig drivers/usb/serial/Kconfig 'USB_SERIAL_KEYSPAN_USA19QI'
drop_fw_file firmware/keyspan/usa19qw.HEX firmware/keyspan/usa19qw.fw
clean_kconfig drivers/usb/serial/Kconfig 'USB_SERIAL_KEYSPAN_USA19QW'
drop_fw_file firmware/keyspan/usa19w.HEX firmware/keyspan/usa19w.fw
clean_kconfig drivers/usb/serial/Kconfig 'USB_SERIAL_KEYSPAN_USA19W'
drop_fw_file firmware/keyspan/usa28.HEX firmware/keyspan/usa28.fw
clean_kconfig drivers/usb/serial/Kconfig 'USB_SERIAL_KEYSPAN_USA28'
drop_fw_file firmware/keyspan/usa28xa.HEX firmware/keyspan/usa28xa.fw
clean_kconfig drivers/usb/serial/Kconfig 'USB_SERIAL_KEYSPAN_USA28XA'
drop_fw_file firmware/keyspan/usa28xb.HEX firmware/keyspan/usa28xb.fw
clean_kconfig drivers/usb/serial/Kconfig 'USB_SERIAL_KEYSPAN_USA28XB'
drop_fw_file firmware/keyspan/usa28x.HEX firmware/keyspan/usa28x.fw
clean_kconfig drivers/usb/serial/Kconfig 'USB_SERIAL_KEYSPAN_USA28X'
drop_fw_file firmware/keyspan/usa49w.HEX firmware/keyspan/usa49w.fw
clean_kconfig drivers/usb/serial/Kconfig 'USB_SERIAL_KEYSPAN_USA49W'
drop_fw_file firmware/keyspan/usa49wlc.HEX firmware/keyspan/usa49wlc.fw
clean_kconfig drivers/usb/serial/Kconfig 'USB_SERIAL_KEYSPAN_USA49WLC'
reject_firmware drivers/usb/serial/keyspan.c
clean_blob drivers/usb/serial/keyspan.c
clean_kconfig drivers/usb/serial/Kconfig 'USB_SERIAL_KEYSPAN'
clean_mk CONFIG_USB_SERIAL_KEYSPAN drivers/usb/serial/Makefile

announce USB_SERIAL_KEYSPAN_PDA - "USB Keyspan PDA Single Port Serial Driver"
clean_sed '
s,request_ihex_firmware,/*KEYSPAN_PDA*/&,
' drivers/usb/serial/keyspan_pda.c 'accept Free firmware'

announce USB_SERIAL_EDGEPORT - "USB Inside Out Edgeport Serial Driver"
clean_fw firmware/edgeport/boot.H16 firmware/edgeport/boot.fw
clean_fw firmware/edgeport/boot2.H16 firmware/edgeport/boot2.fw
clean_fw firmware/edgeport/down.H16 firmware/edgeport/down.fw
clean_fw firmware/edgeport/down2.H16 firmware/edgeport/down2.fw
reject_firmware drivers/usb/serial/io_edgeport.c
clean_blob drivers/usb/serial/io_edgeport.c
clean_kconfig drivers/usb/serial/Kconfig 'USB_SERIAL_EDGEPORT'
clean_mk CONFIG_USB_SERIAL_EDGEPORT drivers/usb/serial/Makefile

announce USB_SERIAL_EDGEPORT_TI - "USB Inside Out Edgeport Serial Driver (TI devices)"
clean_fw firmware/edgeport/down3.bin.ihex firmware/edgeport/down3.bin
reject_firmware drivers/usb/serial/io_ti.c
clean_blob drivers/usb/serial/io_ti.c
clean_kconfig drivers/usb/serial/Kconfig 'USB_SERIAL_EDGEPORT_TI'
clean_mk CONFIG_USB_SERIAL_EDGEPORT_TI drivers/usb/serial/Makefile

announce USB_SERIAL_TI - "USB TI 3410/5052 Serial Driver"
drop_fw_file firmware/ti_3410.fw.ihex firmware/ti_3410.fw
drop_fw_file firmware/ti_5052.fw.ihex firmware/ti_5052.fw
drop_fw_file firmware/mts_cdma.fw.ihex firmware/mts_cdma.fw
drop_fw_file firmware/mts_gsm.fw.ihex firmware/mts_gsm.fw
drop_fw_file firmware/mts_edge.fw.ihex firmware/mts_edge.fw
reject_firmware drivers/usb/serial/ti_usb_3410_5052.c
clean_blob drivers/usb/serial/ti_usb_3410_5052.c
clean_kconfig drivers/usb/serial/Kconfig 'USB_SERIAL_TI'
clean_mk CONFIG_USB_SERIAL_TI drivers/usb/serial/Makefile

announce USB_SERIAL_WHITEHEAT - "USB ConnectTech WhiteHEAT Serial Driver"
clean_fw firmware/whiteheat.HEX firmware/whiteheat.fw
clean_fw firmware/whiteheat_loader.HEX firmware/whiteheat_loader.fw
clean_fw firmware/whiteheat_loader_debug.HEX firmware/whiteheat_loader_debug.fw
reject_firmware drivers/usb/serial/whiteheat.c
clean_blob drivers/usb/serial/whiteheat.c
clean_kconfig drivers/usb/serial/Kconfig 'USB_SERIAL_WHITEHEAT'
clean_mk CONFIG_USB_SERIAL_WHITEHEAT drivers/usb/serial/Makefile

# uwb

announce UWB_I1480U - Support for Intel Wireless UWB Link 1480 HWA
reject_firmware drivers/uwb/i1480/dfu/i1480-dfu.h
reject_firmware drivers/uwb/i1480/dfu/mac.c
reject_firmware drivers/uwb/i1480/dfu/phy.c
clean_blob drivers/uwb/i1480/dfu/usb.c
clean_kconfig drivers/uwb/Kconfig 'UWB_I1480U'
clean_mk CONFIG_UWB_I1480U drivers/uwb/i1480/dfu/Makefile



#########
# Sound #
#########

announce SND_CS46XX - "Cirrus Logic (Sound Fusion) CS4280/CS461x/CS462x/CS463x"
# This appears to have been extracted from some non-Free driver
clean_file sound/pci/cs46xx/cs46xx_image.h
# The following blobs are definitely extracted from non-Free drivers.
clean_file sound/pci/cs46xx/imgs/cwc4630.h
clean_file sound/pci/cs46xx/imgs/cwcasync.h
clean_file sound/pci/cs46xx/imgs/cwcsnoop.h
clean_sed '
/^\(int \)\?snd_cs46xx_download_image([^;]*$/,/^}$/{
  /for.*BA1_MEMORY_COUNT/i\
#if 0
  /^}$/{
    i\
#else\
	snd_printk(KERN_ERR "cs46xx: Missing Free firmware\\n");\
	return -EINVAL;\
#endif
  }
}
s/cs46xx_dsp_load_module(chip, [&]cwc\(4630\|async\|snoop\)_module)/(snd_printk(KERN_ERR "cs46xx: Missing Free firmware\\n"),-EINVAL)/
' sound/pci/cs46xx/cs46xx_lib.c 'report missing Free firmware'
clean_blob sound/pci/cs46xx/cs46xx_lib.c
clean_kconfig sound/pci/Kconfig 'SND_CS46XX'
clean_mk 'CONFIG_SND_CS46XX' sound/pci/cs46xx/Makefile

announce SND_KORG1212 - "Korg 1212 IO"
drop_fw_file firmware/korg/k1212.dsp.ihex firmware/korg/k1212.dsp
reject_firmware sound/pci/korg1212/korg1212.c
clean_blob sound/pci/korg1212/korg1212.c
clean_kconfig sound/pci/Kconfig 'SND_KORG1212'
clean_mk 'CONFIG_SND_KORG1212' sound/pci/korg1212/Makefile

announce SND_MAESTRO3 - "ESS Allegro/Maestro3"
drop_fw_file firmware/ess/maestro3_assp_kernel.fw.ihex firmware/ess/maestro3_assp_kernel.fw
drop_fw_file firmware/ess/maestro3_assp_minisrc.fw.ihex firmware/ess/maestro3_assp_minisrc.fw
reject_firmware sound/pci/maestro3.c
clean_blob sound/pci/maestro3.c
clean_kconfig sound/pci/Kconfig 'SND_MAESTRO3'
clean_mk 'CONFIG_SND_MAESTRO3' sound/pci/Makefile

announce SND_YMFPCI - "Yamaha YMF724/740/744/754"
drop_fw_file firmware/yamaha/ds1_ctrl.fw.ihex firmware/yamaha/ds1_ctrl.fw
drop_fw_file firmware/yamaha/ds1_dsp.fw.ihex firmware/yamaha/ds1_dsp.fw
drop_fw_file firmware/yamaha/ds1e_ctrl.fw.ihex firmware/yamaha/ds1e_ctrl.fw
reject_firmware sound/pci/ymfpci/ymfpci_main.c
clean_blob sound/pci/ymfpci/ymfpci_main.c
clean_kconfig sound/pci/Kconfig 'SND_YMFPCI'
clean_mk 'CONFIG_SND_YMFPCI' sound/pci/ymfpci/Makefile

announce SND_SB16_CSP - "SB16 Advanced Signal Processor"
drop_fw_file firmware/sb16/alaw_main.csp.ihex firmware/sb16/alaw_main.csp
drop_fw_file firmware/sb16/mulaw_main.csp.ihex firmware/sb16/mulaw_main.csp
drop_fw_file firmware/sb16/ima_adpcm_init.csp.ihex firmware/sb16/ima_adpcm_init.csp
drop_fw_file firmware/sb16/ima_adpcm_capture.csp.ihex firmware/sb16/ima_adpcm_capture.csp
drop_fw_file firmware/sb16/ima_adpcm_playback.csp.ihex firmware/sb16/ima_adpcm_playback.csp
reject_firmware sound/isa/sb/sb16_csp.c
clean_blob sound/isa/sb/sb16_csp.c
clean_kconfig sound/isa/Kconfig 'SND_SB16_CSP'
clean_mk 'CONFIG_SND_SB16_CSP' sound/isa/sb/Makefile

announce SND_WAVEFRONT - "Turtle Beach Maui,Tropez,Tropez+ (Wavefront)"
drop_fw_file firmware/yamaha/yss225_registers.bin.ihex firmware/yamaha/yss225_registers.bin
reject_firmware sound/isa/wavefront/wavefront_fx.c
clean_blob sound/isa/wavefront/wavefront_fx.c
reject_firmware sound/isa/wavefront/wavefront_synth.c
clean_blob sound/isa/wavefront/wavefront_synth.c
clean_kconfig sound/isa/Kconfig 'SND_WAVEFRONT'
clean_mk 'CONFIG_SND_WAVEFRONT' sound/isa/wavefront/Makefile

announce SND_VX_LIB - Digigram VX soundcards
reject_firmware sound/drivers/vx/vx_hwdep.c
clean_blob sound/drivers/vx/vx_hwdep.c
clean_kconfig sound/drivers/Kconfig 'SND_VX_LIB'
clean_mk CONFIG_SND_VX_LIB sound/drivers/vx/Makefile

announce SND_DARLA20 - "(Echoaudio) Darla20"
clean_blob sound/pci/echoaudio/darla20.c
clean_kconfig sound/pci/Kconfig 'SND_DARLA20'
clean_mk CONFIG_SND_DARLA20 sound/pci/echoaudio/Makefile

announce SND_DARLA24 - "(Echoaudio) Darla24"
clean_blob sound/pci/echoaudio/darla24.c
clean_kconfig sound/pci/Kconfig 'SND_DARLA24'
clean_mk CONFIG_SND_DARLA24 sound/pci/echoaudio/Makefile

announce SND_ECHO3G - "(Echoaudio) 3G cards"
clean_blob sound/pci/echoaudio/echo3g.c
clean_kconfig sound/pci/Kconfig 'SND_ECHO3G'
clean_mk CONFIG_SND_ECHO3G sound/pci/echoaudio/Makefile

announce SND_GINA20 - "(Echoaudio) Gina20"
clean_blob sound/pci/echoaudio/gina20.c
clean_kconfig sound/pci/Kconfig 'SND_GINA20'
clean_mk CONFIG_SND_GINA20 sound/pci/echoaudio/Makefile

announce SND_GINA24 - "(Echoaudio) Gina24"
clean_blob sound/pci/echoaudio/gina24.c
clean_kconfig sound/pci/Kconfig 'SND_GINA24'
clean_mk CONFIG_SND_GINA24 sound/pci/echoaudio/Makefile

announce SND_INDIGO - "(Echoaudio) Indigo"
clean_blob sound/pci/echoaudio/indigo.c
clean_kconfig sound/pci/Kconfig 'SND_INDIGO'
clean_mk CONFIG_SND_INDIGO sound/pci/echoaudio/Makefile

announce SND_INDIGODJ - "(Echoaudio) Indigo DJ"
clean_blob sound/pci/echoaudio/indigodj.c
clean_kconfig sound/pci/Kconfig 'SND_INDIGODJ'
clean_mk CONFIG_SND_INDIGODJ sound/pci/echoaudio/Makefile

announce SND_INDIGODJX - "(Echoaudio) Indigo DJx"
clean_blob sound/pci/echoaudio/indigodjx.c
clean_kconfig sound/pci/Kconfig 'SND_INDIGODJX'
clean_mk CONFIG_SND_INDIGODJX sound/pci/echoaudio/Makefile

announce SND_INDIGOIO - "(Echoaudio) Indigo IO"
clean_blob sound/pci/echoaudio/indigoio.c
clean_kconfig sound/pci/Kconfig 'SND_INDIGOIO'
clean_mk CONFIG_SND_INDIGOIO sound/pci/echoaudio/Makefile

announce SND_INDIGOIOX - "(Echoaudio) Indigo IOx"
clean_blob sound/pci/echoaudio/indigoiox.c
clean_kconfig sound/pci/Kconfig 'SND_INDIGOIOX'
clean_mk CONFIG_SND_INDIGOIOX sound/pci/echoaudio/Makefile

announce SND_LAYLA20 - "(Echoaudio) Layla20"
clean_blob sound/pci/echoaudio/layla20.c
clean_kconfig sound/pci/Kconfig 'SND_LAYLA20'
clean_mk CONFIG_SND_LAYLA20 sound/pci/echoaudio/Makefile

announce SND_LAYLA24 - "(Echoaudio) Layla24"
clean_blob sound/pci/echoaudio/layla24.c
clean_kconfig sound/pci/Kconfig 'SND_LAYLA24'
clean_mk CONFIG_SND_LAYLA24 sound/pci/echoaudio/Makefile

announce SND_MIA - "(Echoaudio) Mia"
clean_blob sound/pci/echoaudio/mia.c
clean_kconfig sound/pci/Kconfig 'SND_MIA'
clean_mk CONFIG_SND_MIA sound/pci/echoaudio/Makefile

announce SND_MONA - "(Echoaudio) Mona"
clean_blob sound/pci/echoaudio/mona.c
clean_kconfig sound/pci/Kconfig 'SND_MONA'
clean_mk CONFIG_SND_MONA sound/pci/echoaudio/Makefile

announce SND_'<(Echoaudio)>' - "(Echoaudio) all of the above "
reject_firmware sound/pci/echoaudio/echoaudio.c
clean_blob sound/pci/echoaudio/echoaudio.c

announce SND_EMU10K1 - "Emu10k1 (SB Live!, Audigy, E-mu APS)"
reject_firmware sound/pci/emu10k1/emu10k1_main.c
clean_blob sound/pci/emu10k1/emu10k1_main.c
clean_kconfig sound/pci/Kconfig 'SND_EMU10K1'
clean_mk CONFIG_SND_EMU10K1 sound/pci/emu10k1/Makefile

announce SND_MIXART - "Digigram miXart"
reject_firmware sound/pci/mixart/mixart_hwdep.c
clean_blob sound/pci/mixart/mixart_hwdep.c
clean_kconfig sound/pci/Kconfig 'SND_MIXART'
clean_mk CONFIG_SND_MIXART sound/pci/mixart/Makefile

announce SND_PCXHR - "Digigram PCXHR"
reject_firmware sound/pci/pcxhr/pcxhr_hwdep.c
clean_blob sound/pci/pcxhr/pcxhr_hwdep.c
clean_kconfig sound/pci/Kconfig 'SND_PCXHR'
clean_mk CONFIG_SND_PCXHR sound/pci/pcxhr/Makefile

announce SND_RIPTIDE - "Conexant Riptide"
reject_firmware sound/pci/riptide/riptide.c
clean_blob sound/pci/riptide/riptide.c
clean_kconfig sound/pci/Kconfig 'SND_RIPTIDE'
clean_mk CONFIG_SND_RIPTIDE sound/pci/riptide/Makefile

announce SND_HDSP - "RME Hammerfall DSP Audio"
reject_firmware sound/pci/rme9652/hdsp.c
clean_blob sound/pci/rme9652/hdsp.c
clean_kconfig sound/pci/Kconfig 'SND_HDSP'
clean_mk CONFIG_SND_HDSP sound/pci/rme9652/Makefile

announce SND_AICA - "Dreamcast Yamaha AICA sound"
reject_firmware sound/sh/aica.c
clean_blob sound/sh/aica.c
clean_kconfig sound/sh/Kconfig 'SND_AICA'
clean_mk CONFIG_SND_AICA sound/sh/Makefile

announce SND_MSND_PINNACLE - "Support for Turtle Beach MultiSound Pinnacle"
clean_blob sound/isa/msnd/msnd_pinnacle.h
reject_firmware sound/isa/msnd/msnd_pinnacle.c
clean_blob sound/isa/msnd/msnd_pinnacle.c
clean_kconfig sound/isa/Kconfig 'SND_MSND_PINNACLE'
clean_mk CONFIG_SND_MSND_PINNACLE sound/isa/msnd/Makefile

announce SND_MSND_CLASSIC - "Support for Turtle Beach MultiSound Classic, Tahiti, Monterey"
clean_blob sound/isa/msnd/msnd_classic.h
clean_kconfig sound/isa/Kconfig 'SND_MSND_CLASSIC'
clean_mk CONFIG_SND_MSND_CLASSIC sound/isa/msnd/Makefile

announce SOUND_MSNDCLAS - "Support for Turtle Beach MultiSound Classic, Tahiti, Monterey (oss)"
clean_blob sound/oss/msnd_classic.h
clean_kconfig sound/oss/Kconfig 'SOUND_MSNDCLAS'
clean_sed '
/^config MSNDCLAS_INIT_FILE$/, /^config / {
  /^	default.*msndinit\.bin/ s,".*","/*(DEBLOBBED)*/",;
}
/^config MSNDCLAS_PERM_FILE$/, /^config / {
  /^	default.*msndperm\.bin/ s,".*","/*(DEBLOBBED)*/",;
}' sound/oss/Kconfig 'removed default firmware'
clean_mk CONFIG_SOUND_MSNDCLAS sound/oss/Makefile

announce SOUND_MSNDPIN - "Support for Turtle Beach MultiSound Pinnacle (oss)"
clean_blob sound/oss/msnd_pinnacle.h
clean_kconfig sound/oss/Kconfig 'SOUND_MSNDPIN'
clean_sed '
/^config MSNDPIN_INIT_FILE$/, /^config / {
  /^	default.*pndspini\.bin/ s,".*","/*(DEBLOBBED)*/",;
}
/^config MSNDPIN_PERM_FILE$/, /^config / {
  /^	default.*pndsperm\.bin/ s,".*","/*(DEBLOBBED)*/",;
}' sound/oss/Kconfig 'removed default firmware'
clean_mk CONFIG_SOUND_MSNDPIN sound/oss/Makefile

announce SOUND_SSCAPE - "Ensoniq SoundScape support"
clean_blob sound/oss/sscape.c
clean_kconfig sound/oss/Kconfig 'SOUND_SSCAPE'
clean_mk CONFIG_SOUND_SSCAPE sound/oss/Makefile

announce SOUND_TRIX - "MediaTrix AudioTrix Pro support"
clean_blob sound/oss/trix.c
clean_kconfig sound/oss/Kconfig 'SOUND_TRIX'
clean_sed '
/^config TRIX_BOOT_FILE$/, /^config / {
  /^	default.*trxpro\.hex/ s,".*","/*(DEBLOBBED)*/",;
}' sound/oss/Kconfig 'removed default firmware'
clean_mk CONFIG_SOUND_TRIX sound/oss/Makefile

announce SOUND_TRIX - "See above,"
announce SOUND_PAS - "ProAudioSpectrum 16 support,"
announce SOUND_SB - "100% Sound Blaster compatibles (SB16/32/64, ESS, Jazz16) support"
clean_blob sound/oss/sb_common.c
clean_kconfig sound/oss/Kconfig 'SOUND_PAS'
clean_kconfig sound/oss/Kconfig 'SOUND_SB'
clean_mk CONFIG_SOUND_PAS sound/oss/Makefile
clean_mk CONFIG_SOUND_SB sound/oss/Makefile

announce SOUND_PSS - "PSS (AD1848, ADSP-2115, ESC614) support"
clean_sed 's,^\( [*] .*synth"\)\.$,\1/*.,' sound/oss/pss.c 'avoid nested comments'
clean_blob sound/oss/pss.c
clean_kconfig sound/oss/Kconfig 'SOUND_PSS'
clean_sed '
/^config PSS_BOOT_FILE$/, /^config / {
  /^	default.*dsp001\.ld/ s,".*","/*(DEBLOBBED)*/",;
}' sound/oss/Kconfig 'removed default firmware'
clean_mk CONFIG_SOUND_PSS sound/oss/Makefile

#################
# Documentation #
#################

announce Documentation - "non-Free firmware scripts and documentation"
clean_blob Documentation/dvb/avermedia.txt
clean_blob Documentation/dvb/opera-firmware.txt
clean_blob Documentation/dvb/ttusb-dec.txt
clean_blob Documentation/sound/alsa/ALSA-Configuration.txt
clean_blob Documentation/sound/oss/MultiSound
clean_blob Documentation/sound/oss/PSS
clean_blob Documentation/sound/oss/PSS-updates
clean_file Documentation/dvb/get_dvb_firmware
clean_file Documentation/video4linux/extract_xc3028.pl
clean_sed s,usb8388,whatever,g drivers/base/Kconfig 'removed blob name'
clean_blob firmware/README.AddingFirmware
clean_blob firmware/WHENCE

if $errors; then
  echo errors above were ignored because of --force >&2
fi

exit 0
