package smartmart.tx;

import java.math.BigDecimal;
import java.sql.Connection;
import java.sql.Date;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.LocalDate;
import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

import smartmart.db.AppLogin;
import smartmart.db.DBConnection;

/**
 * T7 : จัดส่งสินค้าออนไลน์แบบแบ่งส่ง (Partial shipment)
 *      สร้างรอบจัดส่งใหม่ (shipment_seq ถัดไป) แล้วระบุว่ารายการสินค้าใดอยู่ในรอบนั้น
 *      รายการที่ยังไม่ส่งจะมี shipment_seq เป็น NULL (backorder) และบวกค่าส่งเข้า web_sale
 *
 * ผู้ใช้        : ระบบคลังสินค้า (login_app_warehouse)
 * Isolation    : SERIALIZABLE
 * เหตุผล       : Transaction นี้อ่าน "ชุดของแถว" แล้วตัดสินใจจากชุดนั้น 2 จุด คือ
 *                MAX(shipment_seq) และรายการที่ shipment_seq IS NULL
 *                ถ้าพนักงาน 2 คนสร้างรอบส่งของคำสั่งซื้อเดียวกันพร้อมกัน อาจได้เลขรอบซ้ำ
 *                หรือหยิบรายการเดียวกันไปคนละรอบ = Phantom Read
 *                SERIALIZABLE ล็อกช่วงของ key (key-range lock) จึงกันแถวใหม่/แถวที่เปลี่ยนในช่วงนั้นได้
 */
public class T7CreateShipment {

    private static final String SQL_SALE_EXISTS =
            "SELECT COUNT(*) FROM dbo.web_sale WHERE web_sale_numb = ?";
    private static final String SQL_PENDING_ITEMS =
            "SELECT wsi.SKU, wsi.quantity, p.shipping_weight FROM dbo.web_sale_item wsi "
            + "JOIN dbo.product_stocked ps ON ps.SKU = wsi.SKU "
            + "JOIN dbo.product p ON p.UPC = ps.UPC "
            + "WHERE wsi.web_sale_numb = ? AND wsi.shipment_seq IS NULL";
    private static final String SQL_NEXT_SEQ =
            "SELECT ISNULL(MAX(shipment_seq), 0) + 1 FROM dbo.web_sale_shipment WHERE web_sale_numb = ?";
    private static final String SQL_INSERT_SHIPMENT =
            "INSERT INTO dbo.web_sale_shipment (web_sale_numb, shipment_seq, ship_date, shipping_charge) VALUES (?, ?, ?, ?)";
    private static final String SQL_ASSIGN_ITEM =
            "UPDATE dbo.web_sale_item SET shipment_seq = ? "
            + "WHERE web_sale_numb = ? AND SKU = ? AND shipment_seq IS NULL";
    private static final String SQL_ADD_SHIPPING =
            "UPDATE dbo.web_sale SET shipping_total = shipping_total + ?, total = total + ? WHERE web_sale_numb = ?";

    private int isolationLevel = Connection.TRANSACTION_SERIALIZABLE;
    private int maxAttempts = 3;

    public T7CreateShipment withIsolation(int level) {
        this.isolationLevel = level;
        return this;
    }

    /**
     * ส่งรายการ skus ของคำสั่งซื้อ webSaleNumb ในรอบใหม่
     * @return shipment_seq ของรอบที่สร้าง
     */
    public int ship(int webSaleNumb, List<String> skus) throws SQLException, BusinessRuleException {
        if (skus == null || skus.isEmpty()) {
            throw new BusinessRuleException("Choose at least one item to ship");
        }
        Set<String> unique = new LinkedHashSet<>(skus);
        return TxHelper.runWithDeadlockRetry(maxAttempts, attempt -> shipOnce(webSaleNumb, unique));
    }

    private int shipOnce(int webSaleNumb, Set<String> skus) throws SQLException, BusinessRuleException {
        try (Connection conn = DBConnection.open(AppLogin.WAREHOUSE_APP)) {
            conn.setAutoCommit(false);
            conn.setTransactionIsolation(isolationLevel);    // SERIALIZABLE
            try (PreparedStatement psExists = conn.prepareStatement(SQL_SALE_EXISTS);
                 PreparedStatement psPending = conn.prepareStatement(SQL_PENDING_ITEMS);
                 PreparedStatement psNextSeq = conn.prepareStatement(SQL_NEXT_SEQ);
                 PreparedStatement psShipment = conn.prepareStatement(SQL_INSERT_SHIPMENT);
                 PreparedStatement psAssign = conn.prepareStatement(SQL_ASSIGN_ITEM);
                 PreparedStatement psShipping = conn.prepareStatement(SQL_ADD_SHIPPING)) {

                // (1) SELECT คำสั่งซื้อต้องมีอยู่จริง
                psExists.setInt(1, webSaleNumb);
                try (ResultSet rs = psExists.executeQuery()) {
                    rs.next();
                    if (rs.getInt(1) == 0) {
                        throw new BusinessRuleException("Web sale #" + webSaleNumb + " not found");
                    }
                }

                // (2) SELECT รายการที่ยังไม่ส่ง พร้อมน้ำหนัก (ใช้คิดค่าส่ง)
                Map<String, BigDecimal> pendingWeight = new HashMap<>();
                psPending.setInt(1, webSaleNumb);
                try (ResultSet rs = psPending.executeQuery()) {
                    while (rs.next()) {
                        BigDecimal weight = rs.getBigDecimal("shipping_weight")
                                .multiply(BigDecimal.valueOf(rs.getInt("quantity")));
                        pendingWeight.put(rs.getString("SKU"), weight);
                    }
                }
                BigDecimal totalWeight = BigDecimal.ZERO;
                for (String sku : skus) {
                    totalWeight = totalWeight.add(pendingWeight.getOrDefault(sku, BigDecimal.ZERO));
                }
                BigDecimal charge = Pricing.shippingCharge(totalWeight);

                // (3) SELECT เลขรอบถัดไป
                int seq;
                psNextSeq.setInt(1, webSaleNumb);
                try (ResultSet rs = psNextSeq.executeQuery()) {
                    rs.next();
                    seq = rs.getInt(1);
                }

                // (4) INSERT รอบจัดส่งใหม่
                psShipment.setInt(1, webSaleNumb);
                psShipment.setInt(2, seq);
                psShipment.setDate(3, Date.valueOf(LocalDate.now()));
                psShipment.setBigDecimal(4, charge);
                psShipment.executeUpdate();

                // (5) UPDATE ผูกแต่ละรายการเข้ารอบนี้ (ต้องยังไม่เคยส่ง ไม่งั้นยกเลิกทั้งรอบ)
                for (String sku : skus) {
                    psAssign.setInt(1, seq);
                    psAssign.setInt(2, webSaleNumb);
                    psAssign.setString(3, sku);
                    if (psAssign.executeUpdate() != 1) {
                        throw new BusinessRuleException("SKU " + sku + " is not a pending item of web sale #"
                                + webSaleNumb + " (already shipped or not in this order)");
                    }
                }

                // (6) UPDATE บวกค่าส่งเข้าค่าส่งรวมและยอดสุทธิของคำสั่งซื้อ
                psShipping.setBigDecimal(1, charge);
                psShipping.setBigDecimal(2, charge);
                psShipping.setInt(3, webSaleNumb);
                psShipping.executeUpdate();

                conn.commit();
                return seq;

            } catch (SQLException | BusinessRuleException | RuntimeException e) {
                TxHelper.rollbackQuietly(conn, e);           // รอบจัดส่งที่ INSERT ไปแล้วจะหายไปด้วย
                throw e;
            }
        }
    }
}
