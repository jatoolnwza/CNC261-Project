package smartmart.test;

import java.math.BigDecimal;
import java.time.LocalDate;

import smartmart.db.AppLogin;
import smartmart.db.DBConnection;
import smartmart.tx.T8CreatePromotion;

/** ทดสอบ T8 สร้าง/ยกเลิกโปรโมชัน : Run As > Java Application */
public final class TestT8CreatePromotion {

    private static final AppLogin APP = AppLogin.PRODUCT_MANAGER;
    private static final String UPC = "099000000005";               // Steel Water Bottle
    private static final LocalDate TEST_YEAR = LocalDate.of(2031, 1, 1);
    private static final String COUNT_TEST_PROMOS =
            "SELECT COUNT(*) FROM dbo.sales_promotion WHERE UPC = ? AND promotion_start_date >= ?";

    public static void main(String[] args) throws Exception {
        run();
        Check.summary();
    }

    public static void run() throws Exception {
        Check.title("TEST T8 : Create / cancel promotion   (login = " + DBConnection.userOf(APP)
                + ", isolation = SERIALIZABLE)");

        Check.step("Setup: delete test promotions of UPC " + UPC + " that start in 2031 or later");
        TestSupport.execute(APP, "DELETE FROM dbo.sales_promotion WHERE UPC = ? AND promotion_start_date >= ?", UPC, TEST_YEAR);

        T8CreatePromotion t8 = new T8CreatePromotion();
        Check.step("Case 1: create 2031-03-01 .. 2031-03-10 (15%) -> COMMIT");
        t8.create(UPC, LocalDate.of(2031, 3, 1), LocalDate.of(2031, 3, 10), 1, "Spring sale", new BigDecimal("15"));
        Check.equal(1, TestSupport.queryInt(APP, COUNT_TEST_PROMOS, UPC, TEST_YEAR), "test promotions");

        Check.step("Case 2: create 2031-03-05 .. 2031-03-15 -> overlaps case 1 -> ROLLBACK");
        Check.expectFailure("overlapping promotion is rejected", () -> t8.create(UPC,
                LocalDate.of(2031, 3, 5), LocalDate.of(2031, 3, 15), 1, "Overlap", new BigDecimal("20")));
        Check.equal(1, TestSupport.queryInt(APP, COUNT_TEST_PROMOS, UPC, TEST_YEAR), "test promotions");

        Check.step("Case 3: create 2031-03-11 .. 2031-03-20 -> starts the day after case 1 ends -> COMMIT");
        t8.create(UPC, LocalDate.of(2031, 3, 11), LocalDate.of(2031, 3, 20), 3, "Back-to-back sale", new BigDecimal("10"));
        Check.equal(2, TestSupport.queryInt(APP, COUNT_TEST_PROMOS, UPC, TEST_YEAR), "test promotions");

        Check.step("Case 4: cancel the 2031-03-11 promotion (not started yet) -> DELETE");
        Check.that(t8.cancelIfNotStarted(UPC, LocalDate.of(2031, 3, 11)), "cancelIfNotStarted returned true");
        Check.equal(1, TestSupport.queryInt(APP, COUNT_TEST_PROMOS, UPC, TEST_YEAR), "test promotions");

        Check.step("Case 5: try to cancel the sneakers promotion that started on 2026-01-01 -> not allowed");
        Check.that(!t8.cancelIfNotStarted("099000000002", LocalDate.of(2026, 1, 1)), "cancelIfNotStarted returned false");
        Check.equal(1, TestSupport.queryInt(APP,
                "SELECT COUNT(*) FROM dbo.sales_promotion WHERE UPC = ? AND promotion_start_date = ?",
                "099000000002", LocalDate.of(2026, 1, 1)), "started promotion still exists");

        Check.step("Case 6: unknown product / end date before start date -> rejected");
        Check.expectFailure("unknown UPC is rejected", () -> t8.create("000000000000",
                LocalDate.of(2031, 4, 1), LocalDate.of(2031, 4, 2), 1, "x", new BigDecimal("5")));
        Check.expectFailure("end before start is rejected", () -> t8.create(UPC,
                LocalDate.of(2031, 4, 10), LocalDate.of(2031, 4, 1), 1, "x", new BigDecimal("5")));

        Check.step("Case 7: update the 2031-03-01 promotion's discount from 15% to 25% -> COMMIT");
        Check.that(t8.update(UPC, LocalDate.of(2031, 3, 1), new BigDecimal("25"), "Spring sale - revised"),
                "update returned true");
        Check.money("25.00", TestSupport.queryDecimal(APP,
                "SELECT discount_percent FROM dbo.sales_promotion WHERE UPC = ? AND promotion_start_date = ?",
                UPC, LocalDate.of(2031, 3, 1)), "discount_percent after update");

        Check.step("Case 8: update a promotion that does not exist -> no rows changed");
        Check.that(!t8.update(UPC, LocalDate.of(2031, 9, 9), new BigDecimal("50"), "x"),
                "update returned false");
    }
}
