package smartmart.model;

/** 1 รายการในคำสั่งซื้อออนไลน์ (T6) : SKU ในคลัง + จำนวน + ที่อยู่จัดส่งของรายการนี้ */
public final class WebOrderLine {

    public final String sku;
    public final int quantity;
    public final int shippingAddressNumb;

    public WebOrderLine(String sku, int quantity, int shippingAddressNumb) {
        this.sku = sku;
        this.quantity = quantity;
        this.shippingAddressNumb = shippingAddressNumb;
    }

    @Override
    public String toString() {
        return sku + " x" + quantity + " -> address #" + shippingAddressNumb;
    }
}
