package smartmart.tx;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.Objects;

import smartmart.db.AppLogin;
import smartmart.db.DBConnection;

/**
 * T2 : โอนสต็อกสินค้าจาก Warehouse ไปยัง Store
 *      ลด number_on_hand ที่คลัง และเพิ่มที่สาขา ต้องสำเร็จพร้อมกันทั้งสองฝั่ง
 *      ถ้าฝั่งใดล้มเหลว ต้อง rollback ทั้งหมด (Atomicity)
 *
 * ผู้ใช้        : ระบบคลังสินค้า (login_app_warehouse)
 * Isolation    : REPEATABLE READ
 * เหตุผล       : โปรแกรมอ่าน number_on_hand มาคำนวณค่าใหม่แล้วเขียนกลับ ถ้าใช้ READ COMMITTED
 *                แล้วมี 2 คนโอนพร้อมกัน ทั้งคู่จะอ่านได้ค่าเดิม (เช่น 10) แล้วต่างคนต่างเขียน 7
 *                = Lost Update ซึ่งเกิดจาก Non-Repeatable Read
 *                REPEATABLE READ ล็อกแถวที่อ่านไว้จนจบ Transaction คนที่สองจึงแก้ทับไม่ได้
 *                (SQL Server จะเลือกฝั่งหนึ่งเป็น deadlock victim แล้วโค้ดนี้จะรันใหม่ให้อัตโนมัติ)
 */
public class T2TransferStock {

    private static final String SQL_READ_STOCK =
            "SELECT UPC, size, color, in_store, number_on_hand FROM dbo.product_stocked WHERE SKU = ?";
    private static final String SQL_SET_ON_HAND =
            "UPDATE dbo.product_stocked SET number_on_hand = ? WHERE SKU = ?";

    private int isolationLevel = Connection.TRANSACTION_REPEATABLE_READ;
    private long pauseAfterReadMs = 0;
    private int maxAttempts = 3;

    public T2TransferStock withIsolation(int level) {
        this.isolationLevel = level;
        return this;
    }

    /** ใช้เฉพาะตอน Demo : หยุดรอหลังอ่านสต็อก เพื่อให้อีก Transaction เข้ามาทำงานซ้อน */
    public T2TransferStock withPauseAfterRead(long millis) {
        this.pauseAfterReadMs = millis;
        return this;
    }

    /**
     * โอนสินค้า qty ชิ้น จาก fromSku (ในคลัง) ไป toSku (ในสาขา)
     * @return จำนวนคงเหลือที่คลังต้นทางหลังโอน
     */
    public int transfer(String fromSku, String toSku, int qty) throws SQLException, BusinessRuleException {
        if (qty <= 0) {
            throw new BusinessRuleException("Quantity must be greater than 0");
        }
        if (fromSku.equals(toSku)) {
            throw new BusinessRuleException("Source and destination SKU must be different");
        }
        return TxHelper.runWithDeadlockRetry(maxAttempts, attempt -> transferOnce(fromSku, toSku, qty));
    }

    private int transferOnce(String fromSku, String toSku, int qty) throws SQLException, BusinessRuleException {
        try (Connection conn = DBConnection.open(AppLogin.WAREHOUSE_APP)) {
            conn.setAutoCommit(false);                       // 1 Transaction = หลายคำสั่ง
            conn.setTransactionIsolation(isolationLevel);    // REPEATABLE READ
            try (PreparedStatement psRead = conn.prepareStatement(SQL_READ_STOCK);
                 PreparedStatement psSet = conn.prepareStatement(SQL_SET_ON_HAND)) {

                // (1) SELECT สต็อกต้นทาง : ต้องอยู่ในคลัง และมีของพอ
                StockRow from = readRow(psRead, fromSku);
                if (from == null) {
                    throw new BusinessRuleException("Source SKU " + fromSku + " not found");
                }
                if (from.inStore) {
                    throw new BusinessRuleException("Source SKU " + fromSku + " is not in a warehouse");
                }
                if (from.onHand < qty) {
                    throw new BusinessRuleException("Not enough stock at " + fromSku
                            + ": on hand " + from.onHand + ", requested " + qty);
                }

                TxHelper.pause(pauseAfterReadMs);            // (Demo เท่านั้น)

                // (2) UPDATE ลดสต็อกที่คลัง ด้วยค่าที่คำนวณจากข้อ (1)
                setOnHand(psSet, fromSku, from.onHand - qty);

                // (3) SELECT สต็อกปลายทาง : ต้องอยู่ในสาขา และเป็นสินค้าเดียวกัน (UPC/size/color)
                StockRow to = readRow(psRead, toSku);
                if (to == null) {
                    throw new BusinessRuleException("Destination SKU " + toSku + " not found");
                }
                if (!to.inStore) {
                    throw new BusinessRuleException("Destination SKU " + toSku + " is not in a store");
                }
                if (!from.sameItemAs(to)) {
                    throw new BusinessRuleException("Destination SKU " + toSku
                            + " is a different item (UPC/size/color) from " + fromSku);
                }

                // (4) UPDATE เพิ่มสต็อกที่สาขา
                setOnHand(psSet, toSku, to.onHand + qty);

                conn.commit();                               // สำเร็จทั้งสองฝั่ง -> บันทึกพร้อมกัน
                return from.onHand - qty;

            } catch (SQLException | BusinessRuleException | RuntimeException e) {
                TxHelper.rollbackQuietly(conn, e);           // ล้มเหลวฝั่งใด -> ยกเลิกทั้งหมด
                throw e;
            }
        }
    }

    private static StockRow readRow(PreparedStatement ps, String sku) throws SQLException {
        ps.setString(1, sku);
        try (ResultSet rs = ps.executeQuery()) {
            if (!rs.next()) {
                return null;
            }
            return new StockRow(rs.getString("UPC"), rs.getString("size"), rs.getString("color"),
                    rs.getBoolean("in_store"), rs.getInt("number_on_hand"));
        }
    }

    private static void setOnHand(PreparedStatement ps, String sku, int newOnHand) throws SQLException {
        ps.setInt(1, newOnHand);
        ps.setString(2, sku);
        int rows = ps.executeUpdate();
        if (rows != 1) {
            throw new SQLException("Expected to update 1 row for SKU " + sku + " but updated " + rows);
        }
    }

    /** ข้อมูลสต็อก 1 แถวที่อ่านมา */
    private static final class StockRow {
        final String upc;
        final String size;
        final String color;
        final boolean inStore;
        final int onHand;

        StockRow(String upc, String size, String color, boolean inStore, int onHand) {
            this.upc = upc;
            this.size = size;
            this.color = color;
            this.inStore = inStore;
            this.onHand = onHand;
        }

        boolean sameItemAs(StockRow other) {
            return upc.equals(other.upc) && Objects.equals(size, other.size) && Objects.equals(color, other.color);
        }
    }
}
