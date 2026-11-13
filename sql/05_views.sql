/* =====================================================================
   SmartMart  |  05_views.sql
   ใช้กับรายงานข้อ 2.3 : Views สำหรับป้องกันการเข้าถึงข้อมูลของแต่ละ Role
   หลักคิด : ผู้ใช้/แอปได้สิทธิ์ SELECT ที่ "View" แทนตารางจริง
     1) ซ่อนคอลัมน์ที่ไม่จำเป็น (column protection)  เช่น ไม่ให้เห็น card_token, ราคา
     2) ซ่อนแถวที่ไม่ใช่ของตัวเอง (row protection)     เช่น เห็นเฉพาะสาขา/คลัง/ลูกค้าของตัวเอง
     3) Materialized (Indexed) View เก็บผลสรุปไว้จริง ทำให้ query สรุปยอดเร็วขึ้น
   รันหลัง 03  (กด F5 ทั้งไฟล์ได้)
   ===================================================================== */
USE SmartMart;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* V1 : แคตตาล็อกสินค้า + ส่วนลดที่ใช้ได้วันนี้ (ไม่มีข้อมูลสต็อก/ต้นทุน) */
DROP VIEW IF EXISTS dbo.v_product_catalog;
GO
CREATE VIEW dbo.v_product_catalog
AS
SELECT p.UPC, p.product_name, p.product_unit, p.shipping_weight, p.web_orderable,
       ISNULL(pr.discount_percent, 0) AS current_discount_percent,
       pr.promotion_end_date          AS promotion_ends
FROM dbo.product p
OUTER APPLY (SELECT TOP (1) sp.discount_percent, sp.promotion_end_date
             FROM dbo.sales_promotion sp
             WHERE sp.UPC = p.UPC
               AND CAST(GETDATE() AS DATE) BETWEEN sp.promotion_start_date AND sp.promotion_end_date
             ORDER BY sp.promotion_start_date DESC) pr;
GO

/* V2 : สต็อกทุกที่ + ราคาขายหลังหักโปรโมชัน  (ใช้กับ T1 ค้นหาสินค้า) */
DROP VIEW IF EXISTS dbo.v_stock_by_location;
GO
CREATE VIEW dbo.v_stock_by_location
AS
SELECT ps.SKU, ps.UPC, p.product_name, ps.size, ps.color,
       CASE WHEN ps.in_store = 1 THEN 'STORE' ELSE 'WAREHOUSE' END AS location_type,
       ps.store_numb, d.dept_name, ps.warehouse_id,
       COALESCE(s.city, w.city)             AS city,
       COALESCE(s.state_code, w.state_code) AS state_code,
       ps.number_on_hand, ps.retail_price,
       ISNULL(pr.discount_percent, 0) AS discount_percent,
       CAST(ROUND(ps.retail_price * (100 - ISNULL(pr.discount_percent, 0)) / 100, 2) AS DECIMAL(10,2)) AS sale_price
FROM dbo.product_stocked ps
JOIN dbo.product p          ON p.UPC = ps.UPC
LEFT JOIN dbo.department d  ON d.store_numb = ps.store_numb AND d.dept_numb = ps.dept_numb
LEFT JOIN dbo.store s       ON s.store_numb = ps.store_numb
LEFT JOIN dbo.warehouse w   ON w.warehouse_id = ps.warehouse_id
OUTER APPLY (SELECT TOP (1) sp.discount_percent
             FROM dbo.sales_promotion sp
             WHERE sp.UPC = ps.UPC
               AND CAST(GETDATE() AS DATE) BETWEEN sp.promotion_start_date AND sp.promotion_end_date
             ORDER BY sp.promotion_start_date DESC) pr;
GO

/* V3 : สต็อกเฉพาะสาขาของตัวเอง (พนักงานแคชเชียร์ / แอป POS)
   - พนักงาน (user ของคน)  : ดูสาขาจากตาราง staff_assignment ตามชื่อ user ที่ล็อกอิน -> แก้เองไม่ได้
   - แอป POS (ไม่มีใน staff_assignment) : แอปบอกสาขาผ่าน SESSION_CONTEXT('store_numb')
   - ไม่รู้ว่าเป็นสาขาไหน -> ได้ 0 แถว */
DROP VIEW IF EXISTS dbo.v_store_stock;
GO
CREATE VIEW dbo.v_store_stock
AS
SELECT ps.SKU, ps.UPC, p.product_name, ps.size, ps.color,
       ps.store_numb, ps.dept_numb, d.dept_name, ps.number_on_hand, ps.retail_price
FROM dbo.product_stocked ps
JOIN dbo.product p     ON p.UPC = ps.UPC
JOIN dbo.department d  ON d.store_numb = ps.store_numb AND d.dept_numb = ps.dept_numb
WHERE ps.in_store = 1
  AND ps.store_numb = COALESCE(
        (SELECT sa.store_numb FROM dbo.staff_assignment sa WHERE sa.db_user_name = USER_NAME()),
        CAST(SESSION_CONTEXT(N'store_numb') AS INT));
GO

/* V4 : สต็อกเฉพาะคลังของตัวเอง (พนักงานคลัง / แอปคลัง) ไม่แสดงราคาขาย */
DROP VIEW IF EXISTS dbo.v_warehouse_stock;
GO
CREATE VIEW dbo.v_warehouse_stock
AS
SELECT ps.SKU, ps.UPC, p.product_name, ps.size, ps.color, ps.warehouse_id, ps.number_on_hand
FROM dbo.product_stocked ps
JOIN dbo.product p ON p.UPC = ps.UPC
WHERE ps.in_store = 0
  AND ps.warehouse_id = COALESCE(
        (SELECT sa.warehouse_id FROM dbo.staff_assignment sa WHERE sa.db_user_name = USER_NAME()),
        CAST(SESSION_CONTEXT(N'warehouse_id') AS INT));
GO

/* V5 : รายการออนไลน์ที่ยังไม่ส่ง (backorder) ของคลังตัวเอง พร้อมที่อยู่จัดส่ง
   ไม่แสดงข้อมูลบัตร ราคา เบอร์โทร รหัสผ่าน */
DROP VIEW IF EXISTS dbo.v_warehouse_pending_items;
GO
CREATE VIEW dbo.v_warehouse_pending_items
AS
SELECT wsi.web_sale_numb, ws.sale_date, wsi.SKU, p.product_name, wsi.quantity, ps.warehouse_id,
       a.first_name + ' ' + a.last_name AS ship_to_name,
       a.street, a.city, a.state_code, a.zip
FROM dbo.web_sale_item wsi
JOIN dbo.web_sale ws                    ON ws.web_sale_numb = wsi.web_sale_numb
JOIN dbo.product_stocked ps             ON ps.SKU = wsi.SKU
JOIN dbo.product p                      ON p.UPC = ps.UPC
JOIN dbo.web_sale_shipping_address a    ON a.shipping_address_numb = wsi.shipping_address_numb
WHERE wsi.shipment_seq IS NULL
  AND ps.warehouse_id = COALESCE(
        (SELECT sa.warehouse_id FROM dbo.staff_assignment sa WHERE sa.db_user_name = USER_NAME()),
        CAST(SESSION_CONTEXT(N'warehouse_id') AS INT));
GO

/* V6 : ประวัติคำสั่งซื้อของ "ลูกค้าที่ล็อกอินอยู่" เท่านั้น (แอปเว็บใช้ login เดียวกันทุกลูกค้า
   จึงให้แอปบอกเลขลูกค้าผ่าน SESSION_CONTEXT('web_customer_numb') หลังลูกค้าล็อกอินสำเร็จ)
   แสดงบัตรแค่ 4 ตัวท้าย ไม่แสดง card_token */
DROP VIEW IF EXISTS dbo.v_customer_orders;
GO
CREATE VIEW dbo.v_customer_orders
AS
SELECT ws.web_sale_numb, ws.sale_date, wsi.SKU, p.product_name, wsi.quantity, wsi.unit_price,
       wsi.shipment_seq, sh.ship_date,
       CASE WHEN wsi.shipment_seq IS NULL THEN 'PENDING (BACKORDER)' ELSE 'SHIPPED' END AS item_status,
       ws.merchandise_total, ws.tax_total, ws.shipping_total, ws.total,
       c.card_last4
FROM dbo.web_sale ws
JOIN dbo.web_sale_item wsi           ON wsi.web_sale_numb = ws.web_sale_numb
JOIN dbo.product_stocked ps          ON ps.SKU = wsi.SKU
JOIN dbo.product p                   ON p.UPC = ps.UPC
JOIN dbo.web_customer_credit_card c  ON c.web_customer_numb = ws.web_customer_numb AND c.card_numb = ws.card_numb
LEFT JOIN dbo.web_sale_shipment sh   ON sh.web_sale_numb = wsi.web_sale_numb AND sh.shipment_seq = wsi.shipment_seq
WHERE ws.web_customer_numb = CAST(SESSION_CONTEXT(N'web_customer_numb') AS INT);
GO

/* V7 : MATERIALIZED VIEW (ใน SQL Server เรียกว่า Indexed View)
   ยอดสต็อกรวมต่อสินค้า แยก "ในสาขา" กับ "ในคลัง"
   - WITH SCHEMABINDING + UNIQUE CLUSTERED INDEX = SQL Server เก็บผลลัพธ์ลงดิสก์จริง
     และอัปเดตให้อัตโนมัติทุกครั้งที่ product_stocked เปลี่ยน
   - ต้องมี COUNT_BIG(*) เมื่อมี GROUP BY และ SUM ต้องเป็นคอลัมน์ NOT NULL */
DROP VIEW IF EXISTS dbo.v_stock_summary;
GO
CREATE VIEW dbo.v_stock_summary
WITH SCHEMABINDING
AS
SELECT ps.UPC,
       ps.in_store,
       SUM(ps.number_on_hand) AS total_on_hand,
       COUNT_BIG(*)           AS sku_count
FROM dbo.product_stocked ps
GROUP BY ps.UPC, ps.in_store;
GO
CREATE UNIQUE CLUSTERED INDEX UCX_v_stock_summary ON dbo.v_stock_summary (UPC, in_store);
GO

/* ---------------------------------------------------------------------
   ทดลองใช้ View (แคปผลใส่รายงานข้อ 2.3)
   --------------------------------------------------------------------- */
-- V1, V2 : ใครที่มีสิทธิ์ก็เห็นเหมือนกัน
SELECT TOP (10) * FROM dbo.v_product_catalog ORDER BY current_discount_percent DESC, UPC;
SELECT * FROM dbo.v_stock_by_location WHERE product_name LIKE 'Running%';

-- V3 : admin ไม่ได้ผูกกับสาขาใด -> 0 แถว จนกว่าจะบอกสาขาผ่าน SESSION_CONTEXT (แบบที่แอป POS ทำ)
SELECT COUNT(*) AS rows_without_context FROM dbo.v_store_stock;
EXEC sp_set_session_context @key = N'store_numb', @value = 1;
SELECT * FROM dbo.v_store_stock WHERE SKU NOT LIKE 'X%' ORDER BY SKU;   -- ไม่เอาข้อมูล bulk (SKU ขึ้นต้น X)
EXEC sp_set_session_context @key = N'store_numb', @value = NULL;

-- V5 : รายการรอส่งของคลัง 1
EXEC sp_set_session_context @key = N'warehouse_id', @value = 1;
SELECT * FROM dbo.v_warehouse_pending_items;
EXEC sp_set_session_context @key = N'warehouse_id', @value = NULL;

-- V6 : ลูกค้า #1 (Alice) เห็นเฉพาะคำสั่งซื้อของตัวเอง
EXEC sp_set_session_context @key = N'web_customer_numb', @value = 1;
SELECT * FROM dbo.v_customer_orders;
EXEC sp_set_session_context @key = N'web_customer_numb', @value = NULL;
GO

/* ---------------------------------------------------------------------
   เทียบ Materialized View กับการคำนวณสดจากตาราง (แคปแท็บ Messages)
   ดูค่า "logical reads" : ยิ่งน้อยยิ่งดี
   WITH (NOEXPAND) = บังคับให้อ่านจากผลที่เก็บไว้ใน indexed view
   (จำเป็นใน Express/Standard edition, Developer/Enterprise เลือกใช้เองได้)
   --------------------------------------------------------------------- */
SET STATISTICS IO ON;

-- (ก) คำนวณสดจากตาราง product_stocked ทุกครั้ง
SELECT UPC, in_store, SUM(number_on_hand) AS total_on_hand
FROM dbo.product_stocked
GROUP BY UPC, in_store;

-- (ข) อ่านจาก materialized view ที่คำนวณไว้แล้ว
SELECT UPC, in_store, total_on_hand
FROM dbo.v_stock_summary WITH (NOEXPAND);

SET STATISTICS IO OFF;
GO
