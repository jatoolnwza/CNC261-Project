package smartmart.test;

import java.math.BigDecimal;
import java.util.Arrays;
import java.util.Collections;

import smartmart.db.AppLogin;
import smartmart.db.DBConnection;
import smartmart.model.Receipt;
import smartmart.model.WebOrderLine;
import smartmart.tx.T6PlaceWebOrder;
import smartmart.tx.T7CreateShipment;

/** ทดสอบ T7 จัดส่งแบบแบ่งส่ง : Run As > Java Application */
public final class TestT7CreateShipment {

    private static final AppLogin SHOP = AppLogin.WEBSHOP_APP;
    private static final AppLogin WAREHOUSE = AppLogin.WAREHOUSE_APP;
    private static final String BACKPACK = "W1-T6-01";     // 2.20 lb
    private static final String HEADPHONES = "W1-T6-02";   // 0.90 lb
    private static final String ITEM_SEQ =
            "SELECT shipment_seq FROM dbo.web_sale_item WHERE web_sale_numb = ? AND SKU = ?";
    private static final String SHIPPING_TOTAL = "SELECT shipping_total FROM dbo.web_sale WHERE web_sale_numb = ?";
    private static final String TOTAL = "SELECT total FROM dbo.web_sale WHERE web_sale_numb = ?";
    private static final String COUNT_SHIPMENTS = "SELECT COUNT(*) FROM dbo.web_sale_shipment WHERE web_sale_numb = ?";

    public static void main(String[] args) throws Exception {
        run();
        Check.summary();
    }

    public static void run() throws Exception {
        Check.title("TEST T7 : Partial shipment   (login = " + DBConnection.userOf(WAREHOUSE)
                + ", isolation = SERIALIZABLE)");

        Check.step("Setup: create a new order with T6 (backpack -> CA, headphones -> NY)");
        TestSupport.setStock(SHOP, BACKPACK, 50);
        TestSupport.setStock(SHOP, HEADPHONES, 50);
        Receipt order = new T6PlaceWebOrder().placeOrder(1, 1, Arrays.asList(
                new WebOrderLine(BACKPACK, 1, 1), new WebOrderLine(HEADPHONES, 1, 2)));
        int sale = order.number;
        Check.info("web sale " + order);
        BigDecimal totalBefore = TestSupport.queryDecimal(WAREHOUSE, TOTAL, sale);

        Check.step("Case 1: ship only the backpack -> shipment 1, headphones stay on backorder");
        int seq1 = new T7CreateShipment().ship(sale, Collections.singletonList(BACKPACK));
        Check.equal(1, seq1, "shipment_seq");
        Check.same(1, TestSupport.queryNullableInt(WAREHOUSE, ITEM_SEQ, sale, BACKPACK), "backpack shipment_seq");
        Check.same(null, TestSupport.queryNullableInt(WAREHOUSE, ITEM_SEQ, sale, HEADPHONES), "headphones shipment_seq (NULL = backorder)");
        Check.money("6.10", TestSupport.queryDecimal(WAREHOUSE,
                "SELECT shipping_charge FROM dbo.web_sale_shipment WHERE web_sale_numb = ? AND shipment_seq = 1", sale),
                "shipping charge 5.00 + 0.50 x 2.20 lb");
        Check.money("6.10", TestSupport.queryDecimal(WAREHOUSE, SHIPPING_TOTAL, sale), "web_sale.shipping_total");
        Check.money(totalBefore.add(new BigDecimal("6.10")).toPlainString(),
                TestSupport.queryDecimal(WAREHOUSE, TOTAL, sale), "web_sale.total increased by 6.10");

        Check.step("Case 2: ship the headphones later -> shipment 2");
        int seq2 = new T7CreateShipment().ship(sale, Collections.singletonList(HEADPHONES));
        Check.equal(2, seq2, "shipment_seq");
        Check.same(2, TestSupport.queryNullableInt(WAREHOUSE, ITEM_SEQ, sale, HEADPHONES), "headphones shipment_seq");
        Check.money("11.55", TestSupport.queryDecimal(WAREHOUSE, SHIPPING_TOTAL, sale), "shipping_total (6.10 + 5.45)");

        Check.step("Case 3: ship the backpack again -> new shipment row was inserted, then ROLLED BACK");
        Check.expectFailure("second shipment of the same item is rejected",
                () -> new T7CreateShipment().ship(sale, Collections.singletonList(BACKPACK)));
        Check.equal(2, TestSupport.queryInt(WAREHOUSE, COUNT_SHIPMENTS, sale), "shipments of this order still 2");
        Check.money("11.55", TestSupport.queryDecimal(WAREHOUSE, SHIPPING_TOTAL, sale), "shipping_total unchanged");

        Check.step("Case 4: web sale #999999 does not exist -> rejected");
        Check.expectFailure("shipment is rejected",
                () -> new T7CreateShipment().ship(999999, Collections.singletonList(BACKPACK)));
    }
}
