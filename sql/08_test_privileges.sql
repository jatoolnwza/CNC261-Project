/* =====================================================================
   SmartMart  |  08_test_privileges.sql
   ใช้กับรายงานข้อ 2.2 และวิดีโอ Demo : ทดสอบว่าแต่ละ Role ทำได้/ทำไม่ได้ ตามที่ออกแบบ
   EXECUTE AS USER = '...' : ให้ admin "สวมสิทธิ์" เป็น user นั้นชั่วคราว  /  REVERT = กลับเป็น admin
   วิธีใช้ : ไฮไลต์ทีละบล็อก (TEST 1 ... TEST 10) แล้วกด F5
     [OK]     = ต้องรันผ่าน   -> แคปแท็บ Results
     [DENIED] = ต้องขึ้น error สีแดง "... permission was denied ..." -> แคปแท็บ Messages
   (error สิทธิ์ไม่ทำให้บล็อกหยุด คำสั่ง REVERT ท้ายบล็อกจึงยังทำงาน)
   ===================================================================== */
USE SmartMart;
GO

/* ===== TEST 1 : role_inventory_reader (inv_reader1) ===== */
EXECUTE AS USER = 'inv_reader1';
SELECT USER_NAME() AS running_as;
SELECT TOP (5) SKU, product_name, location_type, number_on_hand, sale_price
FROM dbo.v_stock_by_location ORDER BY SKU;                         -- [OK] อ่านผ่าน View ได้
SELECT TOP (5) * FROM dbo.product_stocked;                          -- [DENIED] อ่านตารางจริงไม่ได้
UPDATE dbo.product SET product_name = product_name WHERE UPC = '012345000001';  -- [DENIED] แก้ไขไม่ได้
REVERT;
GO

/* ===== TEST 2 : role_store_cashier (cashier_s1 = สาขา 1) ===== */
EXECUTE AS USER = 'cashier_s1';
SELECT USER_NAME() AS running_as;
SELECT store_numb, SKU, product_name, number_on_hand FROM dbo.v_store_stock
WHERE SKU NOT LIKE 'X%' ORDER BY SKU;                              -- [OK] เห็นเฉพาะสาขา 1
EXEC sp_set_session_context @key = N'store_numb', @value = 2;      -- ลองแอบเปลี่ยนเป็นสาขา 2
SELECT DISTINCT store_numb AS still_only_store FROM dbo.v_store_stock;  -- [OK] ยังเป็นสาขา 1 เพราะ staff_assignment มาก่อน
EXEC sp_set_session_context @key = N'store_numb', @value = NULL;
SELECT TOP (5) * FROM dbo.product_stocked;                          -- [DENIED]
INSERT INTO dbo.in_store_sale (store_numb, payment_type_code) VALUES (1, 1);   -- [DENIED] ต้องขายผ่านแอป POS
REVERT;
GO

/* ===== TEST 3 : role_store_cashier (cashier_s2 = สาขา 2) ใช้ View เดียวกันแต่เห็นคนละแถว ===== */
EXECUTE AS USER = 'cashier_s2';
SELECT USER_NAME() AS running_as;
SELECT store_numb, SKU, product_name, number_on_hand FROM dbo.v_store_stock
WHERE SKU NOT LIKE 'X%' ORDER BY SKU;                              -- [OK] เห็นเฉพาะสาขา 2
REVERT;
GO

/* ===== TEST 4 : role_warehouse_staff (wh_staff1 = คลัง 1) ===== */
EXECUTE AS USER = 'wh_staff1';
SELECT USER_NAME() AS running_as;
SELECT * FROM dbo.v_warehouse_stock WHERE SKU NOT LIKE 'X%' ORDER BY SKU;  -- [OK] เฉพาะคลัง 1 และไม่มีคอลัมน์ราคา
SELECT * FROM dbo.v_warehouse_pending_items;                        -- [OK] รายการรอส่งของคลัง 1 (ไม่เห็นของคลัง 3)
SELECT * FROM dbo.web_customer_credit_card;                         -- [DENIED] ห้ามเห็นข้อมูลบัตร
UPDATE dbo.product_stocked SET number_on_hand = 0 WHERE SKU = 'W1-0001';  -- [DENIED] แก้สต็อกตรง ๆ ไม่ได้
REVERT;
GO

/* ===== TEST 5 : role_product_manager (pm1) ===== */
EXECUTE AS USER = 'pm1';
SELECT USER_NAME() AS running_as;
BEGIN TRAN;
    UPDATE dbo.product_stocked SET retail_price = 13.49 WHERE SKU = 'S1-2-0001';    -- [OK] แก้ราคาได้
    INSERT INTO dbo.sales_promotion (UPC, promotion_start_date, promotion_end_date, promotion_type_code, promotion_details, discount_percent)
    VALUES ('012345000006', '2027-02-01', '2027-02-14', 3, 'Valentine towel sale', 10.00);   -- [OK] สร้างโปรได้
    SELECT SKU, retail_price FROM dbo.product_stocked WHERE SKU = 'S1-2-0001';
    UPDATE dbo.product_stocked SET number_on_hand = 999 WHERE SKU = 'S1-2-0001';     -- [DENIED] แก้จำนวนสต็อกไม่ได้ (column-level)
ROLLBACK TRAN;
SELECT TOP (5) * FROM dbo.web_customer;                             -- [DENIED] ไม่เกี่ยวกับข้อมูลลูกค้า
REVERT;
GO

/* ===== TEST 6 : role_reference_admin (ref_admin1) ===== */
EXECUTE AS USER = 'ref_admin1';
SELECT USER_NAME() AS running_as;
BEGIN TRAN;
    UPDATE dbo.state SET sales_tax_rate = 0.0750 WHERE state_code = 'CA';   -- [OK] แก้อัตราภาษีได้
    SELECT * FROM dbo.state WHERE state_code = 'CA';
ROLLBACK TRAN;
DELETE FROM dbo.payment_type WHERE payment_type_code = 99;          -- [DENIED] ไม่มีสิทธิ์ DELETE
SELECT TOP (5) * FROM dbo.product;                                  -- [DENIED]
REVERT;
GO

/* ===== TEST 7 : role_dba (dba1) ทำ DDL ได้ แต่อ่านข้อมูลไม่ได้ ===== */
EXECUTE AS USER = 'dba1';
SELECT USER_NAME() AS running_as;
CREATE TABLE dbo.dba_test (id INT NOT NULL PRIMARY KEY, note VARCHAR(20) NULL);   -- [OK] CREATE
ALTER TABLE dbo.dba_test ADD created_at DATETIME2 NULL;                            -- [OK] ALTER
DROP TABLE dbo.dba_test;                                                           -- [OK] DROP
SELECT TOP (5) * FROM dbo.product;                                                 -- [DENIED] (DENY SELECT)
REVERT;
GO

/* ===== TEST 8 : role_pos_app (login_app_pos) ===== */
EXECUTE AS USER = 'login_app_pos';
SELECT USER_NAME() AS running_as;
SELECT COUNT(*) AS rows_before_context FROM dbo.v_store_stock;      -- [OK] 0 แถว ยังไม่บอกว่าเป็นเครื่องของสาขาไหน
EXEC sp_set_session_context @key = N'store_numb', @value = 1;       -- แอป POS ของสาขา 1 บอกฐานข้อมูล
SELECT TOP (5) store_numb, SKU, product_name, number_on_hand FROM dbo.v_store_stock
WHERE SKU NOT LIKE 'X%' ORDER BY SKU;                              -- [OK] สาขา 1
EXEC sp_set_session_context @key = N'store_numb', @value = NULL;
UPDATE dbo.product_stocked SET retail_price = 1.00 WHERE SKU = 'S1-2-0001';  -- [DENIED] แก้ได้เฉพาะ number_on_hand
SELECT TOP (5) * FROM dbo.web_customer;                             -- [DENIED]
REVERT;
GO

/* ===== TEST 9 : role_webshop_app (login_app_webshop) ===== */
EXECUTE AS USER = 'login_app_webshop';
SELECT USER_NAME() AS running_as;
EXEC sp_set_session_context @key = N'web_customer_numb', @value = 1;
SELECT * FROM dbo.v_customer_orders;                                -- [OK] เห็นเฉพาะคำสั่งซื้อของ Alice
EXEC sp_set_session_context @key = N'web_customer_numb', @value = 2;
SELECT * FROM dbo.v_customer_orders;                                -- [OK] เห็นเฉพาะคำสั่งซื้อของ Bob
EXEC sp_set_session_context @key = N'web_customer_numb', @value = NULL;
SELECT TOP (5) * FROM dbo.in_store_sale;                            -- [DENIED] ไม่เกี่ยวกับการขายหน้าร้าน
DELETE FROM dbo.web_customer WHERE web_customer_numb = 999;         -- [DENIED] ลบลูกค้าไม่ได้
REVERT;
GO

/* ===== TEST 10 : role_warehouse_app (login_app_warehouse) ===== */
EXECUTE AS USER = 'login_app_warehouse';
SELECT USER_NAME() AS running_as;
EXEC sp_set_session_context @key = N'warehouse_id', @value = 1;
SELECT * FROM dbo.v_warehouse_pending_items;                        -- [OK]
EXEC sp_set_session_context @key = N'warehouse_id', @value = NULL;
SELECT TOP (5) * FROM dbo.web_customer_credit_card;                 -- [DENIED]
INSERT INTO dbo.web_sale (web_customer_numb, card_numb) VALUES (1, 1);   -- [DENIED] สร้างคำสั่งซื้อไม่ได้
REVERT;
GO

-- ต้องกลับมาเป็น admin แล้ว (ไม่ใช่ชื่อ user ด้านบน)
SELECT USER_NAME() AS running_as_now, @@TRANCOUNT AS open_transactions;
GO
