# CutiePi 移植记录

## 实机状态

2026-11-16：用户说明设备当前没有系统，无法 SSH。此阶段按量产 CM4 CutiePi 的公开资料准备；板卡版本、实际 CM4 配置、EEPROM、屏幕和外设工作状态尚未在实机核验。

已插入约 32GB 的可移除卡，检查时标识为 `/dev/disk6`，容量精确为 31914983424 字节。boot 分区保留 2022-04-02 CutiePi 镜像的配置和少量文件，缺少内核和启动固件；已备份这些启动文件到 `artifacts/sd-boot-before/`。未检查 Linux 根分区的数据内容，未对卡执行写入。
用户明确要求不要使用 1TB 外置硬盘。它不能作为镜像存储位置、构建目录或刷写目标；后续刷卡必须重新核验目标为约 32GB 的可移除卡，不能依赖可能变化的 disk 编号。

## 内核候选

- 来源：<https://github.com/raspberrypi/linux/tree/rpi-6.12.y>
- 固定 revision：`ab4372076bb840600e522ae776887ae2bc488fa6`
- 源码版本：6.12.116。
- 初次构建使用 `bcm2711_defconfig`，目标为 ARM64 CM4。
- 这是树莓派硬件基线，尚不是验证完成的 Ubuntu Touch 内核。
- 已检查 defconfig 含 `DRM_VC4=m`、`DRM_V3D=m`、`DRM_PANEL_ILITEK_ILI9881C=m`、`TOUCHSCREEN_GOODIX=m`、`BACKLIGHT_PWM=m`、`SECURITY_APPARMOR=y`。
- `CONFIG_LSM` 为空，同时 `CONFIG_DEFAULT_SECURITY_APPARMOR=y`。Ubuntu Touch 适配阶段需要确认启动后的实际 LSM 列表、AppArmor 功能和用户空间策略兼容性，不能由一个配置项就认定应用沙箱可用。

## 硬件映射

| 功能 | 官方资料与源码中的配置 | 下一步验证 |
| --- | --- | --- |
| 内屏 | `cutiepi-panel` overlay，DSI1，`nwe,nwe080`，ILI9881C 驱动 | KMS 是否识别，背光和画面是否正常 |
| 触控 | 同一 overlay 中的 Goodix GT9271，I2C6 地址 0x5d | 输入事件、方向和坐标映射 |
| GPU | `vc4-kms-v3d`，VC4/V3D | Mesa 和 Mir 的实际后端与加速 |
| MCU | `enable_uart=1`、`dtoverlay=uart1`，旧软件打开 `/dev/ttyS0`，115200 波特率 | 新内核设备名及协议响应；不配置此串口为 console |
| 电源 | MCU cutoff 命令，由系统关机钩子发送 | 关机真正断电、重启不误断电 |
| IMU | 官方自定义 `mpu6050-i2c5`，I2C5 GPIO10/11，中断 GPIO27 | 源码 overlay 有 `#address-cells = <5>`，不能直接沿用而不检查；先不启用 |
| 相机 | 官方列出 OV5647 | 新内核下的 libcamera 管线和 Ubuntu Touch 相机服务适配；先不启用旧固件 camera 配置 |
| USB | `otg_mode=1` | USB-A host；USB-C 官方标注为充电口，不能假定可用于 ADB |

参考：

- <https://github.com/cutiepi-io/cutiepi-doc/blob/main/OSPortingGuide.md>
- <https://github.com/cutiepi-io/cutiepi-drivers>
- <https://github.com/cutiepi-io/cutiepi-middleware>
- <https://github.com/cutiepi-io/pi-gen_stage4.5-cutiepi>

## Ubuntu Touch 根文件系统

已取得 <https://gitlab.com/ubports/development/core/rootfs-builder-debos>。
具体 revision 见 `upstream-revisions.txt`。

- 顶层 `raspberrypi.yaml` 经 `mainline-rootfs-core.yaml` 仍引用 Xenial CI 下载地址；此配方不是当前 CutiePi 镜像基础。
- 当前 `ubuntu-touch/common-base.yaml` 使用 Ubuntu 26.04 和 UBports `26.04-1.x` 仓库。
- `ubuntu-touch/ubuntu-touch-pdk-img.yaml` 的 `variant=mainline` 复用了当前 Ubuntu Touch 通用 hooks 和 `ubuntu-touch-core-mainline` / `ubuntu-touch-mainline` 包。
- PDK 的通用 GRUB/EFI 分区和 host 目录挂载服务是虚拟开发机专用配置，不能直接当 CM4 启动镜像使用。
- 后续应复用当前 mainline 用户空间的包与 hooks，适配树莓派启动分区、固件、内核模块和 CutiePi 配置。构建主机的 Ubuntu 24.04 与目标系统版本相互独立。

已新增 `dev/cutiepi-rootfs.yaml` 和构建脚本，首轮选择上游当前 `26.04-1.x` 的 mainline 路线，属于开发镜像。配方复用通用 hooks，加入 Mesa、固件、SSH 和虚拟键盘，不沿用 PDK 的 GRUB/EFI 或 host 挂载配置。
检查仓库依赖发现 `ubuntu-touch-mainline` 仍硬依赖 Mir 1 会话。在 Ubuntu Touch 初始化后单独运行 debos 动作，移除这个包装元包并安装 `lomiri-qt5-mir2`、`qtmir-qt5-mir2`、`ubuntu-touch-session-wayland` 和 `mir-graphics-drivers-desktop`。组装镜像时验证 Ubuntu Touch 本体和 core-mainline 保留。
直接构建使用 debos v1.1.5，与上游 Dockerfile 一致。基础压缩包下载到构建缓存，在解包前通过上游 SHA-256 校验。live-build 配方中的 `/scratch/pkg.deb` 改为从临时构建目录读取，以适应专用 Linux VM 的直接执行模式。
开发 SSH 私钥保存在本机 `artifacts/cutiepi-dev-key`（已 gitignore），仅公钥进入镜像；额外公钥（如 joe 的 RSA 钥匙）放在已跟踪的 `dev/extra-authorized-keys`，构建时追加到 `authorized_keys`。禁用密码和 root SSH 登录，每次首次启动生成独立 SSH host key。
为首次启动启用最多 64MiB 的持久 journal，便于故障后采集日志。

新增独立的 `cutiepi-deviceinfo` overlay，仅设置板卡 model 为 CutiePi、chassis-type 为 tablet，保留 CM4 compatible 和驱动选择；匹配 `/etc/deviceinfo/devices/cutiepi.yaml`，设置 GridUnit=12、原生竖屏和 tablet 类型。已离线编译并与设备树合成验证 model/chassis 属性。尚需实机验证屏幕实际方向和缩放。

## 触摸驱动调查（2026-11-16）

结论：驱动不缺。官方 `cutiepi-drivers` 仓库没有独立触摸驱动，触摸靠 `cutiepi-panel` overlay 的 fragment@8（i2c6@5d、IRQ gpio21、reset gpio26）实例化 `goodix,gt9271`，复用内核自带 goodix 驱动；rpi-6.12.y `drivers/input/touchscreen/goodix.c` 的 of_match 含 `goodix,gt9271`，本内核 `goodix_ts` 模块已编译核验。config.txt 与官方一致（`dtparam=i2c_arm=on` + `dtoverlay=cutiepi-panel`，官方要求 `#dtparam=spi=on` 保持注释，我们未启用 spi）。

实机触摸无响应的已知缺口是**权限/会话**：官方移植指南要求 `gpasswd -a <user> input render dialout`，原配方漏加，已在 `cutiepi-rootfs.yaml` 补上（下一张镜像生效）。实机需 `usermod -aG input,render,dialout phablet` 后重新登录。另一个高危因素：经 SSH 手动拉起的图形会话没有 seat/logind ACL，Lomiri 读不到 `/dev/input/event*`，触摸必然失效。

## 首轮内核构建结果

2026-11-16 已完成 `Image modules dtbs` 和模块安装，版本 `6.12.116-v8+`。
关键模块 vermagic 和内核版本一致，KMS/Pi4 映射、CutiePi 内屏/触控、UART1 合成通过。
完整离线检查输出在 `artifacts/kernel-verification.txt`，内核包在 `artifacts/cutiepi-kernel-6.12.116-baseline.tar.gz`。
此阶段仍未在设备启动。

## 首个 SD 开发镜像

2026-11-16 已生成 `artifacts/cutiepi-ut-mainline-dev.img.gz`。解压后为 8 GiB，内含 FAT 启动分区和 ext4 根分区。组装通过两个分区的离线检查，并确认安装了 Ubuntu Touch、Lomiri Mir 2、Wayland 会话和 GBM/KMS 后端。复制到 Mac 后 SHA-256 一致。

镜像包含本地 Wi-Fi 配置。组装时已验证 NetworkManager 能读取配置，并为未启用压缩固件加载的内核提供解压后的 CM4 无线固件。SSH 采用专用公钥，已检查服务端配置，首次启动生成设备自己的主机密钥。开机约 75 秒后，启动分区会写入 `cutiepi-boot-report.txt`。

已写入 31.9 GB microSD 并实机启动，Wi-Fi 和专用公钥 SSH 已确认可用。

## 首次上机的黑屏修正

首次启动时 LightDM 已自动登录，Wayland 的 `ubuntu-touch-session.target` 没有启动 Lomiri。手动启动 Lomiri 后，上游 wrapper 遗留的 Mir 1 环境选项导致 Mir 2 报 `unrecognised option`。去掉这些选项并显式选择 Mesa EGL 后，Mir 2 识别内屏 800×1280 和 V3D 渲染节点。Lomiri 仍会经 Android properties 库加载兼容链接器，因此为该进程增加 glibc 的静态 TLS 预留空间作为当前版本的临时处理。

`dev/install-native-session.sh` 将这些设置写入设备的 phablet 用户配置，也可在组装时安装到镜像。Lomiri 服务达到 active，内屏 DSI 输出已启用，用户确认看到了画面。还需验证重启后自动进入界面，以及 Goodix 触控坐标和息屏唤醒。原先导出的镜像早于这次修正。实机的设备树 model 仍由固件报告为 Raspberry Pi Compute Module 4，导致 CutiePi 的 DeviceInfo 配置没有自动匹配。

## 内屏与触控测试镜像

用 `dev/rebuild-screen-touch.sh` 从曾在实机启动的原始镜像（SHA-256 `1f3ed709f66064c1d77463e176792f734c7b273235c2f506e1b2050f355ec0d4`）生成 `cutiepi-ut-mainline-screen-touch.img.gz`。保留原内核、固件、系统包、Wi-Fi 和 SSH 设置。

LightDM 自动选择 CutiePi 会话，由会话启动 `ubuntu-touch-session-unencrypted.target` 和 Lomiri。会话与 Repowerd 显式载入 CutiePi 配置，背光路径为 `/sys/class/backlight/rpi_backlight`。启动时阻止树莓派固件追加 HDMI 模式，并用小写 `:d` 禁用两个 HDMI 输出，留下 DSI 内屏作为唯一输出。旧镜像的日志已确认系统识别 Goodix 触控设备，但也启用了额外的 HDMI 输出，内屏坐标因此不是从桌面原点开始。此次仅改变显示拓扑和会话，不更改 Goodix 的驱动或校准。

已检查 LightDM 生效配置、启动参数中的根分区标识及 FAT/ext4 文件系统。内屏连续启动和实际触控仍需用新镜像上机验证。

## 验收顺序

1. 编译和检查内核 Image、模块、CM4 DTB、CutiePi overlay。
2. 组装带调试入口的 SD 镜像：启动固件、启动配置、mainline 根文件系统、网络和 SSH。应先准备登录方式，再交付刷卡测试。
3. 实机验证内屏/触控、GPU/Mir/Lomiri，收集首轮日志。
4. 接入 MCU、电量、亮度和按键，验证关机/重启，再处理旋转、音频和相机。

编译成功或离线设备树合成成功，都不能替代实机启动和外设验证。

## 设备树离线验证的注意事项

`vc4-kms-v3d` 在 BCM2711 上由 `overlay_map.dtb` 映射到 `vc4-kms-v3d-pi4`，打包时必须保留该映射文件。
这些 overlay 还使用树莓派的 `__dormant__` 扩展，通用 `fdtoverlay` 直接合成报 `FDT_ERR_NOTFOUND`，不能据此判定驱动或 overlay 不兼容。
已编译树莓派官方 `dtmerge`，对 Pi4 KMS、CutiePi 内屏/触控、UART1 顺序合成成功，结果 compatible 为 `raspberrypi,4-compute-module brcm,bcm2711`。
工具源码固定于 `raspberrypi/utils` 的 `eac8944a8f30a8365ea57e4d20d268baadd0eb67`。
