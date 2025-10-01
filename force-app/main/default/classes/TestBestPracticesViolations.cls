public with sharing class TestBestPracticesViolations {
    
    // Best Practice Violation: Empty catch block
    public static void badExceptionHandling() {
        try {
            Account acc = [SELECT Id FROM Account LIMIT 1];
        } catch (Exception e) {
            // Empty catch block - bad practice
        }
    }
    
    // Best Practice Violation: Unused variable
    public static void unusedVariables() {
        String unusedVar = 'This is never used';
        Integer anotherUnused = 42;
        
        System.debug('Hello World');
    }
    
    // Best Practice Violation: Method too long
    public static void veryLongMethod() {
        // This method is intentionally long to trigger PMD warnings
        String var1 = 'value1';
        String var2 = 'value2';
        String var3 = 'value3';
        String var4 = 'value4';
        String var5 = 'value5';
        String var6 = 'value6';
        String var7 = 'value7';
        String var8 = 'value8';
        String var9 = 'value9';
        String var10 = 'value10';
        String var11 = 'value11';
        String var12 = 'value12';
        String var13 = 'value13';
        String var14 = 'value14';
        String var15 = 'value15';
        String var16 = 'value16';
        String var17 = 'value17';
        String var18 = 'value18';
        String var19 = 'value19';
        String var20 = 'value20';
        
        System.debug(var1 + var2 + var3 + var4 + var5);
        System.debug(var6 + var7 + var8 + var9 + var10);
        System.debug(var11 + var12 + var13 + var14 + var15);
        System.debug(var16 + var17 + var18 + var19 + var20);
    }
    
    // Best Practice Violation: Too many parameters
    public static void tooManyParameters(String param1, String param2, String param3, 
                                       String param4, String param5, String param6, 
                                       String param7, String param8, String param9, 
                                       String param10) {
        System.debug('Too many parameters');
    }
}
