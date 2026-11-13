package smartmart.test;

import java.math.BigDecimal;
import java.sql.Connection;
import java.sql.Date;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.LocalDate;

import smartmart.db.AppLogin;
import smartmart.db.DBConnection;

/**
 * คำสั่งช่วยสำหรับเตรียม/ตรวจข้อมูลในการทดสอบ
 * ใช้ Login ของแอปเดียวกับที่ Transaction ใช้ (ไม่ใช้ admin) จึงพิสูจน์ด้วยว่าสิทธิ์ที่ GRANT ไว้พอใช้งาน
 */
public final class TestSupport {

    private TestSupport() {
    }

    public static int stockOf(AppLogin login, String sku) throws SQLException {
        return queryInt(login, "SELECT number_on_hand FROM dbo.product_stocked WHERE SKU = ?", sku);
    }

    public static void setStock(AppLogin login, String sku, int qty) throws SQLException {
        int rows = execute(login, "UPDATE dbo.product_stocked SET number_on_hand = ? WHERE SKU = ?", qty, sku);
        if (rows != 1) {
            throw new IllegalStateException("Test data row " + sku + " is missing - run sql/01 and sql/02 again");
        }
    }

    public static int queryInt(AppLogin login, String sql, Object... params) throws SQLException {
        Object value = queryValue(login, sql, params);
        return value == null ? 0 : ((Number) value).intValue();
    }

    public static Integer queryNullableInt(AppLogin login, String sql, Object... params) throws SQLException {
        Object value = queryValue(login, sql, params);
        return value == null ? null : ((Number) value).intValue();
    }

    public static BigDecimal queryDecimal(AppLogin login, String sql, Object... params) throws SQLException {
        Object value = queryValue(login, sql, params);
        return value == null ? null : new BigDecimal(value.toString());
    }

    public static String queryString(AppLogin login, String sql, Object... params) throws SQLException {
        Object value = queryValue(login, sql, params);
        return value == null ? null : value.toString();
    }

    /** คืนค่าคอลัมน์แรกของแถวแรก (null ถ้าไม่มีแถว หรือค่าเป็น NULL) */
    public static Object queryValue(AppLogin login, String sql, Object... params) throws SQLException {
        try (Connection conn = DBConnection.open(login);
             PreparedStatement ps = prepare(conn, sql, params);
             ResultSet rs = ps.executeQuery()) {
            return rs.next() ? rs.getObject(1) : null;
        }
    }

    public static int execute(AppLogin login, String sql, Object... params) throws SQLException {
        try (Connection conn = DBConnection.open(login);
             PreparedStatement ps = prepare(conn, sql, params)) {
            return ps.executeUpdate();
        }
    }

    private static PreparedStatement prepare(Connection conn, String sql, Object... params) throws SQLException {
        PreparedStatement ps = conn.prepareStatement(sql);
        try {
            for (int i = 0; i < params.length; i++) {
                Object p = params[i];
                if (p instanceof LocalDate) {
                    ps.setDate(i + 1, Date.valueOf((LocalDate) p));
                } else {
                    ps.setObject(i + 1, p);
                }
            }
            return ps;
        } catch (SQLException e) {
            ps.close();
            throw e;
        }
    }
}
