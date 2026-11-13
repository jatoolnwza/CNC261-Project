package smartmart.model;

import java.math.BigDecimal;

/** ผลลัพธ์ของการขาย (T3/T4 = เลขบิล, T6 = เลขคำสั่งซื้อ) พร้อมยอดเงิน */
public final class Receipt {

    public final int number;
    public final BigDecimal subtotal;
    public final BigDecimal tax;
    public final BigDecimal total;

    public Receipt(int number, BigDecimal subtotal, BigDecimal tax, BigDecimal total) {
        this.number = number;
        this.subtotal = subtotal;
        this.tax = tax;
        this.total = total;
    }

    @Override
    public String toString() {
        return "#" + number + "  subtotal=" + subtotal + "  tax=" + tax + "  total=" + total;
    }
}
