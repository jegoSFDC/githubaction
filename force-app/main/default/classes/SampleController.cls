/**
 * @description Sample Apex Controller for testing delta deployment
 * @author Test User
 * @date 2025-01-30
 */
public with sharing class SampleController {
    
    /**
     * @description Sample method to demonstrate functionality
     * @return String sample message
     */
    public static String getSampleMessage() {
        return 'Hello from Sample Controller!';
    }
    
    /**
     * @description Method to process sample data
     * @param inputData String input data
     * @return String processed result
     */
    public static String processData(String inputData) {
        if (String.isBlank(inputData)) {
            return 'No data provided';
        }
        return 'Processed: ' + inputData;
    }
}
