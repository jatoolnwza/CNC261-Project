package smartmart.test;

import java.math.BigDecimal;
import java.sql.Connection;
import java.time.LocalDate;

import smartmart.db.AppLogin;
import smartmart.tx.T8CreatePromotion;
import smartmart.tx.TxHelper;

/**
 * DEMO ปัญหา PHANTOM READ กับ T8 และวิธีแก้ด้วย SERIALIZABLE
 *
 * เหตุการณ์ : ฝ่ายสินค้า 2 คนสร้างโปรของ Steel Water Bottle "พร้อมกัน" ช่วงวันที่ทับกัน
 *            A = 2031-05-01..05-10   B = 2031-05-05..05-15
 * รอบ 1 : READ COMMITTED -> ทั้งคู่ SELECT แล้วไม่เจอโปรที่ทับ จึง INSERT ทั้งคู่ = โปรซ้อน 2 อัน (Phantom)
 * รอบ 2 : SERIALIZABLE   -> key-range lock กันการ INSERT เข้าช่วงที่อีกคนอ่านไว้ คนหนึ่งเป็น deadlock victim
 *                           รันใหม่แล้วเจอโปรของอีกคน จึงถูกปฏิเสธ เหลือ 1 อัน
 */
public final class DemoPhantom {

    private static final AppLogin APP = AppLogin.PRODUCT_MANAGER;
    private static final String UPC = "099000000005";
    private static final LocalDate FROM_2031 = LocalDate.of(2031, 1, 1);

    public static void main(String[] args) throws Exception {
        Check.title("DEMO 3 : PHANTOM READ  (two T8 'create promotion' at the same time)");
        Check.info("Manager A: 2031-05-01 .. 2031-05-10    Manager B: 2031-05-05 .. 2031-05-15  (they overlap)");
        Check.info("Correct result: only ONE of them is saved");

        int rc = runRound(Connection.TRANSACTION_READ_COMMITTED);
        Check.that(rc == 2, "PROBLEM SHOWN - READ COMMITTED: " + rc
                + " overlapping promotions were saved (each check missed the other's new row = PHANTOM)");

        int ser = runRound(Connection.TRANSACTION_SERIALIZABLE);
        Check.that(ser == 1, "FIXED - SERIALIZABLE: " + ser + " promotion saved, the other was rejected");

        cleanUp();
        Check.summary();
    }

    private static int runRound(int isolation) throws Exception {
        Check.step("Round: T8 isolation = " + TxHelper.isolationName(isolation));
        cleanUp();
        Thread a = worker("manager-A", isolation, LocalDate.of(2031, 5, 1), LocalDate.of(2031, 5, 10));
        Thread b = worker("manager-B", isolation, LocalDate.of(2031, 5, 5), LocalDate.of(2031, 5, 15));
        a.start();
        b.start();
        a.join();
        b.join();
        int saved = TestSupport.queryInt(APP,
                "SELECT COUNT(*) FROM dbo.sales_promotion WHERE UPC = ? AND promotion_start_date >= ?", UPC, FROM_2031);
        Check.info("Promotions saved for May 2031 = " + saved);
        return saved;
    }

    private static Thread worker(String name, int isolation, LocalDate start, LocalDate end) {
        return new Thread(() -> {
            try {
                DemoDirtyRead.log(name + " : T8 checks overlap, waits 2 s, then inserts " + start + ".." + end);
                new T8CreatePromotion()
                        .withIsolation(isolation)
                        .withPauseAfterCheck(2000)
                        .create(UPC, start, end, 1, "Demo " + name, new BigDecimal("10"));
                DemoDirtyRead.log(name + " : COMMIT");
            } catch (Exception e) {
                DemoDirtyRead.log(name + " : REJECTED -> " + e.getMessage());
            }
        }, name);
    }

    private static void cleanUp() throws Exception {
        TestSupport.execute(APP, "DELETE FROM dbo.sales_promotion WHERE UPC = ? AND promotion_start_date >= ?", UPC, FROM_2031);
    }
}
