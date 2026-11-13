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
