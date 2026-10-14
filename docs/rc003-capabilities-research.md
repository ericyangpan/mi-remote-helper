# RC003 hardware capabilities

**English** · [简体中文](rc003-capabilities-research.zh-CN.md)

Observed on 2026-10-03 using macOS CoreBluetooth and IOKit. These observations describe one device/firmware combination, not every RC003 revision.

## Device profile

| Field | Observed value |
| --- | --- |
| Model (`2A24`) | `RC003` |
| Manufacturer (`2A29`) | `MIOM` |
| Hardware (`2A27`) | `V2.0` |
| Firmware (`2A26`) | `2671` |
| Software (`2A28`) | `A.7.0.6` |
| HID VID / PID | `0x2717 / 0x32B8` |

These are model and protocol identifiers, not device serial numbers or Bluetooth addresses.

## Supported and unconfirmed capabilities

The microphone, 13 physical buttons and battery level have application or hardware evidence. The microphone requires holding Voice. Battery level uses `180F / 2A19`; `2BED` was also readable and notified. The app now reads its charging state and shows a lightning bolt in the battery icon while charging; physical charging transitions still need verification.

No verified accelerometer, gyroscope, magnetometer, ambient-light, proximity, motion-gesture or air-mouse interface is available. Missing descriptors or notifications do not prove the hardware is absent: a sensor could be internal to firmware or require an unknown activation protocol.

The [Xiaomi product page](https://www.mi.com/xiaomi-bluetooth-remote-2-pro) describes NFC casting. That does not establish motion sensing or a BLE event for phone contact. Specifications for other Xiaomi remote models do not establish RC003 capabilities.

## GATT observations

CoreBluetooth exposed six services and 25 characteristics. This is the API-visible subset, not a complete ATT database. The operating system's HID path was examined separately through IOKit.

| Service | Characteristics | Observed purpose |
| --- | ---: | --- |
| `180F` | 2 | Battery level and status |
| `180A` | 9 | Device information |
| `AB5E0001-5A21-4F05-BC7D-AF01F617B664` | 3 | ATVV write, audio notification and control notification |
| `8A7A0001-2C42-C2A2-0F36-41928C259B78` | 5 | Two writes without response and three notifications; semantics unknown |
| `01BF` | 1 | `0001` supports write without response; no readable sensor value |
| `FE59` | 5 | Includes UUIDs matching Nordic Secure DFU; update operations were not exercised |

The private notification UUIDs start with `8A7A0102`, `8A7A0103` and `8A7A0112`, sharing the service suffix. `FE59` includes `8EC90001-F315-4F60-9FB8-838830DAEA50` and `8EC90002-F315-4F60-9FB8-838830DAEA50`. A matching DFU UUID does not identify the processor or prove the presence of motion hardware.

## HID observations

| Report ID | Usage page | Payload, excluding report ID |
| --- | --- | --- |
| `1` | `0x07` Keyboard | 6 bytes, three 16-bit items |
| `6`, `7`, `8` | `0xFF00` Vendor Defined | 120 bytes each; semantics unknown |

The descriptor contained no Sensors usage page (`0x20`), standard mouse axes or orientation fields. Report length alone cannot identify audio or motion data.

An approximately 315-second observation received battery notifications and eight keyboard reports, but no private-service or vendor-report notifications. Actions were not individually time-aligned with the capture, so this is a negative observation under the default connection state, not a calibrated motion test. No unknown activation commands, DFU operations or audio capture were used. Private notification subscriptions were restored afterward.

The captured nonzero keys were OK, Back and Voice, not the reported directional-key control; that correspondence remains unverified.

Confirming motion hardware requires a matching board/component identification or firmware evidence. Confirming a usable motion interface additionally requires documented activation and decoded, action-correlated data. Bluetooth signal strength is not a substitute for three-axis motion measurements.

## Protocol references

- [Bluetooth SIG assigned numbers](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/Assigned_Numbers/out/en/index-en.html) and [Battery Service](https://www.bluetooth.com/specifications/specs/battery-service/).
- [USB-IF HID Usage Tables](https://www.usb.org/sites/default/files/hut1_3_0.pdf).
- [Nordic firmware architecture and DFU](https://nordicsemiconductor.github.io/Nordic-Thingy52-FW/documentation/firmware_architecture.html).
