package smartmart.model;

/** ที่อยู่จัดส่งของลูกค้าออนไลน์ (T5) */
public final class ShippingAddress {

    public final String street;
    public final String city;
    public final String stateCode;
    public final String zip;
    public final String firstName;
    public final String lastName;

    public ShippingAddress(String street, String city, String stateCode, String zip,
                           String firstName, String lastName) {
        this.street = street;
        this.city = city;
        this.stateCode = stateCode;
        this.zip = zip;
        this.firstName = firstName;
        this.lastName = lastName;
    }
}
