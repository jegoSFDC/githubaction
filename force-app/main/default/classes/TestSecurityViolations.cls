public with sharing class TestSecurityViolations {
    
    // Security Violation: Hardcoded password
    private static final String PASSWORD = 'admin123';
    
    // Security Violation: SQL injection vulnerability
    public static List<Account> getAccountsByName(String name) {
        String query = 'SELECT Id, Name FROM Account WHERE Name = \'' + name + '\'';
        return Database.query(query);
    }
    
    // Security Violation: SOQL injection
    public static List<Contact> searchContacts(String searchTerm) {
        String soql = 'SELECT Id, Name, Email FROM Contact WHERE Name LIKE \'%' + searchTerm + '%\'';
        return Database.query(soql);
    }
    
    // Security Violation: DML in loop
    public static void updateAccounts(List<Account> accounts) {
        for (Account acc : accounts) {
            acc.Description = 'Updated';
            update acc; // This is bad - DML in loop
        }
    }
    
    // Security Violation: Unescaped output
    public static String generateHtml(String userInput) {
        return '<div>' + userInput + '</div>'; // XSS vulnerability
    }
    
    // Security Violation: Hardcoded URL
    public static void callExternalService() {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://hardcoded-api.example.com/data');
        req.setMethod('GET');
    }
}
