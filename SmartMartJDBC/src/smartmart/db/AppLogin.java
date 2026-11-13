package smartmart.db;

/**
 * Login ที่แต่ละแอปพลิเคชันใช้ต่อฐานข้อมูล (ตรงกับตาราง Application Logins ในรายงานข้อ 2)
 * ชื่อ user / password อ่านจากไฟล์ db.properties ด้วย key = "<key>.user" และ "<key>.password"
 */
public enum AppLogin {

    /** login_app_webshop  -> role_webshop_app   : T1 ค้นหาสินค้า, T5 สมัครสมาชิก, T6 สั่งซื้อออนไลน์ */
    WEBSHOP_APP("webshop"),

    /** login_app_pos      -> role_pos_app       : T3 ขายเงินสด, T4 ขายบัตรเครดิต */
    POS_APP("pos"),

    /** login_app_warehouse -> role_warehouse_app : T2 โอนสต็อก, T7 จัดส่งแบบแบ่งส่ง */
    WAREHOUSE_APP("warehouse"),

    /** pm1                -> role_product_manager : T8 สร้าง/ยกเลิกโปรโมชัน */
    PRODUCT_MANAGER("pm");

    private final String key;

    AppLogin(String key) {
        this.key = key;
    }

    public String key() {
        return key;
    }
}
