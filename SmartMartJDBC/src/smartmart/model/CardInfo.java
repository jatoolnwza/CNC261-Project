package smartmart.model;

import java.time.LocalDate;

/**
 * ข้อมูลบัตรเครดิตที่ได้จาก payment gateway
 * ระบบเก็บเฉพาะ token และเลข 4 ตัวท้าย ไม่เก็บเลขบัตรเต็ม
 */
public final class CardInfo {

    public final String token;
    public final String last4;
    public final LocalDate expDate;
    public final String nameOnCard;

    public CardInfo(String token, String last4, LocalDate expDate, String nameOnCard) {
        this.token = token;
        this.last4 = last4;
        this.expDate = expDate;
        this.nameOnCard = nameOnCard;
    }
}
