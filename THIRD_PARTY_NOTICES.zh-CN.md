# 第三方声明

[English](THIRD_PARTY_NOTICES.md) · **简体中文**

本页为说明性翻译。GPL 与字体许可证原文保持不变，详见各自许可证文件。

## Open Voice Bridge

- 来源：https://github.com/nijez/open-voice-bridge
- 固定版本：`1796b149f752ff2d2fa82fd818f8a5a2bc60802a`
- 版权所有：Copyright (C) 2026 Open Voice Bridge contributors.
- 许可证：GPL-3.0-only，全文见 [LICENSE](LICENSE)。

ATVV 编解码器、蓝牙生命周期、外设桥接、设备配置、语音控制边沿跟踪及 CoreAudio 设备目录改编自 Open Voice Bridge。音频输出路由、设备专属语音键映射，以及 RC003 按键 usage、报告解析、快捷键录制、键盘和媒体事件注入，也源于上述固定版本。按键读取器优先独占访问设备，失败时使用设备专属 UserKeyMapping 屏蔽原动作，不使用全局键盘事件过滤器。

修改包含仅支持 macOS 的 Xcode 应用、仅确认 RC003 型号、有界音频缓冲、默认左 Control 的可选语音键、连接超时、输入校验，以及保留收音开始前的解码同步。

Open Voice Bridge 的初始 RC003 协议适配源于 https://github.com/xxb26553663-star/remote-bridge-hub，固定版本为 `8a93f321ac71a602300c6cd77f7256fa4b63068e`，许可为 GPL-3.0-only。本项目保留此归属，不包含上游品牌素材、Sparkle 二进制或 Windows 组件。

Mi Remote Helper 采用 GPL-3.0-only 分发。

## BlackHole

https://github.com/ExistentialAudio/BlackHole 是用户单独安装的外部虚拟音频设备。仓库不附带 BlackHole 驱动二进制或安装器。应用可以使用已安装的 BlackHole 或 MiRemoteV 回环设备。

小米、微信名称仅表示兼容的硬件和软件，不表示背书或隶属关系。

## 字体

- Arvo Regular、Bold：https://github.com/google/fonts/tree/main/ofl/arvo
- Poppins Regular、Medium、SemiBold：https://github.com/google/fonts/tree/main/ofl/poppins

未修改的字体按 SIL Open Font License 1.1 打包。完整版权及许可证位于 `MiRemoteHelper/MiRemoteHelper/Design/Fonts/Arvo-OFL.txt` 和 `Poppins-OFL.txt`，并复制到 App 资源中。字体仅在应用进程内注册。中文采用 macOS 提供的苹方 SC，快捷键采用原生系统字体。

## RC003 产品照片

- 来源：[小米蓝牙遥控器 2 Pro 官方产品页](https://www.mi.com/xiaomi-bluetooth-remote-2-pro)。
- 原图：https://cdn.cnbj1.fds.api.mi-img.com/product-images/xiaomi-bluetooth-remote-2-prob7e569/section-02_list1.jpg
- 版权归小米及相关权利人所有，不包含在软件的 GPL-3.0-only 许可中。目前没有可再分发授权记录，署名与本说明不替代许可。
- 照片用于展示兼容遥控器与实体按键，本项目与小米无隶属或背书关系。
- 如权利人认为使用侵犯其权益，请通过项目 Issue 提供图片位置及权属依据；如有侵权，我们将删除。请先请求私下联系渠道，不要公开敏感证明材料。

## 修改声明

Mi Remote Helper 部分基于 Open Voice Bridge 修改。截至 2026-10-08，修改包含原生 macOS 界面、按应用映射、点按开关式听写控制、音频恢复及可配置的系统输入锁定。Copyright © 2026 Mi Remote Helper contributors. 软件按 GPL-3.0-only 提供，不含担保；源码与应用均附完整许可证。单独授权的素材继续适用上述各自条款。
