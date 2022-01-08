#!/usr/bin/env mksh
# -*- mode: sh -*-
#-
# Copyright © 2022
#	mirabilos <m@mirbsd.org>
#
# Provided that these terms and disclaimer and all copyright notices
# are retained or reproduced in an accompanying document, permission
# is granted to deal in this work without restriction, including un‐
# limited rights to use, publicly perform, distribute, sell, modify,
# merge, give away, or sublicence.
#
# This work is provided “AS IS” and WITHOUT WARRANTY of any kind, to
# the utmost extent permitted by applicable law, neither express nor
# implied; without malicious intent or gross negligence. In no event
# may a licensor, author or contributor be held liable for indirect,
# direct, other damage, loss, or other issues arising in any way out
# of dealing in the work, even if advised of the possibility of such
# damage or existence of a defect, except proven that it results out
# of said person’s immediate fault when using the work as intended.
#-
# Installs an MBR bootmanager or bootloader to a hard disc.

export LC_ALL=C
unset LANGUAGE
set -e
me=${0##*/}
trap 'print -ru2 -- E: '"${me@Q}"'"[$LINENO]: unexpected errorlevel $?, aborting"' ERR
set -o pipefail

mydir=$(realpath "$0/..")
cd "$mydir"

die() {
	print -ru2 -- "E: $*"
	exit 1
}

usage() {
	print -ru2 \
"Usage:	$me -l [-a] [-p n] /dev/sdX
	$me -m [-a] [-p n] [-t n] /dev/sdX
Load the MBR from the disc, update it (with -a, also randomise the serial
number) and show the new MBR and partition table; ask for confirmation,
then write to disc. -p 1..4 overrides the partition to boot. -m installs
the boot manager; -t to change its menu timeout (default 10000 ms)"
	exit ${1:-1}
}

# From MirOS: src/sbin/fdisk/partlist.sh,v 1.1 2022/01/08 07:27:57 tg Exp $
parttype_unknown='<Unknown ID>'
function parttypes_init {
	integer i=0

	set -A parttypes
	while ((# i <= 0xFF )); do
		parttypes[i++]=$parttype_unknown
	done
	unset -f parttypes_init
}
parttypes_init
parttypes[0x00]='unused      '	# unused
parttypes[0x01]='FAT <16M CHS'	# Primary DOS usually with 12-bit FAT
parttypes[0x02]='XENIX /     '	# XENIX / filesystem
parttypes[0x03]='XENIX /usr  '	# XENIX /usr filesystem
parttypes[0x04]='FAT <32M CHS'	# Primary DOS usually with 16-bit FAT
parttypes[0x05]='Extended CHS'	# Extended DOS within 1024 cylinders
parttypes[0x06]='FAT <2GB CHS'	# Primary 'big' DOS (> 32 MiB)
parttypes[0x07]='HPFS/QNX/AUX'	# OS/2 HPFS, QNX-2 or Advanced UNIX
parttypes[0x08]='AIX fs      '	# AIX filesystem
parttypes[0x09]='AIX/Coherent'	# AIX boot partition or Coherent
parttypes[0x0A]='OS/2 Bootmgr'	# OS/2 Boot Manager or OPUS
parttypes[0x0B]='FAT >2GB CHS'	# Primary DOS usually w/ 32-bit FAT
parttypes[0x0C]='FAT >2GB LBA'	# Primary DOS u.w/ 32-bit FAT LBA-mapped
parttypes[0x0E]='FAT <2GB LBA'	# Primary DOS u.w/ 16-bit FAT LBA-mapped
parttypes[0x0F]='Extended LBA'	# Extended DOS LBA-mapped
parttypes[0x10]='OPUS        '	# OPUS
parttypes[0x11]='OS/2 hidden '	# OS/2 BM: hidden DOS 12-bit FAT
parttypes[0x12]='Compaq Diag.'	# Compaq Diagnostics
parttypes[0x14]='OS/2 hidden '	# OS/2 BM: hidden DOS 16-bit FAT <32M or Novell DOS 7.0 bug
parttypes[0x16]='OS/2 hidden '	# OS/2 BM: hidden DOS 16-bit FAT >=32M
parttypes[0x17]='OS/2 hidden '	# OS/2 BM: hidden IFS
parttypes[0x18]='AST swap    '	# AST Windows swapfile
parttypes[0x19]='Willowtech  '	# Willowtech Photon coS
parttypes[0x1C]='Thinkpad Rec'	# IBM Thinkpad recovery partition
parttypes[0x20]='Willowsoft  '	# Willowsoft OFS1
parttypes[0x24]='NEC DOS     '	# NEC DOS
parttypes[0x27]='MirBSD      '	# MirOS BSD disklabel
parttypes[0x38]='Theos       '	# Theos
parttypes[0x39]='Plan 9      '	# Plan 9
parttypes[0x40]='VENIX 286   '	# VENIX 286 or LynxOS
parttypes[0x41]='Lin/Minux DR'	# Linux/MINIX (sharing disk with DRDOS) or Personal RISC boot
parttypes[0x42]='Dynamic Disc'	# NT LVM; SFS or Linux swap (sharing disk with DRDOS)
parttypes[0x43]='Linux DR    '	# Linux native (sharing disk with DRDOS)
parttypes[0x4D]='QNX 4.2 Pri '	# QNX 4.2 Primary
parttypes[0x4E]='QNX 4.2 Sec '	# QNX 4.2 Secondary
parttypes[0x4F]='QNX 4.2 Ter '	# QNX 4.2 Tertiary
parttypes[0x50]='DM          '	# DM (disk manager)
parttypes[0x51]='DMaux/Novell'	# DM6 Aux1 (or Novell)
parttypes[0x52]='CP/M or SysV'	# CP/M or Microport SysV/AT
parttypes[0x53]='DMaux3      '	# DM6 Aux3
parttypes[0x54]='Ontrack     '	# Ontrack
parttypes[0x55]='EZ-Drive    '	# EZ-Drive (disk manager)
parttypes[0x56]='Golden Bow  '	# Golden Bow (disk manager)
parttypes[0x5C]='Priam       '	# Priam Edisk (disk manager)
parttypes[0x61]='SpeedStor   '	# SpeedStor
parttypes[0x63]='ISC, HURD, *'	# ISC, System V/386, GNU HURD or Mach
parttypes[0x64]='NetWare 2.xx'	# Novell NetWare 2.xx
parttypes[0x65]='NetWare 3.xx'	# Novell NetWare 3.xx
parttypes[0x66]='NetWare 386 '	# Novell 386 NetWare
parttypes[0x67]='Novell      '	# Novell
parttypes[0x68]='Novell      '	# Novell
parttypes[0x69]='Novell      '	# Novell
parttypes[0x70]='DiskSecure  '	# DiskSecure Multi-Boot
parttypes[0x75]='PCIX        '	# PCIX
parttypes[0x80]='Minix (old) '	# Minix 1.1 ... 1.4a
parttypes[0x81]='Minix (new) '	# Minix 1.4b ... 1.5.10
parttypes[0x82]='Linux swap  '	# Linux swap
parttypes[0x83]='Linux fs    '	# Linux filesystem
parttypes[0x84]='OS/2 hidden '	# OS/2 hidden C: drive
parttypes[0x85]='Linux ext.  '	# Linux extended LBA
parttypes[0x86]='NT FAT VS   '	# NT FAT volume set
parttypes[0x87]='NTFS VS     '	# NTFS volume set or HPFS mirrored
parttypes[0x88]='O.ADK cfgfs '	# OpenADK cfgfs or fwcf
parttypes[0x93]='Amoeba FS   '	# Amoeba filesystem
parttypes[0x94]='Amoeba BBT  '	# Amoeba bad block table
parttypes[0x96]='ISO 9660    '	# ISO 9660 (CHRP, manifold-boot)
parttypes[0x99]='Mylex       '	# Mylex EISA SCSI
parttypes[0x9F]='BSDI        '	# BSDI BSD/OS
parttypes[0xA0]='NotebookSave'	# Phoenix NoteBIOS save-to-disk
parttypes[0xA5]='FreeBSD     '	# FreeBSD
parttypes[0xA6]='OpenBSD     '	# OpenBSD
parttypes[0xA7]='NEXTSTEP    '	# NEXTSTEP
parttypes[0xA8]='MacOS X     '	# MacOS X main partition
parttypes[0xA9]='NetBSD      '	# NetBSD
parttypes[0xAB]='MacOS X boot'	# MacOS X boot partition
parttypes[0xB7]='BSDI filesys'	# BSDI BSD/386 filesystem
parttypes[0xB8]='BSDI swap   '	# BSDI BSD/386 swap
parttypes[0xBF]='Solaris     '	# Solaris
parttypes[0xC0]='CTOS        '	# CTOS
parttypes[0xC1]='DRDOSs FAT12'	# DRDOS/sec (FAT-12)
parttypes[0xC4]='DRDOSs < 32M'	# DRDOS/sec (FAT-16, < 32M)
parttypes[0xC6]='DRDOSs >=32M'	# DRDOS/sec (FAT-16, >= 32M)
parttypes[0xC7]='HPFS Disbled'	# Syrinx (Cyrnix?) or HPFS disabled
parttypes[0xDA]='non-FS data '	# raw / non-filesystem data
parttypes[0xDB]='CPM/C.DOS/C*'	# Concurrent CPM or C.DOS or CTOS
parttypes[0xDE]='Dell Maint  '	# Dell maintenance partition
parttypes[0xE1]='SpeedStor   '	# DOS access or SpeedStor 12-bit FAT extended partition
parttypes[0xE3]='SpeedStor   '	# DOS R/O or SpeedStor or Storage Dimensions
parttypes[0xE4]='SpeedStor   '	# SpeedStor 16-bit FAT extended partition < 1024 cyl.
parttypes[0xEB]='BeOS/i386   '	# BeOS for Intel
parttypes[0xEE]='EFI GPT     '	# EFI Protective Partition
parttypes[0xEF]='EFI Sys     '	# EFI System Partition
parttypes[0xF1]='SpeedStor   '	# SpeedStor or Storage Dimensions
parttypes[0xF2]='DOS 3.3+ Sec'	# DOS 3.3+ Secondary
parttypes[0xF4]='SpeedStor   '	# SpeedStor >1024 cyl. or LANstep or IBM PS/2 IML
parttypes[0xFD]='Linux oRAID '	# Linux (old) RAID autodetect
parttypes[0xFF]='Xenix BBT   '	# Xenix Bad Block Table
# end of partlist

echo '[WIP] tbd'
print -r -- "[${parttypes[0xFD]}]"
print -r -- "[${parttypes[0xFE]}]"
usage 0
