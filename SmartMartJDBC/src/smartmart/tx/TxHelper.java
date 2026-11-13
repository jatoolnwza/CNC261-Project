package smartmart.tx;

import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.SQLException;

/** เครื่องมือช่วยที่ทุก Transaction ใช้ร่วมกัน */
public final class TxHelper {

    /** SQL Server error 1205 = transaction นี้ถูกเลือกเป็น deadlock victim และถูก rollback แล้ว */
    public static final int SQLSERVER_DEADLOCK = 1205;
    /** SQL Server error 2627 / 2601 = ข้อมูลซ้ำกับ PRIMARY KEY / UNIQUE */
    public static final int SQLSERVER_DUPLICATE_KEY = 2627;
    public static final int SQLSERVER_DUPLICATE_INDEX_KEY = 2601;

    private TxHelper() {
    }

    /** งาน 1 รอบของ Transaction (attempt = รอบที่เท่าไร เริ่มที่ 1) */
    @FunctionalInterface
    public interface TxWork<T> {
        T run(int attempt) throws SQLException, BusinessRuleException;
    }

    /**
     * รัน Transaction และถ้าถูกเลือกเป็น deadlock victim (เกิดได้ใน REPEATABLE READ / SERIALIZABLE)
     * ให้รันใหม่ทั้ง Transaction ได้ไม่เกิน maxAttempts รอบ
     */
    public static <T> T runWithDeadlockRetry(int maxAttempts, TxWork<T> work)
            throws SQLException, BusinessRuleException {
        for (int attempt = 1; ; attempt++) {
            try {
                return work.run(attempt);
            } catch (SQLException e) {
                if (isDeadlock(e) && attempt < maxAttempts) {
                    System.out.println("    ! " + Thread.currentThread().getName() + ": attempt " + attempt
                            + " was the DEADLOCK VICTIM (error 1205) -> rolled back, retrying the whole transaction");
                    pause(200L * attempt);
                    continue;
                }
                throw e;
            }
        }
    }

    /** rollback โดยไม่ให้ error ของ rollback ไปบัง error ตัวจริง */
    public static void rollbackQuietly(Connection conn, Exception cause) {
        try {
            conn.rollback();
        } catch (SQLException rollbackError) {
            cause.addSuppressed(rollbackError);
        }
    }

    public static boolean isDeadlock(SQLException e) {
        return hasErrorCode(e, SQLSERVER_DEADLOCK) || "40001".equals(e.getSQLState());
    }

    public static boolean isDuplicateKey(SQLException e) {
        return hasErrorCode(e, SQLSERVER_DUPLICATE_KEY) || hasErrorCode(e, SQLSERVER_DUPLICATE_INDEX_KEY);
    }

    private static boolean hasErrorCode(SQLException e, int code) {
        for (SQLException x = e; x != null; x = x.getNextException()) {
            if (x.getErrorCode() == code) {
                return true;
            }
        }
        return false;
    }

    /** หน่วงเวลา ใช้เฉพาะตอน Demo ให้ 2 Transaction ทำงานซ้อนกัน */
    public static void pause(long millis) {
        if (millis <= 0) {
            return;
        }
        try {
            Thread.sleep(millis);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }

    /** อ่านคอลัมน์ INT ที่อาจเป็น NULL */
    public static Integer getNullableInt(ResultSet rs, String column) throws SQLException {
        int value = rs.getInt(column);
        return rs.wasNull() ? null : value;
    }

    public static String isolationName(int level) {
        switch (level) {
            case Connection.TRANSACTION_READ_UNCOMMITTED:
                return "READ UNCOMMITTED";
            case Connection.TRANSACTION_READ_COMMITTED:
                return "READ COMMITTED";
            case Connection.TRANSACTION_REPEATABLE_READ:
                return "REPEATABLE READ";
            case Connection.TRANSACTION_SERIALIZABLE:
                return "SERIALIZABLE";
            default:
                return "LEVEL " + level;
        }
    }
}
