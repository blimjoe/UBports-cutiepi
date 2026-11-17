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

2026-11-17 实机已进入 Ubuntu Touch 竖屏界面。Mir 确认识别 Goodix 触控和 800×1280 DSI 输出，内屏逻辑原点为 (0, 0)，两个 HDMI 输出均为 disconnected。用户反馈触控位置偏差。可运行 `dev/touch-probe.qml`，按编号采集四个已知目标在 Wayland 应用里收到的归一化坐标，用于判断轴交换、镜像、缩放或平移。

触控修正采用 `GridUnit: 8`。QtMir 用 `GRID_UNIT_PX / 8` 作为显示缩放，原来的 12 对应 1.5 倍，使逻辑屏幕变成 533×853。实测触控坐标相对界面约放大 1.5 倍，右侧和底部会落到窗口外。切为 1 倍后，逻辑屏幕为 800×1280，四个测试点均落在对应圆内，归一化实际坐标为 (0.1563, 0.1781)、(0.8363, 0.1797)、(0.1325, 0.8195)、(0.8700, 0.8219)。新的 `cutiepi-ut-mainline-touch-1x.img.gz` 在设备配置中保留这项设置。

## 电源键短按

`cutiepi-power-button.service` 从 `/dev/ttyS0` 以 115200 波特率读取 CutiePi MCU 帧。收到短按时回复 `0xF1`，并通过 Repowerd 订阅的 `com.lomiri.SystemCompositor.PowerButton` 系统总线接口依次发送 `Press` 和 `Release`。系统服务使用现有 D-Bus 策略持有该名称。固件处理长按，桥接程序不会发送确认关机或直接断电命令。

伪串口与独立 D-Bus 测试通过，涵盖分段帧、错误校验恢复、短按 ACK、D-Bus 信号顺序及长按无输出。实机诊断已收到有效电池和充电帧。新版 `cutiepi-ut-mainline-power-key.img.gz` 预先启用短按服务，并保留已验证的 1 倍触控设置。刷卡后需验证短按息屏、再次短按唤醒。

## MPU6050 与屏幕旋转

按 [CutiePi 官方移植指南](https://github.com/cutiepi-io/cutiepi-doc/blob/main/OSPortingGuide.md) 启用 GPIO10/11 上的 I²C5。MPU6050 使用地址 `0x68`、GPIO27 中断和原厂安装矩阵。CM4 内核已有 MPU6050 的 IIO 模块，由设备树触发加载。

Lomiri 的 Qt 方向传感器从 `iio-sensor-proxy` 获取加速度推断的朝向。SensorFW 从同一 MPU6050 读取三轴角速度，并通过 Qt `QGyroscope` 提供读数。设备规则为加速度启用轮询，使陀螺仪仍可读取 IIO 原始通道。

`cutiepi-ut-mainline-imu-v1.img.gz` 已通过设备树合成和文件系统检查。模拟 IIO 的 Qt 测试同时收到竖屏、横屏和符合输入的稳定三轴角速度。上机后关闭旋转锁定，竖持平板并向两侧各转动 90°，验证显示方向及旋转后的触控。启动分区的 `cutiepi-boot-report.txt` 会记录 IIO 设备和传感器服务状态。

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

## 应用与软键盘的原生 EGL 环境

实机上 Maliit 和系统设置均因加载 libhybris 时出现 `cannot allocate memory in static TLS block` 而退出。原先 Mesa EGL 和 TLS 配置仅在 Lomiri 的服务环境中设置，独立的应用与键盘服务未继承。

`install-native-session.sh` 生成的桌面包装脚本现在通过 `dbus-update-activation-environment --systemd` 发布 Mesa EGL 路径与 TLS 配置，在桌面启动前供后续服务使用。此修改同时覆盖镜像构建与当前用户安装。实机热更新后 Maliit 保持运行，系统设置与 Morph 浏览器进程启动成功，并建立 Wayland 会话；屏幕实际显示和点击输入框弹出键盘仍需人工验收。当前压缩镜像尚未重新打包。

## 使用中误息屏

原生会话没有提供 `com.lomiri.SystemCompositor.UserActivity`，Repowerd 因此无法从触摸重置空闲计时。新增 `cutiepi-user-activity.service`，以非独占方式读取 Goodix evdev 的实际触摸帧，每秒最多转发一次 `Activity(int32 0)`。设备断开后重新查找事件节点；没有输入时不发送心跳，保留空闲息屏。接口名称、路径和参数取自 Repowerd 的 `lsc_user_activity.cpp`。

两个镜像组装入口均安装并启用服务。模拟输入测试覆盖空闲 SYN、触摸、重复事件节流、抬手及设备 EOF。实机安装需要 sudo，安装后仍需验证持续操作超过原息屏时长、停止操作后自动息屏和短按电源键。

开发设备可按需执行 `sudo bash enable-phablet-sudo.sh`，为 phablet 启用免密 sudo。脚本检查用户存在，校验规则，并以 root:root、0440 安装 `/etc/sudoers.d/99-cutiepi-phablet`。该配置不默认加入镜像。首次执行仍需已有的管理员权限。

## 预先完成边缘手势教学

设备安装的 AccountsService 接口注释明确说明 `demo-edges`、`DemoEdges2` 表示旧版、新版教学已运行，不能当作启用开关关闭。当前 Lomiri 的教学还包含 `left-drawer`，因此完整集合为 `left`、`top`、`right`、`left-long`、`left-drawer`。

镜像会话安装时运行 `complete-gesture-tutorial.py ROOT`，补齐已完成列表并保留其他账户设置、原布尔值及未知教学项。已有配置首次修改前备份，账户文件权限为 0600。运行中的设备可用 `sudo python3 complete-gesture-tutorial.py --live` 经 AccountsService D-Bus 更新，避免直接改文件被进程缓存覆盖。

实机读取文件和 D-Bus 均已完成五项，实时修复入口执行后再次确认，不需要为此重启。离线测试验证重复执行、设置保留、未知项目保留及文件权限。此变更已接入镜像构建，现有压缩镜像尚未重新打包。

## 旋转失效时先检查桌面锁定

实机曾出现 `com.lomiri.touch.system rotation-lock=true`，但 `org.ayatana.indicator.display rotation-lock=false`。此时 MPU6050、IIO Sensor Proxy 和 QtMir 方向事件仍然正常，桌面却被旧设置锁住。两个 schema 默认值均为 false；尚无证据说明哪个操作写入了旧锁定值。

以 phablet 身份执行 `gsettings set com.lomiri.touch.system rotation-lock false` 后恢复，设置持久保存，无需重启。用户重新旋转实机时，Lomiri 日志已依次收到 Portrait、Landscape、Portrait、InvertedLandscape。此前移植配置没有丢失，此次不修改驱动，也不在每次启动强制覆盖用户的旋转锁定偏好。

排查时同时读取两套 schema 的 `rotation-lock` 和 `orientation-lock`。SSH 中使用 `monitor-sensor --accel` 可能被传感器授权策略拒绝，可通过 `sudo monitor-sensor --accel` 诊断；这不等于桌面无法读取传感器。

## OV5647 原生取流与相机预览

官方板载摄像头为 OV5647。启动时显式加载 `ov5647` overlay，使用 Unicam + libcamera 的 rpi/vc4 管线。不要沿用旧固件相机栈的 `start_x`。当前内核已编译 AppArmor，但 `CONFIG_LSM=""`；启动参数显式启用 AppArmor 后，Click 相机应用才能通过 aa-exec 启动。

原生管线需让 video 组访问 DMA heap，并在相机策略中允许 media、v4l-subdev、DMA heap、摄像头 sysfs 和 udev 元数据。ubuntu-sdk 模板对 udev 数据的显式 deny 会覆盖相机策略 allow，因此移除该显式拒绝，由其他应用的隐式拒绝继续保护。原生策略只加入 camera policy group，不关闭 AppArmor。

`QT_GSTREAMER_CAMERABIN_VIDEOSRC=libcamerasrc` 将 Qt5 相机输入接到 libcamera。两个镜像入口安装依赖、权限和启动配置；已验证非 root 用户枚举 OV5647、底层连续抓取 5 帧、相机应用实时预览。用户随后报告保存照片时 SIGSEGV，横屏预览布局也需继续修复；当前不能视为完整相机适配。压缩镜像尚未重新生成。

相机保存 SIGSEGV 的 GDB 调用栈位于 `preview-appsrc` 的 GStreamer 视频转换线程，执行地址落在动态生成的代码中。设置 `ORC_CODE=backup` 使用转换后备路径后，用户实机再次拍照保存未崩溃，并确认 Pictures/camera.ubports 中生成非空 JPEG。此配置已持久写入会话环境。横屏取景布局仍在排查。

镜像还启用 `cutiepi-camera-policy.service`，在 AppArmor 加载后、LightDM 启动前重新生成 Click 策略，以保证修改的 camera policy group 被已有预装应用采用。实际设备已安装并启用该服务，systemd 单元校验通过。

## 原生软键盘窗口显示

除 EGL 启动问题外，CutiePi 的触摸、HDMI 遥控和 keyd 虚拟键盘节点使 Lomiri 判断有硬件键盘；Greeter 还会重置 always-show-osk。窗口模式会将键盘报告高度设为 0。实机恢复 Staged 平板模式，并在 CutiePi 会话中为带触摸屏的 tablet 保持 OSK 可用。

Mir 2 输入法窗口还可能不产生工作区通知。InputMethod.qml 增加 SurfaceManager 原生输入法窗口兜底，保留后续窗口重建的绑定；键盘服务使用 wl-shell 避免输入面板被标为 hidden。脚本重复应用检查通过，用户已确认浏览器和切换应用后的输入框均能弹出键盘。keyd 服务已恢复运行，软件渲染测试配置和临时输入测试应用已删除。
