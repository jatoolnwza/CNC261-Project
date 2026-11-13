/* =====================================================================
   SmartMart  |  07_security_roles_logins.sql
   ใช้กับรายงานข้อ 2.1-2.2 : สร้าง Login (ระดับ Server), User + Role (ระดับ Database)
                            และ GRANT / DENY สิทธิ์ตามตาราง Roles
   ก่อนรัน : เปิด SQL Server Authentication (Mixed Mode) ตามคู่มือขั้นที่ 0 แล้ว
   รันหลัง 05 (ต้องมี View ก่อนจึง GRANT ที่ View ได้)   รันซ้ำได้
   รหัสผ่านทุกบัญชีสำหรับงานนี้ : SmartMart@2026
   ===================================================================== */

/* ---------------------------------------------------------------------
   1) LOGIN ระดับ Server (SQL Server Authentication)
      พนักงาน 7 คน (คนละ Role) + แอปพลิเคชัน 3 ตัว
   --------------------------------------------------------------------- */
USE master;
GO
IF SUSER_ID(N'inv_reader1')         IS NULL CREATE LOGIN inv_reader1         WITH PASSWORD = N'SmartMart@2026', DEFAULT_DATABASE = SmartMart, CHECK_POLICY = OFF;
IF SUSER_ID(N'cashier_s1')          IS NULL CREATE LOGIN cashier_s1          WITH PASSWORD = N'SmartMart@2026', DEFAULT_DATABASE = SmartMart, CHECK_POLICY = OFF;
IF SUSER_ID(N'cashier_s2')          IS NULL CREATE LOGIN cashier_s2          WITH PASSWORD = N'SmartMart@2026', DEFAULT_DATABASE = SmartMart, CHECK_POLICY = OFF;
IF SUSER_ID(N'wh_staff1')           IS NULL CREATE LOGIN wh_staff1           WITH PASSWORD = N'SmartMart@2026', DEFAULT_DATABASE = SmartMart, CHECK_POLICY = OFF;
IF SUSER_ID(N'pm1')                 IS NULL CREATE LOGIN pm1                 WITH PASSWORD = N'SmartMart@2026', DEFAULT_DATABASE = SmartMart, CHECK_POLICY = OFF;
IF SUSER_ID(N'ref_admin1')          IS NULL CREATE LOGIN ref_admin1          WITH PASSWORD = N'SmartMart@2026', DEFAULT_DATABASE = SmartMart, CHECK_POLICY = OFF;
IF SUSER_ID(N'dba1')                IS NULL CREATE LOGIN dba1                WITH PASSWORD = N'SmartMart@2026', DEFAULT_DATABASE = SmartMart, CHECK_POLICY = OFF;
IF SUSER_ID(N'login_app_webshop')   IS NULL CREATE LOGIN login_app_webshop   WITH PASSWORD = N'SmartMart@2026', DEFAULT_DATABASE = SmartMart, CHECK_POLICY = OFF;
IF SUSER_ID(N'login_app_pos')       IS NULL CREATE LOGIN login_app_pos       WITH PASSWORD = N'SmartMart@2026', DEFAULT_DATABASE = SmartMart, CHECK_POLICY = OFF;
IF SUSER_ID(N'login_app_warehouse') IS NULL CREATE LOGIN login_app_warehouse WITH PASSWORD = N'SmartMart@2026', DEFAULT_DATABASE = SmartMart, CHECK_POLICY = OFF;
GO

USE SmartMart;
GO

/* ---------------------------------------------------------------------
   2) ROLE ระดับ Database  (6 Role ของคน + 3 Role ของแอป)
   --------------------------------------------------------------------- */
IF DATABASE_PRINCIPAL_ID(N'role_inventory_reader') IS NULL CREATE ROLE role_inventory_reader;
IF DATABASE_PRINCIPAL_ID(N'role_store_cashier')    IS NULL CREATE ROLE role_store_cashier;
IF DATABASE_PRINCIPAL_ID(N'role_warehouse_staff')  IS NULL CREATE ROLE role_warehouse_staff;
IF DATABASE_PRINCIPAL_ID(N'role_product_manager')  IS NULL CREATE ROLE role_product_manager;
IF DATABASE_PRINCIPAL_ID(N'role_reference_admin')  IS NULL CREATE ROLE role_reference_admin;
IF DATABASE_PRINCIPAL_ID(N'role_dba')              IS NULL CREATE ROLE role_dba;
IF DATABASE_PRINCIPAL_ID(N'role_webshop_app')      IS NULL CREATE ROLE role_webshop_app;
IF DATABASE_PRINCIPAL_ID(N'role_pos_app')          IS NULL CREATE ROLE role_pos_app;
IF DATABASE_PRINCIPAL_ID(N'role_warehouse_app')    IS NULL CREATE ROLE role_warehouse_app;
GO

/* ---------------------------------------------------------------------
   3) USER ในฐานข้อมูล (ผูกกับ Login ชื่อเดียวกัน) แล้วใส่เข้า Role
   --------------------------------------------------------------------- */
IF DATABASE_PRINCIPAL_ID(N'inv_reader1')         IS NULL CREATE USER inv_reader1         FOR LOGIN inv_reader1;
IF DATABASE_PRINCIPAL_ID(N'cashier_s1')          IS NULL CREATE USER cashier_s1          FOR LOGIN cashier_s1;
IF DATABASE_PRINCIPAL_ID(N'cashier_s2')          IS NULL CREATE USER cashier_s2          FOR LOGIN cashier_s2;
IF DATABASE_PRINCIPAL_ID(N'wh_staff1')           IS NULL CREATE USER wh_staff1           FOR LOGIN wh_staff1;
IF DATABASE_PRINCIPAL_ID(N'pm1')                 IS NULL CREATE USER pm1                 FOR LOGIN pm1;
IF DATABASE_PRINCIPAL_ID(N'ref_admin1')          IS NULL CREATE USER ref_admin1          FOR LOGIN ref_admin1;
IF DATABASE_PRINCIPAL_ID(N'dba1')                IS NULL CREATE USER dba1                FOR LOGIN dba1;
IF DATABASE_PRINCIPAL_ID(N'login_app_webshop')   IS NULL CREATE USER login_app_webshop   FOR LOGIN login_app_webshop;
IF DATABASE_PRINCIPAL_ID(N'login_app_pos')       IS NULL CREATE USER login_app_pos       FOR LOGIN login_app_pos;
IF DATABASE_PRINCIPAL_ID(N'login_app_warehouse') IS NULL CREATE USER login_app_warehouse FOR LOGIN login_app_warehouse;
GO

ALTER ROLE role_inventory_reader ADD MEMBER inv_reader1;
ALTER ROLE role_store_cashier    ADD MEMBER cashier_s1;
ALTER ROLE role_store_cashier    ADD MEMBER cashier_s2;
ALTER ROLE role_warehouse_staff  ADD MEMBER wh_staff1;
ALTER ROLE role_product_manager  ADD MEMBER pm1;
ALTER ROLE role_reference_admin  ADD MEMBER ref_admin1;
ALTER ROLE role_dba              ADD MEMBER dba1;
ALTER ROLE role_webshop_app      ADD MEMBER login_app_webshop;
ALTER ROLE role_pos_app          ADD MEMBER login_app_pos;
ALTER ROLE role_warehouse_app    ADD MEMBER login_app_warehouse;
GO

/* ---------------------------------------------------------------------
   4) ผูกพนักงานกับสาขา/คลัง (View V3-V5 ใช้กรองแถว "เฉพาะของตัวเอง")
      ทุกคนใน role_store_cashier / role_warehouse_staff ต้องมีแถวที่นี่
   --------------------------------------------------------------------- */
DELETE FROM dbo.staff_assignment;
INSERT INTO dbo.staff_assignment (db_user_name, store_numb, warehouse_id) VALUES
 (N'cashier_s1', 1,    NULL),
 (N'cashier_s2', 2,    NULL),
 (N'wh_staff1',  NULL, 1);
GO

/* ---------------------------------------------------------------------
   5) GRANT / DENY สิทธิ์ของแต่ละ Role
   --------------------------------------------------------------------- */

-- R1 role_inventory_reader : พนักงานทั่วไป ค้นหาสินค้า/สต็อก (T1) อ่านอย่างเดียว ผ่าน View
GRANT SELECT ON dbo.v_product_catalog   TO role_inventory_reader;
GRANT SELECT ON dbo.v_stock_by_location TO role_inventory_reader;
GRANT SELECT ON dbo.v_stock_summary     TO role_inventory_reader;
GRANT SELECT ON dbo.product_taxed       TO role_inventory_reader;

-- R2 role_store_cashier : แคชเชียร์ ดูสต็อกเฉพาะสาขาตัวเอง  (บันทึกการขายทำผ่านแอป POS เท่านั้น)
GRANT SELECT ON dbo.v_store_stock     TO role_store_cashier;
GRANT SELECT ON dbo.v_product_catalog TO role_store_cashier;
GRANT SELECT ON dbo.payment_type      TO role_store_cashier;

-- R3 role_warehouse_staff : พนักงานคลัง ดูสต็อก/รายการรอส่ง เฉพาะคลังตัวเอง (บันทึกผ่านแอปคลัง)
GRANT SELECT ON dbo.v_warehouse_stock         TO role_warehouse_staff;
GRANT SELECT ON dbo.v_warehouse_pending_items TO role_warehouse_staff;
GRANT SELECT ON dbo.warehouse                 TO role_warehouse_staff;

-- R4 role_product_manager : ฝ่ายสินค้า ดูแลสินค้า ภาษี โปรโมชัน (T8) และราคาขาย
GRANT SELECT, INSERT, UPDATE         ON dbo.product         TO role_product_manager;
GRANT SELECT, INSERT, DELETE         ON dbo.product_taxed   TO role_product_manager;
GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.sales_promotion TO role_product_manager;
GRANT SELECT                         ON dbo.promotion_type  TO role_product_manager;
GRANT SELECT                         ON dbo.product_stocked TO role_product_manager;
GRANT UPDATE (retail_price)          ON dbo.product_stocked TO role_product_manager;  -- แก้ได้เฉพาะคอลัมน์ราคา
GRANT SELECT ON dbo.v_stock_by_location TO role_product_manager;
GRANT SELECT ON dbo.v_stock_summary     TO role_product_manager;

-- R5 role_reference_admin : ดูแลตารางอ้างอิง (อัตราภาษี วิธีชำระเงิน ประเภทโปรโมชัน) ห้ามลบ
GRANT SELECT, INSERT, UPDATE ON dbo.state          TO role_reference_admin;
GRANT SELECT, INSERT, UPDATE ON dbo.payment_type   TO role_reference_admin;
GRANT SELECT, INSERT, UPDATE ON dbo.promotion_type TO role_reference_admin;

-- R6 role_dba : สร้าง/แก้/ลบ โครงสร้าง (DDL) ได้ แต่ห้ามอ่าน/แก้ข้อมูลธุรกิจ
GRANT CREATE TABLE, CREATE VIEW, CREATE PROCEDURE, CREATE FUNCTION TO role_dba;
GRANT ALTER ON SCHEMA::dbo TO role_dba;         -- ALTER / DROP ตารางใน schema dbo ได้
GRANT VIEW DEFINITION TO role_dba;              -- ดูโครงสร้าง (metadata) ได้
DENY SELECT, INSERT, UPDATE, DELETE ON SCHEMA::dbo TO role_dba;

-- A1 role_webshop_app (login_app_webshop) : เว็บขายออนไลน์  T1, T5, T6
GRANT SELECT ON dbo.v_product_catalog   TO role_webshop_app;
GRANT SELECT ON dbo.v_stock_by_location TO role_webshop_app;
GRANT SELECT ON dbo.v_customer_orders   TO role_webshop_app;
GRANT SELECT ON dbo.product             TO role_webshop_app;
GRANT SELECT ON dbo.product_stocked     TO role_webshop_app;
GRANT UPDATE (number_on_hand) ON dbo.product_stocked TO role_webshop_app;   -- ตัดสต็อกได้ แก้ราคาไม่ได้
GRANT SELECT ON dbo.sales_promotion     TO role_webshop_app;
GRANT SELECT ON dbo.product_taxed       TO role_webshop_app;
GRANT SELECT ON dbo.state               TO role_webshop_app;
GRANT SELECT, INSERT ON dbo.web_customer              TO role_webshop_app;
GRANT SELECT, INSERT ON dbo.web_customer_credit_card  TO role_webshop_app;
GRANT SELECT, INSERT ON dbo.web_sale_shipping_address TO role_webshop_app;
GRANT SELECT, INSERT ON dbo.web_sale                  TO role_webshop_app;
GRANT UPDATE (merchandise_total, tax_total, total) ON dbo.web_sale TO role_webshop_app;
GRANT SELECT, INSERT ON dbo.web_sale_item             TO role_webshop_app;

-- A2 role_pos_app (login_app_pos) : ระบบ POS หน้าร้าน  T3, T4
GRANT SELECT ON dbo.v_store_stock   TO role_pos_app;
GRANT SELECT ON dbo.payment_type    TO role_pos_app;
GRANT SELECT ON dbo.store           TO role_pos_app;
GRANT SELECT ON dbo.state           TO role_pos_app;
GRANT SELECT ON dbo.product_stocked TO role_pos_app;
GRANT UPDATE (number_on_hand) ON dbo.product_stocked TO role_pos_app;
GRANT SELECT ON dbo.sales_promotion TO role_pos_app;
GRANT SELECT ON dbo.product_taxed   TO role_pos_app;
GRANT SELECT, INSERT ON dbo.in_store_sale       TO role_pos_app;
GRANT UPDATE (product_total, sales_tax, total) ON dbo.in_store_sale TO role_pos_app;
GRANT SELECT, INSERT ON dbo.in_store_sale_item  TO role_pos_app;
GRANT SELECT, INSERT ON dbo.credit_sale_details TO role_pos_app;

-- A3 role_warehouse_app (login_app_warehouse) : ระบบคลังสินค้า  T2, T7
GRANT SELECT ON dbo.v_warehouse_pending_items TO role_warehouse_app;
GRANT SELECT ON dbo.v_warehouse_stock         TO role_warehouse_app;
GRANT SELECT ON dbo.product                   TO role_warehouse_app;
GRANT SELECT ON dbo.product_stocked           TO role_warehouse_app;
GRANT UPDATE (number_on_hand) ON dbo.product_stocked TO role_warehouse_app;
GRANT SELECT ON dbo.web_sale                  TO role_warehouse_app;
GRANT UPDATE (shipping_total, total) ON dbo.web_sale TO role_warehouse_app;
GRANT SELECT ON dbo.web_sale_item             TO role_warehouse_app;
GRANT UPDATE (shipment_seq) ON dbo.web_sale_item TO role_warehouse_app;
GRANT SELECT, INSERT ON dbo.web_sale_shipment TO role_warehouse_app;
GO

/* ---------------------------------------------------------------------
   6) ตรวจผล (แคปใส่รายงานข้อ 2.2)
   --------------------------------------------------------------------- */
-- 6.1 สมาชิกของแต่ละ Role
SELECT r.name AS role_name, m.name AS member_user, sp.name AS server_login
FROM sys.database_role_members rm
JOIN sys.database_principals r ON r.principal_id = rm.role_principal_id
JOIN sys.database_principals m ON m.principal_id = rm.member_principal_id
LEFT JOIN sys.server_principals sp ON sp.sid = m.sid
WHERE r.name LIKE 'role[_]%'
ORDER BY r.name, m.name;

-- 6.2 สิทธิ์ทั้งหมดของแต่ละ Role (Privilege matrix)
SELECT pr.name         AS role_name,
       pe.state_desc   AS grant_or_deny,
       pe.permission_name,
       CASE pe.class
            WHEN 0 THEN 'DATABASE'
            WHEN 1 THEN OBJECT_SCHEMA_NAME(pe.major_id) + '.' + OBJECT_NAME(pe.major_id)
                        + CASE WHEN pe.minor_id > 0 THEN ' (' + COL_NAME(pe.major_id, pe.minor_id) + ')' ELSE '' END
            WHEN 3 THEN 'SCHEMA::' + SCHEMA_NAME(pe.major_id)
            ELSE pe.class_desc
       END AS on_object
FROM sys.database_permissions pe
JOIN sys.database_principals pr ON pr.principal_id = pe.grantee_principal_id
WHERE pr.name LIKE 'role[_]%'
ORDER BY role_name, on_object, pe.permission_name;
GO
