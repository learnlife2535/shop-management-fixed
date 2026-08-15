# ร้านค้าของฉัน — ระบบจัดการร้านค้า

เว็บไซต์ static สำหรับระบบจัดการร้านค้าครบวงจร มีหน้าเข้าสู่ระบบและโมดูล POS, สินค้า, สต๊อก, แคตตาล็อก, ประวัติการขาย, รายงาน, พนักงาน และการตั้งค่า รองรับภาษาไทย อังกฤษ พม่า และลาว

## ความสามารถหลัก

- จุดขาย (POS) พร้อมการสแกนบาร์โค้ดและชำระเงินผ่าน QR พร้อมเพย์
- จัดการสินค้า รูปภาพ รายละเอียด ราคา สต๊อก และบาร์โค้ด
- รับสินค้าเข้าสต๊อกด้วยบาร์โค้ด และตัดสต๊อกอัตโนมัติเมื่อขาย
- สร้างแคตตาล็อกสินค้าและส่งออกข้อมูล CSV/JSON สำหรับช่องทางออนไลน์
- รองรับบทบาทพนักงานหน้าร้าน พนักงานออนไลน์ และเจ้าของร้าน
- รองรับ 4 ภาษา: ไทย อังกฤษ พม่า และลาว

## โครงสร้างไฟล์

| รายการ | หน้าที่ |
|---|---|
| `index.html` | จุดเริ่มต้นของเว็บไซต์และ metadata สำหรับ SEO/social sharing |
| `assets/` | JavaScript และ CSS ที่คอมไพล์แล้ว |
| `favicon.svg` | ไอคอนเว็บไซต์ |
| `og-cover.svg` | ภาพประกอบเมื่อแชร์ลิงก์ |
| `_redirects` | กฎ redirect สำหรับ static hosting ที่รองรับ Netlify-style redirects |
| `llms.txt` | สรุปความสามารถและเทคโนโลยีของระบบ |
| `audit-findings.md` | บันทึกผลตรวจสอบและการแก้ไขโครงสร้างไฟล์ |

เว็บไซต์นี้เป็น **ไฟล์ static build** จึงไม่ต้องติดตั้ง dependency เพิ่มเติมเพื่อเปิดหน้าเว็บ หากต้องการแก้ตรรกะเชิงลึก ควรใช้ source project ของ React/TypeScript เนื่องจากชุดนี้เป็นไฟล์ build แล้ว

## เปิดใช้งานในเครื่อง

```bash
python3 -m http.server 4173
```

จากนั้นเปิด `http://localhost:4173` ในเบราว์เซอร์

## เผยแพร่ด้วย GitHub Pages

หลังเปิดใช้งาน GitHub Pages ให้เลือก branch ที่ต้องการเผยแพร่และโฟลเดอร์ root (`/`). เนื่องจาก `index.html` และโฟลเดอร์ `assets/` อยู่ใน root ของ repository เว็บไซต์จะโหลดได้โดยตรง

## การเชื่อมต่อฐานข้อมูลและ Environment Variables

เว็บไซต์เวอร์ชันที่เผยแพร่เชื่อมต่อ Supabase project `klvbswzhydvqtljqrjel` ผ่าน `public` schema โดยใช้ publishable/anon key สำหรับฝั่ง browserเท่านั้น ไม่ใช้ service-role key บน frontend และไม่มีไฟล์ `.env` ใน repository เนื่องจากชุดนี้เป็น static build ที่คอมไพล์แล้ว

ตารางหลักที่รองรับการใช้งาน ได้แก่ `products_v2`, `employees_v2`, `albums_v2`, `album_products_v2`, `sales`, `sale_items_v2`, `stock_entries_v2` และ `shop_settings_v2` การตั้งค่า RLS และสิทธิ์ของตารางถูกสร้างผ่าน migration ของ Supabase แล้ว และผ่าน smoke test การสร้าง อ่าน แก้ไข และลบข้อมูลจำลองเรียบร้อย

หากพัฒนา source project ต่อด้วย Vite ให้เก็บค่าการเชื่อมต่อไว้ในไฟล์ `.env.local` ที่ไม่ commit ขึ้น Git เช่น `VITE_SUPABASE_URL` และ `VITE_SUPABASE_PUBLISHABLE_KEY` จากนั้นให้ inject ค่าในขั้นตอน build/deploy แทนการฝังค่าแบบ static bundle การทดสอบ production ควรใช้บัญชีพนักงานที่สร้างใน `employees_v2` และไม่ควรนำ service-role key ไปไว้ใน browser
