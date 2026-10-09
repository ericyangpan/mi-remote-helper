# RC003 硬件能力

[English](rc003-capabilities-research.md) · **简体中文**

观察日期为 2026-10-03，使用 macOS CoreBluetooth 与 IOKit。结果对应一组设备与固件组合，不代表所有 RC003 版本。

## 设备信息

| 字段 | 观察值 |
| --- | --- |
| 型号（`2A24`） | `RC003` |
| 厂商（`2A29`） | `MIOM` |
| 硬件版本（`2A27`） | `V2.0` |
| 固件版本（`2A26`） | `2671` |
| 软件版本（`2A28`） | `A.7.0.6` |
| HID VID / PID | `0x2717 / 0x32B8` |

以上为型号和协议标识，不是设备序列号或蓝牙地址。

## 已支持和未确认的能力

麦克风、13 个实体按键及电量已有应用或硬件证据。麦克风要求按住语音键。电量使用 `180F / 2A19`；`2BED` 也可读取并发送通知，但尚未验证充电状态切换。

目前没有经过验证的加速度计、陀螺仪、磁力计、环境光、接近感应、运动手势或空中鼠标接口。缺少描述字段或通知不代表不存在对应硬件：传感器可能只供固件内部使用，或需要未知的激活协议。

[小米产品页](https://www.mi.com/xiaomi-bluetooth-remote-2-pro)介绍了 NFC 投屏。这不能证明存在运动传感器，也不能证明手机接触会产生 BLE 事件。其他小米遥控器型号的参数不能作为 RC003 能力的证据。

## GATT 观察

CoreBluetooth 暴露了 6 个服务、25 个特征。这是 API 可见的子集，不是完整 ATT 数据库。系统的 HID 通道通过 IOKit 单独检查。

| 服务 | 特征数 | 观察到的用途 |
| --- | ---: | --- |
| `180F` | 2 | 电量与电池状态 |
| `180A` | 9 | 设备信息 |
| `AB5E0001-5A21-4F05-BC7D-AF01F617B664` | 3 | ATVV 写入、音频通知及控制通知 |
| `8A7A0001-2C42-C2A2-0F36-41928C259B78` | 5 | 两个无响应写入和三个通知，语义未知 |
| `01BF` | 1 | `0001` 支持无响应写入，没有可读取的传感器值 |
| `FE59` | 5 | 包含匹配 Nordic Secure DFU 的 UUID，未执行更新操作 |

私有通知特征 UUID 分别以 `8A7A0102`、`8A7A0103`、`8A7A0112` 开头，与服务使用相同后缀。`FE59` 包含 `8EC90001-F315-4F60-9FB8-838830DAEA50` 和 `8EC90002-F315-4F60-9FB8-838830DAEA50`。匹配 DFU UUID 不能确定处理器型号，也不能证明存在运动硬件。

## HID 观察

| Report ID | Usage page | 负载，不含 Report ID |
| --- | --- | --- |
| `1` | `0x07` Keyboard | 6 字节，三个 16 位项 |
| `6`、`7`、`8` | `0xFF00` Vendor Defined | 各 120 字节，语义未知 |

描述中没有 Sensors usage page（`0x20`）、标准鼠标轴或姿态字段。仅凭报告长度不能判断其为音频或运动数据。

约 315 秒的观察收到了电池通知和八条键盘报告，未收到私有服务或厂商报告通知。动作未与采样逐项对齐，因此这是默认连接状态下的阴性观察，不是校准后的运动测试。没有使用未知激活命令、DFU 操作或音频采集。私有通知订阅在观察后已恢复。

捕获的非零键值为确定、返回及语音，并非所报告的方向键对照，该对应关系尚未核实。

确认运动硬件需要对应型号的电路板、元件识别或固件证据。确认可用运动接口还需要明确的激活方式，以及已解码且与动作对应的数据。蓝牙信号强度不能替代三轴运动测量。

## 协议参考

- [Bluetooth SIG 编号](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/Assigned_Numbers/out/en/index-en.html)及[电池服务](https://www.bluetooth.com/specifications/specs/battery-service/)。
- [USB-IF HID Usage Tables](https://www.usb.org/sites/default/files/hut1_3_0.pdf)。
- [Nordic 固件架构与 DFU](https://nordicsemiconductor.github.io/Nordic-Thingy52-FW/documentation/firmware_architecture.html)。
