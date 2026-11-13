package smartmart.db;

import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.Reader;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.Properties;

/**
 * เปิด Connection ไปยัง SQL Server ด้วย JDBC (Microsoft JDBC Driver for SQL Server)
 * - URL และ user/password อยู่ในไฟล์ db.properties ที่โฟลเดอร์ราก (root) ของโปรเจกต์
 * - แต่ละแอปใช้ Login ของตัวเอง ตามหลัก least privilege ที่ออกแบบไว้ในข้อ 2
 * - ผู้เรียกต้องปิด Connection เองด้วย try-with-resources เสมอ
 */
public final class DBConnection {

    private static Properties config;

    private DBConnection() {
    }

    /** เปิด Connection ใหม่ด้วย Login ของแอปที่ระบุ */
    public static Connection open(AppLogin login) throws SQLException {
        Properties cfg = config();
        String url = cfg.getProperty("db.url");
        String user = cfg.getProperty(login.key() + ".user");
        String password = cfg.getProperty(login.key() + ".password");
        if (url == null || user == null || password == null) {
            throw new IllegalStateException("db.properties must contain db.url, "
                    + login.key() + ".user and " + login.key() + ".password");
        }
        Connection conn = DriverManager.getConnection(url.trim(), user.trim(), password.trim());
        // ให้ค่า SET ตรงกับที่ Indexed View / Filtered Index ต้องการเมื่อแก้ข้อมูลในตารางที่มีสิ่งเหล่านี้
        try (Statement st = conn.createStatement()) {
            st.execute("SET ARITHABORT ON");
        } catch (SQLException e) {
            conn.close();
            throw e;
        }
        return conn;
    }

    /** ชื่อ user ที่ใช้กับ Login นี้ (ไว้แสดงผลตอนทดสอบ) */
    public static String userOf(AppLogin login) {
        return config().getProperty(login.key() + ".user", "?").trim();
    }

    private static synchronized Properties config() {
        if (config == null) {
            Path file = Paths.get("db.properties");
            if (!Files.exists(file)) {
                throw new IllegalStateException("db.properties not found at " + file.toAbsolutePath()
                        + "  (Run the program with the project folder as the working directory)");
            }
            Properties p = new Properties();
            try (InputStream in = Files.newInputStream(file);
                 Reader reader = new InputStreamReader(in, StandardCharsets.UTF_8)) {
                p.load(reader);
            } catch (IOException e) {
                throw new IllegalStateException("Cannot read db.properties", e);
            }
            config = p;
        }
        return config;
    }
}
