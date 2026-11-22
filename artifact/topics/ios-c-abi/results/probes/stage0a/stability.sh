#!/bin/zsh
# usage: stability.sh <udid> <tag> <run#>
S=${STAGE0A_WORK:?set STAGE0A_WORK to a work directory}
U=$1; v=$2; r=$3; B=com.jonghyunkim.ios.nativetoolkit.example
t0=$(date +%s)
for t in testP1_interruptionMonitor testP2_springboardAlert testP3_springboardDeny; do
  xcrun simctl uninstall $U $B
  ${0:A:h}/run.sh $U stab-$v-r$r-$t Stage0aPermissionProbeTests/$t
done
xcrun simctl uninstall $U $B
N=Stage0aNotificationProbeTests
extra=()
[ $v = 26 ] && extra=($N/testN9_coldStartFromActionButton)
${0:A:h}/run.sh $U stab-$v-r$r-main Stage0aDialogProbeTests Stage0aShareProbeTests \
  $N/testN1_foregroundBanner $N/testN1b_foregroundBannerTap $N/testN2_backgroundBanner $N/testN3_scheduledTenSeconds \
  $N/testN4_notificationCenterTapOpensApp $N/testN5_actionButtonOpen $N/testN6_actionButtonFromBackground \
  $N/testN7_textInputAction $N/testN8_coldStartFromNotificationCenter $N/testN10_coldStartFromBannerTap \
  $N/testN11_coldStartFromBannerAction $extra \
  Stage0aClipboardProbeTests/testC1_allowPasteAlert Stage0aClipboardProbeTests/testC2_pasteControlTap
echo "host-pbcopy-$(date +%s)" | xcrun simctl pbcopy $U
${0:A:h}/run.sh $U stab-$v-r$r-c3 Stage0aClipboardProbeTests/testC3_allowPasteAfterHostPbcopy
echo "== stability $v run $r total=$(( $(date +%s) - t0 ))s"
