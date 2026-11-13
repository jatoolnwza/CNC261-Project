package smartmart.tx;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.sql.Date;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.LocalDate;

/** กติกาการคิดราคา ส่วนลด และภาษี ที่ T3, T4, T6 ใช้ร่วมกัน */
public final class Pricing {

    /** SELECT ส่วนลดของโปรโมชันที่ยังไม่หมดอายุ ณ วันที่ขาย (ถ้ามีหลายโปร ใช้โปรที่เริ่มล่าสุด) */
    public static final String SQL_ACTIVE_DISCOUNT =
            "SELECT TOP (1) discount_percent FROM dbo.sales_promotion "
            + "WHERE UPC = ? AND ? BETWEEN promotion_start_date AND promotion_end_date "
            + "ORDER BY promotion_start_date DESC";

    /** SELECT ว่าสินค้านี้ต้องเสียภาษีในรัฐนั้นไหม (มีแถวใน product_taxed = ต้องเสีย) */
    public static final String SQL_IS_TAXED =
            "SELECT COUNT(*) FROM dbo.product_taxed WHERE UPC = ? AND state_code = ?";

    private static final BigDecimal HUNDRED = new BigDecimal("100");

    private Pricing() {
    }

    public static BigDecimal activeDiscount(PreparedStatement ps, String upc, LocalDate day) throws SQLException {
        ps.setString(1, upc);
        ps.setDate(2, Date.valueOf(day));
        try (ResultSet rs = ps.executeQuery()) {
            return rs.next() ? rs.getBigDecimal(1) : BigDecimal.ZERO;
        }
    }

    public static boolean isTaxed(PreparedStatement ps, String upc, String stateCode) throws SQLException {
        ps.setString(1, upc);
        ps.setString(2, stateCode);
        try (ResultSet rs = ps.executeQuery()) {
            rs.next();
            return rs.getInt(1) > 0;
        }
    }

    /** ราคาต่อหน่วยหลังหักส่วนลด ปัดเศษ 2 ตำแหน่งแบบ HALF_UP (เหมือน ROUND ของ SQL Server) */
    public static BigDecimal discountedPrice(BigDecimal retailPrice, BigDecimal discountPercent) {
        return retailPrice.multiply(HUNDRED.subtract(discountPercent))
                .divide(HUNDRED, 2, RoundingMode.HALF_UP);
    }

    /** ค่าส่ง 1 รอบ = 5.00 + 0.50 x น้ำหนักรวม (ปอนด์) */
    public static BigDecimal shippingCharge(BigDecimal totalWeight) {
        return new BigDecimal("5.00").add(new BigDecimal("0.50").multiply(totalWeight))
                .setScale(2, RoundingMode.HALF_UP);
    }

    public static BigDecimal money(BigDecimal raw) {
        return raw.setScale(2, RoundingMode.HALF_UP);
    }
}
