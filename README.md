# Ubuntu Touch on CutiePi

当前阶段为 CutiePi 的首次 Ubuntu Touch 开发镜像构建和上机准备。

2026-11-16：已在本机创建并启动 `cutiepi-dev`，运行 `dev/bootstrap.sh` 成功；`dev/verify.sh` 已通过 ARM64 C 程序编译运行、设备树编译和反编译、ext4 镜像创建、loop 挂载写入及文件系统检查。Guest 为 Ubuntu 24.04.5 LTS，内核 `6.8.0-147-generic`。该内核仅用于构建主机。

## 开发虚拟机

- 管理工具：Lima，使用 Apple Virtualization.Framework (`vz`)。
- 名称：`cutiepi-dev`。
- 系统：Ubuntu Server 24.04 ARM64。
- 资源：6 核 CPU、8GiB RAM、60GiB 按需增长磁盘。
- 镜像来源和 SHA-256 固定在 `dev/lima.yaml`。
- 本项目只读挂载到虚拟机 `/mnt/project`；构建源码和产物应放在虚拟机内部的 `~/cutiepi`，以保留 Linux 文件系统语义。

在 macOS 终端执行：

```sh
# 首次创建，在本项目目录运行
brew install lima
limactl start --name=cutiepi-dev --tty=false dev/lima.yaml

# 安装构建工具
limactl shell --workdir=/tmp cutiepi-dev bash /mnt/project/dev/bootstrap.sh

# 验证 ARM64 编译、设备树编译、ext4 镜像创建和 loop 挂载
limactl shell --workdir=/tmp cutiepi-dev bash /mnt/project/dev/verify.sh

# 进入 Linux
limactl shell --workdir=/home/bdong.guest/cutiepi cutiepi-dev

# 查看状态、停止和再次启动
limactl list
limactl stop cutiepi-dev
limactl start cutiepi-dev
```

进入 Linux 后，工作目录为：

```text
~/cutiepi/src     上游源码
~/cutiepi/build   编译目录
~/cutiepi/images  生成的镜像
```

`/home/bdong.guest` 是本机环境的 guest home；在其他机器重建时用 `limactl shell --workdir=/tmp cutiepi-dev printenv HOME` 查询。
`dev/lima.yaml` 中的主机项目挂载路径也需要按机器调整。
虚拟磁盘和系统数据位于 `~/.lima/cutiepi-dev`。
修改 YAML 不会自动更新已有实例的配置。

## 验证范围

环境检查成功仅代表基础工具可以工作，不代表 CutiePi 内核或 Ubuntu Touch 已移植成功。
已编译树莓派 6.12.116 ARM64 内核，并离线合成 CM4 和 CutiePi 所需的设备树。
GPU、DSI 屏幕、触控、MCU 和电源管理最终必须在实机验证。

## 编译 CM4 / CutiePi 内核基线

当前按官方硬件资料推进，实机没有系统。内核 revision、硬件映射和根文件系统调查见 [移植记录](docs/porting-notes.md)。

```sh
limactl shell --workdir=/tmp cutiepi-dev bash /mnt/project/dev/build-dtmerge.sh
limactl shell --workdir=/tmp cutiepi-dev bash /mnt/project/dev/build-kernel.sh
limactl shell --workdir=/tmp cutiepi-dev bash /mnt/project/dev/verify-kernel.sh \
  /home/bdong.guest/cutiepi/images/kernel-ab4372076bb840600e522ae776887ae2bc488fa6
```

构建使用固定源码版本的 `bcm2711_defconfig`。产物包含 kernel8.img、CM4 DTB、overlay 和模块；尚不包含启动固件、Ubuntu Touch 根文件系统或完整 SD 镜像。
`verify-kernel.sh` 使用树莓派官方 dtmerge 验证 overlay 合成，并检查关键模块的内核版本。

## 开发根文件系统与 SD 镜像

当前目标为上游 `26.04-1.x` mainline 开发分支。主机上的 `artifacts/cutiepi-dev-key.pub` 公钥进入开发镜像，对应私钥仅留在 Mac。

```sh
limactl shell --workdir=/tmp cutiepi-dev bash /mnt/project/dev/setup-rootfs-tools.sh
limactl shell --workdir=/tmp cutiepi-dev bash /mnt/project/dev/fetch-firmware.sh
limactl shell --workdir=/tmp cutiepi-dev bash /mnt/project/dev/build-rootfs.sh
limactl shell --workdir=/tmp cutiepi-dev bash /mnt/project/dev/assemble-image.sh
```

根文件系统脚本要求已取得移植记录中固定版本的 `rootfs-builder-debos` 源码，主机 `artifacts/` 下已有专用 SSH 密钥。
首次仅能通过 Wi-Fi 调试时，在 Mac 上执行 `python3 dev/configure-wifi.py` 生成本地连接配置。镜像包含该配置，应保存在本机。
镜像组装在虚拟机内进行。Mac 端可运行 `bash dev/flash-microsd.sh`，脚本先校验镜像，再识别这张 31.9 GB USB 可移除卡（31,914,983,424 字节）。终端确认磁盘编号后会覆盖整卡，并要求 Mac 管理员授权。

刷卡后把卡插入 CutiePi 开机。可用 `ssh -i artifacts/cutiepi-dev-key phablet@cutiepi.local` 连接。同一局域网无法解析主机名时，用路由器为 CutiePi 分配的 IP。开机约 75 秒后，系统会在启动分区写入 `cutiepi-boot-report.txt`，可关机后插回 Mac 查看。

## 参考

- [Lima 文档](https://lima-vm.io/docs/)
- [CutiePi OS Porting Guide](https://github.com/cutiepi-io/cutiepi-doc/blob/main/OSPortingGuide.md)
- [CutiePi 驱动](https://github.com/cutiepi-io/cutiepi-drivers)
- [UBports 树莓派项目](https://gitlab.com/ubports/porting/community-ports/raspberrypi)
