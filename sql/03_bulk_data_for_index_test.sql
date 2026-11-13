/* =====================================================================
   SmartMart  |  03_bulk_data_for_index_test.sql
   ใช้กับรายงานข้อ 2.4 : เพิ่มข้อมูลจำนวนมากเพื่อให้เห็นผลของ Index ชัดเจน
   - สินค้า 5,000 รายการ (UPC ขึ้นต้นด้วย 5)
   - สต็อก 60,000 แถว (SKU ขึ้นต้นด้วย X) กระจายในทุกสาขา/คลัง
   ถ้ามีข้อมูลแค่ไม่กี่แถว SQL Server จะ Scan ทั้งตารางเสมอเพราะเร็วกว่า
   จึงมองไม่เห็นความต่างระหว่าง "มี index" กับ "ไม่มี index"
   รันหลัง 02  (ใช้เวลาประมาณ 5-20 วินาที)
   ===================================================================== */
USE SmartMart;
GO
SET NOCOUNT ON;

IF EXISTS (SELECT 1 FROM dbo.product WHERE UPC LIKE '5%')
BEGIN
    PRINT 'Bulk data already loaded - skipped.';
    RETURN;
END;

-- 1) สินค้า 5,000 รายการ
WITH n AS (
    SELECT TOP (5000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS i
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
)
INSERT INTO dbo.product (UPC, product_name, product_unit, shipping_weight, web_orderable)
SELECT CONCAT('5', RIGHT(CONCAT('00000000000', i), 11)),
       CONCAT(CHOOSE(i % 8 + 1, 'Basic', 'Premium', 'Eco', 'Smart', 'Classic', 'Ultra', 'Mini', 'Pro'), ' ',
              CHOOSE(i % 10 + 1, 'Shirt', 'Lamp', 'Kettle', 'Speaker', 'Pillow',
                                 'Notebook', 'Charger', 'Blender', 'Jacket', 'Mug'),
              ' #', i),
       'each',
       CAST((i % 50) / 10.0 + 0.1 AS DECIMAL(8,2)),
       CASE WHEN i % 10 = 0 THEN 0 ELSE 1 END
FROM n;

-- 2) สต็อก 60,000 แถว : i หาร 3 ลงตัว = อยู่คลัง, ที่เหลือ = อยู่สาขา (แผนก 2 หรือ 3 ซึ่งมีทุกสาขา)
WITH n AS (
    SELECT TOP (60000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS i
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
)
INSERT INTO dbo.product_stocked (SKU, UPC, in_store, store_numb, dept_numb, warehouse_id, size, color, number_on_hand, retail_price)
SELECT CONCAT('X', RIGHT(CONCAT('000000', i), 6)),
       CONCAT('5', RIGHT(CONCAT('00000000000', (i - 1) % 5000 + 1), 11)),
       CASE WHEN i % 3 = 0 THEN 0 ELSE 1 END,
       CASE WHEN i % 3 = 0 THEN NULL ELSE i % 4 + 1 END,
       CASE WHEN i % 3 = 0 THEN NULL WHEN i % 2 = 0 THEN 2 ELSE 3 END,
       CASE WHEN i % 3 = 0 THEN i % 4 + 1 ELSE NULL END,
       CHOOSE(i % 4 + 1, 'S', 'M', 'L', 'XL'),
       CHOOSE(i % 5 + 1, 'Red', 'Blue', 'Green', 'Black', 'White'),
       i % 97,
       CAST(5 + (i % 200) * 0.5 AS DECIMAL(10,2))
FROM n;

UPDATE STATISTICS dbo.product WITH FULLSCAN;
UPDATE STATISTICS dbo.product_stocked WITH FULLSCAN;
GO

SELECT (SELECT COUNT(*) FROM dbo.product)         AS product_rows,
       (SELECT COUNT(*) FROM dbo.product_stocked) AS product_stocked_rows;
GO
