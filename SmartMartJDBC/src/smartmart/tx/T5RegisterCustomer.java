package smartmart.tx;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.sql.Connection;
import java.sql.Date;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;

import smartmart.db.AppLogin;
import smartmart.db.DBConnection;
import smartmart.model.CardInfo;
import smartmart.model.ShippingAddress;

/**
 * T5 : สมัครสมาชิกออนไลน์ สร้างบัญชีลูกค้า + บันทึกบัตรเครดิต + ที่อยู่จัดส่ง
 *      ถ้าบันทึกส่วนใดไม่สำเร็จ (เช่น user_id ซ้ำ, รัฐไม่มีอยู่จริง) ต้องยกเลิกทั้งหมด
 *
 * ผู้ใช้        : เว็บขายออนไลน์ (login_app_webshop)
 * Isolation    : READ COMMITTED
 * เหตุผล       : ปัญหาที่อาจเกิดคือ Phantom — สองคนสมัคร user_id เดียวกันพร้อมกัน ต่างคนต่าง SELECT
 *                ไม่เจอ แล้ว INSERT ทั้งคู่ แต่ตาราง web_customer มี UNIQUE (user_id) ฐานข้อมูลจะปฏิเสธคนที่สอง
 *                เอง (error 2627) โค้ดนี้จับ error นั้นแล้ว rollback ทั้งหมด จึงไม่ต้องใช้ SERIALIZABLE
 *                ซึ่งจะล็อกช่วงข้อมูลกว้างและทำให้ระบบช้าโดยไม่จำเป็น
 */
public class T5RegisterCustomer {

    private static final String SQL_CHECK_USER_ID =
            "SELECT COUNT(*) FROM dbo.web_customer WHERE user_id = ?";
    private static final String SQL_INSERT_CUSTOMER =
            "INSERT INTO dbo.web_customer (first_name, last_name, phone, user_id, password_hash) VALUES (?, ?, ?, ?, ?)";
    private static final String SQL_INSERT_CARD =
            "INSERT INTO dbo.web_customer_credit_card (web_customer_numb, card_numb, card_token, card_last4, exp_date, name_on_card) "
            + "VALUES (?, 1, ?, ?, ?, ?)";
    private static final String SQL_INSERT_ADDRESS =
            "INSERT INTO dbo.web_sale_shipping_address (web_customer_numb, street, city, state_code, zip, first_name, last_name) "
            + "VALUES (?, ?, ?, ?, ?, ?, ?)";

    private int isolationLevel = Connection.TRANSACTION_READ_COMMITTED;

    public T5RegisterCustomer withIsolation(int level) {
        this.isolationLevel = level;
        return this;
    }

    /** @return web_customer_numb ของลูกค้าใหม่ */
    public int register(String firstName, String lastName, String phone, String userId, String password,
                        CardInfo card, ShippingAddress address) throws SQLException, BusinessRuleException {
        if (userId == null || userId.trim().isEmpty()) {
            throw new BusinessRuleException("user_id is required");
        }
        if (password == null || password.length() < 6) {
            throw new BusinessRuleException("Password must be at least 6 characters");
        }
        try (Connection conn = DBConnection.open(AppLogin.WEBSHOP_APP)) {
            conn.setAutoCommit(false);
            conn.setTransactionIsolation(isolationLevel);
            try (PreparedStatement psCheck = conn.prepareStatement(SQL_CHECK_USER_ID);
                 PreparedStatement psCustomer = conn.prepareStatement(SQL_INSERT_CUSTOMER, Statement.RETURN_GENERATED_KEYS);
                 PreparedStatement psCard = conn.prepareStatement(SQL_INSERT_CARD);
                 PreparedStatement psAddress = conn.prepareStatement(SQL_INSERT_ADDRESS)) {

                // (1) SELECT ตรวจ user_id ซ้ำ
                psCheck.setString(1, userId);
                try (ResultSet rs = psCheck.executeQuery()) {
                    rs.next();
                    if (rs.getInt(1) > 0) {
                        throw new BusinessRuleException("user_id '" + userId + "' is already taken");
                    }
                }

                // (2) INSERT บัญชีลูกค้า (เก็บรหัสผ่านเป็น hash ไม่เก็บตัวจริง)
                psCustomer.setString(1, firstName);
                psCustomer.setString(2, lastName);
                psCustomer.setString(3, phone);
                psCustomer.setString(4, userId);
                psCustomer.setString(5, hashPassword(userId, password));
                psCustomer.executeUpdate();
                int customerNumb;
                try (ResultSet keys = psCustomer.getGeneratedKeys()) {
                    keys.next();
                    customerNumb = keys.getInt(1);
                }

                // (3) INSERT บัตรใบแรกของลูกค้า (card_numb = 1)
                psCard.setInt(1, customerNumb);
                psCard.setString(2, card.token);
                psCard.setString(3, card.last4);
                psCard.setDate(4, Date.valueOf(card.expDate));
                psCard.setString(5, card.nameOnCard);
                psCard.executeUpdate();

                // (4) INSERT ที่อยู่จัดส่ง
                psAddress.setInt(1, customerNumb);
                psAddress.setString(2, address.street);
                psAddress.setString(3, address.city);
                psAddress.setString(4, address.stateCode);
                psAddress.setString(5, address.zip);
                psAddress.setString(6, address.firstName);
                psAddress.setString(7, address.lastName);
                psAddress.executeUpdate();

                conn.commit();                               // ครบทั้ง 3 ตาราง -> บันทึก
                return customerNumb;

            } catch (SQLException e) {
                TxHelper.rollbackQuietly(conn, e);           // ส่วนใดพัง -> ยกเลิกทั้ง 3 ตาราง
                if (TxHelper.isDuplicateKey(e)) {
                    throw new BusinessRuleException("user_id '" + userId + "' is already taken (UNIQUE constraint)", e);
                }
                throw e;
            } catch (BusinessRuleException | RuntimeException e) {
                TxHelper.rollbackQuietly(conn, e);
                throw e;
            }
        }
    }

    /** SHA-256 ของ "user_id:password" (งานจริงควรใช้ bcrypt/Argon2 ที่มี salt สุ่ม) */
    static String hashPassword(String userId, String password) {
        try {
            MessageDigest md = MessageDigest.getInstance("SHA-256");
            byte[] digest = md.digest((userId + ":" + password).getBytes(StandardCharsets.UTF_8));
            StringBuilder hex = new StringBuilder("sha256:");
            for (byte b : digest) {
                hex.append(String.format("%02x", b));
            }
            return hex.toString();
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }
}
