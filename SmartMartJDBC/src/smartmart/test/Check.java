package smartmart.test;

import java.math.BigDecimal;

/** ตัวช่วยตรวจผลแบบง่าย พิมพ์ PASS / FAIL ลง Console (ไม่ต้องติดตั้ง JUnit) */
public final class Check {

    private static int passed;
    private static int failed;

    private Check() {
    }

    @FunctionalInterface
    public interface Action {
        void run() throws Exception;
    }

    public static void title(String text) {
        System.out.println();
        System.out.println("==================================================================");
        System.out.println(" " + text);
        System.out.println("==================================================================");
    }

    public static void step(String text) {
        System.out.println();
        System.out.println("[" + text + "]");
    }

    public static void info(String text) {
        System.out.println("    " + text);
    }

    public static void that(boolean ok, String description) {
        if (ok) {
            passed++;
            System.out.println("    PASS  " + description);
        } else {
            failed++;
            System.out.println("    FAIL  " + description);
        }
    }

    public static void equal(long expected, long actual, String what) {
        that(expected == actual, what + " = " + actual + "  (expected " + expected + ")");
    }

    /** เทียบค่าแบบ Object (String, Integer ที่อาจเป็น null) */
    public static void same(Object expected, Object actual, String what) {
        boolean same = expected == null ? actual == null : expected.equals(actual);
        that(same, what + " = " + actual + "  (expected " + expected + ")");
    }

    public static void money(String expected, BigDecimal actual, String what) {
        boolean same = actual != null && actual.compareTo(new BigDecimal(expected)) == 0;
        that(same, what + " = " + actual + "  (expected " + expected + ")");
    }

    /** คาดว่าต้องล้มเหลว (ถูก rollback) : ผ่านเมื่อเกิด exception */
    public static Exception expectFailure(String description, Action action) {
        try {
            action.run();
        } catch (Exception e) {
            passed++;
            System.out.println("    PASS  " + description);
            System.out.println("          -> " + e.getClass().getSimpleName() + ": " + e.getMessage());
            return e;
        }
        failed++;
        System.out.println("    FAIL  " + description + "  (expected an error but it succeeded)");
        return null;
    }

    public static int failedCount() {
        return failed;
    }

    public static void summary() {
        System.out.println();
        System.out.println("------------------------------------------------------------------");
        System.out.println(" RESULT: " + passed + " passed, " + failed + " failed");
        System.out.println("------------------------------------------------------------------");
    }
}
