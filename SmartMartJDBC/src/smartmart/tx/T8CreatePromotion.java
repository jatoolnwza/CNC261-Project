package smartmart.tx;

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
 * T8 : สร้างโปรโมชันให้สินค้า ตรวจว่าสินค้านั้นไม่มีโปรโมชันอื่นที่ช่วงวันที่ทับกันอยู่ก่อน แล้วจึงบันทึก
 *      แก้ไขส่วนลด/รายละเอียดของโปรโมชัน (คูปอง) ที่มีอยู่แล้ว และยกเลิกโปรโมชันที่ยังไม่เริ่ม
 *
 * ผู้ใช้        : ฝ่ายสินค้า (pm1 ใน role_product_manager)
 * Isolation    : SERIALIZABLE (create) / ค่าที่ตั้งผ่าน withIsolation() (update)
 * เหตุผล       : การตรวจ "ไม่มีแถวที่ช่วงวันที่ทับกัน" เป็นการอ่านช่วงของแถว (range)
 *                ถ้าใช้ READ COMMITTED หรือ REPEATABLE READ แล้วมี 2 คนสร้างโปรของสินค้าเดียวกันพร้อมกัน
 *                ทั้งคู่จะ SELECT ไม่เจอแถวที่ทับ แล้ว INSERT ทั้งคู่ = Phantom Read -> โปรซ้อนกัน 2 อัน
 *                SERIALIZABLE ล็อกช่วงของ key ที่อ่าน คนที่สองจึง INSERT แถวใหม่เข้าช่วงนั้นไม่ได้
 *
 * การทับซ้อนของงานตอนแก้ไขคูปอง (ดูรายละเอียดที่เมธอด update) : ขณะที่แอดมินกำลังแก้ไขส่วนลดของโปรโมชัน
 * UPDATE จะล็อกแถวนั้นไว้จนกว่าจะ commit เสร็จ ลูกค้าที่พยายามอ่านส่วนลดไปใช้ตอนเช็คเอาท์ในเวลาเดียวกัน
 * จะถูกบล็อกให้รอโดยอัตโนมัติ จึงรับประกันได้ว่าคูปองจะใช้งานได้ก็ต่อเมื่อแก้ไขเสร็จสมบูรณ์แล้วเท่านั้น
 */
public class T8CreatePromotion {

    private static final String SQL_PRODUCT_EXISTS =
            "SELECT COUNT(*) FROM dbo.product WHERE UPC = ?";
    private static final String SQL_OVERLAPS =
            "SELECT COUNT(*) FROM dbo.sales_promotion "
            + "WHERE UPC = ? AND promotion_start_date <= ? AND promotion_end_date >= ?";
    private static final String SQL_INSERT =
            "INSERT INTO dbo.sales_promotion (UPC, promotion_start_date, promotion_end_date, promotion_type_code, "
            + "promotion_details, discount_percent) VALUES (?, ?, ?, ?, ?, ?)";
    private static final String SQL_CANCEL_NOT_STARTED =
            "DELETE FROM dbo.sales_promotion WHERE UPC = ? AND promotion_start_date = ? AND promotion_start_date > ?";
    private static final String SQL_UPDATE_DISCOUNT =
            "UPDATE dbo.sales_promotion SET discount_percent = ?, promotion_details = ? "
            + "WHERE UPC = ? AND promotion_start_date = ?";

    private int isolationLevel = Connection.TRANSACTION_SERIALIZABLE;
    private long pauseAfterCheckMs = 0;
    private long pauseBeforeCommitMs = 0;
    private int maxAttempts = 3;

    public T8CreatePromotion withIsolation(int level) {
        this.isolationLevel = level;
        return this;
    }

    /** ใช้เฉพาะตอน Demo : หยุดรอหลังตรวจช่วงวันที่ เพื่อให้อีก Transaction เข้ามาทำงานซ้อน */
    public T8CreatePromotion withPauseAfterCheck(long millis) {
        this.pauseAfterCheckMs = millis;
        return this;
    }

    /** ใช้เฉพาะตอน Demo : หยุดรอหลัง UPDATE ก่อน commit เพื่อจำลองว่าแอดมินกำลังตรวจทานส่วนลดใหม่อยู่ */
    public T8CreatePromotion withPauseBeforeCommit(long millis) {
        this.pauseBeforeCommitMs = millis;
        return this;
    }

    public void create(String upc, LocalDate start, LocalDate end, int promotionTypeCode,
                       String details, BigDecimal discountPercent) throws SQLException, BusinessRuleException {
        if (end.isBefore(start)) {
            throw new BusinessRuleException("End date " + end + " is before start date " + start);
        }
        if (discountPercent.signum() <= 0 || discountPercent.compareTo(new BigDecimal("100")) > 0) {
            throw new BusinessRuleException("Discount must be between 0 and 100 percent");
        }
        TxHelper.runWithDeadlockRetry(maxAttempts, attempt -> {
            createOnce(upc, start, end, promotionTypeCode, details, discountPercent);
            return null;
        });
    }

    private void createOnce(String upc, LocalDate start, LocalDate end, int promotionTypeCode,
                            String details, BigDecimal discountPercent) throws SQLException, BusinessRuleException {
        try (Connection conn = DBConnection.open(AppLogin.PRODUCT_MANAGER)) {
            conn.setAutoCommit(false);
            conn.setTransactionIsolation(isolationLevel);    // SERIALIZABLE
            try (PreparedStatement psProduct = conn.prepareStatement(SQL_PRODUCT_EXISTS);
                 PreparedStatement psOverlap = conn.prepareStatement(SQL_OVERLAPS);
                 PreparedStatement psInsert = conn.prepareStatement(SQL_INSERT)) {

                // (1) SELECT สินค้าต้องมีอยู่จริง
                psProduct.setString(1, upc);
                try (ResultSet rs = psProduct.executeQuery()) {
                    rs.next();
                    if (rs.getInt(1) == 0) {
                        throw new BusinessRuleException("Product UPC " + upc + " not found");
                    }
                }

                // (2) SELECT มีโปรเดิมที่ช่วงวันที่ทับกันไหม (ทับ = start เดิม <= end ใหม่ และ end เดิม >= start ใหม่)
                psOverlap.setString(1, upc);
                psOverlap.setDate(2, Date.valueOf(end));
                psOverlap.setDate(3, Date.valueOf(start));
                try (ResultSet rs = psOverlap.executeQuery()) {
                    rs.next();
                    int overlapping = rs.getInt(1);
                    if (overlapping > 0) {
                        throw new BusinessRuleException("Promotion " + start + ".." + end + " overlaps "
                                + overlapping + " existing promotion(s) of UPC " + upc);
                    }
                }

                TxHelper.pause(pauseAfterCheckMs);           // (Demo เท่านั้น)

                // (3) INSERT โปรโมชันใหม่
                psInsert.setString(1, upc);
                psInsert.setDate(2, Date.valueOf(start));
                psInsert.setDate(3, Date.valueOf(end));
                psInsert.setInt(4, promotionTypeCode);
                psInsert.setString(5, details);
                psInsert.setBigDecimal(6, discountPercent);
                psInsert.executeUpdate();

                conn.commit();
            } catch (SQLException | BusinessRuleException | RuntimeException e) {
                TxHelper.rollbackQuietly(conn, e);
                throw e;
            }
        }
    }

    /**
     * แก้ไขส่วนลด/รายละเอียดของโปรโมชัน (คูปอง) ที่มีอยู่แล้ว
     *
     * การทับซ้อนของงาน (Concurrency Control) : UPDATE จะล็อกแถวนี้แบบ exclusive (X lock) ทันที
     * และถือล็อกไว้จนกว่าจะ commit หรือ rollback เสร็จ ไม่ว่า Transaction อื่นจะใช้ Isolation Level ใดก็ตาม
     * ธุรกรรมอื่นที่พยายาม SELECT แถวเดียวกัน (เช่น ลูกค้าอ่านส่วนลดตอนเช็คเอาท์ใน Pricing.activeDiscount)
     * จะถูก "บล็อกให้รอ" โดยอัตโนมัติจนกว่า Transaction นี้จะจบ จึงไม่มีทางอ่านเจอค่าส่วนลดที่แก้ไขค้างอยู่ครึ่งเดียว
     * (กัน Dirty Read) และรับประกันว่าลูกค้าจะ "ใช้คูปองได้ก็ต่อเมื่อแอดมินอัปเดตเสร็จสมบูรณ์แล้วเท่านั้น"
     *
     * @return true = แก้ไขสำเร็จ, false = ไม่พบโปรโมชันที่ระบุ
     */
    public boolean update(String upc, LocalDate promotionStartDate, BigDecimal newDiscountPercent, String newDetails)
            throws SQLException, BusinessRuleException {
        if (newDiscountPercent.signum() <= 0 || newDiscountPercent.compareTo(new BigDecimal("100")) > 0) {
            throw new BusinessRuleException("Discount must be between 0 and 100 percent");
        }
        return TxHelper.runWithDeadlockRetry(maxAttempts,
                attempt -> updateOnce(upc, promotionStartDate, newDiscountPercent, newDetails));
    }

    private boolean updateOnce(String upc, LocalDate promotionStartDate, BigDecimal newDiscountPercent,
                               String newDetails) throws SQLException {
        try (Connection conn = DBConnection.open(AppLogin.PRODUCT_MANAGER)) {
            conn.setAutoCommit(false);
            conn.setTransactionIsolation(isolationLevel);
            try (PreparedStatement psUpdate = conn.prepareStatement(SQL_UPDATE_DISCOUNT)) {

                // (1) UPDATE -> SQL Server ล็อกแถวนี้ทันที (X lock) ไม่ว่าใครจะมาอ่านก็ต้องรอ
                psUpdate.setBigDecimal(1, newDiscountPercent);
                psUpdate.setString(2, newDetails);
                psUpdate.setString(3, upc);
                psUpdate.setDate(4, Date.valueOf(promotionStartDate));
                int rows = psUpdate.executeUpdate();
                if (rows == 0) {
                    conn.commit();
                    return false;
                }

                // (2) หน่วงเวลา (Demo เท่านั้น) จำลองว่าแอดมินกำลังตรวจทานก่อนกดยืนยัน
                //     ระหว่างนี้ลูกค้าที่พยายามอ่านส่วนลดของโปรนี้จะถูกบล็อกรออยู่ที่ SELECT
                TxHelper.pause(pauseBeforeCommitMs);

                conn.commit();   // ปล่อยล็อก -> ธุรกรรมที่รอค้างอยู่อ่านค่าใหม่ได้ทันที
                return true;
            } catch (SQLException | RuntimeException e) {
                TxHelper.rollbackQuietly(conn, e);
                throw e;
            }
        }
    }

    /**
     * DELETE โปรโมชันที่ยังไม่เริ่ม (วันเริ่ม > วันนี้) เท่านั้น
     * @return true = ยกเลิกสำเร็จ, false = ไม่พบ หรือโปรเริ่มไปแล้ว
     */
    public boolean cancelIfNotStarted(String upc, LocalDate start) throws SQLException {
        try (Connection conn = DBConnection.open(AppLogin.PRODUCT_MANAGER)) {
            conn.setAutoCommit(false);
            conn.setTransactionIsolation(Connection.TRANSACTION_READ_COMMITTED);
            try (PreparedStatement ps = conn.prepareStatement(SQL_CANCEL_NOT_STARTED)) {
                ps.setString(1, upc);
                ps.setDate(2, Date.valueOf(start));
                ps.setDate(3, Date.valueOf(LocalDate.now()));
                int rows = ps.executeUpdate();
                conn.commit();
                return rows == 1;
            } catch (SQLException | RuntimeException e) {
                TxHelper.rollbackQuietly(conn, e);
                throw e;
            }
        }
    }
}
