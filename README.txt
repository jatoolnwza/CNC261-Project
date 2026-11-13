SmartMart Starter Kit (DBMS Project)
====================================

ลำดับการทำ (รายละเอียดทุกขั้น + แคปตรงไหน วางตรงไหน อยู่ในคู่มือ Claude Doc)

ใน SSMS (เปิดไฟล์ทีละไฟล์ แล้วกด F5 ยกเว้นที่คู่มือบอกให้รันทีละส่วน)
  sql/01_create_database_tables.sql   สร้างฐานข้อมูล SmartMart + 20 ตาราง
  sql/02_sample_data.sql              ข้อมูลตัวอย่าง
  sql/03_bulk_data_for_index_test.sql ข้อมูลจำนวนมากสำหรับวัดผล index
  sql/04_queries_T1_T8.sql            SQL ของ T1-T8 (ไฮไลต์ทีละบล็อก)
  sql/05_views.sql                    Views + Materialized (Indexed) View
  sql/06_indexes.sql                  Non-clustered index (รันส่วน A -> B -> C)
  sql/07_security_roles_logins.sql    Logins / Roles / GRANT  (ต้องเปิด Mixed Mode ก่อน)
  sql/08_test_privileges.sql          ทดสอบสิทธิ์ทีละ Role (ไฮไลต์ทีละ TEST)
  sql/SmartMart_ALL_IN_ONE.sql        รวม 01-08 ไว้ไฟล์เดียว สำหรับแนบส่ง

ใน Eclipse
  File > Import > General > Existing Projects into Workspace > เลือกโฟลเดอร์ SmartMartJDBC
  ใส่ไฟล์ mssql-jdbc-xx.jre11.jar ใน SmartMartJDBC/lib แล้ว Add to Build Path (ดู lib/README.txt)
  แก้ db.url ใน db.properties ถ้า SQL Server ไม่ได้อยู่ที่ localhost:1433
  รัน smartmart.test.RunAllTests แล้วตามด้วย DemoDirtyRead, DemoLostUpdate, DemoPhantom

รหัสผ่านทุก Login ในงานนี้ : SmartMart@2026
