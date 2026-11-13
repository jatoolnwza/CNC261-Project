package smartmart.test;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.Arrays;
import java.util.Collections;

import smartmart.db.AppLogin;
import smartmart.db.DBConnection;
import smartmart.model.Receipt;
import smartmart.model.WebOrderLine;
import smartmart.tx.T6PlaceWebOrder;

/** ทดสอบ T6 สั่งซื้อออนไลน์ : Run As > Java Application */
public final class TestT6PlaceWebOrder {

    private static final AppLogin APP = AppLogin.WEBSHOP_APP;
    private static final String BACKPACK = "W1-T6-01";     // 49.99 โปร 5%  คลัง 1
    private static final String HEADPHONES = "W1-T6-02";   // 89.99 ไม่มีโปร คลัง 1
    private static final String COUNT_SALES = "SELECT COUNT(*) FROM dbo.web_sale";

    public static void main(String[] args) throws Exception {
        run();
        Check.summary();
    }

    public static void run() throws Exception {
        Check.title("TEST T6 : Place web order   (login = " + DBConnection.userOf(APP)
                + ", isolation = REPEATABLE READ)");

        Check.step("Setup: reset test stock " + BACKPACK + " = 50, " + HEADPHONES + " = 50");
        TestSupport.setStock(APP, BACKPACK, 50);
        TestSupport.setStock(APP, HEADPHONES, 50);
        int salesBefore = TestSupport.queryInt(APP, COUNT_SALES);

        Check.step("Case 1: Alice (customer 1, card 1) - backpack to CA address, 2 headphones to NY address -> COMMIT");
        Receipt r = new T6PlaceWebOrder().placeOrder(1, 1, Arrays.asList(
                new WebOrderLine(BACKPACK, 1, 1),        // ที่อยู่ #1 Los Angeles, CA (ภาษี 7.25%)
                new WebOrderLine(HEADPHONES, 2, 2)));    // ที่อยู่ #2 New York, NY (ภาษี 4%)
        Check.info("web sale " + r);
        Check.money("227.47", r.subtotal, "merchandise_total (47.49 + 2 x 89.99)");
        Check.money("10.64", r.tax, "tax_total (47.49 x 7.25% + 179.98 x 4%)");
        Check.money("238.11", r.total, "total (shipping is added later by T7)");
        Check.equal(49, TestSupport.stockOf(APP, BACKPACK), "warehouse stock " + BACKPACK);
        Check.equal(48, TestSupport.stockOf(APP, HEADPHONES), "warehouse stock " + HEADPHONES);
        Check.equal(2, TestSupport.queryInt(APP,
                "SELECT COUNT(*) FROM dbo.web_sale_item WHERE web_sale_numb = ? AND shipment_seq IS NULL", r.number),
                "items waiting to ship (shipment_seq IS NULL)");
        Check.equal(2, rowsInCustomerOrdersView(1, r.number), "rows of this order in v_customer_orders for customer 1");
        Check.equal(0, rowsInCustomerOrdersView(2, r.number), "rows of this order in v_customer_orders for customer 2 (Bob)");

        Check.step("Case 2: 1000 backpacks (more than stock) -> ROLLBACK");
        Check.expectFailure("order is rejected", () -> new T6PlaceWebOrder().placeOrder(1, 1,
                Collections.singletonList(new WebOrderLine(BACKPACK, 1000, 1))));
        Check.equal(49, TestSupport.stockOf(APP, BACKPACK), "stock unchanged");

        Check.step("Case 3: line 1 OK, line 2 = Organic Milk (web_orderable = 0) -> line 1 must be ROLLED BACK too");
        Check.expectFailure("order is rejected", () -> new T6PlaceWebOrder().placeOrder(1, 1, Arrays.asList(
                new WebOrderLine(BACKPACK, 1, 1),
                new WebOrderLine("W1-0005", 1, 1))));
        Check.equal(49, TestSupport.stockOf(APP, BACKPACK), "stock of line 1 unchanged");
        Check.equal(salesBefore + 1, TestSupport.queryInt(APP, COUNT_SALES), "web_sale rows (only the order from case 1)");

        Check.step("Case 4: Alice uses Bob's address (#3) -> ROLLBACK");
        Check.expectFailure("order is rejected", () -> new T6PlaceWebOrder().placeOrder(1, 1,
                Collections.singletonList(new WebOrderLine(BACKPACK, 1, 3))));

        Check.step("Case 5: card #9 is not Alice's -> ROLLBACK");
        Check.expectFailure("order is rejected", () -> new T6PlaceWebOrder().placeOrder(1, 9,
                Collections.singletonList(new WebOrderLine(BACKPACK, 1, 1))));

        Check.step("Case 6: store SKU (S1-T3-01) cannot be ordered online -> ROLLBACK");
        Check.expectFailure("order is rejected", () -> new T6PlaceWebOrder().placeOrder(1, 1,
                Collections.singletonList(new WebOrderLine("S1-T3-01", 1, 1))));
        Check.equal(salesBefore + 1, TestSupport.queryInt(APP, COUNT_SALES), "web_sale rows unchanged");
    }

    /** แอปบอกฐานข้อมูลว่าลูกค้าคนไหนล็อกอินอยู่ แล้วอ่านผ่าน View v_customer_orders */
    private static int rowsInCustomerOrdersView(int customerNumb, int webSaleNumb) throws SQLException {
        try (Connection conn = DBConnection.open(APP)) {
            try (PreparedStatement ps = conn.prepareStatement(
                    "EXEC sp_set_session_context @key = N'web_customer_numb', @value = ?")) {
                ps.setInt(1, customerNumb);
                ps.execute();
            }
            try (PreparedStatement ps = conn.prepareStatement(
                    "SELECT COUNT(*) FROM dbo.v_customer_orders WHERE web_sale_numb = ?")) {
                ps.setInt(1, webSaleNumb);
                try (ResultSet rs = ps.executeQuery()) {
                    rs.next();
                    return rs.getInt(1);
                }
            }
        }
    }
}
