package smartmart.tx;

import java.math.BigDecimal;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.sql.Timestamp;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

import smartmart.db.AppLogin;
import smartmart.db.DBConnection;
import smartmart.model.Receipt;
import smartmart.model.WebOrderLine;

/**
 * T6 : สั่งซื้อสินค้าออนไลน์ ชำระด้วยบัตรเครดิตที่บันทึกไว้ 1 ใบ
 *      สินค้าแต่ละรายการส่งไปคนละที่อยู่ได้, ตรวจว่าขายออนไลน์ได้ (web_orderable) และมีสต็อกพอ
 *      แล้วตัดสต็อกที่ Warehouse, ภาษีคิดตามรัฐปลายทางของแต่ละรายการ
 *      ค่าส่งยังเป็น 0 จนกว่าจะจัดส่งจริง (T7 จะบวกเพิ่มทีละรอบ)
 *
 * ผู้ใช้        : เว็บขายออนไลน์ (login_app_webshop)
 * Isolation    : REPEATABLE READ
 * เหตุผล       : เหมือน T2/T3 — อ่านสต็อกคลังแล้วเขียนค่าใหม่ ถ้าสองคำสั่งซื้อแย่งสินค้าชิ้นเดียวกัน
 *                ภายใต้ READ COMMITTED จะเกิด Lost Update หรือขายเกินสต็อก
 *                และบัตร/ที่อยู่ที่ตรวจแล้วต้องไม่ถูกแก้ระหว่างทำรายการ
 */
public class T6PlaceWebOrder {

    private static final String SQL_CARD =
            "SELECT exp_date FROM dbo.web_customer_credit_card WHERE web_customer_numb = ? AND card_numb = ?";
    private static final String SQL_INSERT_SALE =
            "INSERT INTO dbo.web_sale (web_customer_numb, card_numb, sale_date, merchandise_total, shipping_total, tax_total, total) "
            + "VALUES (?, ?, ?, 0, 0, 0, 0)";
    private static final String SQL_ADDRESS_TAX =
            "SELECT a.state_code, st.sales_tax_rate FROM dbo.web_sale_shipping_address a "
            + "JOIN dbo.state st ON st.state_code = a.state_code "
            + "WHERE a.shipping_address_numb = ? AND a.web_customer_numb = ?";
    private static final String SQL_READ_STOCK =
            "SELECT ps.UPC, ps.in_store, ps.number_on_hand, ps.retail_price, p.web_orderable, p.product_name "
            + "FROM dbo.product_stocked ps JOIN dbo.product p ON p.UPC = ps.UPC WHERE ps.SKU = ?";
    private static final String SQL_INSERT_ITEM =
            "INSERT INTO dbo.web_sale_item (web_sale_numb, SKU, quantity, unit_price, shipping_address_numb, shipment_seq) "
            + "VALUES (?, ?, ?, ?, ?, NULL)";
    private static final String SQL_SET_ON_HAND =
            "UPDATE dbo.product_stocked SET number_on_hand = ? WHERE SKU = ?";
    private static final String SQL_UPDATE_TOTALS =
            "UPDATE dbo.web_sale SET merchandise_total = ?, tax_total = ?, total = ? WHERE web_sale_numb = ?";

    private int isolationLevel = Connection.TRANSACTION_REPEATABLE_READ;
    private int maxAttempts = 3;

    public T6PlaceWebOrder withIsolation(int level) {
        this.isolationLevel = level;
        return this;
    }

    /** @return ใบเสร็จ (number = web_sale_numb) */
    public Receipt placeOrder(int customerNumb, int cardNumb, List<WebOrderLine> lines)
            throws SQLException, BusinessRuleException {
        validate(lines);
        return TxHelper.runWithDeadlockRetry(maxAttempts, attempt -> placeOnce(customerNumb, cardNumb, lines));
    }

    private Receipt placeOnce(int customerNumb, int cardNumb, List<WebOrderLine> lines)
            throws SQLException, BusinessRuleException {
        LocalDate today = LocalDate.now();
        try (Connection conn = DBConnection.open(AppLogin.WEBSHOP_APP)) {
            conn.setAutoCommit(false);
            conn.setTransactionIsolation(isolationLevel);
            try (PreparedStatement psCard = conn.prepareStatement(SQL_CARD);
                 PreparedStatement psSale = conn.prepareStatement(SQL_INSERT_SALE, Statement.RETURN_GENERATED_KEYS);
                 PreparedStatement psAddress = conn.prepareStatement(SQL_ADDRESS_TAX);
                 PreparedStatement psStock = conn.prepareStatement(SQL_READ_STOCK);
                 PreparedStatement psDiscount = conn.prepareStatement(Pricing.SQL_ACTIVE_DISCOUNT);
                 PreparedStatement psTaxed = conn.prepareStatement(Pricing.SQL_IS_TAXED);
                 PreparedStatement psItem = conn.prepareStatement(SQL_INSERT_ITEM);
                 PreparedStatement psSetOnHand = conn.prepareStatement(SQL_SET_ON_HAND);
                 PreparedStatement psTotals = conn.prepareStatement(SQL_UPDATE_TOTALS)) {

                // (1) SELECT บัตรต้องเป็นของลูกค้าคนนี้ และยังไม่หมดอายุ
                psCard.setInt(1, customerNumb);
                psCard.setInt(2, cardNumb);
                try (ResultSet rs = psCard.executeQuery()) {
                    if (!rs.next()) {
                        throw new BusinessRuleException("Card #" + cardNumb + " does not belong to customer #" + customerNumb);
                    }
                    if (rs.getDate("exp_date").toLocalDate().isBefore(today)) {
                        throw new BusinessRuleException("Card #" + cardNumb + " has expired");
                    }
                }

                // (2) INSERT หัวคำสั่งซื้อ (ยอด 0 ไว้ก่อน)
                psSale.setInt(1, customerNumb);
                psSale.setInt(2, cardNumb);
                psSale.setTimestamp(3, Timestamp.valueOf(LocalDateTime.now()));
                psSale.executeUpdate();
                int saleNumb;
                try (ResultSet keys = psSale.getGeneratedKeys()) {
                    keys.next();
                    saleNumb = keys.getInt(1);
                }

                // (3) ทีละรายการ
                BigDecimal merchandiseTotal = BigDecimal.ZERO;
                BigDecimal rawTax = BigDecimal.ZERO;
                for (WebOrderLine line : lines) {
                    // (3.1) SELECT ที่อยู่ต้องเป็นของลูกค้าคนนี้ + อัตราภาษีรัฐปลายทาง
                    String destState;
                    BigDecimal taxRate;
                    psAddress.setInt(1, line.shippingAddressNumb);
                    psAddress.setInt(2, customerNumb);
                    try (ResultSet rs = psAddress.executeQuery()) {
                        if (!rs.next()) {
                            throw new BusinessRuleException("Address #" + line.shippingAddressNumb
                                    + " does not belong to customer #" + customerNumb);
                        }
                        destState = rs.getString("state_code");
                        taxRate = rs.getBigDecimal("sales_tax_rate");
                    }

                    // (3.2) SELECT สินค้า : ต้องอยู่ในคลัง, ขายออนไลน์ได้, สต็อกพอ
                    String upc;
                    int onHand;
                    BigDecimal retailPrice;
                    psStock.setString(1, line.sku);
                    try (ResultSet rs = psStock.executeQuery()) {
                        if (!rs.next()) {
                            throw new BusinessRuleException("SKU " + line.sku + " not found");
                        }
                        if (rs.getBoolean("in_store")) {
                            throw new BusinessRuleException("SKU " + line.sku + " is store stock - web orders ship from a warehouse");
                        }
                        if (!rs.getBoolean("web_orderable")) {
                            throw new BusinessRuleException(rs.getString("product_name") + " (" + line.sku
                                    + ") cannot be ordered online (web_orderable = 0)");
                        }
                        upc = rs.getString("UPC");
                        onHand = rs.getInt("number_on_hand");
                        retailPrice = rs.getBigDecimal("retail_price");
                    }
                    if (onHand < line.quantity) {
                        throw new BusinessRuleException("Not enough stock for " + line.sku
                                + ": on hand " + onHand + ", requested " + line.quantity);
                    }

                    // (3.3) ราคา หลังหักโปรโมชัน + ภาษีตามรัฐปลายทาง
                    BigDecimal unitPrice = Pricing.discountedPrice(retailPrice, Pricing.activeDiscount(psDiscount, upc, today));
                    BigDecimal lineTotal = unitPrice.multiply(BigDecimal.valueOf(line.quantity));
                    merchandiseTotal = merchandiseTotal.add(lineTotal);
                    if (Pricing.isTaxed(psTaxed, upc, destState)) {
                        rawTax = rawTax.add(lineTotal.multiply(taxRate));
                    }

                    // (3.4) INSERT รายการ (shipment_seq = NULL = ยังไม่ส่ง)
                    psItem.setInt(1, saleNumb);
                    psItem.setString(2, line.sku);
                    psItem.setInt(3, line.quantity);
                    psItem.setBigDecimal(4, unitPrice);
                    psItem.setInt(5, line.shippingAddressNumb);
                    psItem.executeUpdate();

                    // (3.5) UPDATE ตัดสต็อกที่คลัง
                    psSetOnHand.setInt(1, onHand - line.quantity);
                    psSetOnHand.setString(2, line.sku);
                    psSetOnHand.executeUpdate();
                }

                // (4) UPDATE ยอดรวม ภาษี ยอดสุทธิ
                BigDecimal taxTotal = Pricing.money(rawTax);
                BigDecimal total = merchandiseTotal.add(taxTotal);
                psTotals.setBigDecimal(1, merchandiseTotal);
                psTotals.setBigDecimal(2, taxTotal);
                psTotals.setBigDecimal(3, total);
                psTotals.setInt(4, saleNumb);
                psTotals.executeUpdate();

                conn.commit();
                return new Receipt(saleNumb, merchandiseTotal, taxTotal, total);

            } catch (SQLException | BusinessRuleException | RuntimeException e) {
                TxHelper.rollbackQuietly(conn, e);           // คำสั่งซื้อ รายการ และสต็อก ย้อนกลับทั้งหมด
                throw e;
            }
        }
    }

    private static void validate(List<WebOrderLine> lines) throws BusinessRuleException {
        if (lines == null || lines.isEmpty()) {
            throw new BusinessRuleException("An order needs at least one item");
        }
        Set<String> seen = new HashSet<>();
        for (WebOrderLine line : lines) {
            if (line.quantity <= 0) {
                throw new BusinessRuleException("Quantity of " + line.sku + " must be greater than 0");
            }
            if (!seen.add(line.sku)) {
                throw new BusinessRuleException("SKU " + line.sku + " appears twice - combine the quantities");
            }
        }
    }
}
