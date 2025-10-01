/**
 * @description Test class for SampleController
 * @author Test User
 * @date 2025-01-30
 */
@IsTest
public class SampleControllerTest {
    
    @IsTest
    static void testGetSampleMessage() {
        Test.startTest();
        String result = SampleController.getSampleMessage();
        Test.stopTest();
        
        System.assertEquals('Hello from Sample Controller!', result, 'Sample message should match expected value');
    }
    
    @IsTest
    static void testProcessDataWithValidInput() {
        String inputData = 'Test Data';
        
        Test.startTest();
        String result = SampleController.processData(inputData);
        Test.stopTest();
        
        System.assertEquals('Processed: Test Data', result, 'Processed result should match expected value');
    }
    
    @IsTest
    static void testProcessDataWithBlankInput() {
        String inputData = '';
        
        Test.startTest();
        String result = SampleController.processData(inputData);
        Test.stopTest();
        
        System.assertEquals('No data provided', result, 'Should return no data message for blank input');
    }
    
    @IsTest
    static void testProcessDataWithNullInput() {
        String inputData = null;
        
        Test.startTest();
        String result = SampleController.processData(inputData);
        Test.stopTest();
        
        System.assertEquals('No data provided', result, 'Should return no data message for null input');
    }
}
