/* =====================================================================
   SmartMart  |  06_indexes.sql
   ใช้กับรายงานข้อ 2.4 : Non-Clustered Index เพื่อเร่ง Query ในข้อ 1.4
   วิธีใช้ (สำคัญ) : รันทีละส่วน A -> B -> C  โดยไฮไลต์ส่วนนั้นแล้วกด F5
     ก่อนรันส่วน A และ C ให้กด Ctrl+M (Include Actual Execution Plan) ให้ปุ่มติด
     แล้วแคป 2 อย่าง : แท็บ Messages (logical reads) และแท็บ Execution plan
   ต้องรัน 03_bulk_data_for_index_test.sql มาก่อน ไม่งั้นจะไม่เห็นความต่าง
   ===================================================================== */
USE SmartMart;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* =====================================================================
   ส่วน A : วัดผล "ก่อน" มี index  (ลบ index เดิมทิ้งก่อน รันซ้ำได้)
   ===================================================================== */
DROP INDEX IF EXISTS IX_product_product_name        ON dbo.product;
DROP INDEX IF EXISTS IX_product_stocked_UPC         ON dbo.product_stocked;
DROP INDEX IF EXISTS IX_product_stocked_store       ON dbo.product_stocked;
DROP INDEX IF EXISTS IX_product_stocked_warehouse   ON dbo.product_stocked;
DROP INDEX IF EXISTS IX_web_sale_item_unshipped     ON dbo.web_sale_item;
DROP INDEX IF EXISTS IX_web_sale_customer_date      ON dbo.web_sale;
GO
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

-- Q1 (T1) ค้นหาสินค้าด้วยชื่อขึ้นต้น แล้วดูสต็อกทุกที่
SELECT p.UPC, p.product_name, ps.SKU, ps.in_store, ps.store_numb, ps.warehouse_id,
       ps.number_on_hand, ps.retail_price
FROM dbo.product p
JOIN dbo.product_stocked ps ON ps.UPC = p.UPC
WHERE p.product_name LIKE 'Wireless%';

-- Q2 (T6, T2) หาสต็อกของสินค้า 1 UPC ในทุกคลัง
SELECT SKU, warehouse_id, number_on_hand, retail_price
FROM dbo.product_stocked
WHERE UPC = '500000001234' AND in_store = 0;

-- Q3 (T3 / v_store_stock) สต็อกแผนก Electronics ของสาขา 2
SELECT SKU, UPC, number_on_hand, retail_price
FROM dbo.product_stocked
WHERE in_store = 1 AND store_numb = 2 AND dept_numb = 3;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO

/* =====================================================================
   ส่วน B : สร้าง Non-Clustered Index
   ===================================================================== */

-- IX1 : T1 ค้นหาด้วยชื่อสินค้า (LIKE 'คำ%')  -> Index Seek แทน Scan ทั้งตาราง product
CREATE NONCLUSTERED INDEX IX_product_product_name
    ON dbo.product (product_name);

-- IX2 : T1 (JOIN ด้วย UPC), T6 / T2 (หาสต็อกของสินค้า)  -> covering index มีคอลัมน์ที่ query ใช้ครบ
CREATE NONCLUSTERED INDEX IX_product_stocked_UPC
    ON dbo.product_stocked (UPC)
    INCLUDE (in_store, store_numb, dept_numb, warehouse_id, size, color, number_on_hand, retail_price);

-- IX3 : T3/T4 และ v_store_stock (สต็อกของสาขา/แผนก)  -> Filtered index เก็บเฉพาะแถวในสาขา
CREATE NONCLUSTERED INDEX IX_product_stocked_store
    ON dbo.product_stocked (store_numb, dept_numb)
    INCLUDE (UPC, size, color, number_on_hand, retail_price)
    WHERE in_store = 1;

-- IX4 : v_warehouse_stock (สต็อกของคลัง)  -> Filtered index เก็บเฉพาะแถวในคลัง
CREATE NONCLUSTERED INDEX IX_product_stocked_warehouse
    ON dbo.product_stocked (warehouse_id)
    INCLUDE (UPC, size, color, number_on_hand)
    WHERE in_store = 0;

-- IX5 : T7 และ v_warehouse_pending_items (รายการที่ยังไม่ส่ง)  -> เก็บเฉพาะแถว shipment_seq IS NULL
CREATE NONCLUSTERED INDEX IX_web_sale_item_unshipped
    ON dbo.web_sale_item (web_sale_numb, SKU)
    INCLUDE (quantity, shipping_address_numb)
    WHERE shipment_seq IS NULL;

-- IX6 : v_customer_orders (ประวัติคำสั่งซื้อของลูกค้า เรียงวันที่ล่าสุดก่อน)
CREATE NONCLUSTERED INDEX IX_web_sale_customer_date
    ON dbo.web_sale (web_customer_numb, sale_date DESC);
GO

-- index ที่มีอยู่แล้วโดยอัตโนมัติ (ไม่ต้องสร้างเพิ่ม):
--   PK ทุกตัว = clustered index เช่น PK_sales_promotion (UPC, promotion_start_date) ใช้กับ T3/T6/T8
--   UQ_web_customer_user_id = unique non-clustered index ใช้กับ T5 (ตรวจ user_id ซ้ำ)
SELECT OBJECT_NAME(i.object_id) AS table_name, i.name AS index_name, i.type_desc,
       i.is_unique, i.has_filter, i.filter_definition
FROM sys.indexes i
WHERE OBJECTPROPERTY(i.object_id, 'IsUserTable') = 1 AND i.name IS NOT NULL
ORDER BY table_name, i.type_desc, index_name;
GO

/* =====================================================================
   ส่วน C : วัดผล "หลัง" มี index  (Query เดิมทุกตัว)  -> เทียบกับส่วน A
   ===================================================================== */
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT p.UPC, p.product_name, ps.SKU, ps.in_store, ps.store_numb, ps.warehouse_id,
       ps.number_on_hand, ps.retail_price
FROM dbo.product p
JOIN dbo.product_stocked ps ON ps.UPC = p.UPC
WHERE p.product_name LIKE 'Wireless%';

SELECT SKU, warehouse_id, number_on_hand, retail_price
FROM dbo.product_stocked
WHERE UPC = '500000001234' AND in_store = 0;

SELECT SKU, UPC, number_on_hand, retail_price
FROM dbo.product_stocked
WHERE in_store = 1 AND store_numb = 2 AND dept_numb = 3;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO
