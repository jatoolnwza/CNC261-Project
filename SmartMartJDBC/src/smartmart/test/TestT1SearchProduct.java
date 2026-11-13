package smartmart.test;

import java.util.List;

import smartmart.db.AppLogin;
import smartmart.db.DBConnection;
import smartmart.model.StockInfo;
import smartmart.tx.T1SearchProduct;

/** ทดสอบ T1 ค้นหาสินค้า : Run As > Java Application */
public final class TestT1SearchProduct {

    public static void main(String[] args) throws Exception {
        run();
        Check.summary();
    }

    public static void run() throws Exception {
        Check.title("TEST T1 : Search product   (login = " + DBConnection.userOf(AppLogin.WEBSHOP_APP)
                + ", isolation = READ COMMITTED)");
        T1SearchProduct t1 = new T1SearchProduct();

        Check.step("Case 1: search \"Running\" -> test SKU S1-T3-01 with a 10% promotion");
        List<StockInfo> rows = t1.search("Running");
        print(rows);
        StockInfo sneakers = find(rows, "S1-T3-01");
        Check.that(sneakers != null, "S1-T3-01 is in the result");
        if (sneakers != null) {
            Check.same("STORE", sneakers.locationType, "location type");
            Check.money("59.99", sneakers.retailPrice, "retail price");
            Check.money("53.99", sneakers.salePrice, "sale price after 10% promotion");
        }

        Check.step("Case 2: search \"Wireless\" -> one product can be in several stores and warehouses");
        rows = t1.search("Wireless");
        print(rows);
        Check.that(rows.size() >= 4, "found " + rows.size() + " locations (expected at least 4)");

        Check.step("Case 3: keyword \"%\" is treated as normal text, not as a LIKE wildcard");
        Check.equal(0, t1.search("%").size(), "rows for keyword \"%\"");

        Check.step("Case 4: search \"zzz\" -> nothing found");
        Check.equal(0, t1.search("zzz").size(), "rows for keyword \"zzz\"");
    }

    private static StockInfo find(List<StockInfo> rows, String sku) {
        for (StockInfo row : rows) {
            if (sku.equals(row.sku)) {
                return row;
            }
        }
        return null;
    }

    private static void print(List<StockInfo> rows) {
        for (StockInfo row : rows) {
            Check.info(row.toString());
        }
    }
}
