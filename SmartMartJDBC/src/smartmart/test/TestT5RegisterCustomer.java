package smartmart.test;

import java.time.LocalDate;

import smartmart.db.AppLogin;
import smartmart.db.DBConnection;
import smartmart.model.CardInfo;
import smartmart.model.ShippingAddress;
import smartmart.tx.T5RegisterCustomer;

/** ทดสอบ T5 สมัครสมาชิกออนไลน์ : Run As > Java Application */
public final class TestT5RegisterCustomer {

    private static final AppLogin APP = AppLogin.WEBSHOP_APP;
    private static final String COUNT_USER = "SELECT COUNT(*) FROM dbo.web_customer WHERE user_id = ?";

    public static void main(String[] args) throws Exception {
        run();
        Check.summary();
    }

    public static void run() throws Exception {
        Check.title("TEST T5 : Register web customer   (login = " + DBConnection.userOf(APP)
                + ", isolation = READ COMMITTED + UNIQUE(user_id))");
        long stamp = System.currentTimeMillis() % 1_000_000_000L;   // ให้ user_id ไม่ซ้ำในแต่ละรอบที่รัน
        String userId = "tester" + stamp;

        Check.step("Case 1: new user '" + userId + "' -> customer + card + address -> COMMIT");
        int id = new T5RegisterCustomer().register("Test", "User", "206-555-0199", userId, "secret123",
                card("4000"), address("WA"));
        Check.info("new web_customer_numb = " + id);
        Check.equal(1, TestSupport.queryInt(APP, COUNT_USER, userId), "web_customer rows");
        Check.equal(1, TestSupport.queryInt(APP,
                "SELECT COUNT(*) FROM dbo.web_customer_credit_card WHERE web_customer_numb = ?", id), "saved cards");
        Check.equal(1, TestSupport.queryInt(APP,
                "SELECT COUNT(*) FROM dbo.web_sale_shipping_address WHERE web_customer_numb = ?", id), "saved addresses");
        String hash = TestSupport.queryString(APP, "SELECT password_hash FROM dbo.web_customer WHERE user_id = ?", userId);
        Check.that(hash != null && hash.startsWith("sha256:"), "password stored as a hash, not plain text");

        Check.step("Case 2: register the same user_id again -> ROLLBACK");
        Check.expectFailure("duplicate user_id is rejected", () -> new T5RegisterCustomer()
                .register("Copy", "Cat", null, userId, "secret123", card("4001"), address("WA")));
        Check.equal(1, TestSupport.queryInt(APP, COUNT_USER, userId), "still only 1 customer with this user_id");

        String userId2 = "tester" + stamp + "b";
        Check.step("Case 3: address state 'ZZ' does not exist -> 3rd INSERT fails -> 1st and 2nd INSERT ROLLED BACK");
        Check.expectFailure("registration fails at the address step", () -> new T5RegisterCustomer()
                .register("Bad", "State", null, userId2, "secret123", card("4002"), address("ZZ")));
        Check.equal(0, TestSupport.queryInt(APP, COUNT_USER, userId2), "no customer '" + userId2 + "' left behind");

        String userId3 = "tester" + stamp + "c";
        Check.step("Case 4: card_last4 '12AB' violates CHECK -> customer INSERT ROLLED BACK");
        Check.expectFailure("registration fails at the card step", () -> new T5RegisterCustomer()
                .register("Bad", "Card", null, userId3, "secret123", card("12AB"), address("WA")));
        Check.equal(0, TestSupport.queryInt(APP, COUNT_USER, userId3), "no customer '" + userId3 + "' left behind");
    }

    private static CardInfo card(String last4) {
        return new CardInfo("tok_" + System.nanoTime(), last4, LocalDate.of(2030, 1, 31), "TEST USER");
    }

    private static ShippingAddress address(String state) {
        return new ShippingAddress("1 Test St", "Seattle", state, "98101", "Test", "User");
    }
}
