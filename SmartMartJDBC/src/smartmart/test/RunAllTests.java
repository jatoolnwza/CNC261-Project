package smartmart.test;

/** รันการทดสอบทุก Transaction ต่อกัน : Run As > Java Application */
public final class RunAllTests {

    @FunctionalInterface
    private interface TestCase {
        void run() throws Exception;
    }

    public static void main(String[] args) {
        runSafely("T1", TestT1SearchProduct::run);
        runSafely("T2", TestT2TransferStock::run);
        runSafely("T3/T4", TestT3T4InStoreSale::run);
        runSafely("T5", TestT5RegisterCustomer::run);
        runSafely("T6", TestT6PlaceWebOrder::run);
        runSafely("T7", TestT7CreateShipment::run);
        runSafely("T8", TestT8CreatePromotion::run);
        Check.summary();
    }

    /** ถ้าการทดสอบใดพังกลางทาง ให้รายงานแล้วไปทดสอบตัวถัดไป */
    private static void runSafely(String name, TestCase test) {
        try {
            test.run();
        } catch (Exception e) {
            Check.that(false, "TEST " + name + " stopped with an unexpected error: " + e);
        }
    }
}
