# 映射定义 v2

[English](mapping-definitions.md) · **简体中文**

映射按当前前台应用的 Bundle ID 精确匹配，不按显示名称或窗口标题匹配。优先级：启用的应用扩展中对应动作的覆盖 → 全局映射 → 内置默认值。短按、双击和长按分别解析；显式 `disabled` 表示无操作，省略该项则继承全局。语音键短按可自定义和导出；长按固定为语音输入，双击可自定义，默认为无操作。

切换前台应用会取消尚未触发的短按、双击和长按；松开旧按键不会在新应用中触发补发。应用扩展只改变键盘/媒体/鼠标映射，不改变语音会话。

## 使用

在按键映射页选择“全局”或具体应用。应用配置的每个动作可选择“继承全局”，也可设置自己的动作。编辑某个应用配置不等于激活该配置；仅当前台应用匹配且扩展启用时才生效。应用扩展可单独停用、移除或恢复全部继承。

“添加应用”选择一个 macOS `.app`，从其 Info.plist 读取 Bundle ID。内置 Codex 扩展匹配 `com.openai.codex`，默认语音键短按为 Command-Option-I，其余动作继承全局。导入应用定义也可添加未安装的应用扩展。

“导出”保存当前编辑配置的 JSON 文件：全局导出完整的 12 个普通键短按/双击/长按定义及语音键短按和双击；应用扩展只导出自己的覆盖项。应用扩展启用状态、蓝牙设备、音频设备、权限、登录项和应用路径不包含在文件中。

“导入”先展示定义的作用范围和各动作。确认后，全局定义替换全部全局按键配置，保留应用扩展；应用定义仅替换同一 Bundle ID 的扩展覆盖，保留该扩展原来的启用状态。新应用扩展默认启用。空应用定义表示全部继承全局。

## 文件结构

```json
{
  "format": "mi-remote-helper.mapping",
  "version": 4,
  "name": "Codex",
  "scope": "application",
  "bundleIdentifier": "com.openai.codex",
  "shortPress": {},
  "longPress": {},
  "doublePress": {}
}
```

- `format` 固定为 `mi-remote-helper.mapping`，`version` 当前为整数 `4`，同时接受 v1/v2/v3 文件并迁移；旧版应用会拒绝 v4 文件。
- `name` 是可读名称，最多 80 个字符，不能含控制字符。
- `scope` 为 `global` 或 `application`；全局定义不携带 `bundleIdentifier`，应用定义必须提供该字段。
- Bundle ID 按大小写精确匹配，包含句点，最多 255 个 ASCII 字母、数字、连字符、句点，首字符为字母或数字。
- `shortPress`、`doublePress`、`longPress` 均为按键标识到动作定义的对象；v4 三个字段都必须存在。全局短按和双击包含 13 个按键，长按包含 12 个普通按键，应用可仅包含覆盖项。
- 文件最大 256 KiB；未知版本、未知按键/动作、语音键长按覆盖和无效快捷键都会拒绝整份导入，不部分应用。
- 长按阈值为 0.5 秒，每次只执行短按、双击、长按之一。设有双击动作时，首次松开后等待 0.3 秒；窗口内第二次按下且短按松开执行双击，第二次持续长按则只执行长按。双击为无操作时，短按松开立即执行。

`microphone` 仅可出现在 `shortPress` 中，全局默认无操作。Codex 默认 Command-Option-I，Grok Bot 默认 Command-I；Codex 中需将“聚焦主聊天”配置为相应快捷键。语音键短按在松开时执行映射，不启动听写；长按 0.5 秒后开始听写，不发送短按动作。手势尚未确定时，最多保留 0.5 秒的起始 PCM 音频于内存；长按时送出，短按时丢弃。

普通按键标识：`power`、`up`、`left`、`ok`、`right`、`down`、`back`、`volume_up`、`home`、`volume_down`、`menu`、`tv`。

### 预设动作

```json
{ "type": "preset", "action": "pageUp" }
```

允许的 `action`：`disabled`、`escape`、`returnKey`、`arrowUp`、`arrowDown`、`arrowLeft`、`arrowRight`、`homeKey`、`endKey`、`pageUp`、`pageDown`、`deleteBackward`、`clearText`、`showDesktop`、`contextMenu`、`appSwitcher`、`mouseRightClick`、`volumeUp`、`volumeDown`、`volumeMute`、`playPause`。

`contextMenu` 与 `mouseRightClick` 均在当前鼠标指针位置发送一次右键点击，用于打开该位置的上下文菜单。输入焦点不会改变右键的目标位置。需要 Shift-F10 的应用可使用自定义快捷键。

`clearText` 在当前聚焦控件是文本框、文本区或组合框时发送 Command-A 后 Delete，清空该控件的全部文字；其他控件上不执行。仅发送到触发时的前台应用。旧版不认识此动作时会拒绝导入，应先更新应用。

### 自定义快捷键

```json
{
  "type": "shortcut",
  "chord": {
    "keyCode": 8,
    "keyLabel": "C",
    "modifiers": 1
  }
}
```

此例为 Command-C。`keyCode` 是 0–127 的 macOS 虚拟物理键码；`keyLabel` 为最多 24 字符的非空显示标签，不参与按键匹配。修饰键按位组合：Command=1、Control=2、Option=4、Shift=8，无修饰键为 0。使用界面的快捷键录制可避免手工填写键码。

扩展仅包含声明式映射数据，不加载脚本、动态库或可执行代码。以后增加动作类型或改变定义语义时应提升格式版本，并提供明确的迁移。

## 示例

- [Codex 扩展](../Examples/codex.mapping.json)：所有动作继承全局，包括 OK 的短按、长按和双击。
- [全局默认配置](../Examples/global-defaults.mapping.json)：完整默认定义，OK 长按 Shift+Return、双击 Command+Return，左右长按 Home/End，上下长按 Page Up/Page Down，回退键长按清空全部文字。

旧版 `buttonMappings.v1`、`buttonHoldMappings.v1` 设置继续作为全局配置读取；应用配置保存在 `applicationMappings.v1`，全局双击保存在 `buttonDoubleMappings.v1`。v1 全局文件迁移后双击全部为无操作；v1 应用文件迁移后双击全部继承全局。
