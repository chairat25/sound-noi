# Sound Control

แอป menu-bar บน macOS ที่เล่นเสียงเมื่อ Mac ทำอะไรบางอย่าง: เสียบสายชาร์จ, ล็อกจอ, เสียบ USB, เน็ตหลุด, กดคีย์บอร์ด, ดาวน์โหลดเสร็จ รวม 60 เหตุการณ์
ทุก trigger เปลี่ยนเสียงได้เอง ใช้ sound pack สำเร็จรูป หรือสร้าง pack ของตัวเองแบบเป็น game master ก็ได้

ฟีเจอร์ทั้งหมดเปิดใช้ได้เลย ไม่มีระบบ Pro/License

---

## ความต้องการ

- macOS 15 (Sequoia) ขึ้นไป · Apple Silicon หรือ Intel

## ติดตั้งด้วยคำสั่งเดียว (แนะนำ)

เปิด **Terminal** แล้ววาง:

```bash
curl -fsSL https://raw.githubusercontent.com/chairat25/sound-noi/main/install.sh | bash
```

สคริปต์โหลด release ล่าสุด, เช็ค SHA-256, ติดตั้งลง `/Applications` แล้วเปิดแอปให้ ไม่เจอหน้าต่าง "Apple could not verify…" เพราะไฟล์ที่โหลดผ่าน `curl` ไม่ถูกติด quarantine. รันซ้ำเพื่ออัพเดตเป็นเวอร์ชันใหม่ได้ (settings และเสียงที่ import ไว้ยังอยู่)

ตัวเลือก: `SOUND_CONTROL_VERSION=1.2.0` เลือกเวอร์ชัน, `SOUND_CONTROL_DIR=~/Applications` เปลี่ยนที่ติดตั้ง, `SOUND_CONTROL_NO_OPEN=1` ไม่เปิดแอปหลังติดตั้ง เช่น `curl -fsSL …/install.sh | SOUND_CONTROL_NO_OPEN=1 bash`

## ติดตั้งจาก DMG

1. โหลด `SoundControl-<version>.dmg` จากหน้า [Releases](https://github.com/chairat25/sound-noi/releases/latest)
2. เปิด DMG แล้วลาก **Sound Control** ไปวางที่ **Applications**
3. เปิดครั้งแรก: แอปไม่ได้ notarize กับ Apple macOS จึงบล็อกไว้ ปลดได้ 2 วิธี
   - เปิดแอปหนึ่งครั้ง (จะขึ้นเตือน) กด **Done** → เปิด **System Settings → Privacy & Security** ใหม่ → ปุ่ม **Open Anyway** อยู่ใต้ "Allow applications from" (ขึ้นแค่ราว 1 ชั่วโมงหลังลองเปิด และต้องเปิดหน้า Settings ใหม่หลังลองเปิดแอป)
   - หรือใน Terminal:
     ```bash
     xattr -dr com.apple.quarantine "/Applications/Sound Control.app"
     ```
4. ไอคอน waveform ◉ จะขึ้นใน menu bar

ตรวจไฟล์ที่โหลดมา: `shasum -a 256 SoundControl-<version>.dmg` แล้วเทียบกับไฟล์ `.sha256` ใน release

อัพเดตเวอร์ชัน: Quit แอปตัวเดิม → ลากตัวใหม่ไปทับใน Applications (settings และเสียงที่ import ไว้ยังอยู่) → ต้องให้สิทธิ์ Input Monitoring ใหม่ถ้าใช้ trigger คีย์บอร์ด/เมาส์

## Build เอง

ต้องมี Xcode 16+ หรือ Swift 6 toolchain

```bash
git clone https://github.com/chairat25/sound-noi.git
cd sound-noi
scripts/build-app.sh                     # ได้ build/Sound Control.app (เฉพาะ CPU เครื่องนี้)
scripts/build-app.sh --install           # build แล้ว copy ไป /Applications
scripts/build-app.sh --universal --dmg   # แบบ release: Apple Silicon + Intel, ได้ .dmg .zip .sha256 ใน build/
```

ตอนเปิดครั้งแรก หน้าต่างหลักจะเด้งขึ้นมาเอง หลังจากนั้นแอปจะอยู่ใน menu bar เท่านั้น (ไอคอน waveform ◉)

> แอป sign แบบ ad-hoc ถ้า build ใหม่ macOS จะมองเป็นแอปใหม่ ต้องให้สิทธิ์ Input Monitoring ใหม่อีกครั้ง

## วิธีใช้

### Menu bar
คลิกไอคอนใน menu bar:
- **สวิตช์ Listening** เปิด/ปิดเสียงทั้งหมดทีเดียว
- **Volume** ระดับเสียงหลัก
- **Pack** เปลี่ยน sound pack ที่ใช้อยู่
- **Recent** 5 event ล่าสุด
- **Open Sound Control…** (⌘,) เปิดหน้าต่างหลัก · **Quit** (⌘Q)

### Triggers
รายการเหตุการณ์ทั้งหมด แบ่งตามหมวด แต่ละแถวมี:

| ส่วน | ทำอะไร |
|---|---|
| สวิตช์ | เปิด/ปิด trigger นั้น |
| chip เสียง (สีม่วง) | เลือกเสียงเดียวแบบเร็วๆ หรือ **Follow pack** ให้ pack เป็นคนเลือก |
| ▶ | ฟังตัวอย่าง (เล่นได้แม้ Listening ปิดอยู่) |
| ⚙ (slider) | เปิดหน้ารายละเอียด: ใส่หลายเสียง, เลือก Rotate/Shuffle, ปรับ volume เฉพาะ trigger |

- **Turn on recommended** เปิดชุดที่แนะนำ (ไม่ต้องขอ permission)
- ปุ่ม ⋯ มี Turn everything on/off, หัวหมวดมี Turn all on/off ของหมวดนั้น
- ช่องค้นหา + filter All / On / Off
- ดับเบิลคลิกแถวเพื่อเปิดหน้ารายละเอียด

**ใส่หลายเสียงให้ trigger เดียว:** ⚙ → เลือก *My own sounds* → *Add sound* หลายครั้ง → เลือก *Rotate in order* (เล่นวนตามลำดับ) หรือ *Shuffle* (สุ่ม ไม่ซ้ำกับครั้งก่อน)

### Sound Packs
pack คือ "เครื่องดนตรี" ที่เล่นทุก trigger ซึ่งตั้งเป็น Follow pack แต่ละ trigger มีท่วงทำนอง (motif) ของตัวเอง เช่น เสียบสาย = เสียงไล่ขึ้น, ถอดสาย = ไล่ลง ทุก pack จึงสื่อความหมายเหมือนกันแต่คนละสำเนียง

| Pack | สไตล์ |
|---|---|
| Crystal | เสียงแก้ว/ระฆังกังวาน (ค่าเริ่มต้น) |
| Arcade | square wave แบบเกม 8-bit |
| Marimba | เสียงไม้ ระนาด สั้นๆ อบอุ่น |
| Cosmic | sine ลอยๆ มี vibrato |
| Soft Keys | คลิกเบาๆ เหมาะกับเสียงพิมพ์ |
| macOS Classic | เสียง alert ที่มีอยู่แล้วใน Mac |

เสียงใน synth pack ถูกสร้างด้วยโค้ดตอนรัน (ไม่มีไฟล์เสียงในแอป) และแต่ละเสียงมี 2 takes ที่จะสลับกันเล่น

**เป็น game master — สร้าง pack ของตัวเอง:**
1. Sound Packs → **New pack** → เลือก pack ตั้งต้น
2. ตั้งชื่อ แล้วเลือกเสียง override ทีละ trigger (trigger ที่ไม่ได้ override ใช้เสียงจาก pack ตั้งต้น)
3. กด **Use** เพื่อใช้ pack นั้น
4. **⋯ → Export…** ได้โฟลเดอร์ `.soundpack` (มี `pack.json` + ไฟล์เสียงที่ใช้) ส่งให้คนอื่นได้ · **Import…** เพื่อนำเข้า

ลำดับการเลือกเสียง: เสียงที่ตั้งให้ trigger เอง → override ของ custom pack → เสียงของ pack ตั้งต้น

### My Sounds
- **Import…** หรือลากไฟล์มาวาง รองรับ WAV, AIFF, MP3, M4A, CAF, AAC, FLAC (ยาวไม่เกิน 30 วินาที, ไม่เกิน 25 MB)
- ไฟล์ถูก copy เข้าแอป ย้าย/ลบต้นฉบับได้เลย
- ⋯ → Rename / Delete (ลบแล้ว trigger ที่ใช้เสียงนั้นจะกลับไปใช้เสียงของ pack)

### Activity
ประวัติ event ล่าสุด 200 รายการ: เกิดอะไร, ตอนไหน, เล่นเสียงอะไร หรือถูกข้ามเพราะอะไร (Quiet hours, ไม่มีเสียง ฯลฯ)
event ถี่ๆ (กดคีย์, คลิก, ปรับ volume, สลับแอป) ไม่ถูกบันทึก

### Settings
- Listening, Master volume, **Launch at login**
- **Responsiveness**
  - *Instant sounds*: output พร้อมเล่นตลอดขณะใช้เครื่อง (พักเองเมื่อไม่ได้ใช้ ไม่กันเครื่อง sleep)
  - *One sound per moment*: event ที่เกิดพร้อมกันเล่นแค่ตัวแรก
- **macOS sounds → Replace macOS sounds** (เปิดเป็นค่าเริ่มต้น): ถ้า trigger เปิดอยู่และ macOS มีเสียงของตัวเองในจังหวะเดียวกัน แอปจะ mute เสียง macOS ให้ จะได้ไม่มีเสียงระบบดังก่อนหรือดังทับ
  | trigger ที่เปิด | เสียง macOS ที่ถูก mute |
  |---|---|
  | Charger connected | charging chime |
  | Screenshot taken, Trash changed | interface sound effects (shutter, Trash, Finder) — ถ้ายังได้ยิน ให้ log out/in ใหม่ |
  | Volume changed | volume change feedback |

  ปิด trigger, ปิด Listening หรือ Quit แอป = macOS ได้เสียงคืน (คืนค่าเดิมที่จำไว้)
- **Hide floating screenshot thumbnail**: ไม่ใช่เสียง แต่ถ้าเปิดไว้ macOS เขียนไฟล์ช้า ~5 วินาที เสียง screenshot เลยช้าตาม
- **Quiet hours** ช่วงเวลาที่ไม่เล่นเสียง (ข้ามเที่ยงคืนได้ เช่น 22:00–07:00)
- เกณฑ์ battery low / critical, เวลาที่ถือว่า "ไม่อยู่หน้าเครื่อง"
- Permissions: ปุ่มเปิด System Settings + Recheck
- Reset all settings

## Triggers ทั้งหมด

| หมวด | Triggers |
|---|---|
| Power | Charger connected/disconnected, Battery fully charged, Battery low, Battery critical, Low Power Mode on/off |
| System | You log in, Switched back to you / to another user, Mac sleeps/wakes, Shut down or restart, Lid closed/opened, Mac heating up / cooled down |
| Screen & Display | Screen locked/unlocked, Screen saver starts/stops, Display sleeps/wakes, Display connected/disconnected, Dark/Light mode, Space changed |
| Apps | App launched, App quit, Switched app |
| Devices | USB connected/disconnected, Disk mounted/ejected, Bluetooth connected/disconnected, Audio output changed |
| Audio | Volume changed, Muted, Unmuted |
| Network | Internet connected/lost, Network changed (Wi-Fi ↔ Ethernet) |
| Keyboard & Mouse | Key typed, Return, Delete, Space bar, Mouse click, Right click, Caps Lock on/off |
| Files & Clipboard | Screenshot taken, Download finished, Copied to clipboard, Trash changed |
| Time & Activity | Every hour, Every half hour, You stepped away, Welcome back |

## Permissions

| Trigger | ต้องการ |
|---|---|
| Keyboard & Mouse | **Input Monitoring** — System Settings → Privacy & Security → Input Monitoring → เปิด Sound Control (ดูแค่ key code ไม่เก็บสิ่งที่พิมพ์) |
| Bluetooth | ขอสิทธิ์ Bluetooth ครั้งแรกที่เปิด trigger |
| Download finished | ขอสิทธิ์โฟลเดอร์ Downloads ครั้งแรก |
| Screenshot taken | ขอสิทธิ์โฟลเดอร์ Desktop (หรือโฟลเดอร์ที่เก็บ screenshot) ครั้งแรก. ถ้าไม่อนุญาต ยังทำงานผ่าน Spotlight แต่ช้ากว่า |
| Trash changed | **Full Disk Access** |

monitor แต่ละตัวเริ่มทำงานเฉพาะเมื่อมี trigger ของมันเปิดอยู่ ถ้าไม่เปิด trigger ที่ต้องขอสิทธิ์ แอปก็จะไม่ขอ

## ข้อจำกัดที่รู้

- **Mac goes to sleep / Lid closed / Shut down**: เครื่องอาจหลับหรือปิดก่อนเสียงเล่นจบ
- **Lid** ใช้ได้เฉพาะ MacBook, **Battery** ใช้ได้เฉพาะเครื่องที่มีแบต (Mac ที่ไม่มีจะขึ้นเตือนในแถว trigger)
- **Screenshot taken** ดังเมื่อไฟล์ถูกเขียน ถ้าเปิด floating thumbnail ไว้จะช้า ~5 วินาที (ซ่อนได้ใน Settings) และไม่ดังเมื่อ capture ลง clipboard
- **Instant sounds** ทำให้ output device ทำงานขณะใช้เครื่อง ถ้า AirPods สลับมาที่ Mac เองบ่อยเกินไป ให้ปิด option นี้
- **Display connected** นับจำนวนจอ ถ้าปิดฝาแล้วใช้จอนอก จอในเครื่องจะนับเป็น disconnected
- **Trash changed** ต้องให้ Full Disk Access ไม่งั้นแอปขึ้นเตือนในแถว trigger

## ข้อมูลเก็บที่ไหน

```
~/Library/Application Support/SoundControl/
├── config.json   # การตั้งค่าทั้งหมด (ถ้าไฟล์เสีย จะ rename เป็น config.corrupt-<time>.json แล้วใช้ค่าเริ่มต้น)
└── Sounds/       # ไฟล์เสียงที่ import (<uuid>.<ext>)
```

ถอนการติดตั้ง: ปิด *Hide floating screenshot thumbnail* (ถ้าเปิดไว้) → Quit (คืนเสียง macOS ให้อัตโนมัติ) → ลบ `/Applications/Sound Control.app` และโฟลเดอร์ด้านบน

## Development

```bash
swift build                          # debug build
swift run SoundControl               # รันจาก terminal (launch at login ใช้ไม่ได้ในโหมดนี้)
swift test --enable-code-coverage    # unit tests (Swift Testing)
```

โครงสร้าง:

```
Sources/
├── SoundControlCore/   # logic ล้วน, value types, Swift 6 strict concurrency, มี test ครบ
│   ├── TriggerID.swift, TriggerCatalog.swift   # รายการ trigger + metadata
│   ├── Motif.swift, Synth.swift                # ท่วงทำนอง + synthesizer
│   ├── SoundRef.swift, SoundPack.swift         # ตัวอ้างอิงเสียง, pack สำเร็จรูป/custom
│   ├── AppConfig.swift                         # config + immutable updates
│   ├── SoundResolver.swift, PlaybackGate.swift # เลือกเสียง, กฎว่าจะเล่นหรือไม่
│   ├── Trackers.swift                          # battery/idle/clock/download state machines
│   └── ConfigStore.swift, PackArchive.swift, ActivityLog.swift
└── SoundControl/       # แอป
    ├── AppModel.swift                          # state กลาง
    ├── Audio/                                  # AVAudioEngine + buffer cache
    ├── Monitors/                               # ตัวฟัง event ของระบบ (IOKit, CoreAudio, NSWorkspace, …)
    ├── Services/                               # import เสียง, export/import pack, login item
    └── Views/                                  # SwiftUI
scripts/build-app.sh                            # สร้าง .app + icon + codesign
```

เพิ่ม trigger ใหม่: เพิ่ม case ใน `TriggerID` → ใส่ข้อมูลใน `TriggerCatalog` → ให้ monitor ตัวใดตัวหนึ่ง emit มันและใส่ลง `triggers` set ของ monitor นั้น (test `everyTriggerRegistered` จะฟ้องถ้าลืมข้อ 2)
