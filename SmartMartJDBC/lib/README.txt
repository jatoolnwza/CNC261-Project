วาง JDBC driver ไว้ในโฟลเดอร์นี้ (Put the SQL Server JDBC driver in this folder)

1. ดาวน์โหลด "Microsoft JDBC Driver for SQL Server" (ไฟล์ .zip หรือ .tar.gz) จากเว็บ Microsoft
   https://learn.microsoft.com/sql/connect/jdbc/download-microsoft-jdbc-driver-for-sql-server
2. แตกไฟล์ แล้ว copy ไฟล์  mssql-jdbc-<version>.jre11.jar  มาไว้ที่โฟลเดอร์ lib นี้
   (ใช้ JDK 17 หรือ 21 ก็เลือกไฟล์ .jre11.jar ได้)
3. ใน Eclipse: คลิกขวาที่ไฟล์ jar > Build Path > Add to Build Path
   ไฟล์ jar จะไปโผล่ใต้ "Referenced Libraries"
