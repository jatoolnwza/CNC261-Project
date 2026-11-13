package smartmart.test;

import java.sql.Connection;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CountDownLatch;

import smartmart.db.AppLogin;
import smartmart.tx.T2TransferStock;
import smartmart.tx.TxHelper;

/**
 * DEMO ปัญหา NON-REPEATABLE READ / LOST UPDATE กับ T2 และวิธีแก้ด้วย REPEATABLE READ
 *
 * เหตุการณ์ : พนักงานคลัง 2 คนโอนสินค้า W1-T2-01 -> S1-T2-01 คนละ 3 ชิ้น "พร้อมกัน"
 *            เริ่มต้น คลัง = 10, สาขา = 5   ผลที่ถูกต้อง : คลัง = 4, สาขา = 11 (รวม 15 เท่าเดิม)
 * รอบ 1 : READ COMMITTED  -> ทั้งคู่อ่านคลังได้ 10 แล้วต่างคนต่างเขียน 7 = Lost Update (ของงอกมา 3 ชิ้น)
 * รอบ 2 : REPEATABLE READ -> แถวที่อ่านถูกล็อกจนจบ Transaction, SQL Server เลือก 1 คนเป็น deadlock victim
 *                            คนนั้น rollback แล้ว T2 รันใหม่อัตโนมัติ ได้ผลถูกต้อง 4 / 11
 */
public final class DemoLostUpdate {

    private static final AppLogin APP = AppLogin.WAREHOUSE_APP;
    private static final String FROM = "W1-T2-01";
    private static final String TO = "S1-T2-01";

    public static void main(String[] args) throws Exception {
        Check.title("DEMO 2 : LOST UPDATE / NON-REPEATABLE READ  (two T2 transfers at the same time)");
        Check.info("Start: warehouse " + FROM + " = 10, store " + TO + " = 5. Each worker moves 3 units.");
        Check.info("Correct result: warehouse = 4, store = 11, total stays 15");

        int[] rc = runRound(Connection.TRANSACTION_READ_COMMITTED);
        Check.that(rc[0] == 7 && rc[1] == 11,
                "PROBLEM SHOWN - READ COMMITTED: warehouse = " + rc[0] + ", store = " + rc[1]
                        + ", total = " + (rc[0] + rc[1]) + " -> one decrease was LOST (3 units appeared from nowhere)");

        int[] rr = runRound(Connection.TRANSACTION_REPEATABLE_READ);
        Check.that(rr[0] == 4 && rr[1] == 11,
                "FIXED - REPEATABLE READ: warehouse = " + rr[0] + ", store = " + rr[1] + ", total = " + (rr[0] + rr[1]));
        Check.summary();
    }

    private static int[] runRound(int isolation) throws Exception {
        Check.step("Round: T2 isolation = " + TxHelper.isolationName(isolation));
        TestSupport.setStock(APP, FROM, 10);
        TestSupport.setStock(APP, TO, 5);

        CountDownLatch startTogether = new CountDownLatch(1);
        List<Thread> workers = new ArrayList<>();
        for (String name : new String[] {"worker-A", "worker-B"}) {
            Thread t = new Thread(() -> {
                try {
                    startTogether.await();
                    DemoDirtyRead.log(name + " : T2 starts (reads stock, then waits 2 s before writing)");
                    int left = new T2TransferStock()
                            .withIsolation(isolation)
                            .withPauseAfterRead(2000)
                            .transfer(FROM, TO, 3);
                    DemoDirtyRead.log(name + " : COMMIT  (it believes the warehouse now has " + left + ")");
                } catch (Exception e) {
                    DemoDirtyRead.log(name + " : FAILED -> " + e.getMessage());
                }
            }, name);
            workers.add(t);
            t.start();
        }
        startTogether.countDown();
        for (Thread t : workers) {
            t.join();
        }
        int warehouse = TestSupport.stockOf(APP, FROM);
        int store = TestSupport.stockOf(APP, TO);
        Check.info("Final: warehouse = " + warehouse + ", store = " + store + ", total = " + (warehouse + store));
        return new int[] {warehouse, store};
    }
}
