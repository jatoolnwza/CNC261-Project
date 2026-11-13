package smartmart.test;

import java.math.BigDecimal;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.time.LocalTime;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.atomic.AtomicReference;

import smartmart.db.AppLogin;
import smartmart.db.DBConnection;
import smartmart.model.StockInfo;
import smartmart.tx.T1SearchProduct;
import smartmart.tx.TxHelper;

/**
 * DEMO ปัญหา DIRTY READ กับ T1 และวิธีแก้ด้วย READ COMMITTED
 *
 * เหตุการณ์ : ฝ่ายสินค้า (pm1) แก้ราคา S1-T3-01 เป็น 9999.99 แต่ยังไม่ commit แล้วสุดท้าย rollback
 *            ระหว่างนั้นเว็บ (login_app_webshop) ค้นหาสินค้าด้วย T1
 * รอบ 1 : T1 ใช้ READ UNCOMMITTED -> เห็น 9999.99 ซึ่งเป็นราคาที่ไม่เคยถูกบันทึกจริง (Dirty Read)
 * รอบ 2 : T1 ใช้ READ COMMITTED   -> รอจน pm1 จบ แล้วเห็นราคาจริง 59.99 (ไม่เกิด Dirty Read)
 */
public final class DemoDirtyRead {

    private static final String SKU = "S1-T3-01";
    private static final BigDecimal UNCOMMITTED_PRICE = new BigDecimal("9999.99");

    public static void main(String[] args) throws Exception {
        Check.title("DEMO 1 : DIRTY READ  (T1 search vs. an uncommitted price change)");
        Check.info("Writer (pm1)              : UPDATE retail_price of " + SKU + " = 9999.99, wait 3 s, ROLLBACK");
        Check.info("Reader (login_app_webshop): T1 search \"Running\" while the writer has NOT committed");

        BigDecimal seenWithReadUncommitted = runRound(Connection.TRANSACTION_READ_UNCOMMITTED);
        BigDecimal committedPrice = TestSupport.queryDecimal(AppLogin.WEBSHOP_APP,
                "SELECT retail_price FROM dbo.product_stocked WHERE SKU = ?", SKU);
        Check.info("Committed price in the database after the writer rolled back = " + committedPrice);
        Check.that(seenWithReadUncommitted != null && seenWithReadUncommitted.compareTo(UNCOMMITTED_PRICE) == 0,
                "PROBLEM SHOWN - READ UNCOMMITTED: T1 showed " + seenWithReadUncommitted
                        + " to the customer, a price that never existed (DIRTY READ)");

        BigDecimal seenWithReadCommitted = runRound(Connection.TRANSACTION_READ_COMMITTED);
        Check.that(seenWithReadCommitted != null && seenWithReadCommitted.compareTo(committedPrice) == 0,
                "FIXED - READ COMMITTED: T1 showed " + seenWithReadCommitted + " = committed data only");
        Check.summary();
    }

    private static BigDecimal runRound(int isolation) throws Exception {
        Check.step("Round: T1 isolation = " + TxHelper.isolationName(isolation));
        CountDownLatch priceChanged = new CountDownLatch(1);
        AtomicReference<Exception> writerError = new AtomicReference<>();

        Thread writer = new Thread(() -> {
            try (Connection conn = DBConnection.open(AppLogin.PRODUCT_MANAGER)) {
                conn.setAutoCommit(false);
                try (PreparedStatement ps = conn.prepareStatement(
                        "UPDATE dbo.product_stocked SET retail_price = ? WHERE SKU = ?")) {
                    ps.setBigDecimal(1, UNCOMMITTED_PRICE);
                    ps.setString(2, SKU);
                    ps.executeUpdate();
                }
                log("writer : price set to 9999.99 (NOT committed yet)");
                priceChanged.countDown();
                TxHelper.pause(3000);
                conn.rollback();
                log("writer : ROLLBACK -> price goes back to the old value");
            } catch (Exception e) {
                writerError.set(e);
                priceChanged.countDown();
            }
        }, "writer");
        writer.start();
        priceChanged.await();
        if (writerError.get() != null) {
            throw writerError.get();
        }

        log("reader : T1 search starts");
        long started = System.currentTimeMillis();
        List<StockInfo> rows = new T1SearchProduct().withIsolation(isolation).search("Running");
        long waited = System.currentTimeMillis() - started;
        BigDecimal seen = null;
        for (StockInfo row : rows) {
            if (SKU.equals(row.sku)) {
                seen = row.retailPrice;
            }
        }
        log("reader : T1 finished after " + waited + " ms, price of " + SKU + " = " + seen);
        writer.join();
        if (writerError.get() != null) {
            throw writerError.get();
        }
        return seen;
    }

    static void log(String message) {
        System.out.println("    " + LocalTime.now().truncatedTo(ChronoUnit.MILLIS) + "  " + message);
    }
}
