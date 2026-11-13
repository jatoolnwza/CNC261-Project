/* =====================================================================
   SmartMart  |  02_sample_data.sql
   ข้อมูลตัวอย่าง (รันต่อจาก 01 ทันที บนฐานข้อมูลที่เพิ่งสร้างใหม่)
   แถวที่มีคำว่า [TEST] ในคอมเมนต์ = ข้อมูลที่โปรแกรม Java ใช้ทดสอบ อย่าลบ/แก้
   ===================================================================== */
USE SmartMart;
GO
SET NOCOUNT ON;

-- รัฐ + อัตราภาษีขาย
INSERT INTO dbo.state (state_code, state_name, sales_tax_rate) VALUES
 ('CA', 'California', 0.0725),
 ('NY', 'New York',   0.0400),
 ('TX', 'Texas',      0.0625),
 ('OR', 'Oregon',     0.0000),
 ('WA', 'Washington', 0.0650);

-- สาขา 4 แห่ง
INSERT INTO dbo.store (store_numb, street, city, state_code, zip, main_phone) VALUES
 (1, '1200 Sunset Blvd',  'Los Angeles',   'CA', '90026', '213-555-0101'),
 (2, '88 Market St',      'San Francisco', 'CA', '94105', '415-555-0102'),
 (3, '350 5th Ave',       'New York',      'NY', '10118', '212-555-0103'),
 (4, '600 Congress Ave',  'Austin',        'TX', '78701', '512-555-0104');

-- คลังภูมิภาค 4 แห่ง
INSERT INTO dbo.warehouse (warehouse_id, street, city, state_code, zip, phone) VALUES
 (1, '500 Industrial Way',  'Fresno',   'CA', '93725', '559-555-0201'),
 (2, '75 Commerce Dr',      'Albany',   'NY', '12205', '518-555-0202'),
 (3, '9000 Logistics Pkwy', 'Dallas',   'TX', '75241', '214-555-0203'),
 (4, '2100 NW Front Ave',   'Portland', 'OR', '97209', '503-555-0204');

-- แผนกในแต่ละสาขา (บางสาขาไม่มีแผนก Grocery)
INSERT INTO dbo.department (store_numb, dept_numb, dept_name) VALUES
 (1, 1, 'Grocery'), (1, 2, 'Clothing'), (1, 3, 'Electronics'), (1, 4, 'Home'),
 (2, 2, 'Clothing'), (2, 3, 'Electronics'), (2, 4, 'Home'),
 (3, 2, 'Clothing'), (3, 3, 'Electronics'), (3, 4, 'Home'),
 (4, 1, 'Grocery'), (4, 2, 'Clothing'), (4, 3, 'Electronics');

INSERT INTO dbo.promotion_type (promotion_type_code, promotion_type_name) VALUES
 (1, 'Percent Off'), (2, 'Clearance'), (3, 'Holiday Sale'), (4, 'Member Price');

INSERT INTO dbo.payment_type (payment_type_code, payment_type_text) VALUES
 (1, 'CASH'), (2, 'CREDIT');

-- สินค้า
INSERT INTO dbo.product (UPC, product_name, product_unit, shipping_weight, web_orderable) VALUES
 ('012345000001', 'Cotton T-Shirt',            'each',   0.50, 1),
 ('012345000002', 'Slim Fit Jeans',            'each',   1.50, 1),
 ('012345000003', 'Wireless Mouse',            'each',   0.40, 1),
 ('012345000004', 'USB-C Cable 1m',            'each',   0.20, 1),
 ('012345000005', 'Organic Milk 1 gal',        'gallon', 8.60, 0),   -- ขายหน้าร้านเท่านั้น
 ('012345000006', 'Bath Towel',                'each',   1.20, 1),
 ('012345000007', 'Arabica Coffee Beans 1 lb', 'bag',    1.10, 1),
 ('012345000008', 'LED Desk Lamp',             'each',   3.00, 1),
 ('099000000001', 'Zip Hoodie',                'each',   1.80, 1),   -- [TEST] T2
 ('099000000002', 'Running Sneakers',          'pair',   2.50, 1),   -- [TEST] T1, T3, T4
 ('099000000003', 'Travel Backpack',           'each',   2.20, 1),   -- [TEST] T6, T7
 ('099000000004', 'Wireless Headphones',       'each',   0.90, 1),   -- [TEST] T6, T7
 ('099000000005', 'Steel Water Bottle',        'each',   0.70, 1);   -- [TEST] T8

-- สินค้าที่ต้องเสียภาษีในแต่ละรัฐ (Grocery ไม่เสียภาษี, Oregon ไม่มีภาษีขาย)
INSERT INTO dbo.product_taxed (UPC, state_code) VALUES
 ('012345000001','CA'), ('012345000002','CA'), ('012345000003','CA'), ('012345000004','CA'),
 ('012345000006','CA'), ('012345000008','CA'),
 ('099000000001','CA'), ('099000000002','CA'), ('099000000003','CA'), ('099000000004','CA'), ('099000000005','CA'),
 ('012345000003','NY'), ('012345000004','NY'), ('012345000006','NY'), ('012345000008','NY'),
 ('099000000003','NY'), ('099000000004','NY'), ('099000000005','NY'),
 ('012345000001','TX'), ('012345000002','TX'), ('012345000003','TX'), ('012345000004','TX'),
 ('012345000006','TX'), ('012345000008','TX'),
 ('099000000001','TX'), ('099000000002','TX'), ('099000000003','TX'), ('099000000004','TX'), ('099000000005','TX'),
 ('012345000001','WA'), ('012345000002','WA'), ('012345000003','WA'), ('012345000004','WA'),
 ('012345000006','WA'), ('012345000008','WA');

-- โปรโมชัน
INSERT INTO dbo.sales_promotion (UPC, promotion_start_date, promotion_end_date, promotion_type_code, promotion_details, discount_percent) VALUES
 ('012345000001', '2026-11-01', '2026-12-31', 3, 'Holiday sale: T-shirts 20% off',  20.00),
 ('012345000007', '2026-10-01', '2026-11-30', 4, 'Member price coffee',             15.00),
 ('012345000008', '2026-06-01', '2026-06-30', 2, 'June clearance (already ended)',  30.00),
 ('099000000002', '2026-01-01', '2030-12-31', 1, 'Sneakers 10% off',                10.00),  -- [TEST]
 ('099000000003', '2026-01-01', '2030-12-31', 1, 'Backpack 5% off',                  5.00),  -- [TEST]
 ('099000000005', '2027-01-01', '2027-01-31', 3, 'New Year bottle sale (future)',   25.00);

-- สต็อกในสาขา (in_store = 1 : มี store_numb + dept_numb, warehouse_id = NULL)
INSERT INTO dbo.product_stocked (SKU, UPC, in_store, store_numb, dept_numb, warehouse_id, size, color, number_on_hand, retail_price) VALUES
 ('S1-2-0001', '012345000001', 1, 1, 2, NULL, 'M',     'Black',  25, 12.99),
 ('S1-2-0002', '012345000002', 1, 1, 2, NULL, '32',    'Blue',   15, 39.99),
 ('S1-3-0001', '012345000003', 1, 1, 3, NULL, NULL,    'Black',  30, 19.99),
 ('S1-3-0002', '012345000004', 1, 1, 3, NULL, NULL,    'White',  60,  7.99),
 ('S1-1-0001', '012345000005', 1, 1, 1, NULL, NULL,    NULL,     40,  4.49),
 ('S1-1-0002', '012345000007', 1, 1, 1, NULL, NULL,    NULL,     20,  9.99),
 ('S1-4-0001', '012345000006', 1, 1, 4, NULL, NULL,    'White',  18,  8.99),
 ('S2-2-0001', '012345000001', 1, 2, 2, NULL, 'M',     'Black',  10, 12.99),
 ('S2-3-0001', '012345000003', 1, 2, 3, NULL, NULL,    'Black',  12, 19.99),
 ('S2-3-0002', '012345000004', 1, 2, 3, NULL, NULL,    'White',  50,  7.99),
 ('S3-2-0001', '012345000001', 1, 3, 2, NULL, 'M',     'Black',   8, 13.49),
 ('S3-3-0001', '012345000008', 1, 3, 3, NULL, NULL,    'Silver',  6, 24.99),
 ('S4-1-0001', '012345000007', 1, 4, 1, NULL, NULL,    NULL,     25,  9.49),
 ('S4-3-0001', '012345000004', 1, 4, 3, NULL, NULL,    'White',  40,  7.49),
 ('S1-T2-01',  '099000000001', 1, 1, 2, NULL, 'L',     'Gray',    5, 49.99),  -- [TEST] T2 ปลายทาง
 ('S1-T3-01',  '099000000002', 1, 1, 2, NULL, '42',    'White',  20, 59.99),  -- [TEST] T1/T3/T4
 ('S1-T8-01',  '099000000005', 1, 1, 4, NULL, '750ml', 'Steel',  30, 19.99);  -- [TEST] T8

-- สต็อกในคลัง (in_store = 0 : มี warehouse_id, store_numb/dept_numb = NULL)
INSERT INTO dbo.product_stocked (SKU, UPC, in_store, store_numb, dept_numb, warehouse_id, size, color, number_on_hand, retail_price) VALUES
 ('W1-0001',  '012345000001', 0, NULL, NULL, 1, 'M',  'Black',  200, 12.99),
 ('W1-0002',  '012345000002', 0, NULL, NULL, 1, '32', 'Blue',   120, 39.99),
 ('W1-0003',  '012345000003', 0, NULL, NULL, 1, NULL, 'Black',  150, 19.99),
 ('W1-0004',  '012345000004', 0, NULL, NULL, 1, NULL, 'White',  300,  7.99),
 ('W1-0005',  '012345000005', 0, NULL, NULL, 1, NULL, NULL,     100,  4.49),  -- web_orderable = 0
 ('W2-0001',  '012345000008', 0, NULL, NULL, 2, NULL, 'Silver',  80, 24.99),
 ('W2-0002',  '012345000006', 0, NULL, NULL, 2, NULL, 'White',   90,  8.99),
 ('W3-0001',  '012345000007', 0, NULL, NULL, 3, NULL, NULL,      60,  9.49),
 ('W4-0001',  '012345000001', 0, NULL, NULL, 4, 'M',  'Black',   70, 12.99),
 ('W1-T2-01', '099000000001', 0, NULL, NULL, 1, 'L',  'Gray',    10, 49.99),  -- [TEST] T2 ต้นทาง
 ('W1-T6-01', '099000000003', 0, NULL, NULL, 1, NULL, 'Navy',    50, 49.99),  -- [TEST] T6/T7
 ('W1-T6-02', '099000000004', 0, NULL, NULL, 1, NULL, 'Black',   50, 89.99);  -- [TEST] T6/T7

-- ลูกค้าออนไลน์ (password: alice123 / bob123 เก็บเป็น SHA-256 ของ "user_id:password")
SET IDENTITY_INSERT dbo.web_customer ON;
INSERT INTO dbo.web_customer (web_customer_numb, first_name, last_name, phone, user_id, password_hash) VALUES
 (1, 'Alice', 'Walker', '213-555-0301', 'alice', 'sha256:82687873531ba0f424d7a891ac39defbf05f53d1032af62fd57353ed638cf5e0'),
 (2, 'Bob',   'Chen',   '512-555-0302', 'bob',   'sha256:8d204bb4c1d3ec5c667600c69fbd86367af0a1084191cbd8253d2d80cb90f0bd');
SET IDENTITY_INSERT dbo.web_customer OFF;

INSERT INTO dbo.web_customer_credit_card (web_customer_numb, card_numb, card_token, card_last4, exp_date, name_on_card) VALUES
 (1, 1, 'tok_alice_visa_01', '4242', '2028-12-31', 'ALICE WALKER'),
 (1, 2, 'tok_alice_mc_02',   '5454', '2029-06-30', 'ALICE WALKER'),
 (2, 1, 'tok_bob_visa_01',   '1111', '2027-09-30', 'BOB CHEN');

SET IDENTITY_INSERT dbo.web_sale_shipping_address ON;
INSERT INTO dbo.web_sale_shipping_address (shipping_address_numb, web_customer_numb, street, city, state_code, zip, first_name, last_name) VALUES
 (1, 1, '742 Evergreen Ter', 'Los Angeles', 'CA', '90001', 'Alice', 'Walker'),
 (2, 1, '20 W 34th St',      'New York',    'NY', '10001', 'Alice', 'Walker'),   -- ส่งของขวัญไปนิวยอร์ก
 (3, 2, '1100 Congress Ave', 'Austin',      'TX', '78701', 'Bob',   'Chen');
SET IDENTITY_INSERT dbo.web_sale_shipping_address OFF;

-- คำสั่งซื้อออนไลน์ตัวอย่าง
-- #1 Alice : T-Shirt x2 -> CA (ส่งแล้ว รอบที่ 1) , USB-C x3 -> NY (ยังไม่ส่ง = backorder)
-- #2 Bob   : Coffee  x2 -> TX (ยังไม่ส่ง, อยู่คลัง 3)
SET IDENTITY_INSERT dbo.web_sale ON;
INSERT INTO dbo.web_sale (web_sale_numb, web_customer_numb, card_numb, sale_date, merchandise_total, shipping_total, tax_total, total) VALUES
 (1, 1, 1, '2026-11-02 10:15:00', 44.75, 5.50, 2.47, 52.72),
 (2, 2, 1, '2026-11-05 14:30:00', 16.14, 0.00, 0.00, 16.14);
SET IDENTITY_INSERT dbo.web_sale OFF;

INSERT INTO dbo.web_sale_shipment (web_sale_numb, shipment_seq, ship_date, shipping_charge) VALUES
 (1, 1, '2026-11-03', 5.50);

INSERT INTO dbo.web_sale_item (web_sale_numb, SKU, quantity, unit_price, shipping_address_numb, shipment_seq) VALUES
 (1, 'W1-0001', 2, 10.39, 1, 1),
 (1, 'W1-0004', 3,  7.99, 2, NULL),
 (2, 'W3-0001', 2,  8.07, 3, NULL);

-- บิลขายหน้าร้านตัวอย่าง
SET IDENTITY_INSERT dbo.in_store_sale ON;
INSERT INTO dbo.in_store_sale (transaction_numb, store_numb, payment_type_code, transaction_date, product_total, sales_tax, total) VALUES
 (1, 1, 1, '2026-11-01 09:30:00', 28.97, 1.45, 30.42),   -- เงินสด
 (2, 2, 2, '2026-11-04 18:05:00', 10.39, 0.75, 11.14);   -- บัตรเครดิต
SET IDENTITY_INSERT dbo.in_store_sale OFF;

INSERT INTO dbo.in_store_sale_item (transaction_numb, SKU, quantity, unit_price) VALUES
 (1, 'S1-1-0001', 2,  4.49),
 (1, 'S1-3-0001', 1, 19.99),
 (2, 'S2-2-0001', 1, 10.39);

INSERT INTO dbo.credit_sale_details (transaction_numb, card_token, card_last4, exp_date, name_on_card) VALUES
 (2, 'tok_instore_0001', '4242', '2028-12-31', 'JOHN DOE');
GO

-- ตรวจผล : นับจำนวนแถวทุกตาราง (แคปใส่รายงานได้)
SELECT t.name AS table_name, SUM(p.rows) AS row_count
FROM sys.tables t
JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0, 1)
GROUP BY t.name
ORDER BY t.name;
GO
