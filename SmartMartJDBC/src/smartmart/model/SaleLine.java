package smartmart.model;

/** 1 รายการในบิลขายหน้าร้าน (T3/T4) : SKU ที่วางขายในสาขา + จำนวน */
public final class SaleLine {

    public final String sku;
    public final int quantity;

    public SaleLine(String sku, int quantity) {
        this.sku = sku;
        this.quantity = quantity;
    }

    @Override
    public String toString() {
        return sku + " x" + quantity;
    }
}
