package smartmart.test;

import java.math.BigDecimal;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.time.LocalDate;
import java.util.concurrent.atomic.AtomicReference;

import smartmart.db.AppLogin;
import smartmart.db.DBConnection;
import smartmart.tx.T8CreatePromotion;

/**
 * DEMO 5 : การทับซ้อนของงานตอนแก้ไขคูปอง (โปรโมชัน)
 *          "ถ้ากำลังอัปเดตคูปอง ลูกค้าต้องอ่าน/ใช้ไม่ได้ จนกว่าจะอัปเดตเสร็จ (commit) ก่อน"
 *
 * เหตุการณ์ : แอดมิน (pm1) แก้ส่วนลดของ Steel Water Bottle จาก 15% เป็น 30%
 *            ใช้เวลาตรวจทาน 3 วินาทีก่อนกด commit จริง
 *            ระหว่างนั้นลูกค้า (login_app_webshop) พยายามอ่านส่วนลดของสินค้าชิ้นเดียวกันตอนเช็คเอาท์
 *
 * รอบ 1 (ปัญหา) : ถ้าฝั่งลูกค้าอ่านด้วย WITH (NOLOCK) จะไม่รอเลย และอาจเห็นค่าที่ยังไม่ commit จริง (Dirty Read)
 * รอบ 2 (แก้แล้ว) : อ่านด้วยวิธีปกติ (ไม่ใช้ NOLOCK) ธุรกรรมของลูกค้าจะถูก "บล็อกให้รอ" โดยอัตโนมัติ
 *                  จนกว่าแอดมินจะ commit เสร็จ แล้วจึงเห็นค่าส่วนลดใหม่ที่ถูกต้องเสมอ ไม่มีทางเห็นค่ากลางๆ
 */
public final class DemoPromotionLock {

    private static final String UPC = "099000000005";
    private static final LocalDate START = LocalDate.of(2027, 6, 1);
    private static final LocalDate END = LocalDate.of(2027, 6, 30);
    private static final BigDecimal OLD_DISCOUNT = new BigDecimal("15.00");
    private static final BigDecimal NEW_DISCOUNT = new BigDecimal("30.00");

    public static void main(String[] args) throws Exception {
        Check.title("DEMO 5 : แก้ไขคูปอง (T8 update) -> ลูกค้าต้องรอจนอัปเดตเสร็จก่อนถึงจะใช้ได้");
        Check.info("Admin (pm1): แก้ discount_percent ของ " + UPC + " จาก " + OLD_DISCOUNT + "% เป็น " + NEW_DISCOUNT
                + "% ใช้เวลาตรวจทาน 3 วิก่อน commit");
        Check.info("Customer (login_app_webshop): อ่านส่วนลดของสินค้าเดียวกันตอนเช็คเอาท์ระหว่างที่แอดมินกำลังแก้");

        runRound(true);   // รอบ 1 : อ่านแบบ NOLOCK (ปัญหา)
        runRound(false);  // รอบ 2 : อ่านแบบปกติ (แก้แล้ว)

        Check.summary();
    }

    private static void runRound(boolean customerUsesNolock) throws Exception {
        String mode = customerUsesNolock ? "WITH (NOLOCK)" : "ปกติ (ไม่ใช้ NOLOCK)";
        Check.step("Round: ลูกค้าอ่านส่วนลดแบบ " + mode);
        resetPromotion();

        AtomicReference<Exception> adminError = new AtomicReference<>();

        Thread admin = new Thread(() -> {
            try {
                log("admin  : เริ่มแก้ไขส่วนลดเป็น " + NEW_DISCOUNT + "% (ยังไม่ commit)");
                new T8CreatePromotion()
                        .withPauseBeforeCommit(3000)
                        .update(UPC, START, NEW_DISCOUNT, "Flash Sale!");
                log("admin  : COMMIT แล้ว (แก้ไขเสร็จสมบูรณ์)");
            } catch (Exception e) {
                adminError.set(e);
            }
        }, "admin");

        admin.start();
        smartmart.tx.TxHelper.pause(400); // ให้แอดมิน UPDATE ไปก่อนแน่ๆ แล้วค่อยให้ลูกค้าเริ่มอ่าน

        log("customer: เริ่มอ่านส่วนลดตอนเช็คเอาท์ (" + mode + ")");
        long startedAt = System.currentTimeMillis();
        BigDecimal seenByCustomer = readDiscount(customerUsesNolock);
        long waitedMs = System.currentTimeMillis() - startedAt;
        log("customer: อ่านเสร็จหลังรอ " + waitedMs + " ms, เห็นส่วนลด = " + seenByCustomer + "%");

        admin.join();
        if (adminError.get() != null) {
            throw adminError.get();
        }

        if (customerUsesNolock) {
            Check.that(waitedMs < 1000,
                    "PROBLEM SHOWN - NOLOCK: ลูกค้าไม่ต้องรอเลย (" + waitedMs
                            + " ms) อาจได้ค่าที่ยังไม่ commit จริง -> เสี่ยง Dirty Read");
        } else {
            Check.that(waitedMs >= 2000,
                    "FIXED - ไม่ใช้ NOLOCK: ลูกค้าถูกบล็อกให้รอจริง (" + waitedMs
                            + " ms) จนกว่าแอดมินจะ commit เสร็จก่อน");
            Check.money("30.00", seenByCustomer, "ลูกค้าเห็นส่วนลดใหม่ที่ถูกต้องหลังรอ");
        }
    }

    /** อ่านส่วนลดของ UPC ด้วย Login ของเว็บขายออนไลน์ เหมือนตอนเช็คเอาท์จริงใน T6/Pricing.activeDiscount */
    private static BigDecimal readDiscount(boolean useNolock) throws Exception {
        String hint = useNolock ? " WITH (NOLOCK) " : " ";
        String sql = "SELECT discount_percent FROM dbo.sales_promotion" + hint
                + "WHERE UPC = ? AND promotion_start_date = ?";
        try (Connection conn = DBConnection.open(AppLogin.WEBSHOP_APP);
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setString(1, UPC);
            ps.setDate(2, java.sql.Date.valueOf(START));
            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() ? rs.getBigDecimal(1) : null;
            }
        }
    }

    /** ลบโปรเก่าของ UPC/START นี้ทิ้ง แล้วสร้างใหม่ด้วยส่วนลดตั้งต้น ก่อนเริ่มแต่ละรอบ */
    private static void resetPromotion() throws Exception {
        TestSupport.execute(AppLogin.PRODUCT_MANAGER,
                "DELETE FROM dbo.sales_promotion WHERE UPC = ? AND promotion_start_date = ?", UPC, START);
        TestSupport.execute(AppLogin.PRODUCT_MANAGER,
                "INSERT INTO dbo.sales_promotion (UPC, promotion_start_date, promotion_end_date, "
                        + "promotion_type_code, promotion_details, discount_percent) VALUES (?, ?, ?, 1, ?, ?)",
                UPC, START, END, "Early Summer Sale", OLD_DISCOUNT);
    }

    private static void log(String message) {
        DemoDirtyRead.log(message);
    }
}
