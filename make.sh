#!/bin/bash

URL="$1"
date="$2"
GITHUB_ENV="$3"
GITHUB_WORKSPACE="$4"
VENDOR_URL="$5"

origin_date=$(echo ${URL} | cut -d"/" -f4)
origin_Bottom_date=$(echo ${VENDOR_URL} | cut -d"/" -f4)
ORIGN_ZIP_NAME=$(echo ${VENDOR_URL} | cut -d"/" -f5)
android_version=$(echo ${URL} | cut -d"_" -f5 | cut -d"." -f1)

magiskboot="$GITHUB_WORKSPACE"/tools/magiskboot

device=shennong

Start_Time() {
  Start_ns=$(date +'%s%N')
}

End_Time() {
  # 小时、分钟、秒、毫秒、纳秒
  local h min s ms ns End_ns time
  End_ns=$(date +'%s%N')
  time=$(expr $End_ns - $Start_ns)
  [[ -z "$time" ]] && return 0
  ns=${time:0-9}
  s=${time%$ns}
  if [[ $s -ge 10800 ]]; then
    echo -e "\e[1;34m - 本次$1用时: 少于100毫秒 \e[0m"
  elif [[ $s -ge 3600 ]]; then
    ms=$(expr $ns / 1000000)
    h=$(expr $s / 3600)
    h=$(expr $s % 3600)
    if [[ $s -ge 60 ]]; then
      min=$(expr $s / 60)
      s=$(expr $s % 60)
    fi
    echo -e "\e[1;34m - 本次$1用时: $h小时$min分$s秒$ms毫秒 \e[0m"
  elif [[ $s -ge 60 ]]; then
    ms=$(expr $ns / 1000000)
    min=$(expr $s / 60)
    s=$(expr $s % 60)
    echo -e "\e[1;34m - 本次$1用时: $min分$s秒$ms毫秒 \e[0m"
  elif [[ -n $s ]]; then
    ms=$(expr $ns / 1000000)
    echo -e "\e[1;34m - 本次$1用时: $s秒$ms毫秒 \e[0m"
  else
    ms=$(expr $ns / 1000000)
    echo -e "\e[1;34m - 本次$1用时: $ms毫秒 \e[0m"
  fi
}

### 系统包下载
echo -e "\e[1;31m - 开始下载系统包 \e[0m"
echo -e "\e[1;33m - 开始下载待移植包 \e[0m"
Start_Time
aria2c -x16 -j$(nproc) -U "Mozilla/5.0" -d "$GITHUB_WORKSPACE" ${URL}
End_Time 下载待移植包
Start_Time
echo -e "\e[1;33m - 开始下载底包 \e[0m"
aria2c -x16 -j$(nproc) -U "Mozilla/5.0" -d "$GITHUB_WORKSPACE" ${VENDOR_URL}
End_Time 下载底包
### 系统包下载结束

### 解包
sudo chmod -R 777 "$GITHUB_WORKSPACE"/tools
echo -e "\e[1;31m - 开始解包 \e[0m"
Start_Time
mkdir -p "$GITHUB_WORKSPACE"/Third_Party
mkdir -p "$GITHUB_WORKSPACE"/"${device}"
mkdir -p "$GITHUB_WORKSPACE"/images/config
mkdir -p "$GITHUB_WORKSPACE"/zip
ZIP_NAME_Third_Party=$(echo ${URL} | cut -d"/" -f5)
7z x "$GITHUB_WORKSPACE"/$ZIP_NAME_Third_Party -r -o"$GITHUB_WORKSPACE"/Third_Party
rm -rf "$GITHUB_WORKSPACE"/$ZIP_NAME_Third_Party
7z x "$GITHUB_WORKSPACE"/${ORIGN_ZIP_NAME} -o"$GITHUB_WORKSPACE"/"${device}" payload.bin
rm -rf "$GITHUB_WORKSPACE"/${ORIGN_ZIP_NAME}
mkdir -p "$GITHUB_WORKSPACE"/Extra_dir
"$GITHUB_WORKSPACE"/tools/payload-dumper-go -o "$GITHUB_WORKSPACE"/Extra_dir/ "$GITHUB_WORKSPACE"/"${device}"/payload.bin >/dev/null
for image_name in product system system_ext; do
  sudo rm -rf "$GITHUB_WORKSPACE"/Extra_dir/$image_name.img
done
sudo rm -rf "$GITHUB_WORKSPACE"/"${device}"/payload.bin
End_Time 解包
echo -e "\e[1;31m - 开始分解 IMAGE \e[0m"
for i in mi_ext odm system_dlkm vendor vendor_dlkm; do
  echo -e "\e[1;33m - 正在分解: $i \e[0m"
  Start_Time
  cd "$GITHUB_WORKSPACE"/"${device}"
  sudo "$GITHUB_WORKSPACE"/tools/extract.erofs -i "$GITHUB_WORKSPACE"/Extra_dir/$i.img -x >/dev/null
  rm -rf "$GITHUB_WORKSPACE"/Extra_dir/$i.img
  End_Time 分解$i.img
done
sudo mkdir -p "$GITHUB_WORKSPACE"/"${device}"/firmware-update/
sudo cp -rf "$GITHUB_WORKSPACE"/Extra_dir/* "$GITHUB_WORKSPACE"/"${device}"/firmware-update/
for i in mi_ext product system system_ext; do
  echo -e "\e[1;33m - 正在分解: $i \e[0m"
  "$GITHUB_WORKSPACE"/tools/payload-dumper-go -o "$GITHUB_WORKSPACE"/images/ -p $i "$GITHUB_WORKSPACE"/Third_Party/payload.bin >/dev/null
  Start_Time
  cd "$GITHUB_WORKSPACE"/images
  sudo "$GITHUB_WORKSPACE"/tools/extract.erofs -i "$GITHUB_WORKSPACE"/images/$i.img -x >/dev/null
  rm -rf "$GITHUB_WORKSPACE"/images/$i.img
  End_Time 分解$i.img
done
sudo rm -rf "$GITHUB_WORKSPACE"/Third_Party
### 解包结束

### 功能修复
echo -e "\e[1;31m - 开始功能修复 \e[0m"
Start_Time
# 替换 vendor_boot 的 fstab
echo -e "\e[1;31m - 替换 Vendor Boot 的 fstab \e[0m"
mkdir -p "$GITHUB_WORKSPACE"/vendor_boot
cd "$GITHUB_WORKSPACE"/vendor_boot
mv -f "$GITHUB_WORKSPACE"/"${device}"/firmware-update/vendor_boot.img "$GITHUB_WORKSPACE"/vendor_boot
$magiskboot unpack -h "$GITHUB_WORKSPACE"/vendor_boot/vendor_boot.img 2>&1
if [ -f ramdisk.cpio ]; then
  comp=$($magiskboot decompress ramdisk.cpio 2>&1 | grep -v 'raw' | sed -n 's;.*\[\(.*\)\];\1;p')
  if [ "$comp" ]; then
    mv -f ramdisk.cpio ramdisk.cpio.$comp
    $magiskboot decompress ramdisk.cpio.$comp ramdisk.cpio 2>&1
    if [ $? != 0 ] && $comp --help 2>/dev/null; then
      $comp -dc ramdisk.cpio.$comp >ramdisk.cpio
    fi
  fi
  mkdir -p ramdisk
  chmod 755 ramdisk
  cd ramdisk
  EXTRACT_UNSAFE_SYMLINKS=1 cpio -d -F ../ramdisk.cpio -i 2>&1
fi
sudo cp -f "$GITHUB_WORKSPACE"/tools/fstab.qcom "$GITHUB_WORKSPACE"/vendor_boot/ramdisk/first_stage_ramdisk/fstab.qcom
sudo chmod 644 "$GITHUB_WORKSPACE"/vendor_boot/ramdisk/first_stage_ramdisk/fstab.qcom
cd "$GITHUB_WORKSPACE"/vendor_boot/ramdisk/
find | sed 1d | cpio -H newc -R 0:0 -o -F ../ramdisk_new.cpio
cd ..
if [ "$comp" ]; then
  $magiskboot compress=$comp ramdisk_new.cpio 2>&1
  if [ $? != 0 ] && $comp --help 2>/dev/null; then
    $comp -9c ramdisk_new.cpio >ramdisk.cpio.$comp
  fi
fi
ramdisk=$(ls ramdisk_new.cpio* 2>/dev/null | tail -n1)
if [ "$ramdisk" ]; then
  cp -f $ramdisk ramdisk.cpio
  case $comp in
  cpio) nocompflag="-n" ;;
  esac
  $magiskboot repack $nocompflag "$GITHUB_WORKSPACE"/vendor_boot/vendor_boot.img "$GITHUB_WORKSPACE"/"${device}"/firmware-update/vendor_boot.img 2>&1
fi
sudo rm -rf "$GITHUB_WORKSPACE"/vendor_boot
# 替换 vendor 的 fstab
echo -e "\e[1;31m - 替换 vendor 的 fstab \e[0m"
sudo cp -f "$GITHUB_WORKSPACE"/tools/fstab.qcom "$GITHUB_WORKSPACE"/"${device}"/vendor/etc/fstab.qcom
# 替换 Product 的叠加层
echo -e "\e[1;31m - 替换 product 的叠加层 \e[0m"
sudo rm -rf "$GITHUB_WORKSPACE"/images/product/overlay/*
sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/overlay.zip -d "$GITHUB_WORKSPACE"/images/product/overlay
# 替换 mi_ext 的叠加层
echo -e "\e[1;31m - 替换 mi_ext 的叠加层 \e[0m"
sudo rm -rf "$GITHUB_WORKSPACE"/images/mi_ext/product/overlay/*
sudo cp -rf "$GITHUB_WORKSPACE"/"${device}"/mi_ext/product/overlay/* -d "$GITHUB_WORKSPACE"/images/mi_ext/product/overlay
# 替换 device_features 文件
echo -e "\e[1;31m - 替换 device_features 文件 \e[0m"
sudo rm -rf "$GITHUB_WORKSPACE"/images/product/etc/device_features/*
sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/device_features.zip -d "$GITHUB_WORKSPACE"/images/product/etc/device_features/
# 替换 displayconfig 文件
echo -e "\e[1;31m - 替换 displayconfig 文件 \e[0m"
sudo rm -rf "$GITHUB_WORKSPACE"/images/product/etc/displayconfig/*
sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/displayconfig.zip -d "$GITHUB_WORKSPACE"/images/product/etc/
# 修改 build.prop
echo -e "\e[1;31m - 修改 build.prop \e[0m"
build_time=$(date) && build_utc=$(date -d "$build_time" +%s)
sudo sed -i 's/ro.build.user=[^*]*/ro.build.user=kmiit/' "$GITHUB_WORKSPACE"/images/system/system/build.prop
origin_date=$(sudo cat "$GITHUB_WORKSPACE"/images/system/system/build.prop | grep 'ro.build.version.incremental=' | cut -d '=' -f 2)
for date_build_prop in $(sudo find "$GITHUB_WORKSPACE"/images/ -type f -name 'build.prop'); do
  sudo sed -i 's/build.date=[^*]*/build.date='"$build_time"'/' "$date_build_prop"
  sudo sed -i 's/build.date.utc=[^*]*/build.date.utc='"$build_utc"'/' "$date_build_prop"
  sudo sed -i 's/'"${origin_date}"'/'"${date}"'/g' "$date_build_prop"
done
for build_prop in $(sudo find "$GITHUB_WORKSPACE"/"${device}"/ -type f -name "*build.prop"); do
  sudo sed -i 's/'"${origin_Bottom_date}"'/'"${date}"'/' "$build_prop"
  sudo sed -i 's/build.date=[^*]*/build.date='"$build_time"'/' "$build_prop"
  sudo sed -i 's/build.date.utc=[^*]*/build.date.utc='"$build_utc"'/' "$build_prop"
done
# 精简部分应用
echo -e "\e[1;31m - 精简部分应用 \e[0m"
for files in MIGalleryLockscreen MIUIDriveMode MIUIDuokanReader MIUIGameCenter MIUINewHome MIUIYoupin MIUIHuanJi MIUIMiDrive MIUIVirtualSim ThirdAppAssistant XMRemoteController MIUIVipAccount MiuiScanner Xinre SmartHome MiShop MiRadio MIUICompass MediaEditor BaiduIME iflytek.inputmethod MIService MIUIEmail MIUIVideo MIUIMusicT; do
  appsui=$(sudo find "$GITHUB_WORKSPACE"/images/product/data-app/ -type d -iname "*${files}*")
  if [[ $appsui != "" ]]; then
    echo -e "\e[1;33m - 找到精简目录: $appsui \e[0m"
    sudo rm -rf $appsui
  fi
done
# 分辨率修改
echo -e "\e[1;31m - 分辨率修改 \e[0m"
Find_character() {
  FIND_FILE="$1"
  FIND_STR="$2"
  if [ $(grep -c "$FIND_STR" $FIND_FILE) -ne '0' ]; then
    Character_present=true
    echo -e "\e[1;33m - 找到指定字符: $2 \e[0m"
  else
    Character_present=false
    echo -e "\e[1;33m - !未找到指定字符: $2 \e[0m"
  fi
}
Find_character "$GITHUB_WORKSPACE"/images/product/etc/build.prop persist.miui.density_v2
if [[ $Character_present == true ]]; then
  sudo sed -i 's/persist.miui.density_v2=[^*]*/persist.miui.density_v2=480/' "$GITHUB_WORKSPACE"/images/product/etc/build.prop
else
  sudo sed -i ''"$(sudo sed -n '/ro.miui.notch/=' "$GITHUB_WORKSPACE"/images/product/etc/build.prop)"'a persist.miui.density_v2=480' "$GITHUB_WORKSPACE"/images/product/etc/build.prop
fi
## 补全 HyperOS 版本信息
echo -e "\e[1;31m - 补全 HyperOS 版本信息 \e[0m"
product_build_prop=$(sudo find "$GITHUB_WORKSPACE"/images/product/ -type f -name "build.prop")
mi_ext_build_prop=$(sudo find "$GITHUB_WORKSPACE"/images/mi_ext/ -type f -name "build.prop")
search_keywords=("mi.os" "ro.miui")
while IFS= read -r line; do
  for keyword in "${search_keywords[@]}"; do
    if [[ $line == *"$keyword"* ]]; then
      echo -e "\e[1;33m - 找到指定字符: $line \e[0m"
      sudo sed -i "$(sudo sed -n "/ro.product.build.version.sdk/=" "$product_build_prop")a $line" "$product_build_prop"
    fi
  done
done <"$mi_ext_build_prop"
# 替换相机
echo -e "\e[1;31m - 替换相机 \e[0m"
sudo rm -rf "$GITHUB_WORKSPACE"/images/product/priv-app/MiuiCamera/*
sudo cat "$GITHUB_WORKSPACE"/"${device}"_files/MiuiCamera.apk.1 "$GITHUB_WORKSPACE"/"${device}"_files/MiuiCamera.apk.2 "$GITHUB_WORKSPACE"/"${device}"_files/MiuiCamera.apk.3 >"$GITHUB_WORKSPACE"/"${device}"_files/MiuiCamera.apk
sudo cp -f "$GITHUB_WORKSPACE"/"${device}"_files/MiuiCamera.apk "$GITHUB_WORKSPACE"/images/product/priv-app/MiuiCamera/
# 替换相机标定
echo -e "\e[1;31m - 替换相机标定 \e[0m"
sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/CameraTools_beta.zip -d "$GITHUB_WORKSPACE"/images/product/app/
# 占位毒瘤和广告
sudo rm -rf "$GITHUB_WORKSPACE"/images/product/app/AnalyticsCore/*
sudo cp -f "$GITHUB_WORKSPACE"/"${device}"_files/AnalyticsCore.apk "$GITHUB_WORKSPACE"/images/product/app/AnalyticsCore
sudo rm -rf "$GITHUB_WORKSPACE"/images/product/app/MSA/*
sudo cp -f "$GITHUB_WORKSPACE"/"${device}"_files/MSA.apk "$GITHUB_WORKSPACE"/images/product/app/MSA
# 常规修改
sudo rm -rf "$GITHUB_WORKSPACE"/"${device}"/vendor/recovery-from-boot.p
sudo rm -rf "$GITHUB_WORKSPACE"/"${device}"/vendor/bin/install-recovery.sh
# 修复 init 崩溃
echo -e "\e[1;31m - 修复 init 崩溃 \e[0m"
sudo sed -i "/start qti-testscripts/d" "$GITHUB_WORKSPACE"/"${device}"/vendor/etc/init/hw/init.qcom.rc
# 添加刷机脚本
sudo unzip -o -q "$GITHUB_WORKSPACE"/tools/flashtools.zip -d "$GITHUB_WORKSPACE"/images
# 移除 Android 签名校验
sudo mkdir -p "$GITHUB_WORKSPACE"/apk/
Apktool="java -jar "$GITHUB_WORKSPACE"/tools/apktool.jar"
echo -e "\e[1;31m - 移除 Android 签名校验 \e[0m"
sudo cp -rf "$GITHUB_WORKSPACE"/images/system/system/framework/services.jar "$GITHUB_WORKSPACE"/apk/services.apk
cd "$GITHUB_WORKSPACE"/apk
sudo $Apktool d -q "$GITHUB_WORKSPACE"/apk/services.apk
fbynr='getMinimumSignatureSchemeVersionForTargetSdk'
sudo find "$GITHUB_WORKSPACE"/apk/services/smali_classes2/com/android/server/pm/ "$GITHUB_WORKSPACE"/apk/services/smali_classes2/com/android/server/pm/pkg/parsing/ -type f -maxdepth 1 -name "*.smali" -exec grep -H "$fbynr" {} \; | cut -d ':' -f 1 | while read i; do
  hs=$(grep -n "$fbynr" "$i" | cut -d ':' -f 1)
  sz=$(sudo tail -n +"$hs" "$i" | grep -m 1 "move-result" | tr -dc '0-9')
  hs1=$(sudo awk -v HS=$hs 'NR>=HS && /move-result /{print NR; exit}' "$i")
  hss=$hs
  sedsc="const/4 v${sz}, 0x0"
  { sudo sed -i "${hs},${hs1}d" "$i" && sudo sed -i "${hss}i\\${sedsc}" "$i"; } && echo -e "\e[1;33m - ${i}  修改成功 \e[0m"
done
cd "$GITHUB_WORKSPACE"/apk/services/
sudo $Apktool b -q -f -c "$GITHUB_WORKSPACE"/apk/services/ -o services.jar
sudo cp -rf "$GITHUB_WORKSPACE"/apk/services/services.jar "$GITHUB_WORKSPACE"/images/system/system/framework/services.jar
# 对齐系统更新获取更新路径
echo -e "\e[1;31m - 对齐系统更新获取更新路径 \e[0m"
for mod_device_build in $(sudo find "$GITHUB_WORKSPACE"/images/ -type f -name 'build.prop' 2>/dev/null | xargs grep -rl 'ro.product.mod_device=' | sed 's/^\.\///' | sort); do
  if echo "${date}" | grep -q "XM" || echo "${date}" | grep -q "DEV"; then
    sudo sed -i 's/ro.product.mod_device=[^*]*/ro.product.mod_device=shennong/' "$mod_device_build"
  else
    sudo sed -i 's/ro.product.mod_device=[^*]*/ro.product.mod_device=shennong_pre/' "$mod_device_build"
  fi
done
# 替换更改文件/删除多余文件
echo -e "\e[1;31m - 替换更改文件/删除多余文件 \e[0m"
sudo cp -r "$GITHUB_WORKSPACE"/"${device}"/* "$GITHUB_WORKSPACE"/images
sudo rm -rf "$GITHUB_WORKSPACE"/"${device}"
sudo rm -rf "$GITHUB_WORKSPACE"/"${device}"_files
End_Time 功能修复
### 功能修复结束

### 生成 super.img
echo -e "\e[1;31m - 开始打包 IMAGE \e[0m"
for i in mi_ext odm product system system_ext system_dlkm vendor vendor_dlkm; do
  echo -e "\e[1;31m - 正在生成: $i \e[0m"
  sudo python3 "$GITHUB_WORKSPACE"/tools/fspatch.py "$GITHUB_WORKSPACE"/images/$i "$GITHUB_WORKSPACE"/images/config/"$i"_fs_config
  sudo python3 "$GITHUB_WORKSPACE"/tools/contextpatch.py "$GITHUB_WORKSPACE"/images/$i "$GITHUB_WORKSPACE"/images/config/"$i"_file_contexts
  Start_Time
  sudo "$GITHUB_WORKSPACE"/tools/mkfs.erofs -zlz4hc,9 -T 1230768000 --mount-point /$i --fs-config-file "$GITHUB_WORKSPACE"/images/config/"$i"_fs_config --file-contexts "$GITHUB_WORKSPACE"/images/config/"$i"_file_contexts "$GITHUB_WORKSPACE"/images/$i.img "$GITHUB_WORKSPACE"/images/$i >/dev/null
  End_Time 打包erofs
  eval "$i"_size=$(du -sb "$GITHUB_WORKSPACE"/images/$i.img | awk {'print $1'})
  sudo rm -rf "$GITHUB_WORKSPACE"/images/$i
done
sudo rm -rf "$GITHUB_WORKSPACE"/images/config
Start_Time
"$GITHUB_WORKSPACE"/tools/lpmake --metadata-size 65536 --super-name super --block-size 4096 --partition mi_ext_a:readonly:"$mi_ext_size":qti_dynamic_partitions_a --image mi_ext_a="$GITHUB_WORKSPACE"/images/mi_ext.img --partition mi_ext_b:readonly:0:qti_dynamic_partitions_b --partition odm_a:readonly:"$odm_size":qti_dynamic_partitions_a --image odm_a="$GITHUB_WORKSPACE"/images/odm.img --partition odm_b:readonly:0:qti_dynamic_partitions_b --partition product_a:readonly:"$product_size":qti_dynamic_partitions_a --image product_a="$GITHUB_WORKSPACE"/images/product.img --partition product_b:readonly:0:qti_dynamic_partitions_b --partition system_a:readonly:"$system_size":qti_dynamic_partitions_a --image system_a="$GITHUB_WORKSPACE"/images/system.img --partition system_b:readonly:0:qti_dynamic_partitions_b --partition system_ext_a:readonly:"$system_ext_size":qti_dynamic_partitions_a --image system_ext_a="$GITHUB_WORKSPACE"/images/system_ext.img --partition system_ext_b:readonly:0:qti_dynamic_partitions_b --partition system_dlkm_a:readonly:"$system_dlkm_size":qti_dynamic_partitions_a --image system_dlkm_a="$GITHUB_WORKSPACE"/images/system_dlkm.img --partition system_dlkm_b:readonly:0:qti_dynamic_partitions_b --partition vendor_a:readonly:"$vendor_size":qti_dynamic_partitions_a --image vendor_a="$GITHUB_WORKSPACE"/images/vendor.img --partition vendor_b:readonly:0:qti_dynamic_partitions_b --partition vendor_dlkm_a:readonly:"$vendor_dlkm_size":qti_dynamic_partitions_a --image vendor_dlkm_a="$GITHUB_WORKSPACE"/images/vendor_dlkm.img --partition vendor_dlkm_b:readonly:0:qti_dynamic_partitions_b --device super:8321499136 --metadata-slots 3 --group qti_dynamic_partitions_a:8311013376 --group qti_dynamic_partitions_b:8311013376 --virtual-ab -F --output "$GITHUB_WORKSPACE"/images/super.img
End_Time 打包super
for i in mi_ext odm product system system_ext system_dlkm vendor vendor_dlkm; do
  rm -rf "$GITHUB_WORKSPACE"/images/$i.img
done
### 生成 super.img 结束

### 生成卡刷包
sudo find "$GITHUB_WORKSPACE"/images/ -exec touch -t 200901010000.00 {} \;
zstd -9 -f "$GITHUB_WORKSPACE"/images/super.img -o "$GITHUB_WORKSPACE"/images/super.zst --rm
### 生成卡刷包结束

### 定制 ROM 包名
if [[ "${device}" == "shennong" ]]; then
  sudo 7z a "$GITHUB_WORKSPACE"/zip/miui_shennong_${date}.zip "$GITHUB_WORKSPACE"/images/*
  sudo rm -rf "$GITHUB_WORKSPACE"/images
  md5=$(md5sum "$GITHUB_WORKSPACE"/zip/miui_shennong_${date}.zip)
  echo "MD5=${md5:0:32}" >>$GITHUB_ENV
  zipmd5=${md5:0:10}
  rom_name="miui_"
  if echo "${date}" | grep -q "XM" || echo "${date}" | grep -q "DEV"; then
    rom_name+="shennong_"
  else
    rom_name+="shennongPRE_"
  fi
  rom_name+="${date}_${zipmd5}_${android_version}.0_kmiit.zip"
  sudo mv "$GITHUB_WORKSPACE"/zip/miui_shennong_${date}.zip "$GITHUB_WORKSPACE"/zip/"${rom_name}"
  echo "NEW_PACKAGE_NAME="${rom_name}"" >>$GITHUB_ENV
fi
### 定制 ROM 包名结束
