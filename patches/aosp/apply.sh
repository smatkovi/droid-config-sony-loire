#!/bin/sh
# Nach 'repo sync' im ANDROID_ROOT (~/ps) ausführen:
#   hybris/droid-configs/patches/aosp/apply.sh
set -e
D="$(cd "$(dirname "$0")" && pwd)"
R="$D/../../../../.."   # -> ANDROID_ROOT
cd "$R"
git -C build/make                    apply "$D/build_make.patch"
git -C external/flac                 apply "$D/external_flac.patch"
git -C external/libvpx               apply "$D/external_libvpx.patch"
git -C frameworks/av                 apply "$D/frameworks_av.patch"
git -C vendor/oss/fingerprint        apply "$D/vendor_oss_fingerprint.patch"
git -C vendor/qcom/opensource/camera apply "$D/vendor_qcom_opensource_camera.patch"
git -C hardware/interfaces           am "$D/series/hardware_interfaces/"*.patch
git -C hardware/libhardware          am "$D/series/hardware_libhardware/"*.patch
git -C hardware/qcom/display         am "$D/series/hardware_qcom_display/"*.patch
git -C hardware/qcom/display/sde     am "$D/series/hardware_qcom_display_sde/"*.patch
echo "All AOSP-tree patches applied."
