package smartmart.test;

import smartmart.db.AppLogin;
import smartmart.db.DBConnection;
import smartmart.tx.T2TransferStock;

/** ทดสอบ T2 โอนสต็อก Warehouse -> Store : Run As > Java Application */
public final class TestT2TransferStock {

    private static final AppLogin APP = AppLogin.WAREHOUSE_APP;
    private static final String FROM = "W1-T2-01";   // Zip Hoodie L Gray ในคลัง 1
    private static final String TO = "S1-T2-01";     // สินค้าเดียวกันในสาขา 1 แผนก Clothing

    public static void main(String[] args) throws Exception {
        run();
        Check.summary();
    }

    public static void run() throws Exception {
        Check.title("TEST T2 : Transfer stock warehouse -> store   (login = " + DBConnection.userOf(APP)
                + ", isolation = REPEATABLE READ)");

        Check.step("Setup: reset test stock " + FROM + " = 10, " + TO + " = 5");
        TestSupport.setStock(APP, FROM, 10);
        TestSupport.setStock(APP, TO, 5);

        Check.step("Case 1: transfer 3 units -> both sides updated -> COMMIT");
        int left = new T2TransferStock().transfer(FROM, TO, 3);
        Check.info("transfer() returned warehouse on hand = " + left);
        Check.equal(7, TestSupport.stockOf(APP, FROM), "warehouse " + FROM);
        Check.equal(8, TestSupport.stockOf(APP, TO), "store " + TO);

        Check.step("Case 2: transfer 100 units (not enough stock) -> ROLLBACK");
        Check.expectFailure("transfer is rejected", () -> new T2TransferStock().transfer(FROM, TO, 100));
        Check.equal(7, TestSupport.stockOf(APP, FROM), "warehouse " + FROM + " unchanged");
        Check.equal(8, TestSupport.stockOf(APP, TO), "store " + TO + " unchanged");

        Check.step("Case 3: destination SKU does not exist -> warehouse UPDATE already ran, must be ROLLED BACK");
        Check.expectFailure("transfer to S1-NOT-EXIST fails", () -> new T2TransferStock().transfer(FROM, "S1-NOT-EXIST", 2));
        Check.equal(7, TestSupport.stockOf(APP, FROM), "warehouse " + FROM + " back to 7 (the decrease was rolled back)");

        Check.step("Case 4: destination is a different product (S1-2-0001 = T-Shirt) -> ROLLBACK");
        int tshirtBefore = TestSupport.stockOf(APP, "S1-2-0001");
        Check.expectFailure("transfer to a different product fails", () -> new T2TransferStock().transfer(FROM, "S1-2-0001", 2));
        Check.equal(7, TestSupport.stockOf(APP, FROM), "warehouse " + FROM + " unchanged");
        Check.equal(tshirtBefore, TestSupport.stockOf(APP, "S1-2-0001"), "store S1-2-0001 unchanged");
    }
}
