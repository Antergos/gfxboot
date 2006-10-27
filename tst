#! /bin/sh


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

function switch_disk {
  disk=$1
  tmp=tmp

  if [ -z "$disk" -o ! -f "$tmp/syslinux.img_$disk" ] ; then
    echo "usage:"
    echo "  tst -d disk_number"
    exit 1
  fi

  dd if="$tmp/syslinux.img_$disk" of="$tmp/syslinux.img" conv=notrunc status=noxfer
}


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

function tst_isolinux {
  bin="test/syslinux.rpm"
  src="test/$1"
  dst="$tmp/$1"
  img="$tmp/$1.iso"
  vm_src=test/vm
  vm_tmp=tmp/$1.vm
  isolx=$bin/usr/share/syslinux/isolinux.bin

  rm -rf $dst $vm_tmp
  rm -f $img

  isodir32=boot/i386/loader
  isodir64=boot/x86_64/loader
  mkdir -p $dst/$isodir32 $dst/$isodir64
  cp $isolx $dst/$isodir32/isolinux.bin
  cp $isolx $dst/$isodir64/isolinux.bin
  test/syslinux.rpm/usr/bin/isolinux-config --base=$isodir32 $dst/$isodir32/isolinux.bin
  test/syslinux.rpm/usr/bin/isolinux-config --base=$isodir64 $dst/$isodir64/isolinux.bin

  cp -a $src/* $dst/$isodir32
  rm -f $dst/$isodir32/{linux,initrd}64
  cp -a $logo $dst/$isodir32/bootlogo
  gfx_cfg=$dst/$isodir32/gfxboot.cfg
  [ -f $gfx_cfg ] && mv $gfx_cfg ${gfx_cfg}.tmp
  bin/unpack_bootlogo $dst/$isodir32
  [ -f ${gfx_cfg}.tmp ] && cat ${gfx_cfg}.tmp >>$gfx_cfg
  rm -f ${gfx_cfg}.tmp

  cp -a $src/* $dst/$isodir64
  [ -f $dst/$isodir64/linux64 ] && mv $dst/$isodir64/linux64 $dst/$isodir64/linux
  [ -f $dst/$isodir64/initrd64 ] && mv $dst/$isodir64/initrd64 $dst/$isodir64/initrd
  cp -a $logo $dst/$isodir64/bootlogo
  gfx_cfg=$dst/$isodir64/gfxboot.cfg
  [ -f $gfx_cfg ] && mv $gfx_cfg ${gfx_cfg}.tmp
  bin/unpack_bootlogo $dst/$isodir64
  [ -f ${gfx_cfg}.tmp ] && cat ${gfx_cfg}.tmp >>$gfx_cfg
  rm -f ${gfx_cfg}.tmp

  test/2hl --link --quiet $dst

  echo "$dst/$isodir32/isolinux.bin 1" >$tmp/cd_sort
  echo "$dst/$isodir64/isolinux.bin 1" >>$tmp/cd_sort

  rm -f `find $dst/boot -name \*~`

  # rm -r $dst/boot/x86_64

  mkisofs -o $img -J -r -sort $tmp/cd_sort \
    -b $isodir32/isolinux.bin -c $isodir32/boot.catalog \
    -publisher "Tester" \
    -no-emul-boot -boot-load-size 4 -boot-info-table $dst

  rm -f $tmp/cd_sort

  if [ "$program" = vmware ] ; then
    # vmware
    cp -a $vm_src $vm_tmp
    perl -pi -e "s/^\s*#\s*(floppy0.startConnected)/\$1/" $vm_tmp/gfxboot.vmx
    perl -pi -e "s:<isoimage>:`pwd`/$img:g" $vm_tmp/gfxboot.vmx
    vmware -qx $vm_tmp/gfxboot.vmx
  elif [ "$program" = qemu ] ; then
    # qemu
    qemu -cdrom $img
  elif [ "$program" = bd ] ; then
    # bochs debug wrapper
    bd $img
  elif [ "$program" = bochs ] ; then
    # bochs
    bochs -q 'boot: cdrom' "ata0-master: type=cdrom, path=$img, status=inserted" 'log: /dev/null' 'parport1: enabled=0'
  else
    echo -e "\n***  Error: $program not supported  ***\n"
  fi
}


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

function tst_lilo {
  bin="test/lilo.rpm"
  src="test/$1"
  dst="$tmp/$1"
  img="$tmp/$1.img"
  vm_src=test/vm
  vm_tmp=tmp/$1.vm

  rm -rf $dst $vm_tmp
  rm -f $img

  mkdir -p $dst/boot
  cp -a $src/* $dst/boot
  cp -a $logo $dst/boot/message

  for i in /boot/vmlinuz /boot/initrd ; do
    [ -f $i ] && cp --parents $i $dst
  done

  test/hdimg $img

  sw 0 mount -oloop=/dev/loop7,offset=32256 $img /mnt
  sw 0 cp -r $dst/* /mnt
  sw 0 losetup /dev/loop6 $img
  sw 0 $bin/sbin/lilo -w -C /mnt/boot/lilo.conf -m /mnt/boot/map
  sw 0 losetup -d /dev/loop6
  sw 0 umount /mnt

  if [ "$program" = vmware ] ; then
    # vmware
    cp -a $vm_src $vm_tmp
    perl -pi -e "s/^\s*#\s*(ide1:0.startConnected)/\$1/" $vm_tmp/gfxboot.vmx
    perl -pi -e "s:<floppyimage>:`pwd`/$img:g" $vm_tmp/gfxboot.vmx
    vmware -qx $vm_tmp/gfxboot.vmx
  elif [ "$program" = qemu ] ; then
    # qemu
    qemu -boot c -hda $img
  elif [ "$program" = bd ] ; then
    # bochs debug wrapper
    bd $img
  elif [ "$program" = bochs ] ; then
    # bochs
    bochs -q 'boot: a' "floppya: image=$img, status=inserted" 'log: /dev/null' 'ata0-master: type=disk, path=/dev/null' 'parport1: enabled=0'
  else
    echo -e "\n***  Error: $program not supported  ***\n"
  fi
}


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

function tst_grub {
  bin="test/grub.rpm"
  src="test/$1"
  dst="$tmp/$1"
  img="$tmp/$1.img"
  vm_src=test/vm
  vm_tmp=tmp/$1.vm

  rm -rf $dst $vm_tmp
  rm -f $img

  mkdir -p $dst/boot
  cp -a $src/* $dst/boot
  cp $bin/usr/lib/grub/{fat_stage1_5,stage1,stage2} $dst/boot/grub
  cp -a $logo $dst/boot/message
  for i in /boot/vmlinuz /boot/initrd ; do
    [ -f $i ] && cp --parents $i $dst
  done

  sh -c "echo '(hd0) $img' >$dst/boot/grub/device.map"

  test/hdimg $img

  sw 0 mount -oloop,offset=32256 "$img" /mnt
  sw 0 cp -r $dst/* /mnt
  sw 0 umount /mnt

  echo "setup --prefix=/boot/grub (hd0,0) (hd0,0)" | \
  $bin/usr/sbin/grub --batch --config-file=$dst/boot/grub/menu.lst --device-map=$dst/boot/grub/device.map
  echo

  if [ "$program" = vmware ] ; then
    # vmware
    cp -a $vm_src $vm_tmp
    perl -pi -e "s/^\s*#\s*(ide1:0.startConnected)/\$1/" $vm_tmp/gfxboot.vmx
    perl -pi -e "s:<floppyimage>:`pwd`/$img:g" $vm_tmp/gfxboot.vmx
    vmware -qx $vm_tmp/gfxboot.vmx
  elif [ "$program" = qemu ] ; then
    # qemu
    qemu -boot c -hda $img
  elif [ "$program" = bd ] ; then
    # bochs debug wrapper
    bd $img
  elif [ "$program" = bochs ] ; then
    # bochs
    bochs -q 'boot: a' "floppya: image=$img, status=inserted" 'log: /dev/null' 'ata0-master: type=disk, path=/dev/null' 'parport1: enabled=0'
  else
    echo -e "\n***  Error: $program not supported  \n"
  fi
}


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

function tst_syslinux {
  bin="test/syslinux.rpm"
  src="test/$1"
  dst="$tmp/$1"
  img="$tmp/$1.img"
  vm_src=test/vm
  vm_tmp=tmp/$1.vm
  syslx=$bin/usr/bin/syslinux-nomtools

  rm -rf $dst $vm_tmp
  rm -f $img*

  mkdir -p $dst
  cp -a $src/* $dst
  cp -a $logo $dst/bootlogo

  rm -f $dst/*~

  sw 0 test/mkbootdisk --syslinux=$syslx --out=${img}_ $dst

  sw 0 chown --reference=tmp $img*

  cp $dst.img_1 $img

  if [ "$program" = vmware ] ; then
    # vmware
    cp -a $vm_src $vm_tmp
    perl -pi -e "s/^\s*#\s*(ide1:0.startConnected)/\$1/" $vm_tmp/gfxboot.vmx
    perl -pi -e "s:<floppyimage>:`pwd`/$img:g" $vm_tmp/gfxboot.vmx
    vmware -qx $vm_tmp/gfxboot.vmx
  elif [ "$program" = qemu ] ; then
    # qemu
    qemu -boot a -fda $img
  elif [ "$program" = bd ] ; then
    # bochs debug wrapper
    bd $img
  elif [ "$program" = bochs ] ; then
    # bochs
    bochs -q 'boot: a' "floppya: image=$img, status=inserted" 'log: /dev/null' 'ata0-master: type=disk, path=/dev/null' 'parport1: enabled=0'
  else
    echo -e "\n***  Error: $program not supported  ***\n"
  fi
}



# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

function usage {
  echo "usage: tst [-b] [-d floppy_nr] [-i] [-l language] [-p program] [-s test_src_dir] [-t theme] what"
  exit 1
}


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

while getopts bd:hil:p:s:t: opt ; do
  case $opt in
    \:|\?|h) usage
      ;;

    b) logo=boot
      ;;

    d) disk=$OPTARG
      ;;

    i) logo=install
      ;;

    l) lang="DEFAULT_LANG=$OPTARG"
      ;;

    p) program=$OPTARG
      ;;

    s) src=$OPTARG
      ;;

    t) theme=$OPTARG
      ;;
  esac
done
shift $(($OPTIND - 1))

if [ "$disk" ] ; then
  switch_disk $disk
  exit
fi

theme=${theme:-SuSE}

program=${program:-qemu}

what=$1
what=${what:-cdrom}

[ "$what" = cdrom ] && what=isolinux
[ "$what" = cd ] && what=isolinux
[ "$what" = floppy ] && what=syslinux

if [ ! "$logo" ] ; then
  logo=boot
  [ "$what" = syslinux -o "$what" = isolinux ] && logo=install
fi

[ "$logo" = "boot" ] && logo="themes/$theme/boot/message"
[ "$logo" = "install" ] && logo="themes/$theme/install/bootlogo"

[ "$BOOTLOGO" ] && logo=$BOOTLOGO

[ -x mkbootmsg ] || {
  echo "error: mkbootmsg missing. Try make."
  exit 2
}

if [ ! "$what" ] ; then
  echo "What is "\""$what"\""?"
  usage
fi

make BINDIR=../../ -C themes/$theme prep
make BINDIR=../../ -C themes/$theme $lang || exit

[ -f "$logo" ] || logo="themes/$theme/bootlogo"

if [ ! -f "$logo" ] ; then
  echo "no such file: $logo"
  usage
fi

tmp=tmp
mkdir -p "$tmp" || exit

if [ -z "$src" ] ; then
  src=$what
  [ $what = isolinux ] && src=syslinux
fi

if [ ! -d test/$src ] ; then
  echo "no such directory: $src"
  usage
fi

if [ "`type -t tst_$what`" = function ] ; then
  tst_$what $src
else
  echo "What is "\""$what"\""?"
  usage
fi

