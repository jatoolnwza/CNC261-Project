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
