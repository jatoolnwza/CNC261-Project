package smartmart.test;

import java.time.LocalDate;
import java.util.Arrays;
import java.util.Collections;

import smartmart.db.AppLogin;
import smartmart.db.DBConnection;
import smartmart.model.CardInfo;
import smartmart.model.Receipt;
import smartmart.model.SaleLine;
import smartmart.tx.T3T4InStoreSale;

/** ทดสอบ T3 (เงินสด) และ T4 (บัตรเครดิต) : Run As > Java Application */
public final class TestT3T4InStoreSale {

    private static final AppLogin APP = AppLogin.POS_APP;
    private static final String SNEAKERS = "S1-T3-01";   // 59.99 มีโปร 10% ต้องเสียภาษี CA
    private static final String MOUSE = "S1-3-0001";     // 19.99 ไม่มีโปร ต้องเสียภาษี CA

    public static void main(String[] args) throws Exception {
        run();
        Check.summary();
    }

    public static void run() throws Exception {
        Check.title("TEST T3/T4 : In-store sale at store 1 (CA, tax 7.25%)   (login = "
                + DBConnection.userOf(APP) + ", isolation = REPEATABLE READ)");

        Check.step("Setup: reset test stock " + SNEAKERS + " = 20, " + MOUSE + " = 30");
        TestSupport.setStock(APP, SNEAKERS, 20);
        TestSupport.setStock(APP, MOUSE, 30);

        Check.step("Case 1 (T3 cash): 2 x Running Sneakers + 1 x Wireless Mouse -> COMMIT");
        Receipt r1 = new T3T4InStoreSale().sellCash(1,
                Arrays.asList(new SaleLine(SNEAKERS, 2), new SaleLine(MOUSE, 1)));
        Check.info("receipt " + r1);
        Check.money("127.97", r1.subtotal, "product_total (2 x 53.99 + 19.99)");
        Check.money("9.28", r1.tax, "sales_tax (127.97 x 7.25%)");
        Check.money("137.25", r1.total, "total");
        Check.money("137.25", TestSupport.queryDecimal(APP,
                "SELECT total FROM dbo.in_store_sale WHERE transaction_numb = ?", r1.number), "total stored in in_store_sale");
        Check.equal(1, TestSupport.queryInt(APP,
                "SELECT payment_type_code FROM dbo.in_store_sale WHERE transaction_numb = ?", r1.number), "payment_type_code (1 = CASH)");
        Check.equal(2, TestSupport.queryInt(APP,
                "SELECT COUNT(*) FROM dbo.in_store_sale_item WHERE transaction_numb = ?", r1.number), "rows in in_store_sale_item");
        Check.equal(18, TestSupport.stockOf(APP, SNEAKERS), "stock " + SNEAKERS);
        Check.equal(29, TestSupport.stockOf(APP, MOUSE), "stock " + MOUSE);

        Check.step("Case 2 (T4 credit): 1 x Running Sneakers paid by card -> sale + credit_sale_details -> COMMIT");
        CardInfo card = new CardInfo("tok_test_" + System.currentTimeMillis(), "4242", LocalDate.of(2029, 12, 31), "JOHN DOE");
        Receipt r2 = new T3T4InStoreSale().sellCredit(1, Collections.singletonList(new SaleLine(SNEAKERS, 1)), card);
        Check.info("receipt " + r2);
        Check.money("57.90", r2.total, "total (53.99 + tax 3.91)");
        Check.equal(2, TestSupport.queryInt(APP,
                "SELECT payment_type_code FROM dbo.in_store_sale WHERE transaction_numb = ?", r2.number), "payment_type_code (2 = CREDIT)");
        Check.same("4242", TestSupport.queryString(APP,
                "SELECT card_last4 FROM dbo.credit_sale_details WHERE transaction_numb = ?", r2.number), "card_last4 saved");
        Check.equal(17, TestSupport.stockOf(APP, SNEAKERS), "stock " + SNEAKERS);

        Check.step("Case 3 (T4 fails at the LAST step): card_last4 = 'ABCD' violates CHECK -> whole sale ROLLED BACK");
        int billsBefore = TestSupport.queryInt(APP, "SELECT COUNT(*) FROM dbo.in_store_sale");
        CardInfo badCard = new CardInfo("tok_bad", "ABCD", LocalDate.of(2029, 12, 31), "JOHN DOE");
        Check.expectFailure("credit sale with invalid card data fails",
                () -> new T3T4InStoreSale().sellCredit(1, Collections.singletonList(new SaleLine(SNEAKERS, 1)), badCard));
        Check.equal(billsBefore, TestSupport.queryInt(APP, "SELECT COUNT(*) FROM dbo.in_store_sale"),
                "number of bills unchanged (header + items were rolled back)");
        Check.equal(17, TestSupport.stockOf(APP, SNEAKERS), "stock " + SNEAKERS + " unchanged");

        Check.step("Case 4 (T3): quantity 999 > stock -> ROLLBACK");
        Check.expectFailure("sale is rejected",
                () -> new T3T4InStoreSale().sellCash(1, Collections.singletonList(new SaleLine(SNEAKERS, 999))));
        Check.equal(17, TestSupport.stockOf(APP, SNEAKERS), "stock " + SNEAKERS + " unchanged");

        Check.step("Case 5 (T3): SKU of store 2 sold at store 1 -> ROLLBACK");
        Check.expectFailure("sale is rejected",
                () -> new T3T4InStoreSale().sellCash(1, Collections.singletonList(new SaleLine("S2-2-0001", 1))));

        Check.step("Case 6 (T4): expired card -> rejected before any change");
        CardInfo expired = new CardInfo("tok_old", "1234", LocalDate.of(2020, 1, 31), "JOHN DOE");
        Check.expectFailure("sale is rejected",
                () -> new T3T4InStoreSale().sellCredit(1, Collections.singletonList(new SaleLine(SNEAKERS, 1)), expired));
    }
}
