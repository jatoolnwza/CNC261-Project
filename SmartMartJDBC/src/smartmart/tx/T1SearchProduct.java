package smartmart.tx;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.List;

import smartmart.db.AppLogin;
import smartmart.db.DBConnection;
import smartmart.model.StockInfo;

/**
 * T1 : ค้นหาสินค้าที่พร้อมจำหน่าย ว่าอยู่ Store/แผนกใด หรือ Warehouse ใด เหลือเท่าไร ราคาเท่าไร
 *
 * ผู้ใช้        : เว็บขายออนไลน์ (login_app_webshop) อ่านผ่าน View v_stock_by_location เท่านั้น
 * Isolation    : READ COMMITTED
 * เหตุผล       : กัน Dirty Read คือไม่ให้ลูกค้าเห็นราคา/สต็อกที่ฝ่ายสินค้ากำลังแก้แต่ยังไม่ commit
 *                (ถ้าเขา rollback ราคาที่เห็นจะเป็นราคาที่ไม่เคยมีอยู่จริง)
 *                เป็นการอ่านอย่างเดียว ไม่ต้องใช้ระดับที่สูงกว่านี้ เพราะไม่ได้นำค่าที่อ่านไปเขียนต่อ
 */
public class T1SearchProduct {

    private static final String SQL_SEARCH =
            "SELECT SKU, UPC, product_name, size, color, location_type, store_numb, dept_name, "
            + "       warehouse_id, city, state_code, number_on_hand, retail_price, discount_percent, sale_price "
            + "FROM dbo.v_stock_by_location "
            + "WHERE product_name LIKE ? AND number_on_hand > 0 "
            + "ORDER BY product_name, location_type, store_numb, warehouse_id";

    private int isolationLevel = Connection.TRANSACTION_READ_COMMITTED;

    /** เปลี่ยน isolation level (ใช้ใน DemoDirtyRead เพื่อเทียบกับ READ UNCOMMITTED) */
    public T1SearchProduct withIsolation(int level) {
        this.isolationLevel = level;
        return this;
    }

    /** ค้นหาสินค้าที่ชื่อขึ้นต้นด้วย namePrefix (prefix search จึงใช้ index IX_product_product_name ได้) */
    public List<StockInfo> search(String namePrefix) throws SQLException {
        try (Connection conn = DBConnection.open(AppLogin.WEBSHOP_APP)) {
            conn.setAutoCommit(false);                       // เริ่ม Transaction เอง
            conn.setTransactionIsolation(isolationLevel);    // READ COMMITTED
            try (PreparedStatement ps = conn.prepareStatement(SQL_SEARCH)) {
                ps.setString(1, escapeLike(namePrefix) + "%");   // ค่าจากผู้ใช้ส่งเป็นพารามิเตอร์ กัน SQL Injection
                List<StockInfo> result = new ArrayList<>();
                try (ResultSet rs = ps.executeQuery()) {
                    while (rs.next()) {
                        result.add(new StockInfo(
                                rs.getString("SKU"),
                                rs.getString("UPC"),
                                rs.getString("product_name"),
                                rs.getString("size"),
                                rs.getString("color"),
                                rs.getString("location_type"),
                                TxHelper.getNullableInt(rs, "store_numb"),
                                rs.getString("dept_name"),
                                TxHelper.getNullableInt(rs, "warehouse_id"),
                                rs.getString("city"),
                                rs.getString("state_code"),
                                rs.getInt("number_on_hand"),
                                rs.getBigDecimal("retail_price"),
                                rs.getBigDecimal("discount_percent"),
                                rs.getBigDecimal("sale_price")));
                    }
                }
                conn.commit();                               // อ่านเสร็จ -> จบ Transaction
                return result;
            } catch (SQLException | RuntimeException e) {
                TxHelper.rollbackQuietly(conn, e);
                throw e;
            }
        }
    }

    /** ให้ % _ [ ที่ผู้ใช้พิมพ์มา เป็นตัวอักษรธรรมดา ไม่ใช่ wildcard ของ LIKE */
    static String escapeLike(String text) {
        return text.replace("[", "[[]").replace("%", "[%]").replace("_", "[_]");
    }
}
