/* =====================================================================
   SmartMart  |  SmartMart_ALL_IN_ONE.sql  (สำหรับแนบส่งอาจารย์)
   รวมไฟล์ 01-08 ตามลำดับ : สร้างตาราง, ข้อมูล, Queries T1-T8, Views, Indexes, Roles/Logins, ทดสอบสิทธิ์
   ตอนทำงานจริงให้รันทีละไฟล์ใน sql/ ตามคู่มือ (06 ต้องรันทีละส่วนเพื่อแคปผลก่อน/หลัง)
   ===================================================================== */


/* #####################################################################
   FILE: 01_create_database_tables.sql
   ##################################################################### */
/* =====================================================================
   SmartMart  |  01_create_database_tables.sql
   ใช้กับรายงานข้อ 1.3  : สร้างฐานข้อมูลและตารางตาม ERD
   - สร้างเฉพาะตารางที่ใช้กับ Main Requirements และ Transaction T1-T8
   - รันใน SSMS ด้วยบัญชีผู้ดูแล (Windows Authentication หรือ sa) แล้วกด F5
   - รันซ้ำได้: สคริปต์จะลบฐานข้อมูล SmartMart เดิมทิ้งแล้วสร้างใหม่
   ===================================================================== */
USE master;
GO
IF DB_ID(N'SmartMart') IS NOT NULL
BEGIN
    ALTER DATABASE SmartMart SET SINGLE_USER WITH ROLLBACK IMMEDIATE;  -- ตัด connection ที่ค้างอยู่
    DROP DATABASE SmartMart;
END
GO
CREATE DATABASE SmartMart;
GO
USE SmartMart;
GO

/* ---------------------------------------------------------------------
   ส่วนที่ 1 : องค์กร (State, Store, Warehouse, Department)
   --------------------------------------------------------------------- */

-- Strong entity : รัฐ + อัตราภาษีขาย (รวม state_tax_rates ของตำราไว้ในตารางนี้)
CREATE TABLE dbo.state (
    state_code      CHAR(2)       NOT NULL,
    state_name      VARCHAR(30)   NOT NULL,
    sales_tax_rate  DECIMAL(6,4)  NOT NULL,          -- 0.0725 = 7.25 %
    CONSTRAINT PK_state PRIMARY KEY (state_code),
    CONSTRAINT CK_state_tax_rate CHECK (sales_tax_rate >= 0 AND sales_tax_rate < 1)
);

-- Strong entity : สาขา
CREATE TABLE dbo.store (
    store_numb  INT          NOT NULL,
    street      VARCHAR(60)  NOT NULL,
    city        VARCHAR(40)  NOT NULL,
    state_code  CHAR(2)      NOT NULL,
    zip         VARCHAR(10)  NOT NULL,
    main_phone  VARCHAR(20)  NULL,
    CONSTRAINT PK_store PRIMARY KEY (store_numb),
    CONSTRAINT FK_store_state FOREIGN KEY (state_code) REFERENCES dbo.state (state_code)
);

-- Strong entity : คลังสินค้า
CREATE TABLE dbo.warehouse (
    warehouse_id  INT          NOT NULL,
    street        VARCHAR(60)  NOT NULL,
    city          VARCHAR(40)  NOT NULL,
    state_code    CHAR(2)      NOT NULL,
    zip           VARCHAR(10)  NOT NULL,
    phone         VARCHAR(20)  NULL,
    CONSTRAINT PK_warehouse PRIMARY KEY (warehouse_id),
    CONSTRAINT FK_warehouse_state FOREIGN KEY (state_code) REFERENCES dbo.state (state_code)
);

-- Weak entity : แผนกขึ้นกับสาขา  PK = (store_numb, dept_numb)
CREATE TABLE dbo.department (
    store_numb  INT          NOT NULL,
    dept_numb   INT          NOT NULL,
    dept_name   VARCHAR(40)  NOT NULL,
    CONSTRAINT PK_department PRIMARY KEY (store_numb, dept_numb),
    CONSTRAINT FK_department_store FOREIGN KEY (store_numb) REFERENCES dbo.store (store_numb)
);

/* ---------------------------------------------------------------------
   ส่วนที่ 2 : สินค้า สต็อก โปรโมชัน
   --------------------------------------------------------------------- */

-- Strong entity : สินค้า (ระดับ UPC)
CREATE TABLE dbo.product (
    UPC              VARCHAR(15)   NOT NULL,
    product_name     VARCHAR(100)  NOT NULL,
    product_unit     VARCHAR(20)   NOT NULL,
    shipping_weight  DECIMAL(8,2)  NOT NULL CONSTRAINT DF_product_weight DEFAULT (0),  -- ปอนด์
    web_orderable    BIT           NOT NULL CONSTRAINT DF_product_web DEFAULT (1),    -- 1 = ขายออนไลน์ได้
    CONSTRAINT PK_product PRIMARY KEY (UPC),
    CONSTRAINT CK_product_weight CHECK (shipping_weight >= 0)
);

-- Associative entity (M:N Product-State) : มีแถว = สินค้านี้ต้องเสียภาษีในรัฐนั้น
CREATE TABLE dbo.product_taxed (
    UPC         VARCHAR(15)  NOT NULL,
    state_code  CHAR(2)      NOT NULL,
    CONSTRAINT PK_product_taxed PRIMARY KEY (UPC, state_code),
    CONSTRAINT FK_product_taxed_product FOREIGN KEY (UPC) REFERENCES dbo.product (UPC),
    CONSTRAINT FK_product_taxed_state FOREIGN KEY (state_code) REFERENCES dbo.state (state_code)
);

-- Reference entity : ประเภทโปรโมชัน
CREATE TABLE dbo.promotion_type (
    promotion_type_code  INT          NOT NULL,
    promotion_type_name  VARCHAR(40)  NOT NULL,
    CONSTRAINT PK_promotion_type PRIMARY KEY (promotion_type_code)
);

-- Weak entity : โปรโมชันขึ้นกับสินค้า  PK = (UPC, promotion_start_date)
CREATE TABLE dbo.sales_promotion (
    UPC                   VARCHAR(15)   NOT NULL,
    promotion_start_date  DATE          NOT NULL,
    promotion_end_date    DATE          NOT NULL,
    promotion_type_code   INT           NOT NULL,
    promotion_details     VARCHAR(100)  NULL,
    discount_percent      DECIMAL(5,2)  NOT NULL,      -- 10.00 = ลด 10 %
    CONSTRAINT PK_sales_promotion PRIMARY KEY (UPC, promotion_start_date),
    CONSTRAINT FK_sales_promotion_product FOREIGN KEY (UPC) REFERENCES dbo.product (UPC),
    CONSTRAINT FK_sales_promotion_type FOREIGN KEY (promotion_type_code)
        REFERENCES dbo.promotion_type (promotion_type_code),
    CONSTRAINT CK_sales_promotion_dates CHECK (promotion_end_date >= promotion_start_date),
    CONSTRAINT CK_sales_promotion_discount CHECK (discount_percent > 0 AND discount_percent <= 100)
);

-- Strong entity : สินค้าที่วางอยู่จริง 1 แถว = 1 SKU ณ 1 ที่ (แผนกในสาขา หรือ คลัง)
-- Mutually exclusive relationship : อยู่ได้ที่เดียว บังคับด้วย CHECK CK_ps_location
CREATE TABLE dbo.product_stocked (
    SKU             VARCHAR(20)    NOT NULL,
    UPC             VARCHAR(15)    NOT NULL,
    in_store        BIT            NOT NULL,          -- 1 = อยู่ในสาขา, 0 = อยู่ในคลัง
    store_numb      INT            NULL,
    dept_numb       INT            NULL,
    warehouse_id    INT            NULL,
    size            VARCHAR(10)    NULL,
    color           VARCHAR(20)    NULL,
    number_on_hand  INT            NOT NULL CONSTRAINT DF_ps_on_hand DEFAULT (0),
    retail_price    DECIMAL(10,2)  NOT NULL,
    CONSTRAINT PK_product_stocked PRIMARY KEY (SKU),
    CONSTRAINT FK_ps_product FOREIGN KEY (UPC) REFERENCES dbo.product (UPC),
    CONSTRAINT FK_ps_department FOREIGN KEY (store_numb, dept_numb)
        REFERENCES dbo.department (store_numb, dept_numb),
    CONSTRAINT FK_ps_warehouse FOREIGN KEY (warehouse_id) REFERENCES dbo.warehouse (warehouse_id),
    CONSTRAINT CK_ps_location CHECK (
           (in_store = 1 AND store_numb IS NOT NULL AND dept_numb IS NOT NULL AND warehouse_id IS NULL)
        OR (in_store = 0 AND store_numb IS NULL AND dept_numb IS NULL AND warehouse_id IS NOT NULL)),
    CONSTRAINT CK_ps_on_hand CHECK (number_on_hand >= 0),
    CONSTRAINT CK_ps_price CHECK (retail_price >= 0)
);

/* ---------------------------------------------------------------------
   ส่วนที่ 3 : ขายหน้าร้าน
   --------------------------------------------------------------------- */

-- Reference entity : วิธีชำระเงิน (1 = CASH, 2 = CREDIT)
CREATE TABLE dbo.payment_type (
    payment_type_code  INT          NOT NULL,
    payment_type_text  VARCHAR(20)  NOT NULL,
    CONSTRAINT PK_payment_type PRIMARY KEY (payment_type_code)
);

-- Strong entity : หัวบิลขายหน้าร้าน (product_total, sales_tax, total เป็น derived attribute ที่เก็บไว้)
CREATE TABLE dbo.in_store_sale (
    transaction_numb   INT IDENTITY(1,1) NOT NULL,
    store_numb         INT            NOT NULL,
    payment_type_code  INT            NOT NULL,
    transaction_date   DATETIME2(0)   NOT NULL CONSTRAINT DF_iss_date DEFAULT (SYSDATETIME()),
    product_total      DECIMAL(10,2)  NOT NULL CONSTRAINT DF_iss_product_total DEFAULT (0),
    sales_tax          DECIMAL(10,2)  NOT NULL CONSTRAINT DF_iss_sales_tax DEFAULT (0),
    total              DECIMAL(10,2)  NOT NULL CONSTRAINT DF_iss_total DEFAULT (0),
    CONSTRAINT PK_in_store_sale PRIMARY KEY (transaction_numb),
    CONSTRAINT FK_iss_store FOREIGN KEY (store_numb) REFERENCES dbo.store (store_numb),
    CONSTRAINT FK_iss_payment_type FOREIGN KEY (payment_type_code)
        REFERENCES dbo.payment_type (payment_type_code)
);

-- Weak entity : รายการสินค้าในบิล  PK = (transaction_numb, SKU)
CREATE TABLE dbo.in_store_sale_item (
    transaction_numb  INT            NOT NULL,
    SKU               VARCHAR(20)    NOT NULL,
    quantity          INT            NOT NULL,
    unit_price        DECIMAL(10,2)  NOT NULL,        -- ราคาหลังหักโปรโมชัน
    CONSTRAINT PK_in_store_sale_item PRIMARY KEY (transaction_numb, SKU),
    CONSTRAINT FK_isi_sale FOREIGN KEY (transaction_numb) REFERENCES dbo.in_store_sale (transaction_numb),
    CONSTRAINT FK_isi_sku FOREIGN KEY (SKU) REFERENCES dbo.product_stocked (SKU),
    CONSTRAINT CK_isi_quantity CHECK (quantity > 0)
);

-- Weak entity 1:1 กับ in_store_sale : เก็บเฉพาะบิลที่จ่ายบัตรเครดิต
-- เก็บ token + เลข 4 ตัวท้าย ไม่เก็บเลขบัตรเต็ม
CREATE TABLE dbo.credit_sale_details (
    transaction_numb  INT          NOT NULL,
    card_token        VARCHAR(64)  NOT NULL,
    card_last4        CHAR(4)      NOT NULL,
    exp_date          DATE         NOT NULL,
    name_on_card      VARCHAR(60)  NOT NULL,
    CONSTRAINT PK_credit_sale_details PRIMARY KEY (transaction_numb),
    CONSTRAINT FK_csd_sale FOREIGN KEY (transaction_numb) REFERENCES dbo.in_store_sale (transaction_numb),
    CONSTRAINT CK_csd_last4 CHECK (card_last4 LIKE '[0-9][0-9][0-9][0-9]')
);

/* ---------------------------------------------------------------------
   ส่วนที่ 4 : ขายออนไลน์
   --------------------------------------------------------------------- */

-- Strong entity : ลูกค้าออนไลน์ (user_id ห้ามซ้ำ)
CREATE TABLE dbo.web_customer (
    web_customer_numb  INT IDENTITY(1,1) NOT NULL,
    first_name         VARCHAR(40)   NOT NULL,
    last_name          VARCHAR(40)   NOT NULL,
    phone              VARCHAR(20)   NULL,
    user_id            VARCHAR(30)   NOT NULL,
    password_hash      VARCHAR(100)  NOT NULL,
    CONSTRAINT PK_web_customer PRIMARY KEY (web_customer_numb),
    CONSTRAINT UQ_web_customer_user_id UNIQUE (user_id)
);

-- Weak entity : บัตรที่ลูกค้าบันทึกไว้  PK = (web_customer_numb, card_numb)
CREATE TABLE dbo.web_customer_credit_card (
    web_customer_numb  INT          NOT NULL,
    card_numb          INT          NOT NULL,         -- ลำดับบัตรของลูกค้าคนนั้น 1, 2, 3 ...
    card_token         VARCHAR(64)  NOT NULL,
    card_last4         CHAR(4)      NOT NULL,
    exp_date           DATE         NOT NULL,
    name_on_card       VARCHAR(60)  NOT NULL,
    CONSTRAINT PK_web_customer_credit_card PRIMARY KEY (web_customer_numb, card_numb),
    CONSTRAINT FK_wccc_customer FOREIGN KEY (web_customer_numb) REFERENCES dbo.web_customer (web_customer_numb),
    CONSTRAINT CK_wccc_last4 CHECK (card_last4 LIKE '[0-9][0-9][0-9][0-9]')
);

-- Strong entity : ที่อยู่จัดส่งของลูกค้า (1 ลูกค้ามีได้หลายที่อยู่)
CREATE TABLE dbo.web_sale_shipping_address (
    shipping_address_numb  INT IDENTITY(1,1) NOT NULL,
    web_customer_numb      INT          NOT NULL,
    street                 VARCHAR(60)  NOT NULL,
    city                   VARCHAR(40)  NOT NULL,
    state_code             CHAR(2)      NOT NULL,
    zip                    VARCHAR(10)  NOT NULL,
    first_name             VARCHAR(40)  NOT NULL,
    last_name              VARCHAR(40)  NOT NULL,
    CONSTRAINT PK_web_sale_shipping_address PRIMARY KEY (shipping_address_numb),
    CONSTRAINT FK_wssa_customer FOREIGN KEY (web_customer_numb) REFERENCES dbo.web_customer (web_customer_numb),
    CONSTRAINT FK_wssa_state FOREIGN KEY (state_code) REFERENCES dbo.state (state_code)
);

-- Strong entity : คำสั่งซื้อออนไลน์ (จ่ายด้วยบัตรที่บันทึกไว้ 1 ใบ)
CREATE TABLE dbo.web_sale (
    web_sale_numb      INT IDENTITY(1,1) NOT NULL,
    web_customer_numb  INT            NOT NULL,
    card_numb          INT            NOT NULL,
    sale_date          DATETIME2(0)   NOT NULL CONSTRAINT DF_ws_date DEFAULT (SYSDATETIME()),
    merchandise_total  DECIMAL(10,2)  NOT NULL CONSTRAINT DF_ws_merch DEFAULT (0),
    shipping_total     DECIMAL(10,2)  NOT NULL CONSTRAINT DF_ws_shipping DEFAULT (0),
    tax_total          DECIMAL(10,2)  NOT NULL CONSTRAINT DF_ws_tax DEFAULT (0),
    total              DECIMAL(10,2)  NOT NULL CONSTRAINT DF_ws_total DEFAULT (0),
    CONSTRAINT PK_web_sale PRIMARY KEY (web_sale_numb),
    CONSTRAINT FK_ws_customer FOREIGN KEY (web_customer_numb) REFERENCES dbo.web_customer (web_customer_numb),
    -- FK แบบ 2 คอลัมน์ : บัตรที่ใช้ต้องเป็นบัตรของลูกค้าคนเดียวกันเท่านั้น
    CONSTRAINT FK_ws_card FOREIGN KEY (web_customer_numb, card_numb)
        REFERENCES dbo.web_customer_credit_card (web_customer_numb, card_numb)
);

-- Weak entity : รอบจัดส่งของคำสั่งซื้อ  PK = (web_sale_numb, shipment_seq)
CREATE TABLE dbo.web_sale_shipment (
    web_sale_numb    INT            NOT NULL,
    shipment_seq     INT            NOT NULL,
    ship_date        DATE           NOT NULL,
    shipping_charge  DECIMAL(10,2)  NOT NULL,
    CONSTRAINT PK_web_sale_shipment PRIMARY KEY (web_sale_numb, shipment_seq),
    CONSTRAINT FK_wss_sale FOREIGN KEY (web_sale_numb) REFERENCES dbo.web_sale (web_sale_numb),
    CONSTRAINT CK_wss_charge CHECK (shipping_charge >= 0)
);

-- Weak entity : รายการสินค้าในคำสั่งซื้อ  PK = (web_sale_numb, SKU)
-- shipment_seq = NULL แปลว่ายังไม่ได้ส่ง (backorder)
CREATE TABLE dbo.web_sale_item (
    web_sale_numb          INT            NOT NULL,
    SKU                    VARCHAR(20)    NOT NULL,
    quantity               INT            NOT NULL,
    unit_price             DECIMAL(10,2)  NOT NULL,
    shipping_address_numb  INT            NOT NULL,   -- แต่ละรายการส่งคนละที่อยู่ได้
    shipment_seq           INT            NULL,
    CONSTRAINT PK_web_sale_item PRIMARY KEY (web_sale_numb, SKU),
    CONSTRAINT FK_wsi_sale FOREIGN KEY (web_sale_numb) REFERENCES dbo.web_sale (web_sale_numb),
    CONSTRAINT FK_wsi_sku FOREIGN KEY (SKU) REFERENCES dbo.product_stocked (SKU),
    CONSTRAINT FK_wsi_address FOREIGN KEY (shipping_address_numb)
        REFERENCES dbo.web_sale_shipping_address (shipping_address_numb),
    CONSTRAINT FK_wsi_shipment FOREIGN KEY (web_sale_numb, shipment_seq)
        REFERENCES dbo.web_sale_shipment (web_sale_numb, shipment_seq),
    CONSTRAINT CK_wsi_quantity CHECK (quantity > 0)
);

/* ---------------------------------------------------------------------
   ส่วนที่ 5 : ตารางช่วยด้าน Security (ไม่ใช่ entity ทางธุรกิจ ไม่ต้องใส่ใน ERD)
   ผูก database user ของพนักงานกับสาขา/คลังที่ทำงาน
   เพื่อให้ View กรองแถว "เฉพาะสาขาตัวเอง / เฉพาะคลังตัวเอง" ได้ (ข้อ 2.3)
   --------------------------------------------------------------------- */
CREATE TABLE dbo.staff_assignment (
    db_user_name  SYSNAME  NOT NULL,
    store_numb    INT      NULL,
    warehouse_id  INT      NULL,
    CONSTRAINT PK_staff_assignment PRIMARY KEY (db_user_name),
    CONSTRAINT FK_sa_store FOREIGN KEY (store_numb) REFERENCES dbo.store (store_numb),
    CONSTRAINT FK_sa_warehouse FOREIGN KEY (warehouse_id) REFERENCES dbo.warehouse (warehouse_id)
);
GO

-- ตรวจผล : ต้องได้ 20 ตาราง  (แคปผลนี้ + Object Explorer ใส่รายงานข้อ 1.3)
SELECT t.name AS table_name,
       (SELECT COUNT(*) FROM sys.columns c WHERE c.object_id = t.object_id) AS column_count
FROM sys.tables t
ORDER BY t.name;
GO


/* #####################################################################
   FILE: 02_sample_data.sql
   ##################################################################### */
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


/* #####################################################################
   FILE: 03_bulk_data_for_index_test.sql
   ##################################################################### */
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


/* #####################################################################
   FILE: 04_queries_T1_T8.sql
   ##################################################################### */
/* =====================================================================
   SmartMart  |  04_queries_T1_T8.sql
   ใช้กับรายงานข้อ 1.4 : คำสั่ง SELECT / INSERT / UPDATE / DELETE ของแต่ละ Transaction
   วิธีใช้ : ไฮไลต์ทีละบล็อก (ตั้งแต่หัวข้อ T จนถึง GO) แล้วกด F5 -> แคปแท็บ Results
   - ทุกบล็อกที่แก้ข้อมูลจะจบด้วย ROLLBACK ข้อมูลจริงจึงไม่เปลี่ยน รันกี่รอบก็ได้
   - คำสั่งชุดเดียวกันนี้คือคำสั่งที่โปรแกรม Java ใช้ใน PreparedStatement
     (ใน Java ค่าที่เป็น @ตัวแปร จะเป็นเครื่องหมาย ? แทน)
   ===================================================================== */
USE SmartMart;
GO

/* ---------------------------------------------------------------------
   T1 ค้นหาสินค้าที่พร้อมจำหน่าย : อยู่สาขา/แผนกใด หรือคลังใด เหลือเท่าไร ราคาเท่าไร
   SELECT : product JOIN product_stocked LEFT JOIN department, store, warehouse
            + โปรโมชันที่ยังไม่หมดอายุ (คำนวณราคาขายจริง)
   --------------------------------------------------------------------- */
DECLARE @keyword VARCHAR(100) = 'Running%';     -- ค้นหาด้วยชื่อขึ้นต้น (ใช้ index ได้)

SELECT p.UPC, p.product_name, ps.SKU, ps.size, ps.color,
       CASE WHEN ps.in_store = 1 THEN 'STORE' ELSE 'WAREHOUSE' END AS location_type,
       ps.store_numb, d.dept_name, ps.warehouse_id,
       COALESCE(s.city, w.city) AS city,
       ps.number_on_hand, ps.retail_price,
       ISNULL(pr.discount_percent, 0) AS discount_percent,
       CAST(ROUND(ps.retail_price * (100 - ISNULL(pr.discount_percent, 0)) / 100, 2) AS DECIMAL(10,2)) AS sale_price
FROM dbo.product p
JOIN dbo.product_stocked ps ON ps.UPC = p.UPC
LEFT JOIN dbo.department d  ON d.store_numb = ps.store_numb AND d.dept_numb = ps.dept_numb
LEFT JOIN dbo.store s       ON s.store_numb = ps.store_numb
LEFT JOIN dbo.warehouse w   ON w.warehouse_id = ps.warehouse_id
OUTER APPLY (SELECT TOP (1) sp.discount_percent
             FROM dbo.sales_promotion sp
             WHERE sp.UPC = p.UPC
               AND CAST(GETDATE() AS DATE) BETWEEN sp.promotion_start_date AND sp.promotion_end_date
             ORDER BY sp.promotion_start_date DESC) pr
WHERE p.product_name LIKE @keyword
  AND ps.number_on_hand > 0
ORDER BY p.product_name, location_type, ps.store_numb, ps.warehouse_id;
GO

/* ---------------------------------------------------------------------
   T2 โอนสต็อกจาก Warehouse ไป Store (ต้องสำเร็จพร้อมกันทั้งสองฝั่ง)
   SELECT number_on_hand ต้นทาง -> UPDATE ลดที่คลัง -> SELECT ปลายทาง -> UPDATE เพิ่มที่สาขา
   --------------------------------------------------------------------- */
DECLARE @from_sku VARCHAR(20) = 'W1-T2-01',
        @to_sku   VARCHAR(20) = 'S1-T2-01',
        @qty      INT = 3,
        @from_on_hand INT, @to_on_hand INT;

BEGIN TRAN;
    SELECT 'BEFORE' AS step, SKU, UPC, size, color, in_store, store_numb, dept_numb, warehouse_id, number_on_hand
    FROM dbo.product_stocked WHERE SKU IN (@from_sku, @to_sku);

    -- (SELECT) อ่านสต็อกต้นทาง
    SELECT @from_on_hand = number_on_hand FROM dbo.product_stocked WHERE SKU = @from_sku AND in_store = 0;
    -- (UPDATE) ลดสต็อกที่ Warehouse
    UPDATE dbo.product_stocked SET number_on_hand = @from_on_hand - @qty WHERE SKU = @from_sku;
    -- (SELECT) อ่านสต็อกปลายทาง
    SELECT @to_on_hand = number_on_hand FROM dbo.product_stocked WHERE SKU = @to_sku AND in_store = 1;
    -- (UPDATE) เพิ่มสต็อกที่ Store
    UPDATE dbo.product_stocked SET number_on_hand = @to_on_hand + @qty WHERE SKU = @to_sku;

    SELECT 'AFTER' AS step, SKU, number_on_hand
    FROM dbo.product_stocked WHERE SKU IN (@from_sku, @to_sku);
ROLLBACK TRAN;   -- เปลี่ยนเป็น COMMIT TRAN ถ้าต้องการบันทึกจริง
GO

/* ---------------------------------------------------------------------
   T3 ขายหน้าร้าน ชำระเงินสด (payment_type_code = 1)
   SELECT ภาษีของรัฐที่สาขาตั้งอยู่, สต็อก+ราคา, โปรโมชัน, สินค้าเสียภาษีไหม
   INSERT in_store_sale, in_store_sale_item
   UPDATE ตัดสต็อก, ยอดรวม/ภาษี ในหัวบิล
   --------------------------------------------------------------------- */
DECLARE @store INT = 1, @sku VARCHAR(20) = 'S1-T3-01', @qty INT = 2,
        @today DATE = CAST(GETDATE() AS DATE),
        @state CHAR(2), @rate DECIMAL(6,4), @txn INT,
        @upc VARCHAR(15), @on_hand INT, @price DECIMAL(10,2), @disc DECIMAL(5,2),
        @taxable INT, @unit DECIMAL(10,2), @line DECIMAL(10,2), @tax DECIMAL(10,2);

BEGIN TRAN;
    -- (SELECT) รัฐและอัตราภาษีของสาขา
    SELECT @state = s.state_code, @rate = st.sales_tax_rate
    FROM dbo.store s JOIN dbo.state st ON st.state_code = s.state_code
    WHERE s.store_numb = @store;

    -- (INSERT) หัวบิล ยอดเป็น 0 ไว้ก่อน
    INSERT INTO dbo.in_store_sale (store_numb, payment_type_code, transaction_date, product_total, sales_tax, total)
    VALUES (@store, 1, SYSDATETIME(), 0, 0, 0);
    SET @txn = SCOPE_IDENTITY();

    -- (SELECT) สต็อกและราคา : ต้องเป็นของสาขานี้และมีของพอ
    SELECT @upc = UPC, @on_hand = number_on_hand, @price = retail_price
    FROM dbo.product_stocked
    WHERE SKU = @sku AND in_store = 1 AND store_numb = @store;

    -- (SELECT) โปรโมชันที่ยังไม่หมดอายุ
    SELECT TOP (1) @disc = discount_percent
    FROM dbo.sales_promotion
    WHERE UPC = @upc AND @today BETWEEN promotion_start_date AND promotion_end_date
    ORDER BY promotion_start_date DESC;
    SET @disc = ISNULL(@disc, 0);

    -- (SELECT) สินค้านี้ต้องเสียภาษีในรัฐของสาขาไหม
    SELECT @taxable = COUNT(*) FROM dbo.product_taxed WHERE UPC = @upc AND state_code = @state;

    SET @unit = ROUND(@price * (100 - @disc) / 100, 2);
    SET @line = @unit * @qty;
    SET @tax  = CASE WHEN @taxable > 0 THEN ROUND(@line * @rate, 2) ELSE 0 END;

    -- (INSERT) รายการสินค้าในบิล
    INSERT INTO dbo.in_store_sale_item (transaction_numb, SKU, quantity, unit_price)
    VALUES (@txn, @sku, @qty, @unit);
    -- (UPDATE) ตัดสต็อกของสาขา
    UPDATE dbo.product_stocked SET number_on_hand = @on_hand - @qty WHERE SKU = @sku;
    -- (UPDATE) ใส่ยอดรวมและภาษีในหัวบิล
    UPDATE dbo.in_store_sale
    SET product_total = @line, sales_tax = @tax, total = @line + @tax
    WHERE transaction_numb = @txn;

    SELECT * FROM dbo.in_store_sale      WHERE transaction_numb = @txn;
    SELECT * FROM dbo.in_store_sale_item WHERE transaction_numb = @txn;
    SELECT SKU, number_on_hand AS on_hand_after FROM dbo.product_stocked WHERE SKU = @sku;
ROLLBACK TRAN;
GO

/* ---------------------------------------------------------------------
   T4 ขายหน้าร้าน ชำระด้วยบัตรเครดิต (payment_type_code = 2)
   ขั้นตอนเหมือน T3 ทุกอย่าง + INSERT credit_sale_details ใน transaction เดียวกัน
   --------------------------------------------------------------------- */
DECLARE @store INT = 1, @sku VARCHAR(20) = 'S1-T3-01', @qty INT = 1,
        @today DATE = CAST(GETDATE() AS DATE),
        @state CHAR(2), @rate DECIMAL(6,4), @txn INT,
        @upc VARCHAR(15), @on_hand INT, @price DECIMAL(10,2), @disc DECIMAL(5,2),
        @taxable INT, @unit DECIMAL(10,2), @line DECIMAL(10,2), @tax DECIMAL(10,2);

BEGIN TRAN;
    SELECT @state = s.state_code, @rate = st.sales_tax_rate
    FROM dbo.store s JOIN dbo.state st ON st.state_code = s.state_code
    WHERE s.store_numb = @store;

    INSERT INTO dbo.in_store_sale (store_numb, payment_type_code, transaction_date, product_total, sales_tax, total)
    VALUES (@store, 2, SYSDATETIME(), 0, 0, 0);
    SET @txn = SCOPE_IDENTITY();

    SELECT @upc = UPC, @on_hand = number_on_hand, @price = retail_price
    FROM dbo.product_stocked WHERE SKU = @sku AND in_store = 1 AND store_numb = @store;

    SELECT TOP (1) @disc = discount_percent FROM dbo.sales_promotion
    WHERE UPC = @upc AND @today BETWEEN promotion_start_date AND promotion_end_date
    ORDER BY promotion_start_date DESC;
    SET @disc = ISNULL(@disc, 0);
    SELECT @taxable = COUNT(*) FROM dbo.product_taxed WHERE UPC = @upc AND state_code = @state;

    SET @unit = ROUND(@price * (100 - @disc) / 100, 2);
    SET @line = @unit * @qty;
    SET @tax  = CASE WHEN @taxable > 0 THEN ROUND(@line * @rate, 2) ELSE 0 END;

    INSERT INTO dbo.in_store_sale_item (transaction_numb, SKU, quantity, unit_price) VALUES (@txn, @sku, @qty, @unit);
    UPDATE dbo.product_stocked SET number_on_hand = @on_hand - @qty WHERE SKU = @sku;
    UPDATE dbo.in_store_sale SET product_total = @line, sales_tax = @tax, total = @line + @tax
    WHERE transaction_numb = @txn;

    -- (INSERT) ข้อมูลบัตร : เก็บ token + เลข 4 ตัวท้าย ไม่เก็บเลขบัตรเต็ม
    INSERT INTO dbo.credit_sale_details (transaction_numb, card_token, card_last4, exp_date, name_on_card)
    VALUES (@txn, 'tok_demo_0001', '4242', '2028-12-31', 'JOHN DOE');

    SELECT s.*, c.card_last4, c.name_on_card
    FROM dbo.in_store_sale s JOIN dbo.credit_sale_details c ON c.transaction_numb = s.transaction_numb
    WHERE s.transaction_numb = @txn;
ROLLBACK TRAN;
GO

/* ---------------------------------------------------------------------
   T5 สมัครสมาชิกออนไลน์ : บัญชี + บัตรเครดิต + ที่อยู่จัดส่ง (ล้มส่วนใดต้องยกเลิกทั้งหมด)
   SELECT ตรวจ user_id ซ้ำ -> INSERT web_customer, web_customer_credit_card, web_sale_shipping_address
   --------------------------------------------------------------------- */
DECLARE @user_id VARCHAR(30) = 'charlie', @cust INT;

BEGIN TRAN;
    -- (SELECT) user_id ซ้ำไหม (0 = ใช้ได้)
    SELECT COUNT(*) AS same_user_id FROM dbo.web_customer WHERE user_id = @user_id;

    -- (INSERT) บัญชีลูกค้า  (password_hash ของ charlie123)
    INSERT INTO dbo.web_customer (first_name, last_name, phone, user_id, password_hash)
    VALUES ('Charlie', 'Kim', '206-555-0303', @user_id,
            'sha256:9dfe6528253e0915400eeceb9df22dbe2a8a14e4630722ba96efd20541c2184d');
    SET @cust = SCOPE_IDENTITY();
    -- (INSERT) บัตรใบแรก card_numb = 1
    INSERT INTO dbo.web_customer_credit_card (web_customer_numb, card_numb, card_token, card_last4, exp_date, name_on_card)
    VALUES (@cust, 1, 'tok_charlie_01', '4000', '2029-01-31', 'CHARLIE KIM');
    -- (INSERT) ที่อยู่จัดส่ง
    INSERT INTO dbo.web_sale_shipping_address (web_customer_numb, street, city, state_code, zip, first_name, last_name)
    VALUES (@cust, '400 Pine St', 'Seattle', 'WA', '98101', 'Charlie', 'Kim');

    SELECT * FROM dbo.web_customer               WHERE web_customer_numb = @cust;
    SELECT * FROM dbo.web_customer_credit_card   WHERE web_customer_numb = @cust;
    SELECT * FROM dbo.web_sale_shipping_address  WHERE web_customer_numb = @cust;
ROLLBACK TRAN;
GO

/* ---------------------------------------------------------------------
   T6 สั่งซื้อออนไลน์ด้วยบัตรที่บันทึกไว้ (ตัดสต็อกที่ Warehouse, ภาษีตามรัฐปลายทาง)
   SELECT บัตรเป็นของลูกค้า, ที่อยู่เป็นของลูกค้า, web_orderable + สต็อก, โปรโมชัน, ภาษี
   INSERT web_sale, web_sale_item   UPDATE ตัดสต็อก, ยอดรวม
   --------------------------------------------------------------------- */
DECLARE @cust INT = 1, @card INT = 1, @addr INT = 2, @sku VARCHAR(20) = 'W1-T6-02', @qty INT = 1,
        @today DATE = CAST(GETDATE() AS DATE),
        @exp DATE, @dest_state CHAR(2), @rate DECIMAL(6,4), @sale INT,
        @upc VARCHAR(15), @on_hand INT, @price DECIMAL(10,2), @web BIT, @disc DECIMAL(5,2),
        @taxable INT, @unit DECIMAL(10,2), @line DECIMAL(10,2), @tax DECIMAL(10,2);

BEGIN TRAN;
    -- (SELECT) บัตรนี้เป็นของลูกค้าคนนี้และยังไม่หมดอายุ
    SELECT @exp = exp_date FROM dbo.web_customer_credit_card
    WHERE web_customer_numb = @cust AND card_numb = @card;

    -- (INSERT) หัวคำสั่งซื้อ ยอด 0 ไว้ก่อน
    INSERT INTO dbo.web_sale (web_customer_numb, card_numb, sale_date, merchandise_total, shipping_total, tax_total, total)
    VALUES (@cust, @card, SYSDATETIME(), 0, 0, 0, 0);
    SET @sale = SCOPE_IDENTITY();

    -- (SELECT) ที่อยู่ต้องเป็นของลูกค้าคนนี้ + อัตราภาษีของรัฐปลายทาง
    SELECT @dest_state = a.state_code, @rate = st.sales_tax_rate
    FROM dbo.web_sale_shipping_address a JOIN dbo.state st ON st.state_code = a.state_code
    WHERE a.shipping_address_numb = @addr AND a.web_customer_numb = @cust;

    -- (SELECT) ขายออนไลน์ได้ไหม + สต็อกที่คลัง
    SELECT @upc = ps.UPC, @on_hand = ps.number_on_hand, @price = ps.retail_price, @web = p.web_orderable
    FROM dbo.product_stocked ps JOIN dbo.product p ON p.UPC = ps.UPC
    WHERE ps.SKU = @sku AND ps.in_store = 0;

    SELECT TOP (1) @disc = discount_percent FROM dbo.sales_promotion
    WHERE UPC = @upc AND @today BETWEEN promotion_start_date AND promotion_end_date
    ORDER BY promotion_start_date DESC;
    SET @disc = ISNULL(@disc, 0);
    SELECT @taxable = COUNT(*) FROM dbo.product_taxed WHERE UPC = @upc AND state_code = @dest_state;

    SET @unit = ROUND(@price * (100 - @disc) / 100, 2);
    SET @line = @unit * @qty;
    SET @tax  = CASE WHEN @taxable > 0 THEN ROUND(@line * @rate, 2) ELSE 0 END;

    SELECT @exp AS card_exp_date, @dest_state AS dest_state, @web AS web_orderable,
           @on_hand AS on_hand_before, @unit AS unit_price, @tax AS tax;

    -- (INSERT) รายการสินค้า (shipment_seq = NULL = ยังไม่ส่ง)
    INSERT INTO dbo.web_sale_item (web_sale_numb, SKU, quantity, unit_price, shipping_address_numb, shipment_seq)
    VALUES (@sale, @sku, @qty, @unit, @addr, NULL);
    -- (UPDATE) ตัดสต็อกที่คลัง
    UPDATE dbo.product_stocked SET number_on_hand = @on_hand - @qty WHERE SKU = @sku;
    -- (UPDATE) ยอดรวม + ภาษีตามรัฐปลายทาง (ค่าส่งจะบวกตอนจัดส่ง T7)
    UPDATE dbo.web_sale SET merchandise_total = @line, tax_total = @tax, total = @line + @tax
    WHERE web_sale_numb = @sale;

    SELECT * FROM dbo.web_sale      WHERE web_sale_numb = @sale;
    SELECT * FROM dbo.web_sale_item WHERE web_sale_numb = @sale;
ROLLBACK TRAN;
GO

/* ---------------------------------------------------------------------
   T7 จัดส่งแบบแบ่งส่ง (Partial shipment) ของคำสั่งซื้อ #1 : ส่ง W1-0004 ที่ค้างอยู่
   SELECT รายการที่ยังไม่ส่ง + ลำดับรอบถัดไป -> INSERT web_sale_shipment
   UPDATE ผูก shipment_seq ให้รายการ -> UPDATE ปรับค่าส่งรวมใน web_sale
   ค่าส่ง = 5.00 + 0.50 x น้ำหนักรวม (ปอนด์)
   --------------------------------------------------------------------- */
DECLARE @sale INT = 1, @sku VARCHAR(20) = 'W1-0004', @seq INT, @charge DECIMAL(10,2);

BEGIN TRAN;
    -- (SELECT) รายการที่ยังไม่ได้ส่ง (shipment_seq IS NULL)
    SELECT wsi.SKU, wsi.quantity, p.shipping_weight
    FROM dbo.web_sale_item wsi
    JOIN dbo.product_stocked ps ON ps.SKU = wsi.SKU
    JOIN dbo.product p ON p.UPC = ps.UPC
    WHERE wsi.web_sale_numb = @sale AND wsi.shipment_seq IS NULL;

    -- (SELECT) ลำดับรอบจัดส่งถัดไป
    SELECT @seq = ISNULL(MAX(shipment_seq), 0) + 1 FROM dbo.web_sale_shipment WHERE web_sale_numb = @sale;

    SELECT @charge = 5.00 + 0.50 * SUM(p.shipping_weight * wsi.quantity)
    FROM dbo.web_sale_item wsi
    JOIN dbo.product_stocked ps ON ps.SKU = wsi.SKU
    JOIN dbo.product p ON p.UPC = ps.UPC
    WHERE wsi.web_sale_numb = @sale AND wsi.SKU = @sku AND wsi.shipment_seq IS NULL;

    -- (INSERT) รอบจัดส่งใหม่
    INSERT INTO dbo.web_sale_shipment (web_sale_numb, shipment_seq, ship_date, shipping_charge)
    VALUES (@sale, @seq, CAST(GETDATE() AS DATE), @charge);
    -- (UPDATE) ผูกรายการเข้ารอบนี้
    UPDATE dbo.web_sale_item SET shipment_seq = @seq
    WHERE web_sale_numb = @sale AND SKU = @sku AND shipment_seq IS NULL;
    -- (UPDATE) ปรับค่าส่งรวมและยอดรวม
    UPDATE dbo.web_sale SET shipping_total = shipping_total + @charge, total = total + @charge
    WHERE web_sale_numb = @sale;

    SELECT * FROM dbo.web_sale_shipment WHERE web_sale_numb = @sale;
    SELECT * FROM dbo.web_sale_item     WHERE web_sale_numb = @sale;
    SELECT * FROM dbo.web_sale          WHERE web_sale_numb = @sale;
ROLLBACK TRAN;
GO

/* ---------------------------------------------------------------------
   T8 สร้างโปรโมชัน (ห้ามช่วงวันที่ทับกับโปรเดิมของสินค้าเดียวกัน) / ยกเลิกโปรที่ยังไม่เริ่ม
   SELECT ตรวจช่วงวันที่ทับกัน -> INSERT sales_promotion   |   DELETE โปรที่ยังไม่เริ่ม
   --------------------------------------------------------------------- */
DECLARE @upc VARCHAR(15) = '099000000005',
        @start DATE = '2027-03-01', @end DATE = '2027-03-15';

BEGIN TRAN;
    -- (SELECT) มีโปรเดิมที่ช่วงวันที่ทับกันไหม  (ทับกัน = start เดิม <= end ใหม่ AND end เดิม >= start ใหม่)
    SELECT COUNT(*) AS overlapping
    FROM dbo.sales_promotion
    WHERE UPC = @upc AND promotion_start_date <= @end AND promotion_end_date >= @start;

    IF NOT EXISTS (SELECT 1 FROM dbo.sales_promotion
                   WHERE UPC = @upc AND promotion_start_date <= @end AND promotion_end_date >= @start)
        -- (INSERT) ไม่ทับ -> บันทึกได้
        INSERT INTO dbo.sales_promotion (UPC, promotion_start_date, promotion_end_date, promotion_type_code, promotion_details, discount_percent)
        VALUES (@upc, @start, @end, 1, 'Spring bottle sale', 15.00);
    ELSE
        PRINT 'Overlapping promotion found - not inserted';

    -- (DELETE) ยกเลิกโปรที่ยังไม่เริ่ม (วันเริ่ม > วันนี้) เท่านั้น
    DELETE FROM dbo.sales_promotion
    WHERE UPC = @upc AND promotion_start_date = '2027-01-01'
      AND promotion_start_date > CAST(GETDATE() AS DATE);

    SELECT * FROM dbo.sales_promotion WHERE UPC = @upc;
ROLLBACK TRAN;
GO

-- ตรวจว่าไม่มี transaction ค้าง (ต้องได้ 0) ถ้าได้มากกว่า 0 ให้รัน ROLLBACK TRAN;
SELECT @@TRANCOUNT AS open_transactions;
GO


/* #####################################################################
   FILE: 05_views.sql
   ##################################################################### */
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


/* #####################################################################
   FILE: 06_indexes.sql
   ##################################################################### */
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


/* #####################################################################
   FILE: 07_security_roles_logins.sql
   ##################################################################### */
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


/* #####################################################################
   FILE: 08_test_privileges.sql
   ##################################################################### */
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
