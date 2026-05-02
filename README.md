rs_bridge

Advanced framework compatibility bridge for FiveM — supporting QBCore, QBox, and standalone resources.

![Framework](https://img.shields.io/badge/Framework-QBCore%20%7C%20QBox%20%7C%20Standalone-blue)
![Version](https://img.shields.io/badge/Version-2.0.0-green)

---

Features

- Automatic framework detection (QBCore / QBox / Standalone)
- Unified player system
- Money handling (cash/bank wrappers)
- Job and gang support
- Inventory abstraction layer
- Usable item support
- Server ↔ client callback system
- Notification wrapper
- Progress bar wrapper
- Target system wrapper (qb-target / qbx equivalent ready)

---

Supported Frameworks

- QBCore (`qb-core`)
- QBox (`qbx_core`)
- Standalone (fallback support)

---

Purpose

`rs_bridge` allows developers to write **one resource** that works across multiple frameworks.

Instead of rewriting logic for QBCore and QBox separately, this bridge routes everything through a unified system.

---

Framework Behavior

QBCore
Uses:
- `QBCore.Functions.GetPlayer`
- `QBCore.Functions.AddMoney`
- `QBCore.Functions.CreateUseableItem`

 QBox
Uses native exports:
- `exports.qbx_core:GetPlayer`
- Native QBox player + data handling

Standalone
- Provides fallback logic so scripts don’t break
- Useful for testing or lightweight resources

---

What This Bridge Handles

Player Data
- Get player object
- Get citizen ID
- Get job / gang
- Get identifiers

Money
- Add money
- Remove money
- Check balances

Jobs & Gangs
- Get player job
- Get player gang
- Framework-safe structure

Inventory
- Add items
- Remove items
- Check items

 Usable Items
- Register usable items across frameworks

 Callbacks
- Server → Client
- Client → Server

UI Wrappers
- Notify system
- Progress bar system
- Target interaction system

---

Installation

 QBCore and qbox

```cfg
ensure qb-core or ensure qbox
ensure rs_bridge
