package smartmart.tx;

import java.math.BigDecimal;
import java.sql.Connection;
import java.sql.Date;
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
import smartmart.model.CardInfo;
import smartmart.model.Receipt;
import smartmart.model.SaleLine;

/**
 * T3 : ขายสินค้าหน้าร้าน ชำระด้วยเงินสด
 *      บันทึกบิล + รายการสินค้า, ตัดสต็อกของสาขา, หักส่วนลดโปรโมชันที่ยังไม่หมดอายุ,
 *      คิดภาษีขายตามรัฐของสาขา (เฉพาะสินค้าที่ต้องเสียภาษีในรัฐนั้น)
 * T4 : ขายหน้าร้าน ชำระด้วยบัตรเครดิต = ทำเหมือน T3 + บันทึก credit_sale_details ใน Transaction เดียวกัน
 *
 * ผู้ใช้        : ระบบ POS หน้าร้าน (login_app_pos)
 * Isolation    : REPEATABLE READ
 * เหตุผล       : อ่าน number_on_hand แล้วนำไปคำนวณค่าใหม่ ถ้าสองเครื่อง POS ขาย SKU เดียวกันพร้อมกัน
 *                ภายใต้ READ COMMITTED จะเกิด Lost Update (สต็อกลดไม่ครบ) และราคา/โปรโมชันที่อ่าน
 *                ต้องคงที่ตลอดบิล  REPEATABLE READ จึงพอ (ไม่มีการตรวจ "ช่วงของแถว" ที่ต้องกัน Phantom)
 */
public class T3T4InStoreSale {

    public static final int PAYMENT_CASH = 1;
    public static final int PAYMENT_CREDIT = 2;

    private static final String SQL_STORE_TAX =
            "SELECT s.state_code, st.sales_tax_rate FROM dbo.store s "
            + "JOIN dbo.state st ON st.state_code = s.state_code WHERE s.store_numb = ?";
    private static final String SQL_INSERT_SALE =
            "INSERT INTO dbo.in_store_sale (store_numb, payment_type_code, transaction_date, product_total, sales_tax, total) "
            + "VALUES (?, ?, ?, 0, 0, 0)";
    private static final String SQL_READ_STOCK =
            "SELECT UPC, in_store, store_numb, number_on_hand, retail_price FROM dbo.product_stocked WHERE SKU = ?";
    private static final String SQL_INSERT_ITEM =
            "INSERT INTO dbo.in_store_sale_item (transaction_numb, SKU, quantity, unit_price) VALUES (?, ?, ?, ?)";
    private static final String SQL_SET_ON_HAND =
            "UPDATE dbo.product_stocked SET number_on_hand = ? WHERE SKU = ?";
    private static final String SQL_UPDATE_TOTALS =
            "UPDATE dbo.in_store_sale SET product_total = ?, sales_tax = ?, total = ? WHERE transaction_numb = ?";
    private static final String SQL_INSERT_CREDIT =
            "INSERT INTO dbo.credit_sale_details (transaction_numb, card_token, card_last4, exp_date, name_on_card) "
            + "VALUES (?, ?, ?, ?, ?)";

    private int isolationLevel = Connection.TRANSACTION_REPEATABLE_READ;
    private int maxAttempts = 3;

    public T3T4InStoreSale withIsolation(int level) {
        this.isolationLevel = level;
        return this;
    }

    /** T3 : ขายเงินสด */
    public Receipt sellCash(int storeNumb, List<SaleLine> lines) throws SQLException, BusinessRuleException {
        validate(lines);
        return TxHelper.runWithDeadlockRetry(maxAttempts,
                attempt -> sellOnce(storeNumb, lines, PAYMENT_CASH, null));
    }

    /** T4 : ขายด้วยบัตรเครดิต */
    public Receipt sellCredit(int storeNumb, List<SaleLine> lines, CardInfo card)
            throws SQLException, BusinessRuleException {
        validate(lines);
        if (card == null) {
            throw new BusinessRuleException("Card information is required for a credit sale");
        }
        if (card.expDate.isBefore(LocalDate.now())) {
            throw new BusinessRuleException("Card expired on " + card.expDate);
        }
        return TxHelper.runWithDeadlockRetry(maxAttempts,
                attempt -> sellOnce(storeNumb, lines, PAYMENT_CREDIT, card));
    }

    private Receipt sellOnce(int storeNumb, List<SaleLine> lines, int paymentType, CardInfo card)
            throws SQLException, BusinessRuleException {
        LocalDate today = LocalDate.now();
        try (Connection conn = DBConnection.open(AppLogin.POS_APP)) {
            conn.setAutoCommit(false);
            conn.setTransactionIsolation(isolationLevel);
            try (PreparedStatement psStore = conn.prepareStatement(SQL_STORE_TAX);
                 PreparedStatement psSale = conn.prepareStatement(SQL_INSERT_SALE, Statement.RETURN_GENERATED_KEYS);
                 PreparedStatement psStock = conn.prepareStatement(SQL_READ_STOCK);
                 PreparedStatement psDiscount = conn.prepareStatement(Pricing.SQL_ACTIVE_DISCOUNT);
                 PreparedStatement psTaxed = conn.prepareStatement(Pricing.SQL_IS_TAXED);
                 PreparedStatement psItem = conn.prepareStatement(SQL_INSERT_ITEM);
                 PreparedStatement psSetOnHand = conn.prepareStatement(SQL_SET_ON_HAND);
                 PreparedStatement psTotals = conn.prepareStatement(SQL_UPDATE_TOTALS);
                 PreparedStatement psCredit = conn.prepareStatement(SQL_INSERT_CREDIT)) {

                // (1) SELECT รัฐและอัตราภาษีของสาขา
                String stateCode;
                BigDecimal taxRate;
                psStore.setInt(1, storeNumb);
                try (ResultSet rs = psStore.executeQuery()) {
                    if (!rs.next()) {
                        throw new BusinessRuleException("Store " + storeNumb + " not found");
                    }
                    stateCode = rs.getString("state_code");
                    taxRate = rs.getBigDecimal("sales_tax_rate");
                }

                // (2) INSERT หัวบิล (ยอดเป็น 0 ไว้ก่อน) แล้วรับเลขบิลที่ IDENTITY สร้างให้
                psSale.setInt(1, storeNumb);
                psSale.setInt(2, paymentType);
                psSale.setTimestamp(3, Timestamp.valueOf(LocalDateTime.now()));
                psSale.executeUpdate();
                int txnNumb;
                try (ResultSet keys = psSale.getGeneratedKeys()) {
                    keys.next();
                    txnNumb = keys.getInt(1);
                }

                // (3) ทีละรายการ : SELECT สต็อก/ราคา/โปรโมชัน/ภาษี -> INSERT รายการ -> UPDATE ตัดสต็อก
                BigDecimal productTotal = BigDecimal.ZERO;
                BigDecimal rawTax = BigDecimal.ZERO;
                for (SaleLine line : lines) {
                    String upc;
                    boolean inStore;
                    Integer skuStore;
                    int onHand;
                    BigDecimal retailPrice;
                    psStock.setString(1, line.sku);
                    try (ResultSet rs = psStock.executeQuery()) {
                        if (!rs.next()) {
                            throw new BusinessRuleException("SKU " + line.sku + " not found");
                        }
                        upc = rs.getString("UPC");
                        inStore = rs.getBoolean("in_store");
                        skuStore = TxHelper.getNullableInt(rs, "store_numb");
                        onHand = rs.getInt("number_on_hand");
                        retailPrice = rs.getBigDecimal("retail_price");
                    }
                    if (!inStore || skuStore == null || skuStore.intValue() != storeNumb) {
                        throw new BusinessRuleException("SKU " + line.sku + " is not stocked in store " + storeNumb);
                    }
                    if (onHand < line.quantity) {
                        throw new BusinessRuleException("Not enough stock for " + line.sku
                                + ": on hand " + onHand + ", requested " + line.quantity);
                    }

                    BigDecimal discount = Pricing.activeDiscount(psDiscount, upc, today);
                    BigDecimal unitPrice = Pricing.discountedPrice(retailPrice, discount);
                    BigDecimal lineTotal = unitPrice.multiply(BigDecimal.valueOf(line.quantity));
                    productTotal = productTotal.add(lineTotal);
                    if (Pricing.isTaxed(psTaxed, upc, stateCode)) {
                        rawTax = rawTax.add(lineTotal.multiply(taxRate));
                    }

                    psItem.setInt(1, txnNumb);
                    psItem.setString(2, line.sku);
                    psItem.setInt(3, line.quantity);
                    psItem.setBigDecimal(4, unitPrice);
                    psItem.executeUpdate();

                    psSetOnHand.setInt(1, onHand - line.quantity);
                    psSetOnHand.setString(2, line.sku);
                    psSetOnHand.executeUpdate();
                }

                // (4) UPDATE ยอดรวม ภาษี ยอดสุทธิ ในหัวบิล
                BigDecimal salesTax = Pricing.money(rawTax);
                BigDecimal total = productTotal.add(salesTax);
                psTotals.setBigDecimal(1, productTotal);
                psTotals.setBigDecimal(2, salesTax);
                psTotals.setBigDecimal(3, total);
                psTotals.setInt(4, txnNumb);
                psTotals.executeUpdate();

                // (5) T4 เท่านั้น : INSERT ข้อมูลบัตร (token + เลข 4 ตัวท้าย) ใน Transaction เดียวกัน
                if (card != null) {
                    psCredit.setInt(1, txnNumb);
                    psCredit.setString(2, card.token);
                    psCredit.setString(3, card.last4);
                    psCredit.setDate(4, Date.valueOf(card.expDate));
                    psCredit.setString(5, card.nameOnCard);
                    psCredit.executeUpdate();
                }

                conn.commit();                               // ทุกขั้นสำเร็จ -> บันทึก
                return new Receipt(txnNumb, productTotal, salesTax, total);

            } catch (SQLException | BusinessRuleException | RuntimeException e) {
                TxHelper.rollbackQuietly(conn, e);           // ขั้นใดล้มเหลว -> บิล รายการ สต็อก ย้อนกลับทั้งหมด
                throw e;
            }
        }
    }

    private static void validate(List<SaleLine> lines) throws BusinessRuleException {
        if (lines == null || lines.isEmpty()) {
            throw new BusinessRuleException("A sale needs at least one item");
        }
        Set<String> seen = new HashSet<>();
        for (SaleLine line : lines) {
            if (line.quantity <= 0) {
                throw new BusinessRuleException("Quantity of " + line.sku + " must be greater than 0");
            }
            if (!seen.add(line.sku)) {
                throw new BusinessRuleException("SKU " + line.sku + " appears twice - combine the quantities");
            }
        }
    }
}
