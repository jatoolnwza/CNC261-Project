package smartmart.tx;

/**
 * ข้อผิดพลาดทางธุรกิจ เช่น สต็อกไม่พอ, user_id ซ้ำ, โปรโมชันช่วงวันที่ทับกัน
 * เมื่อเกิดขึ้นกลาง Transaction โค้ดจะ rollback ทุกอย่างที่ทำไปแล้ว
 */
public class BusinessRuleException extends Exception {

    private static final long serialVersionUID = 1L;

    public BusinessRuleException(String message) {
        super(message);
    }

    public BusinessRuleException(String message, Throwable cause) {
        super(message, cause);
    }
}
