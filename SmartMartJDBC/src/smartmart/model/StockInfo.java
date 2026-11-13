package smartmart.model;

import java.math.BigDecimal;

/** 1 แถวผลค้นหาของ T1 : สินค้า 1 SKU อยู่ที่ไหน เหลือเท่าไร ราคาเท่าไร */
public final class StockInfo {

    public final String sku;
    public final String upc;
    public final String productName;
    public final String size;
    public final String color;
    public final String locationType;   // STORE หรือ WAREHOUSE
    public final Integer storeNumb;
    public final String deptName;
    public final Integer warehouseId;
    public final String city;
    public final String stateCode;
    public final int onHand;
    public final BigDecimal retailPrice;
    public final BigDecimal discountPercent;
    public final BigDecimal salePrice;

    public StockInfo(String sku, String upc, String productName, String size, String color,
                     String locationType, Integer storeNumb, String deptName, Integer warehouseId,
                     String city, String stateCode, int onHand,
                     BigDecimal retailPrice, BigDecimal discountPercent, BigDecimal salePrice) {
        this.sku = sku;
        this.upc = upc;
        this.productName = productName;
        this.size = size;
        this.color = color;
        this.locationType = locationType;
        this.storeNumb = storeNumb;
        this.deptName = deptName;
        this.warehouseId = warehouseId;
        this.city = city;
        this.stateCode = stateCode;
        this.onHand = onHand;
        this.retailPrice = retailPrice;
        this.discountPercent = discountPercent;
        this.salePrice = salePrice;
    }

    public String location() {
        if ("STORE".equals(locationType)) {
            return "Store " + storeNumb + " / " + deptName + " (" + city + ", " + stateCode + ")";
        }
        return "Warehouse " + warehouseId + " (" + city + ", " + stateCode + ")";
    }

    @Override
    public String toString() {
        return String.format("%-10s %-22s %-40s on hand %4d  price %8s  -%5s%%  = %8s",
                sku, productName, location(), onHand, retailPrice, discountPercent, salePrice);
    }
}
