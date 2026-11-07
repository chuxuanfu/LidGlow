# LidGlow Lab 本机调试记录

2026-11-07 UTC，Apple Silicon MacBook Pro，macOS 27.2（26B8125）。

## 已验证

- Apple 官方 Command Line Tools 已安装；原生编译及本地 ad-hoc 签名验证通过。
- C 数值核心的 300,000 次随机检查通过。
- 可读取专用背光节点、原始映射及模式；未提高系统原始上限。
- 手动模式可写入背光参数。
- 一键关闭后，读回模式为 0、映射亮度为 0。
- 恢复后，模式及完整映射与测试基线逐项一致，恢复文件清除。
- 呼吸模式在 5% 上限、2 秒周期下，系统映射连续变化且不越界。
- 音乐模式曾成功捕获系统测试音：播放时从 0 升高，音量变化时同步变化，保持在 5% 上限内。
- 检测到未完成恢复时，启动会提示恢复并暂停效果。
- 音频权限被拒绝后，效果停止，原始参数完整恢复，恢复文件清除。

## 本次修改

- 启动/重新打开时显示控制面板；增加辅助功能标签。
- 增加 --debug-window 入口用于本机普通窗口测试，默认仍为菜单栏应用。
- 修复音乐静音后的微弱残光：原先变化阈值会跳过最后一次归零。现在过渡到零时强制写入，同时避免重复写零。
- 增加该残光问题的回归测试，并清理编译警告。

## 尚未完成的验证

- 修复版音乐复测已于重新授权后完成。详见下面的最终验收。
- 未直接观察实体 Logo，系统参数成功不等同于已经确认物理视觉效果。
- 未完成睡眠/唤醒/锁屏、多显示器、DRM、音频设备切换及运行中撤销权限的完整验收。

## 当前状态

已恢复原始系统控制；最后一次检查恢复文件不存在。此记录不代表正式签名公证或全面稳定性验证。

App：build/LidGlow Lab.app
源码：本目录

## 权限问题的确证

系统设置中 LidGlow Lab 的“屏幕与系统音频录制”开关确实为开启。系统 tccd 日志明确报告当前版本与旧许可的代码要求不匹配（kTCCServiceScreenCapture）。旧记录代码哈希为 3a020ef3b54561507559a39d985cd12105c547ce，当前 ad-hoc 签名的指定要求为 ae1666ef331ca49ae970bd1ae1ecfb111590afde。因此不是开关关闭；是重编译改变本地签名身份后旧记录未匹配新版本。尚未重置或修改授权。后续可在用户批准后，仅移除并重新添加该 App 的这一项许可，并从 Finder 启动当前 App 复测。避免通过终端直接启动音频测试，以免系统把许可归属到启动程序。

## 最终验收

用户批准后，仅移除并重新添加了 LidGlow Lab 的屏幕与系统音频录制许可，其他 App 权限保持不变。从 Finder 打开当前签名版本后，音频捕获恢复正常。

九秒测试中：测试音响起后映射从 0 升高到约 18.18 nits，始终低于本次 50 nits 上限；测试音停止后，映射与模式回到精确的 0，并连续多次采样保持为 0。音乐静音残光修复已通过真实系统音频复测。

最后切回系统控制，完整原始映射与模式和基线文件完全一致，恢复文件已清除；系统日志确认调用了停止捕获。最终数值回归测试和签名验证再次通过。当前 App 可直接从 Finder 打开，不需要重新编译。

注意：今后重新编译会改变此 ad-hoc 签名，可能再次需要为新版本重新建立该 App 的录制许可。本次未改变系统安全保护，也未全局重置权限。

## LidGlow 0.2 feature upgrade (2026-11-07 UTC)

Implemented: LidGlow branding and original icon, English app UI/errors, Breathe on each process launch, optional ServiceManagement login launch (left off), Auto Breathe/Music with activity hysteresis and crossfade, adaptive beat pulses, and persistent one-time app-owned audio disclosure consent. macOS authorization is never bypassed.

Passed on the MacBook Pro, macOS 27.2:
- Native arm64 build, Info.plist validation, strict signature verification and `-Wall -Wextra -Werror` source checks.
- Icon pixel inspection at 16, 32 and 1024 px; all standard ICNS representations.
- Real launch defaults to Breathe, all authored controls are English, Launch at login is unchecked.
- Default breathing hardware mapping sampled between 0.36 and 552 nits, within the selected 600-nit ceiling. This is requested mapping, not measured physical brightness.
- Cancelling audio setup returns to Breathe. A TCC failure stops effects and fully restores the original mapping and mode.
- Complete original mapping/mode compare exactly to the saved pre-test baseline after restore/quit, and the recovery file clears.
- Mock-only regression verifies missing recovery-file cleanup after successful property restoration is safe and idempotent, without opening or writing hardware.
- All 20 beat-sensitivity settings, quiet/loud input (amplitude 0.001/0.65), uneven callbacks and opposite-phase stereo pass. Synthetic sampled peaks are about 92%, valleys about 5.6%; highest sensitivity does not saturate.
- Weak accents at sensitivity 1 produce 0/8 pulses, while sensitivity 20 produces 8/8. Sustained 40/80/440/6000 Hz tones do not repeatedly flash or saturate.
- Digital silence/stale buffers, restart, activity hysteresis, short transients, invalid PCM/nonfinite input and randomized invariants pass, including AddressSanitizer and UBSan.
- After authorized one-app permission renewal, real 12-second synthetic system-output audio switched the UI Breathe → Music → Breathe. Captured beat sections requested 6.48–600 nits. Dedicated Music remained exactly zero for eight silence hardware samples.
- The installed `/Applications/LidGlow.app` was signature-verified and compared byte-for-byte to the build. Capture started successfully there, including the final disclosure-preference build as confirmed below. `/Applications/LidGlow Lab.app` was left untouched.

Final disclosure update and permission verification completed after the user explicitly approved renewal for this latest build. Only LidGlow was removed and re-added in Screen & System Audio Recording; ChatGPT and Codex Computer Use permissions remained unchanged. The installed app starts in Breathe after relaunch. Music and Auto both start directly without the app-owned disclosure dialog, using persistent `AudioDisclosureAccepted` consent. macOS authorization remains enforced. The latest installed signature successfully captured actual synthetic output audio: 64 beat samples ranged from 5.89 to 600 nits, then 23 silence samples were exactly zero/mode 0. Final UI was inspected and left running in Breathe at a 60% maximum, 4-second period; Launch at login remains off. Audio capture stops on switching to Breathe. The normal recovery snapshot remains present while the breathing effect owns the hardware, as intended. No blocker remains.

Not validated: actual physical logo appearance, enabling/disabling login launch (deliberately not enabled), full sleep/wake/lock matrix, multiple displays, DRM, audio-route changes and live permission revocation. Private CoreBrightness and local ad-hoc signing remain experimental.
