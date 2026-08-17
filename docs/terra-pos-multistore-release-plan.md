# Terra POS Point — Multi-store operations architecture

## Operating model

ระบบปัจจุบันมีแกน multi-tenant ที่ใช้งานได้แล้วผ่าน `shops`, `shop_members`, `shop_settings_v2`, `products_v2`, `sales`, `sale_items_v2` และ `stock_entries_v2` โดยทุกตารางธุรกิจใหม่ต้องมี `shop_id` และใช้ RLS ที่อ้าง `private.is_shop_member(shop_id, roles)` เพื่อป้องกันข้อมูลข้ามร้าน

| บทบาท | สิทธิ์ในงานหน้าร้าน | สิทธิ์ HR / บัญชี / เอกสาร |
|---|---|---|
| owner | ทุกสิทธิ์ | กำหนดนโยบาย อนุมัติ payroll และดูเอกสารภาษี |
| manager | จัดการสินค้า การขาย สต็อก และรายงาน | จัดการทีม เอกสารการค้า ข้อมูล HR และ payroll draft |
| staff | เพิ่ม/แก้สินค้าตามเดิม ขายและบันทึกสต็อก | ลงเวลา ดูข้อมูลและสลิปของตนเอง |
| viewer | ดูข้อมูลตาม RLS ที่กำหนด | ดูรายงานที่ได้รับอนุญาต בלבד |

## Release sequence

| Release | ขอบเขต | จุดตรวจความปลอดภัย |
|---|---|---|
| R1 — Storefront foundation | แก้อัปโหลดภาพ/QR, ภาษา 4 ภาษา, คู่มือพร้อมวิดีโอ, รายงานยอดขายและสินค้าขายดี | ป้องกัน storage path ข้ามร้านและไม่มี URL รูปปลอม |
| R2 — Commercial documents | รับสินค้า เบิกสินค้า ใบเสนอราคา ใบแจ้งหนี้ ใบเสร็จ และใบเสร็จ No VAT | เลขเอกสารแยกตามร้านและมี immutable issue snapshot |
| R3 — Workforce | โปรไฟล์พนักงานหลายร้าน, ลงเวลาแบบปุ่ม, สวัสดิการ, เอกสารหมดอายุและแจ้งเตือน | พนักงานเห็นเฉพาะข้อมูลของตน, manager เฉพาะร้านของตน |
| R4 — Payroll & accounting | payroll 2 รอบต่อเดือน, รายได้/รายการหัก, สลิป, รับเข้า-ออก, รายรับ ค่าใช้จ่าย และบัญชีแยกประเภท | เก็บ period lock, audit fields และ approval state |
| R5 — Tax support & print | draft ภงด.1/ภงด.1ก, ประกันสังคม ม.33, เอกสารแนบ, A4/thermal print และ Bluetooth capability check | เอกสารเป็น draft until owner approval และต้องตรวจข้อกำกับก่อนยื่นจริง |

## New data boundaries

โมดูล HR จะใช้ employee profile กลางหนึ่งรายการต่อบุคคล และ employee assignment แยกตามร้าน เพื่อให้พนักงานคนเดียวทำงานหลายร้านได้โดยไม่ต้องคัดลอกประวัติส่วนตัว ส่วนข้อมูล attendance, payroll, business document, accounting journal และ employee document ต้องผูกทั้ง `shop_id` และ entity หลักของตนเองเสมอ

การลงเวลาของ release แรกจะเป็น check-in/check-out ผ่านปุ่มในระบบ และบันทึก timestamp ที่มาจาก server เท่านั้น ไม่บันทึก GPS หรือรูปถ่ายตามขอบเขตที่ยืนยันแล้ว

## Existing security observation

พบ legacy policy แบบ public-all บน `products` และ `stock_logs` ขณะที่โมดูล production ใช้ชุด `*_v2` ที่มี RLS อยู่แล้ว Release foundation จะไม่เพิ่มข้อมูลสำคัญลง legacy tables และต้องย้ายหรือจำกัด policy เหล่านี้ก่อนนำข้อมูล HR บัญชี หรือเอกสารภาษีเข้าสู่ระบบ

## Compliance boundary

โมดูลภาษีและเงินเดือนจะจัดเก็บข้อมูล คำนวณ และสร้างเอกสารฉบับร่างตามค่าที่ร้านกำหนด แต่การเปิดใช้สำหรับการยื่นจริงต้องผ่านการตรวจอัตรา กฎเกณฑ์ และแบบฟอร์มล่าสุดกับผู้ทำบัญชีหรือผู้เชี่ยวชาญภาษีของร้านก่อนเสมอ
