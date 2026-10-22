# Changelog

รูปแบบตาม [Keep a Changelog](https://keepachangelog.com/) และใช้ [Semantic Versioning](https://semver.org/)

## [1.2.0] - 2026-10-22

### Added
- release แบบ universal binary (Apple Silicon + Intel) เป็น `.dmg` (ลากลง Applications) และ `.zip` พร้อม checksum SHA-256
- `scripts/build-app.sh --universal --dmg` สำหรับสร้างไฟล์ release

### Changed
- **Replace macOS sounds** ทำงานอัตโนมัติ (เปิดเป็นค่าเริ่มต้น): trigger ไหนเปิดอยู่และ macOS มีเสียงของตัวเองซ้ำ (charging chime, shutter screenshot/Trash, volume feedback) แอปจะ mute เสียง macOS นั้นให้ ไม่ต้องไปเปิดเอง. ใน v1.1 ต้องเปิดเอง เลยยังได้ยินเสียงชาร์จของ macOS ดังก่อนเสียงของแอป
- macOS ได้เสียงคืนเมื่อปิด trigger นั้น, ปิด Listening หรือ Quit แอป และ mute ใหม่ตอนเปิดแอป
- Settings แสดงสถานะ "Muted by Sound Control" / "macOS default" ต่อเสียง ส่วน floating thumbnail ยังเป็น toggle ให้เลือกเอง
- แถว trigger แสดง "Replaces the macOS …" เมื่อแอป mute เสียง macOS ของจังหวะนั้นอยู่

### Fixed
- แอปค้างทั้งตัว (menu bar, Quit, การคืนค่าเสียง) เมื่อ macOS ขอสิทธิ์โฟลเดอร์ Desktop/Downloads เพราะ `open()` บน main thread รอจนกว่าจะกดตอบ prompt. ตอนนี้เปิดโฟลเดอร์บน background queue แล้ว
- `kill`/`pkill` (SIGTERM) ผ่านขั้นตอนปิดแอปปกติ จึงคืนเสียง macOS และบันทึก settings ก่อนออก

## [1.1.0] - 2026-10-22

เน้นเสียงดังทันที และไม่มีเสียง macOS ดังทับ

### Added
- Settings → **macOS sounds that overlap**: ปิด charging chime, interface sound effects (shutter screenshot, Trash), volume change feedback และซ่อน floating screenshot thumbnail. แอปจำค่าเดิมไว้ ปิด toggle เมื่อไหร่ก็คืนค่าเดิมให้ (Reset all settings ไม่ลบค่าเดิมที่จำไว้)
- แถว trigger ที่ macOS เล่นเสียงของตัวเองซ้ำ (Charger connected, Screenshot taken, Trash changed, Volume changed) มีลิงก์ **Silence it**
- **One sound per moment** (เปิดเป็นค่าเริ่มต้น): event ที่เกิดห่างกันไม่ถึง 0.35 วินาที (เช่น wake + display wake, USB + disk mounted) เล่นแค่ตัวแรก ไม่รวม event ถี่ๆ เช่นการพิมพ์
- **Instant sounds** (เปิดเป็นค่าเริ่มต้น): audio output พร้อมเล่นตลอดขณะใช้เครื่อง

### Changed
- เลิก pause audio engine หลังเงียบ 20 วินาที ซึ่งทำให้เสียงถัดไปช้าราว 45 ms (วัดจริง). ตอนนี้ engine พร้อมเล่นตลอดขณะใช้เครื่อง และ pause เมื่อไม่มี input เกิน 60 วินาทีและไม่มีเสียงมา 20 วินาที เพราะ engine ที่รันค้างทำให้ coreaudiod ถือ assertion กัน idle sleep (ตรวจด้วย `pmset -g assertions`)
- โหลด/สร้างเสียงของทุก trigger ที่เปิดไว้ล่วงหน้าตอนเปิดแอปและหลังเปลี่ยน setting ครั้งแรกที่เล่นจึงไม่ต้องรอ
- Charger connected/disconnected ใช้ `IOPSCreateLimitedPowerNotification` ซึ่งยิงทันทีที่เสียบ/ถอด adapter
- Screenshot taken ดูโฟลเดอร์เก็บ screenshot ตรงๆ ร่วมกับ xattr `kMDItemIsScreenCapture` (Spotlight ยังเป็นตัวสำรอง) จึงดังทันทีที่ไฟล์ถูกเขียน
- ลด debounce/poll: clipboard 0.4 → 0.12 s, จอ 1.0 → 0.3 s, โฟลเดอร์ 0.6 → 0.12 s, idle 1.5 → 1.0 s, audio output 0.4 → 0.25 s, dark mode ไม่รอเลย
- unit tests 79 ตัว

## [1.0.0] - 2026-10-22

เวอร์ชันแรก

### Added
- แอป menu-bar (`LSUIElement`) พร้อมหน้าต่างหลัก 5 หน้า: Triggers, Sound Packs, My Sounds, Activity, Settings
- popover ใน menu bar: สวิตช์ Listening, master volume, เลือก pack, 5 event ล่าสุด
- 60 triggers ใน 10 หมวด: Power, System, Screen & Display, Apps, Devices, Audio, Network, Keyboard & Mouse, Files & Clipboard, Time & Activity
- monitor ของระบบ: IOKit power sources, clamshell, USB; NSWorkspace; distributed notifications (lock, screen saver, appearance); CoreAudio (output device, volume, mute); IOBluetooth; NWPathMonitor; CGEvent tap แบบ listen-only; Spotlight screenshot query; การเปลี่ยนแปลงในโฟลเดอร์ Downloads/Trash; clipboard change count; idle time; นาฬิกาตีบอกเวลา
- monitor เริ่มเฉพาะเมื่อมี trigger ของมันเปิดอยู่ จึงไม่ขอ permission โดยไม่จำเป็น
- synthesizer ในตัว: 5 synth pack (Crystal, Arcade, Marimba, Cosmic, Soft Keys) × 18 motif × 2 takes และ pack macOS Classic จากเสียงในระบบ
- ตั้งเสียงต่อ trigger: Follow pack หรือหลายเสียงแบบ Rotate/Shuffle (Shuffle ไม่เล่นเสียงซ้ำติดกัน), volume ต่อ trigger, ฟังตัวอย่าง
- custom pack ("game master"): เลือก pack ตั้งต้น + override ทีละ trigger, export/import เป็นโฟลเดอร์ `.soundpack`
- My Sounds: import / ลากไฟล์มาวาง (WAV, AIFF, MP3, M4A, CAF, AAC, FLAC; ≤ 30 วินาที, ≤ 25 MB), rename, delete พร้อมล้างทุกที่ที่อ้างถึงเสียงนั้น
- Activity log (200 รายการล่าสุด, ไม่บันทึก event ถี่ๆ เช่นการกดคีย์)
- Settings: quiet hours (ข้ามเที่ยงคืนได้), เกณฑ์แบต low/critical, เวลาไม่อยู่หน้าเครื่อง, launch at login (`SMAppService`), สถานะ permission, reset
- cooldown ต่อ trigger กันเสียงรัว, audio engine พักเองเมื่อเงียบ 20 วินาที
- config เก็บเป็น JSON, อ่านแบบทนทาน (key ที่ขาดใช้ค่าเริ่มต้น), ไฟล์เสียถูกเก็บสำรองไว้ ไม่เขียนทับ
- ตรวจ input จากภายนอก: ชนิด/ขนาด/ความยาวไฟล์เสียง, ชื่อไฟล์ใน pack ที่ import (กัน path traversal), ชื่อ system sound
- `scripts/build-app.sh`: build release, ประกอบ `.app`, สร้าง icon, ad-hoc codesign, `--install`
- unit tests 73 ตัวใน `SoundControlCore` (line coverage ~99%)

### Fixed (จาก code review ก่อน release)
- import pack ที่มี sound id ซ้ำทำแอป crash → `validate()` ปฏิเสธ id ซ้ำ, จำกัด 200 เสียงและ `pack.json` ≤ 1 MB, แจ้งเสียงที่ import ไม่สำเร็จ
- ค่าเดียวที่ไม่รู้จักใน `config.json` (trigger/เสียง/pack จากเวอร์ชันอื่น) ทำให้ reset ทั้งไฟล์ → ตอนนี้ข้ามเฉพาะรายการนั้น
- import เสียง: ปฏิเสธ symlink และไฟล์ที่อ่านขนาดไม่ได้, เช็คขนาดก่อนเปิดไฟล์เป็น audio
- เสียง "Audio output changed" ถูกตัดตอนสลับอุปกรณ์ → engine ต่อสายใหม่แล้วเล่นต่อ, หน่วงเสียง 0.4 วินาที
- CoreAudio / Bluetooth callback ที่ค้างคิวทำงานหลัง monitor หยุด; Bluetooth ไม่ส่งเสียงซ้ำ และไม่ดังให้อุปกรณ์ที่ต่ออยู่แล้วตอนเริ่ม
- event tap / run-loop source ถูก invalidate ตอนหยุด, folder watcher ไม่รั่ว file descriptor
- ตีบอกเวลาหลังเครื่องหลับสั้นๆ ข้ามชั่วโมง → gap เกิน 60 วินาทีไม่ตี
- battery critical ต้องต่ำกว่า low เสมอ (low 2–99%, critical 1–98%)
- เสียงไฟล์ไหนโหลดไม่ได้ จะลองเสียงถัดไปใน rotation แทนการเงียบ
- Reset all settings เก็บ My Sounds ไว้ ไม่ทิ้งไฟล์กำพร้า
